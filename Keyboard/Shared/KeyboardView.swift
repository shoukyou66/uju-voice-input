import KVoiceCore
import SwiftUI
import UIKit

/// The KVoice keyboard: a large mic button with its status, the first three
/// modes ("personalities") as one segmented capsule under it, and a row of
/// basic editing keys. Nothing sits on the top edge, which the host app's
/// own bars can draw over.
struct KeyboardView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 0) {
            if model.hasFullAccess {
                Spacer(minLength: 12)
                KeyboardDictationPanel(model: model)
                Spacer(minLength: 6)
                KeyboardPersonaPicker(model: model)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                KeyboardFullAccessExplainer()
                    .padding(.top, 10)
                Spacer(minLength: 6)
            }
            KeyboardBottomRow(model: model)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Modes

private struct KeyboardPersonaPicker: View {
    let model: KeyboardModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.modes.prefix(3)) { mode in
                segment(mode)
            }
        }
        .padding(3)
        .background(KeyboardColors.functionKey, in: .capsule)
        .frame(maxWidth: 360)
        .disabled(model.phase.isActive)
        .opacity(model.phase.isActive ? 0.5 : 1)
    }

    private func segment(_ mode: Mode) -> some View {
        let isActive = mode.id == model.activeModeID
        return Button {
            model.selectMode(mode.id)
        } label: {
            Text(mode.name)
                .font(.footnote.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .background(isActive ? Color.accentColor : Color.clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isActive)
        .accessibilityLabel("\(mode.name) 模式")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Dictation

private struct KeyboardDictationPanel: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                sideSlot {
                    if model.phase.isActive {
                        KeyboardPillButton(title: "取消", systemImage: "xmark", action: model.cancelTapped)
                    }
                }
                Spacer(minLength: 8)
                KeyboardMicButton(phase: model.phase, external: model.dictation.external, action: model.micTapped)
                Spacer(minLength: 8)
                sideSlot {
                    if model.canUndo && !model.phase.isActive {
                        KeyboardPillButton(title: "復原", systemImage: "arrow.uturn.backward", action: model.undoTapped)
                    } else if model.dictation.showsEndSession {
                        Button(action: model.endSessionTapped) {
                            Image(systemName: "power")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 36, height: 36)
                                .background(KeyboardColors.functionKey, in: .circle)
                        }
                        .buttonStyle(KeyboardPressStyle())
                        .accessibilityLabel("結束 KVoice 聆聽")
                    }
                }
            }
            .padding(.horizontal, 12)
            KeyboardStatusLine(phase: model.phase, external: model.dictation.external, modeName: model.activeMode?.name)
        }
    }

    private func sideSlot(@ViewBuilder _ content: () -> some View) -> some View {
        // A fixed-width slot even when empty, so the mic stays centred.
        ZStack { Color.clear; content() }
            .frame(width: 104, height: 36)
    }
}

private struct KeyboardMicButton: View {
    let phase: KeyboardDictation.Phase
    let external: KeyboardDictation.External
    let action: () -> Void
    @State private var pulse = false

    private var isRecording: Bool {
        if case .recording = phase { return true }
        // The app records a dictation started elsewhere: the mic stops it.
        if !phase.isActive, case .appRecording = external { return true }
        return false
    }

    /// Another owner holds the microphone, or a job runs.
    private var isBlocked: Bool {
        if !phase.isActive, case .blocked = external { return true }
        return false
    }

    private var isBusy: Bool {
        switch phase {
        case .waitingForApp, .stopping, .transcribing, .formatting: true
        default: false
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.35), lineWidth: 6)
                        .scaleEffect(pulse ? 1.18 : 1)
                        .opacity(pulse ? 0 : 1)
                }
                Circle()
                    .fill(fill)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                if isBusy {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                } else if isRecording {
                    // The keyboard cannot hear the microphone, so the bars
                    // show that recording runs rather than the actual level.
                    KeyboardRecordingBars()
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 92, height: 92)
            .contentShape(Circle())
        }
        .buttonStyle(KeyboardPressStyle())
        .disabled(isProcessing || isBlocked)
        .accessibilityLabel(isRecording ? "Finish dictation" : "聽寫")
        .onChange(of: isRecording, initial: true) { _, recording in
            pulse = false
            guard recording else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    private var isProcessing: Bool {
        switch phase {
        case .stopping, .transcribing, .formatting: true
        default: false
        }
    }

    private var fill: Color {
        if isRecording { return .red }
        if isProcessing || isBlocked { return Color(uiColor: .systemGray) }
        return .accentColor
    }
}

private struct KeyboardRecordingBars: View {
    private let phases: [Double] = [0, 1.3, 0.6, 2.1, 0.9]

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(phases.indices, id: \.self) { index in
                    let level = 0.35 + 0.65 * abs(sin(time * 3.2 + phases[index]))
                    Capsule()
                        .fill(.white)
                        .frame(width: 5, height: 34 * level)
                }
            }
            .frame(height: 36)
        }
        .accessibilityHidden(true)
    }
}

private struct KeyboardStatusLine: View {
    let phase: KeyboardDictation.Phase
    let external: KeyboardDictation.External
    let modeName: String?

    var body: some View {
        Text(text)
            .font(.subheadline.weight(isError ? .medium : .regular))
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 20)
            .animation(.default, value: text)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var isError: Bool {
        if !phase.isActive, external != .none { return false }
        if case .failed = phase { return true }
        return false
    }

    private var text: String {
        if !phase.isActive {
            switch external {
            case .blocked(let message): return message
            case .appRecording: return "在 KVoice 錄音中…點一下結束"
            case .none: break
            }
        }
        return switch phase {
        case .idle:
            if let modeName { "就緒 · \(modeName)" } else { "就緒" }
        case .waitingForApp(_, .openedApp, _): "開啟 KVoice 中…"
        case .waitingForApp(_, .command, _): "啟動中…"
        case .recording: "錄音中…點一下結束"
        case .stopping, .transcribing: "轉錄中…"
        case .formatting: "整理中…"
        case .inserted: "已填入"
        case .failed(let message): message
        case .cancelled: "已取消"
        }
    }
}

private struct KeyboardPillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .foregroundStyle(Color.primary)
                .background(KeyboardColors.functionKey, in: .capsule)
        }
        .buttonStyle(KeyboardPressStyle())
    }
}

// MARK: - Full Access

private struct KeyboardFullAccessExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("請允許「完整取用」才能聽寫", systemImage: "lock.open")
                .font(.headline)
            Text("KVoice 在 App 裡錄音，再把文字輸入到這裡。鍵盤需要「完整取用」才能與 App 分享。你輸入的內容絕不會被儲存或傳送。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                step(1, "開啟「設定」›「一般」›「鍵盤」›「鍵盤」")
                step(2, "點 KVoice，並開啟「允許完整取用」")
                step(3, "回到這裡並點麥克風")
            }
            .font(.footnote)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }
}

// MARK: - Keys

private struct KeyboardBottomRow: View {
    let model: KeyboardModel

    var body: some View {
        HStack(spacing: 6) {
            if model.showsGlobeKey {
                KeyboardGlobeKey(model: model)
                    .frame(width: 46)
            }
            KeyboardKey(background: KeyboardColors.letterKey, action: model.insertSpace) {
                Text("空白").font(.callout)
            }
            .accessibilityLabel("空白")
            KeyboardRepeatingKey(action: model.deleteBackward) {
                Image(systemName: "delete.left").font(.system(size: 18))
            }
            .frame(width: 58)
            .accessibilityLabel("刪除")
            KeyboardKey(background: KeyboardColors.functionKey, action: model.insertReturn) {
                returnLabel
            }
            .frame(width: 88)
            .accessibilityLabel("換行")
        }
        .frame(height: 44)
    }

    @ViewBuilder private var returnLabel: some View {
        switch model.returnKeyType {
        case .go: Text("go").font(.callout)
        case .search, .google, .yahoo: Text("search").font(.callout)
        case .send: Text("send").font(.callout)
        case .done: Text("done").font(.callout)
        case .next: Text("next").font(.callout)
        case .join: Text("join").font(.callout)
        case .continue: Text("continue").font(.callout)
        case .route: Text("route").font(.callout)
        default: Image(systemName: "return").font(.system(size: 18))
        }
    }
}

private struct KeyboardKey<Label: View>: View {
    let background: Color
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            KeyboardKeyFace(background: background, content: label)
        }
        .buttonStyle(KeyboardPressStyle())
    }
}

private struct KeyboardKeyFace<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background, in: .rect(cornerRadius: 8))
            .shadow(color: KeyboardColors.keyShadow, radius: 0, y: 1)
            .contentShape(.rect)
    }
}

/// Delete: once on touch-down, then repeating while held.
private struct KeyboardRepeatingKey<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        KeyboardKeyFace(background: repeater == nil ? KeyboardColors.functionKey : KeyboardColors.letterKey, content: label)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in begin() }
                    .onEnded { _ in end() }
            )
            .onDisappear(perform: end)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func begin() {
        guard repeater == nil else { return }
        action()
        repeater = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func end() {
        repeater?.cancel()
        repeater = nil
    }
}

/// The globe key is a UIButton so the controller can attach
/// `handleInputModeList(from:with:)` (tap: next keyboard; long press: list).
private struct KeyboardGlobeKey: View {
    let model: KeyboardModel

    var body: some View {
        KeyboardKeyFace(background: KeyboardColors.functionKey) {
            Image(systemName: "globe").font(.system(size: 18))
        }
        .overlay { KeyboardInputModeButton(model: model) }
        .accessibilityLabel("下一個鍵盤")
    }
}

private struct KeyboardInputModeButton: UIViewRepresentable {
    let model: KeyboardModel

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        model.attachInputModeSwitch(to: button)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

private struct KeyboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

enum KeyboardColors {
    static let letterKey = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
    static let functionKey = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
    })
    static let keyShadow = Color(uiColor: UIColor { traits in
        UIColor(white: 0, alpha: traits.userInterfaceStyle == .dark ? 0.5 : 0.3)
    })
    /// The system keyboard backdrop, for hosts that don't provide one.
    static let backdrop = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.17, alpha: 1)
            : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
    })
}
