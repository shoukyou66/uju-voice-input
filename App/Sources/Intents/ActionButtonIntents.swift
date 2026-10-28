import AppIntents
import Foundation
import KVoiceKit
import UniformTypeIdentifiers

/// What Begin Dictation tells the shortcut: "If Outcome is Record".
enum DictationGateOutcome: String, AppEnum {
    case record
    case stoppedExisting
    case alreadyRecording

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "聽寫結果" }
    static var caseDisplayRepresentations: [DictationGateOutcome: DisplayRepresentation] {
        [
            .record: "錄音",
            .stoppedExisting: "已停止原本的錄音",
            .alreadyRecording: "已在錄音中"
        ]
    }

    init(_ outcome: DictationActivityReducer.GateOutcome) {
        // The raw values match (a package test pins them).
        self = DictationGateOutcome(rawValue: outcome.rawValue) ?? .record
    }
}

/// Step 1 of the Action Button shortcut. Runs in the background, decides
/// whether the shortcut should record (see `Docs/DictationStates.md`), and
/// toggles: if KVoice itself is recording, it stops and finishes that
/// dictation instead.
struct BeginDictationIntent: AppIntent {
    static var title: LocalizedStringResource { "開始聽寫" }
    static var description: IntentDescription {
        IntentDescription("從任何 App 準備一次 KVoice 聽寫。請在「錄製音訊」和「轉錄音訊」之前使用；只有結果為「錄音」時才需要錄音。")
    }
    /// Background only: the shortcut keeps the current app in front (the
    /// iOS 26 replacement for `openAppWhenRun = false`).
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "模式", description: "這次聽寫使用的模式。留空則使用目前啟用的模式。")
    var mode: ModeEntity?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$mode) 開始聽寫")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DictationGateOutcome> & ProvidesDialog {
        let model = AppModel.shared
        model.modes.reload()
        if let id = mode?.id, model.modes.mode(id: id) != nil {
            try? model.modes.setActiveMode(id: id)
        }
        let outcome = model.handoff.beginShortcut(modeID: mode?.id)
        return .result(value: DictationGateOutcome(outcome), dialog: IntentDialog(stringLiteral: outcome.dialog))
    }
}

/// Step 3 of the Action Button shortcut: transcribes the Record Audio file
/// in the background and returns the text (copied by the shortcut, typed
/// by a visible KVoice keyboard, saved in History). Continues in the
/// foreground when the job cannot finish in the background budget.
struct TranscribeAudioIntent: AppIntent {
    static var title: LocalizedStringResource { "轉錄音訊" }
    static var description: IntentDescription {
        IntentDescription("用 KVoice 轉錄並整理一段錄音，回傳文字，並儲存到歷史紀錄。")
    }
    /// Background, continuing in the foreground on demand: the iOS 26 form
    /// of `ForegroundContinuableIntent`.
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "音訊", description: "一段錄音，例如來自「錄製音訊」。", supportedContentTypes: [.audio])
    var audio: IntentFile

    @Parameter(title: "模式", description: "留空則使用目前啟用的模式。")
    var mode: ModeEntity?

    @Parameter(title: "語言", description: "語言代碼，例如 en-US。留空則使用模式設定的語言。")
    var language: String?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$mode) 轉錄 \(\.$audio)") {
            \.$language
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = AppModel.shared
        model.modes.reload()
        model.settings.reload()
        let fileExtension = URL(filePath: audio.filename).pathExtension.nonEmpty
            ?? audio.type?.preferredFilenameExtension
            ?? "m4a"
        let text = try await model.transcribeShortcutAudio(
            data: audio.data,
            fileExtension: fileExtension,
            modeID: mode?.id,
            language: language?.trimmingCharacters(in: .whitespaces).nonEmpty,
            isForeground: systemContext.currentMode == .foreground,
            continueInForeground: {
                try await continueInForeground("要在 KVoice 結束這次聽寫嗎？", alwaysConfirm: false)
            }
        )
        return .result(value: text, dialog: IntentDialog(stringLiteral: Self.preview(text)))
    }

    /// A short dialog: the start of the text.
    static func preview(_ text: String) -> String {
        text.count > 120 ? String(text.prefix(117)) + "…" : text
    }
}

extension AudioJobError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: errorDescription ?? "聽寫失敗。")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
