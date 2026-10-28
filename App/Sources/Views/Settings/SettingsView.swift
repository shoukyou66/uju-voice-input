import KVoiceKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.autoCopyKey, store: AppPreferences.store) private var autoCopy = true
    @AppStorage(AppPreferences.keepAliveMinutesKey, store: AppPreferences.store) private var keepAliveMinutes = 5
    @State private var confirmingDeleteHistory = false
    @State private var showsActionButton = AppPreferences.initialScreen == "actionButton"

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section("語音與 AI") {
                    NavigationLink {
                        TranscriptionSettingsView()
                    } label: {
                        SettingsRow(title: "轉錄", detail: settings.settings.defaultEngine.displayName,
                                    icon: "waveform", color: .blue)
                    }
                    NavigationLink {
                        AIProviderSettingsView()
                    } label: {
                        SettingsRow(title: "AI 整理", detail: settings.settings.defaultProvider.kind.displayName,
                                    icon: "sparkles", color: .purple)
                    }
                }

                Section {
                    Toggle("自動拷貝結果", isOn: $autoCopy)
                    Picker("讓鍵盤持續聆聽", selection: $keepAliveMinutes) {
                        ForEach(AppPreferences.keepAliveChoices, id: \.self) { minutes in
                            Text(minutes == 0 ? "關閉" : "\(minutes) 分鐘").tag(minutes)
                        }
                    }
                    .onChange(of: keepAliveMinutes) { _, minutes in
                        if minutes == 0 { model.handoff.endStandby() }
                    }
                } header: {
                    Text("聽寫")
                } footer: {
                    Text("從 KVoice 鍵盤聽寫後，KVoice 會在背景讓麥克風保持待命這麼久，讓鍵盤不用切換 App 就能開始下一次聽寫。等待期間，麥克風指示燈會一直亮著。")
                }

                Section {
                    Picker("保留歷史紀錄", selection: $settings.settings.retention.period) {
                        Text("永久").tag(RetentionPeriod.forever)
                        Text("30 天").tag(RetentionPeriod.days30)
                        Text("7 天").tag(RetentionPeriod.days7)
                    }
                    Toggle("保留錄音檔", isOn: $settings.settings.retention.keepsAudio)
                    Button("刪除所有歷史紀錄", role: .destructive) { confirmingDeleteHistory = true }
                } header: {
                    Text("歷史紀錄")
                } footer: {
                    Text("沒有錄音檔的話，歷史紀錄只會保留文字，聽寫也無法重新轉錄。")
                }
                .onChange(of: settings.settings.retention) {
                    Task { await model.applyRetention() }
                }

                Section("隨處聽寫") {
                    NavigationLink {
                        KeyboardSetupView()
                    } label: {
                        SettingsRow(title: "設定 KVoice 鍵盤", detail: nil, icon: "keyboard", color: .gray)
                    }
                    Button {
                        showsActionButton = true
                    } label: {
                        HStack {
                            SettingsRow(title: "動作按鈕", detail: nil, icon: "button.vertical.right.press", color: .orange)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("隱私") {
                    Label {
                        Text("錄音和逐字稿都只留在這個裝置上。除非你選擇雲端引擎或 AI 供應商，否則不會傳送任何資料；就算選了，也只有該次聽寫的文字或音訊會搭配你的金鑰送出。沒有分析追蹤，也不需要帳號。")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "lock.shield").foregroundStyle(.green)
                    }
                }

                Section("關於") {
                    LabeledContent("版本", value: Self.version)
                    LabeledContent("授權", value: "MIT")
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                }
            }
            .navigationTitle("設定")
            .navigationDestination(isPresented: $showsActionButton) { ActionButtonSetupView() }
            .confirmationDialog("要刪除所有歷史紀錄嗎？", isPresented: $confirmingDeleteHistory, titleVisibility: .visible) {
                Button("全部刪除", role: .destructive) {
                    Task {
                        try? await model.history?.deleteAll()
                        model.historyChanged()
                    }
                }
            } message: {
                Text("所有逐字稿和錄音都會從這個裝置移除。")
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

struct SettingsRow: View {
    let title: String
    let detail: String?
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: .rect(cornerRadius: 8))
            Text(title)
            Spacer()
            if let detail {
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct AIProviderSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                ProviderConfigurationFields(configuration: Binding(
                    get: { settings.settings.defaultProvider },
                    set: { configuration in
                        settings.settings.defaultProvider = configuration
                        settings.settings.providerConfigurations[configuration.kind] = configuration
                    }
                ))
            } header: {
                Text("預設供應商")
            } footer: {
                Text("AI 模式會使用它，除非模式自行指定。Apple Intelligence 在這個裝置上執行，不需要金鑰。其他供應商使用你自己的 API 金鑰，存放在這個裝置的鑰匙圈。")
            }

            Section {
                Text("純聽寫模式不會使用 AI，可離線使用。如果 AI 步驟失敗，KVoice 會保留逐字稿，你說的內容不會遺失。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI 整理")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TranscriptionSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let assets = model.assets
        let engine = settings.settings.defaultEngine
        Form {
            Section {
                ForEach(TranscriptionEngineSelection.Kind.allCases, id: \.self) { kind in
                    Button {
                        select(kind)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.displayName).foregroundStyle(.primary)
                                Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if engine.kind == kind {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                            }
                        }
                    }
                }
            } header: {
                Text("預設引擎")
            } footer: {
                Text("各個模式可以選擇自己的引擎。")
            }

            Section {
                if !AppleSpeechEngine.isAvailable {
                    Label("這部裝置無法使用裝置上的語音辨識。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("語言", value: Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier)
                    if let progress = assets.speechAssetProgress {
                        ProgressView(value: progress) { Text("正在下載語音模型…") }
                    } else {
                        switch assets.speechAssetStatus {
                        case .installed:
                            Label("語音模型已安裝", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .unsupported:
                            Label("不支援你的裝置語言。請在模式中選擇語言。", systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                        case .downloading:
                            Label("語音模型下載中。", systemImage: "arrow.down.circle")
                        case .supported, nil:
                            Button("下載語音模型", systemImage: "arrow.down.circle") {
                                Task { await assets.installSpeechAssets() }
                            }
                        }
                    }
                }
            } header: {
                Text("Apple Speech")
            } footer: {
                Text("Apple 的裝置上辨識器。每種語言第一次使用時會下載一個小型模型。")
            }

            Section {
                ForEach(WhisperModel.all) { whisper in
                    WhisperModelRow(
                        whisper: whisper,
                        isSelected: engine.kind == .whisper && (engine.whisperModelID ?? WhisperModel.base.id) == whisper.id,
                        onSelect: { settings.settings.defaultEngine = .whisper(whisper.id) }
                    )
                }
            } header: {
                Text("Whisper 模型")
            } footer: {
                Text("Whisper 在這個裝置上執行，支援 100 多種語言，會自動偵測語言，也能翻譯成英文。模型只需從 WhisperKit 模型庫下載一次。")
            }

            if engine.kind == .cloud {
                Section {
                    CloudTranscriptionFields(configuration: Binding(
                        get: { settings.settings.defaultEngine.cloud ?? CloudTranscriptionConfiguration(provider: .openAI) },
                        set: { settings.settings.defaultEngine = .cloud($0) }
                    ))
                } header: {
                    Text("雲端轉錄")
                } footer: {
                    Text("音訊會連同你的金鑰傳送給你選擇的供應商：OpenAI、Groq、Google AI Studio、Google Vertex AI，或任何相容 OpenAI 的 /audio/transcriptions 端點。Google 的供應商可接受長度約 \(GeminiTranscriptionEngine.maxAudioMinutes) 分鐘以內的錄音。")
                }
            }

            if engine.kind == .cloud, engine.cloud?.provider == .gemini {
                Section {
                    TextEditor(text: Binding(
                        get: { (settings.settings.vocabulary ?? []).joined(separator: "\n") },
                        set: { settings.settings.vocabulary = $0.components(separatedBy: .newlines) }
                    ))
                    .frame(minHeight: 160)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Text("自訂字典")
                } footer: {
                    Text("一行一個詞，例如人名、軟體名稱、專業用語。模型名稱含 transcribe 時（gemini-3.5-transcribe）會用 Smart 模式整理，並轉成台灣繁體。")
                }
            }
        }
        .navigationTitle("轉錄")
        .navigationBarTitleDisplayMode(.inline)
        .task { await assets.refresh() }
        .alert("下載失敗", isPresented: Binding(
            get: { assets.errorMessage != nil }, set: { if !$0 { assets.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(assets.errorMessage ?? "")
        }
    }

    private func select(_ kind: TranscriptionEngineSelection.Kind) {
        let settings = model.settings
        switch kind {
        case .appleSpeech:
            settings.settings.defaultEngine = .appleSpeech
        case .whisper:
            let installed = WhisperModel.all.first { model.assets.installedWhisperModels.contains($0.id) }
            settings.settings.defaultEngine = .whisper((installed ?? .base).id)
        case .cloud:
            settings.settings.defaultEngine = .cloud(
                settings.settings.defaultEngine.cloud ?? CloudTranscriptionConfiguration(provider: .gemini)
            )
        }
    }
}

struct WhisperModelRow: View {
    @Environment(AppModel.self) private var model
    let whisper: WhisperModel
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        let assets = model.assets
        let installed = assets.installedWhisperModels.contains(whisper.id)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(whisper.name).font(.body.weight(.medium))
                    Text("\(whisper.approximateSizeMB) MB").font(.caption).foregroundStyle(.secondary)
                }
                Text(whisper.summary).font(.caption).foregroundStyle(.secondary)
                if let progress = assets.whisperProgress[whisper.id] {
                    ProgressView(value: progress)
                        .padding(.top, 4)
                }
            }
            Spacer()
            if assets.isDownloading(whisper) {
                Button("取消", systemImage: "xmark.circle") { assets.cancelDownload(whisper) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            } else if installed {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.title3)
                } else {
                    Button("使用", action: onSelect).buttonStyle(.glass).controlSize(.small)
                }
            } else {
                Button("下載", systemImage: "arrow.down.circle") { assets.download(whisper) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .swipeActions {
            if installed {
                Button("刪除", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .contextMenu {
            if installed {
                Button("刪除模型", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .confirmationDialog("要刪除 \(whisper.name) 模型嗎？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("刪除", role: .destructive) { Task { await assets.delete(whisper) } }
        }
    }
}

extension TranscriptionEngineSelection.Kind {
    var summary: String {
        switch self {
        case .appleSpeech: "裝置上執行，除了小型系統模型外不需額外下載。"
        case .whisper: "裝置上執行，可下載模型，支援 100 多種語言。"
        case .cloud: "OpenAI、Groq、Google AI Studio、Vertex AI 或自訂端點，搭配你的 API 金鑰。"
        }
    }
}
