import AppIntents
import Foundation

/// One press starts dictating in the background; the next press stops,
/// transcribes and returns the text (also copied to the clipboard). The
/// first press returns an empty string, so a shortcut can branch on it.
/// Compiled into the app and the widget extension (Control, Live Activity
/// Stop button); it always runs in the app.
/// Also a `LiveActivityIntent`: only those may start a Live Activity while
/// KVoice is in the background, and an audio recording intent must start one.
struct ToggleDictationIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "切換聽寫" }
    static var description: IntentDescription {
        IntentDescription("在背景開始聽寫。再執行一次即可停止；KVoice 會拷貝文字並回傳。")
    }
    /// Background, continuing in the foreground on demand (when iOS does
    /// not let KVoice start the microphone in the background).
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "模式", description: "要用來聽寫的模式。留空則使用目前啟用的模式。")
    var mode: ModeEntity?

    init() {}

    init(mode: ModeEntity?) {
        self.mode = mode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("在 \(\.$mode) 切換聽寫")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        #if !KVOICE_WIDGET_EXTENSION
        let text = try await AppModel.shared.toggleDictation(
            modeID: mode?.id,
            isForeground: systemContext.currentMode == .foreground,
            continueInForeground: { reason in
                try await continueInForeground(IntentDialog(stringLiteral: reason), alwaysConfirm: false)
            }
        )
        return .result(value: text)
        #else
        return .result(value: "")
        #endif
    }
}
