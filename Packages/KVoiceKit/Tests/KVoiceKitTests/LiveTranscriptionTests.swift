import Foundation
import Testing
@testable import KVoiceCore
@testable import KVoiceKit

@Suite struct LiveTranscriptionTests {
    @Test func setupMessageAsksForSmartTextTranscription() throws {
        let json = GeminiLiveTranscriber.setupMessage(languageCodes: ["cmn-Hans-CN", "en-US"], vocabulary: [" KVoice ", "", "語音輸入"])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let setup = try #require(object["setup"] as? [String: Any])
        #expect(setup["model"] as? String == "models/gemini-3.5-transcribe-live")
        let generation = try #require(setup["generationConfig"] as? [String: Any])
        #expect(generation["responseModalities"] as? [String] == ["TEXT"])
        let transcription = try #require(setup["inputAudioTranscription"] as? [String: Any])
        #expect(transcription["mode"] as? String == "SMART")
        #expect(transcription["languageCodes"] as? [String] == ["cmn-Hans-CN", "en-US"])
        #expect(transcription["customVocabulary"] as? [String] == ["KVoice", "語音輸入"])
    }

    @Test func setupMessageOmitsAnEmptyVocabulary() throws {
        let json = GeminiLiveTranscriber.setupMessage(languageCodes: [], vocabulary: [" "])
        #expect(!json.contains("customVocabulary"))
    }

    @Test func audioMessageCarriesBase64PCM() throws {
        let json = GeminiLiveTranscriber.audioMessage(Data([1, 2, 3]))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let audio = try #require((object["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any])
        #expect(audio["data"] as? String == "AQID")
        #expect(audio["mimeType"] as? String == "audio/pcm;rate=16000")
    }

    @Test func parsesServerMessages() {
        func events(_ json: String) -> [GeminiLiveTranscriber.Event] {
            GeminiLiveTranscriber.events(in: Data(json.utf8))
        }
        #expect(events(#"{"setupComplete":{}}"#) == [.setupComplete])
        #expect(events(#"{"serverContent":{},"voiceActivity":{"type":"ACTIVITY_START","audioOffset":"0.640s"}}"#) == [.speechStarted])
        #expect(events(#"{"serverContent":{},"voiceActivity":{"type":"ACTIVITY_END","audioOffset":"6.596062500s"}}"#)
            == [.speechEnded(offset: 6.5960625)])
        #expect(events(#"{"serverContent":{"interimInputTranscription":{"text":"明天下午"}}}"#) == [.interimText("明天下午")])
        #expect(events(#"{"serverContent":{"inputTranscription":{"text":"明天下午三点。"}}}"#) == [.finalText("明天下午三点。")])
        #expect(events(#"{"serverContent":{"generationComplete":true}}"#).isEmpty)
        #expect(events("not json").isEmpty)
    }

    @Test func joinsSegments() {
        #expect(GeminiLiveTranscriber.join(["明天開會。", " 記得帶報價單。"]) == "明天開會。記得帶報價單。")
        #expect(GeminiLiveTranscriber.join(["Hello world.", "Next one"]) == "Hello world. Next one")
        #expect(GeminiLiveTranscriber.join(["好", "", "OK"]) == "好OK")
        #expect(GeminiLiveTranscriber.join([]) == "")
    }

    @Test func convertsFloatSamplesToInt16PCM() {
        let samples: [Float] = [0, 1, -1, 2, .nan]
        let data = samples.withUnsafeBufferPointer { TapWriter.int16PCM($0.baseAddress!, count: $0.count) }
        let values = data.withUnsafeBytes { raw in
            (0..<samples.count).map { Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) }
        }
        #expect(values == [0, 32_767, -32_767, 32_767, 0])
    }

    @MainActor
    @Test func pipelineWithoutAGeminiEngineDoesNotStream() async throws {
        let recorder = StubRecorder()
        let pipeline = DictationPipeline(
            recorder: recorder,
            engines: StubEngines(engine: StubEngine(text: "hello")),
            formatters: StubFormatters(formatter: StubFormatter(error: nil)),
            history: nil,
            settings: { Settings() }
        )
        try await pipeline.startRecording(mode: .dictation)
        #expect(recorder.pcmHandler == nil)
        let result = try await pipeline.stopAndProcess()
        #expect(result.text == "hello")
        #expect(pipeline.liveText.isEmpty)
    }
}
