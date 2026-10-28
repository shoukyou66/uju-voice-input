import AVFoundation
import KVoiceKit
import SwiftUI

/// First launch: microphone, engine, optional AI, keyboard.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void

    enum Step: Int, CaseIterable { case welcome, microphone, engine, ai, keyboard, actionButton }
    @State private var step: Step = .welcome
    @State private var micGranted = AudioRecorder.hasPermission

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .padding(24)
        }
        .animation(.smooth, value: step)
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            OnboardingPage(
                icon: "waveform", title: "歡迎使用 KVoice",
                text: "說一次，就能在任何 App 得到整理好的文字。KVoice 在你的裝置上轉錄，還能把你說的話整理成訊息、電子郵件或筆記。"
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Feature(icon: "lock.shield", text: "預設注重隱私：錄音只會留在這個裝置上。")
                    Feature(icon: "square.stack.3d.up", text: "各種文字都有對應的模式，也可以選不用 AI 的純聽寫。")
                    Feature(icon: "keyboard", text: "一個讓每個 App 都能聽寫的鍵盤。")
                }
            }
        case .microphone:
            OnboardingPage(
                icon: "mic.fill", title: "麥克風",
                text: "KVoice 只在你聽寫時才會聆聽。麥克風開啟時，畫面上會顯示麥克風指示燈。"
            ) {
                if micGranted {
                    Label("麥克風權限已開啟", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    Button("允許使用麥克風", systemImage: "mic") {
                        Task { micGranted = await AudioRecorder.requestPermission() }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        case .engine:
            OnboardingPage(
                icon: "text.bubble", title: "語音辨識",
                text: "選擇語音轉成文字的方式。之後隨時可以在「設定」更改，也可以用你自己的 OpenAI、Groq、Google AI Studio 或 Google Vertex AI 金鑰使用雲端轉錄。"
            ) {
                EngineChoice()
            }
        case .ai:
            OnboardingPage(
                icon: "sparkles", title: "AI 整理（選用）",
                text: "AI 模式會把你說的話改寫成乾淨的文字。可以使用裝置上的 Apple Intelligence，或在「設定」加入你自己的 OpenAI、Anthropic、Google AI Studio (Gemini)、Google Vertex AI、Groq、OpenRouter 或其他相容服務的金鑰。"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    AppleIntelligenceStatus()
                    Text("純聽寫不需要 AI 也能使用。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        case .keyboard:
            OnboardingPage(
                icon: "keyboard", title: "加入 KVoice 鍵盤",
                text: "用 KVoice 鍵盤在任何 App 裡聽寫。"
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    KeyboardSetupSteps()
                    OpenSettingsButton()
                        .buttonStyle(.glass)
                }
            }
        case .actionButton:
            OnboardingPage(
                icon: "button.vertical.right.press", title: "動作按鈕（選用）",
                text: "不用切到 KVoice，就能在任何 App 聽寫。之後可以到「設定」›「動作按鈕」設定。"
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    ActionButtonExplainer()
                    ActionButtonSetupSteps()
                }
                .onAppear { JobNotifier.requestAuthorization() }
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("返回") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    .buttonStyle(.glass)
            }
            Spacer()
            Button(step == Step.allCases.last ? "開始聽寫" : "繼續") {
                if let next = Step(rawValue: step.rawValue + 1) { step = next } else { onFinish() }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}

private struct OnboardingPage<Accessory: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 84, height: 84)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.top, 24)
            Text(title).font(.largeTitle.bold())
            Text(text).font(.body).foregroundStyle(.secondary)
            accessory.padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Feature: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
        }
    }
}

/// Apple Speech or a Whisper model, from onboarding.
private struct EngineChoice: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        let assets = model.assets
        VStack(spacing: 12) {
            option(
                title: "Apple Speech", detail: "內建、速度快，不用下載大型檔案。",
                selected: settings.settings.defaultEngine.kind == .appleSpeech
            ) {
                settings.settings.defaultEngine = .appleSpeech
                Task { await assets.installSpeechAssets() }
            }
            option(
                title: "Whisper Base", detail: "裝置上執行，支援 100 多種語言，需下載 \(WhisperModel.base.approximateSizeMB) MB。",
                selected: settings.settings.defaultEngine.kind == .whisper
            ) {
                settings.settings.defaultEngine = .whisper(WhisperModel.base.id)
                assets.download(.base)
            }
            if let progress = assets.whisperProgress[WhisperModel.base.id] {
                ProgressView(value: progress) { Text("正在下載 Whisper Base…").font(.caption) }
            } else if let progress = assets.speechAssetProgress {
                ProgressView(value: progress) { Text("正在下載語音模型…").font(.caption) }
            }
        }
        .task { await assets.refresh() }
    }

    private func option(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor.opacity(0.25)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 20))
    }
}
