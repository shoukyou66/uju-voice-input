import AppIntents
import Foundation

/// Stops the dictation in progress and returns its text (for Shortcuts).
struct StopDictationIntent: AppIntent {
    static var title: LocalizedStringResource { "停止 KVoice 聽寫" }
    static var description: IntentDescription {
        IntentDescription("停止進行中的 KVoice 聽寫，並回傳完成的文字。")
    }
    static var supportedModes: IntentModes { .background }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = await AppModel.shared.stopDictation()
        return .result(value: result?.text ?? "")
    }
}

struct KVoiceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // First: iOS lists it under Action Button > Shortcut > KVoice.
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: [
                "切換 \(.applicationName) 聽寫",
                "用 \(.applicationName) 切換聽寫"
            ],
            shortTitle: "切換聽寫",
            systemImageName: "waveform.badge.mic"
        )
        AppShortcut(
            intent: DictateIntent(),
            phrases: [
                "用 \(.applicationName) 聽寫",
                "啟動 \(.applicationName)",
                "用 \(.applicationName) 開始聽寫",
                "用 \(.applicationName) 聽寫 \(\.$mode)"
            ],
            shortTitle: "聽寫",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopDictationIntent(),
            phrases: [
                "停止 \(.applicationName)",
                "用 \(.applicationName) 停止聽寫"
            ],
            shortTitle: "停止聽寫",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: BeginDictationIntent(),
            phrases: [
                "用 \(.applicationName) 準備聽寫",
                "準備 \(.applicationName) 聽寫"
            ],
            shortTitle: "開始聽寫",
            systemImageName: "waveform.badge.mic"
        )
        AppShortcut(
            intent: TranscribeAudioIntent(),
            phrases: [
                "用 \(.applicationName) 轉錄音訊",
                "用 \(.applicationName) 轉錄錄音"
            ],
            shortTitle: "轉錄音訊",
            systemImageName: "waveform"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .purple }
}
