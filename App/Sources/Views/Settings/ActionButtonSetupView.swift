import KVoiceKit
import SwiftUI

/// The published "KVoice Dictation" shortcut (an iCloud shortcut link).
/// Empty until it is published; the setup screen then shows manual steps.
enum KVoiceShortcutLink {
    static let url = ""
}

/// Settings › Action Button: how to set up the dictation shortcut, and a
/// debug view of the shared dictation state.
struct ActionButtonSetupView: View {
    var body: some View {
        List {
            Section {
                ActionButtonExplainer()
            }
            Section {
                ToggleSetupSteps()
            } header: {
                Text("開始設定")
            } footer: {
                Text("「控制中心」和「鎖定畫面」也可以放「切換聽寫」控制項。")
            }
            Section {
                DisclosureGroup("進階：「錄製音訊」捷徑") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("改用「捷徑」App 錄音的手動捷徑。只有在「切換聽寫」對你無效時才使用。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ActionButtonSetupSteps()
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                ActionButtonStateTester()
            } header: {
                Text("測試")
            } footer: {
                Text("顯示「開始聽寫」（進階捷徑）現在會回答什麼，但不會真的開始。")
            }
        }
        .navigationTitle("動作按鈕")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { JobNotifier.requestAuthorization() }
    }
}

struct ActionButtonExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("在任何 App 聽寫", systemImage: "button.vertical.right.press")
                .font(.headline)
            Text("按一下動作按鈕開始錄音，再按一下停止。KVoice 會轉錄、把文字拷貝到剪貼簿，並在 KVoice 鍵盤開啟時直接輸入文字。所有內容都會儲存在歷史紀錄。")
            Text("在開著 KVoice 鍵盤的任何 App 裡：按動作按鈕、說話、再按一次，文字就會輸入。之後鍵盤的麥克風不用離開 App 就能使用，KVoice 會持續聆聽（見「設定」中的「讓鍵盤持續聆聽」）。點鍵盤上的 ⏻，或即時動態上的「結束」，即可結束這個階段。")
            Text("KVoice 會嘗試在背景啟動，讓你目前使用的 App 留在前景。如果 iOS 拒絕，KVoice 會短暫開啟來啟動（在鎖定畫面時會要求 Face ID），之後你可以切換回去。「即時動態」會顯示錄音狀態，上面的停止鈕和第二次按下的效果相同。")
                .foregroundStyle(.secondary)
            Text("很長的錄音，或需要比 iOS 背景工作所給時間更久的模式，會改在 KVoice 內完成：停止時會請你開啟 KVoice。")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.vertical, 4)
    }
}

/// The one-step setup: pick Toggle Dictation in the Action Button settings.
struct ToggleSetupSteps: View {
    static let steps: [String] = [
        "開啟「設定」›「動作按鈕」。",
        "滑到「控制項目」，點選控制項目並選擇 KVoice ›「切換聽寫」。或滑到「捷徑」，選擇 KVoice ›「切換聽寫」。",
        "按下動作按鈕開始聽寫，再按一次停止。文字會被拷貝。"
    ]

    var body: some View {
        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
            StepRow(number: index + 1, text: step)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: .circle)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(text).font(.callout)
        }
    }
}

struct ActionButtonSetupSteps: View {
    @Environment(\.openURL) private var openURL

    static let manualSteps: [String] = [
        "開啟「捷徑」App，點 + 建立新捷徑。",
        "加入 KVoice ›「開始聽寫」。",
        "加入「如果」，並設定為：結果為「錄音」。",
        "在「如果」裡面，加入「錄製音訊」。將「開始」設為「立即」，「結束」設為「點一下時」。",
        "在下方加入 KVoice ›「轉錄音訊」，將「音訊」設為「錄製的音訊」。「模式」可不選。",
        "在下方加入「拷貝至剪貼簿」。「結束如果」會結束這個區塊。",
        "替捷徑取名，然後開啟「設定」›「動作按鈕」，選擇「捷徑」並選取它。"
    ]

    var body: some View {
        if let url = URL(string: KVoiceShortcutLink.url), !KVoiceShortcutLink.url.isEmpty {
            Button("加入捷徑", systemImage: "plus.app") { openURL(url) }
            Text("接著開啟「設定」›「動作按鈕」，選擇「捷徑」並選取它。")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(Self.manualSteps.enumerated()), id: \.offset) { index, step in
                StepRow(number: index + 1, text: step)
            }
        }
    }
}

/// The current shared state and the gate's answer, for debugging.
struct ActionButtonStateTester: View {
    @Environment(AppModel.self) private var model
    @State private var answer: String?

    var body: some View {
        let handoff: HandoffCoordinator = model.handoff
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LabeledContent("狀態", value: Self.describe(handoff.activity.effectivePhase(now: context.date)))
        }
        if let answer {
            LabeledContent("「開始聽寫」會回答", value: answer)
        }
        Button("測試", systemImage: "play.circle") {
            answer = DictationGateOutcome(handoff.previewGate()).displayName
        }
        if handoff.effectivePhase.recordingOwner == .shortcut {
            Button("重設動作按鈕錄音", systemImage: "arrow.counterclockwise", role: .destructive) {
                handoff.resetShortcut()
                answer = nil
            }
        }
    }

    static func describe(_ phase: DictationActivity.Phase) -> String {
        switch phase {
        case .idle: "閒置"
        case .standby(let until): "鍵盤聆聽中，直到 \(until.formatted(date: .omitted, time: .shortened))"
        case .recording(.app, let source, _): "在 KVoice 錄音中（\(source.rawValue)）"
        case .recording(.shortcut, _, _): "Recording with the Action Button"
        case .processing(.transcribing, _): "轉錄中"
        case .processing(.formatting, _): "整理中"
        case .delivered: "已送出"
        case .failed(_, let message): "失敗：\(message)"
        }
    }
}

extension DictationGateOutcome {
    var displayName: String {
        switch self {
        case .record: "錄音"
        case .stoppedExisting: "已停止原本的錄音"
        case .alreadyRecording: "已在錄音中"
        }
    }
}
