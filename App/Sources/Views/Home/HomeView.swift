import KVoiceKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.autoCopyKey, store: AppPreferences.store) private var autoCopy = true
    @State private var levels = WaveformView.silentLevels
    @State private var rerunError: String?
    @State private var isRerunning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    ModeChips()
                    recorder
                    if let result = model.currentResult, !model.pipeline.isBusy {
                        ResultCard(
                            result: result,
                            isRerunning: isRerunning,
                            onRerun: { mode in rerun(result, with: mode) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.smooth, value: model.currentResult?.record.id)
                .animation(.smooth, value: model.pipeline.isBusy)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("KVoice")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $autoCopy) {
                        Label("自動拷貝", systemImage: autoCopy ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                    }
                    .toggleStyle(.button)
                    .accessibilityHint("自動把每次的結果拷貝到剪貼簿")
                }
            }
            .onChange(of: model.pipeline.level) { _, level in
                levels.removeFirst()
                levels.append(CGFloat(level))
            }
            .onChange(of: model.isRecording) { _, recording in
                if !recording { withAnimation(.smooth) { levels = WaveformView.silentLevels } }
            }
            .alert("重新執行失敗", isPresented: Binding(get: { rerunError != nil }, set: { if !$0 { rerunError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(rerunError ?? "")
            }
        }
    }

    private var recorder: some View {
        VStack(spacing: 20) {
            WaveformView(levels: levels, isActive: model.isRecording)
                .frame(height: 64)
                .padding(.top, 12)

            RecordButton(
                isRecording: model.isRecording,
                isBusy: model.pipeline.isBusy && !model.isRecording,
                level: CGFloat(model.pipeline.level),
                onStart: { Task { await model.startDictation() } },
                onStop: { Task { await model.stopDictation() } }
            )

            PhaseStatus(autoCopy: autoCopy)
                .frame(minHeight: 44, alignment: .top)

            if model.pipeline.isBusy {
                Button("取消", role: .cancel) { model.cancelDictation() }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rerun(_ result: DictationResult, with mode: Mode) {
        isRerunning = true
        Task {
            defer { isRerunning = false }
            do {
                try await model.rerun(result.record, with: mode, preferAudio: false)
            } catch {
                rerunError = error.localizedDescription
            }
        }
    }
}

/// What the pipeline is doing, in words.
struct PhaseStatus: View {
    @Environment(AppModel.self) private var model
    let autoCopy: Bool

    var body: some View {
        Group {
            switch model.pipeline.phase {
            case .idle:
                if model.handoff.effectivePhase.recordingOwner == .shortcut {
                    // Shortcuts' Record Audio owns the microphone.
                    VStack(spacing: 8) {
                        Label(DictationActivity.Message.shortcutRecordingApp, systemImage: "button.vertical.right.press")
                            .foregroundStyle(.orange)
                        Button("沒在錄音？重設") { model.handoff.resetShortcut() }
                            .font(.footnote)
                    }
                } else if let notice = model.notice {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Text("按住說話，或點一下開始、再點一下結束。")
                        .foregroundStyle(.secondary)
                }
            case .recording:
                Label("聆聽中 · \(model.pipeline.recordingMode?.name ?? model.modes.activeMode.name)",
                      systemImage: "waveform")
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            case .transcribing:
                HStack(spacing: 8) { ProgressView(); Text("轉錄中…") }
            case .formatting:
                HStack(spacing: 8) { ProgressView(); Text("整理中…") }
            case .done:
                Label(autoCopy ? "完成 · 已拷貝到剪貼簿" : "完成", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .animation(.smooth, value: model.pipeline.phase)
    }
}
