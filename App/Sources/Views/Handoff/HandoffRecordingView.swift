import KVoiceKit
import SwiftUI

/// Shown when the keyboard opens KVoice to dictate: recording has started,
/// the user swipes back to their app (or stops here).
struct HandoffRecordingView: View {
    @Environment(AppModel.self) private var model
    @State private var levels = WaveformView.silentLevels

    var body: some View {
        let pipeline = model.pipeline
        VStack(spacing: 28) {
            Spacer()

            let mode = pipeline.recordingMode ?? model.handoff.sessionMode ?? model.modes.activeMode
            Label(mode.name, systemImage: mode.icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

            VStack(spacing: 10) {
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            WaveformView(levels: levels, isActive: model.isRecording)
                .frame(height: 72)
                .padding(.horizontal, 32)

            if model.isRecording {
                swipeBackHint
            }

            Spacer()

            controls
                .padding(.bottom, 24)
        }
        .padding()
        .onChange(of: pipeline.level) { _, level in
            levels.removeFirst()
            levels.append(CGFloat(level))
        }
        .animation(.smooth, value: pipeline.phase)
    }

    private var title: String {
        switch model.pipeline.phase {
        case .recording: "錄音中"
        case .transcribing: "轉錄中…"
        case .formatting: "整理中…"
        case .done: "完成"
        case .failed: "發生錯誤"
        case .idle: "已停止"
        }
    }

    private var subtitle: String {
        switch model.pipeline.phase {
        case .recording: "滑回你的 App 繼續說話。說完後，點鍵盤上或這裡的停止鈕。"
        case .transcribing, .formatting: "文字會輸入到你的 App 裡。"
        case .done: "回到你的 App：KVoice 鍵盤會自動輸入文字。"
        case .failed(let error): error.localizedDescription
        case .idle: "沒有錄到任何聲音。"
        }
    }

    private var swipeBackHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward")
            Text("從螢幕底部邊緣往右滑，或點左上角的返回按鈕")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var controls: some View {
        let pipeline = model.pipeline
        if model.isRecording {
            VStack(spacing: 16) {
                Button {
                    Task { await model.stopDictation() }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.red).interactive(), in: .circle)
                .accessibilityLabel("停止聽寫")

                Button("取消", role: .cancel) { model.cancelDictation() }
                    .buttonStyle(.glass)
            }
        } else if pipeline.isBusy {
            ProgressView().controlSize(.large)
        } else {
            Button("關閉") { model.handoff.isPresentingRecorder = false }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
    }
}
