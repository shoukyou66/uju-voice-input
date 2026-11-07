import Foundation
import Synchronization

/// Streams a recording in progress to Gemini Live transcription
/// (`gemini-3.5-transcribe-live`, smart mode) over a WebSocket, so the
/// transcript is ready almost as soon as the speaker stops.
///
/// Google finalizes each speech segment about 0.5 s after the speaker pauses
/// (`inputTranscription`), and sends interim text while they speak
/// (`interimInputTranscription`). Any failure is recorded and surfaces from
/// `finish()`; the pipeline then transcribes the saved WAV file as before,
/// so a dictation is never lost.
public final class GeminiLiveTranscriber: Sendable {
    public static let model = "gemini-3.5-transcribe-live"
    static let endpoint = URL(string:
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    )!
    static let sampleRate = 16_000.0
    /// About 100 ms of 16 kHz, 16-bit mono PCM per message.
    static let chunkBytes = 3_200
    /// Int16 RMS below this always counts as silence (about -42 dBFS).
    static let voiceFloor: Float = 250
    /// After the end of the stream, how long to wait for speech Google has
    /// not reported yet when the local level says the tail had voice.
    static let tailGrace: Duration = .seconds(1)
    /// After the end of the stream, how long Google may keep reporting speech
    /// before the WAV file is transcribed instead.
    static let speakingGrace: Duration = .seconds(5)
    /// How long the connection may take before the WAV file is used.
    static let connectTimeout: Duration = .seconds(4)

    struct State {
        var finals: [String] = []
        var preview = ""
        var serverSpeaking = false
        /// Seconds into the stream where Google last reported the end of speech.
        var lastEndOffset = 0.0
        var failure: String?
        /// Google accepted the setup.
        var ready = false
        /// When `audioStreamEnd` went out (after all queued audio).
        var endSentAt: ContinuousClock.Instant?
        var closed = false
        // Local voice detection on the audio sent, to know whether the tail
        // could still hold speech Google has not reported.
        var samplesSent = 0
        var lastVoiceSample = 0
        var noise: Float?
    }

    private let state = Mutex(State())
    private let audio: AsyncStream<Data>
    private let audioInput: AsyncStream<Data>.Continuation
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    private let previewHandler: (@Sendable (String) -> Void)?

    /// Connects at once; audio fed before the connection is ready is queued.
    public init(
        apiKey: String,
        languageCodes: [String],
        vocabulary: [String],
        previewHandler: (@Sendable (String) -> Void)? = nil
    ) {
        var request = URLRequest(url: Self.endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        // Google sends nothing while the speaker is silent; the connection
        // wait is limited in `finish()` instead.
        request.timeoutInterval = 900
        session = URLSession(configuration: .ephemeral)
        task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        (audio, audioInput) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        self.previewHandler = previewHandler
        let setup = Self.setupMessage(languageCodes: languageCodes, vocabulary: vocabulary)
        task.resume()
        Task { await self.run(setup: setup) }
    }

    // MARK: Messages

    struct Setup: Encodable {
        struct Body: Encodable {
            struct GenerationConfig: Encodable {
                var responseModalities = ["TEXT"]
            }
            struct InputAudioTranscription: Encodable {
                var languageCodes: [String]
                var mode = "SMART"
                var customVocabulary: [String]?
            }
            var model: String
            var generationConfig = GenerationConfig()
            var inputAudioTranscription: InputAudioTranscription
        }
        var setup: Body
    }

    static func setupMessage(languageCodes: [String], vocabulary: [String]) -> String {
        let terms = vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let message = Setup(setup: .init(
            model: "models/\(model)",
            inputAudioTranscription: .init(
                languageCodes: languageCodes,
                customVocabulary: terms.isEmpty ? nil : Array(terms.prefix(1000))
            )
        ))
        let data = (try? JSONEncoder().encode(message)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func audioMessage(_ pcm: Data) -> String {
        #"{"realtimeInput":{"audio":{"data":""# + pcm.base64EncodedString()
            + #"","mimeType":"audio/pcm;rate=16000"}}}"#
    }

    static let endMessage = #"{"realtimeInput":{"audioStreamEnd":true}}"#

    /// What one server message changes.
    enum Event: Equatable {
        case setupComplete
        case speechStarted
        case speechEnded(offset: Double)
        case interimText(String)
        case finalText(String)
        case error(String)
    }

    static func events(in data: Data) -> [Event] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var events: [Event] = []
        if json["setupComplete"] != nil { events.append(.setupComplete) }
        if let error = json["error"] {
            events.append(.error(String(describing: error).prefix(300).description))
        }
        if let activity = json["voiceActivity"] as? [String: Any], let type = activity["type"] as? String {
            if type == "ACTIVITY_START" {
                events.append(.speechStarted)
            } else if type == "ACTIVITY_END" {
                let raw = (activity["audioOffset"] as? String ?? "0").replacingOccurrences(of: "s", with: "")
                events.append(.speechEnded(offset: Double(raw) ?? 0))
            }
        }
        if let content = json["serverContent"] as? [String: Any] {
            if let done = content["inputTranscription"] as? [String: Any] {
                events.append(.finalText(done["text"] as? String ?? ""))
            } else if let interim = content["interimInputTranscription"] as? [String: Any] {
                events.append(.interimText(interim["text"] as? String ?? ""))
            }
        }
        return events
    }

    /// Google sends one final transcript per pause. Chinese segments join
    /// directly; a space goes between two Latin words.
    static func join(_ segments: [String]) -> String {
        var out = ""
        for segment in segments {
            let part = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = part.unicodeScalars.first else { continue }
            if let last = out.unicodeScalars.last,
               first.isASCII, CharacterSet.alphanumerics.contains(first),
               last.isASCII, CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".,!?")).contains(last) {
                out += " "
            }
            out += part
        }
        return out
    }

    // MARK: Streaming

    /// 16 kHz, 16-bit little-endian mono PCM. Safe to call from the audio thread.
    public func feed(_ pcm: Data) {
        let closed = state.withLock { state -> Bool in
            guard !state.closed, state.failure == nil else { return true }
            let count = pcm.count / 2
            guard count > 0 else { return false }
            let rms: Float = pcm.withUnsafeBytes { raw in
                var sum: Float = 0
                for index in 0..<count {
                    let sample = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)))
                    sum += sample * sample
                }
                return (sum / Float(count)).squareRoot()
            }
            // Background noise follows quick downward, slowly upward.
            let noise = state.noise.map { rms < $0 ? 0.9 * $0 + 0.1 * rms : 0.998 * $0 + 0.002 * rms } ?? rms
            state.noise = noise
            state.samplesSent += count
            if rms > max(noise * 3, Self.voiceFloor) { state.lastVoiceSample = state.samplesSent }
            return false
        }
        if !closed { audioInput.yield(pcm) }
    }

    private func run(setup: String) async {
        do {
            try await task.send(.string(setup))
            guard Self.events(in: try await receiveData()).contains(.setupComplete) else {
                throw TranscriptionError.failed("no setupComplete")
            }
            state.withLock { $0.ready = true }
            Task { await self.receiveLoop() }
            var pending = Data()
            for await chunk in audio {
                pending.append(chunk)
                if pending.count >= Self.chunkBytes {
                    try await task.send(.string(Self.audioMessage(pending)))
                    pending.removeAll(keepingCapacity: true)
                }
            }
            guard !isClosed else { return }
            if !pending.isEmpty { try await task.send(.string(Self.audioMessage(pending))) }
            try await task.send(.string(Self.endMessage))
            state.withLock { $0.endSentAt = ContinuousClock.now }
        } catch {
            fail("send: \(describe(error))")
        }
    }

    private func receiveLoop() async {
        do {
            while !isClosed {
                apply(Self.events(in: try await receiveData()))
            }
        } catch {
            fail("receive: \(describe(error))")
        }
    }

    private func receiveData() async throws -> Data {
        switch try await task.receive() {
        case .string(let text): return Data(text.utf8)
        case .data(let data): return data
        @unknown default: return Data()
        }
    }

    /// Applies one server message's events under one lock, so `finish()`
    /// never sees half of a message.
    private func apply(_ events: [Event]) {
        let preview: String? = state.withLock { state in
            var preview: String?
            for event in events {
                switch event {
                case .setupComplete:
                    break
                case .speechStarted:
                    state.serverSpeaking = true
                case .speechEnded(let offset):
                    state.serverSpeaking = false
                    state.lastEndOffset = offset
                case .interimText(let text):
                    state.preview = text
                    preview = Self.join(state.finals + [text])
                case .finalText(let text):
                    state.finals.append(text)
                    state.preview = ""
                    preview = Self.join(state.finals)
                case .error(let message):
                    if state.failure == nil, !state.closed { state.failure = message }
                }
            }
            return preview
        }
        if let preview { previewHandler?(preview) }
    }

    private var isClosed: Bool { state.withLock { $0.closed } }

    private func fail(_ message: String) {
        state.withLock { state in
            if state.failure == nil, !state.closed { state.failure = message }
        }
    }

    private func describe(_ error: any Error) -> String {
        var text = error.localizedDescription
        if task.closeCode != .invalid {
            let reason = task.closeReason.map { String(decoding: $0, as: UTF8.self) } ?? ""
            text += " (close \(task.closeCode.rawValue) \(reason))"
        }
        return String(text.prefix(300))
    }

    /// Ends the stream and waits until Google has finalized the last speech.
    /// Returns the joined transcript (Simplified, possibly empty); throws
    /// `TranscriptionError.failed` on any failure or after `timeout`.
    public func finish(timeout: Duration = .seconds(12)) async throws -> String {
        audioInput.finish()
        let clock = ContinuousClock()
        let start = clock.now
        defer { close() }
        while true {
            let snapshot = state.withLock { $0 }
            if let failure = snapshot.failure { throw TranscriptionError.failed(failure) }
            let now = clock.now
            if let endSentAt = snapshot.endSentAt {
                // Count from when the end really went out: a slow upload may
                // still have been sending queued audio when `finish()` began.
                let sinceEnd = now - endSentAt
                if !snapshot.serverSpeaking {
                    let lastVoice = Double(snapshot.lastVoiceSample) / Self.sampleRate
                    let caughtUp = snapshot.lastEndOffset >= lastVoice - 0.3 && snapshot.preview.isEmpty
                    if caughtUp || sinceEnd > Self.tailGrace { return Self.join(snapshot.finals) }
                } else if sinceEnd > Self.speakingGrace {
                    throw TranscriptionError.failed("live transcription still hearing speech")
                }
            }
            if !snapshot.ready, now - start > Self.connectTimeout {
                throw TranscriptionError.failed("live transcription could not connect")
            }
            if now - start > timeout { throw TranscriptionError.failed("live transcription timed out") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Stops streaming and closes the connection. Safe to call more than once.
    public func close() {
        let wasClosed = state.withLock { state -> Bool in
            defer { state.closed = true }
            return state.closed
        }
        guard !wasClosed else { return }
        audioInput.finish()
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}
