import AppIntents
import Foundation

/// Opens KVoice and starts dictating; if KVoice is already recording, it
/// stops and processes instead (so one press starts and the next one
/// finishes). Follows the shared `DictationActivity`: it does not start
/// while an Action Button shortcut owns the microphone. Compiled into the app and the widget extension; it
/// always runs in the app.
struct DictateIntent: AppIntent {
    static var title: LocalizedStringResource { "用 KVoice 聽寫" }
    static var description: IntentDescription {
        IntentDescription("開啟 KVoice 並開始錄音。再執行一次即可結束聽寫。")
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "模式", description: "要用來聽寫的模式。留空則使用目前啟用的模式。")
    var mode: ModeEntity?

    init() {}

    init(mode: ModeEntity?) {
        self.mode = mode
    }

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$mode) 聽寫")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !KVOICE_WIDGET_EXTENSION
        let model = AppModel.shared
        model.selectedTab = .home
        if model.pipeline.isRecording {
            await model.stopDictation()
        } else {
            // Refused with a notice while the Action Button records.
            await model.startDictation(modeID: mode?.id, source: .intent)
        }
        #endif
        return .result()
    }
}
