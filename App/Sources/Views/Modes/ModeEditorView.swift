import KVoiceKit
import SwiftUI

struct ModeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Mode
    @State private var showingSymbols = false
    @State private var errorMessage: String?
    let isNew: Bool

    init(mode: Mode, isNew: Bool) {
        _draft = State(initialValue: mode)
        self.isNew = isNew
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Button {
                        showingSymbols = true
                    } label: {
                        Image(systemName: draft.icon)
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(Color.accentColor)
                            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("圖示")
                    TextField("名稱", text: $draft.name)
                        .font(.title3.weight(.medium))
                }
            }

            Section {
                Picker("類型", selection: $draft.kind) {
                    Text("AI 整理").tag(Mode.Kind.aiFormat)
                    Text("純聽寫").tag(Mode.Kind.plainDictation)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(draft.usesAI
                     ? "逐字稿會由你的 AI 供應商依照下方的指示改寫。"
                     : "逐字稿會照你說的原樣填入。可離線使用，不需要 AI。")
            }

            if draft.usesAI {
                Section("提詞") {
                    TextEditor(text: $draft.instructions)
                        .frame(minHeight: 160)
                        .font(.callout)
                }
            }

            Section {
                Picker("口說語言", selection: $draft.language) {
                    Text("自動偵測").tag(String?.none)
                    ForEach(LanguageOptions.tags, id: \.self) { tag in
                        Text(LanguageOptions.name(for: tag)).tag(Optional(tag))
                    }
                }
                Toggle("輸出為英文", isOn: $draft.translateToEnglish)
            } header: {
                Text("語言")
            } footer: {
                Text("Apple 語音辨識無法自動偵測語言，會使用這裡的語言或你的裝置語言。開啟「輸出為英文」時，Whisper 會邊轉錄邊翻譯。")
            }

            Section {
                Toggle("使用不同的 AI 供應商", isOn: Binding(
                    get: { draft.providerOverride != nil },
                    set: { draft.providerOverride = $0 ? model.settings.settings.defaultProvider : nil }
                ))
                .disabled(!draft.usesAI)
                if let override = draft.providerOverride, draft.usesAI {
                    ProviderConfigurationFields(configuration: Binding(
                        get: { override },
                        set: { draft.providerOverride = $0 }
                    ))
                }
            } header: {
                Text("AI 供應商")
            } footer: {
                Text("否則會使用「設定」裡的預設值。所有模式共用 API 金鑰。")
            }

            Section {
                Toggle("使用不同的引擎", isOn: Binding(
                    get: { draft.engineOverride != nil },
                    set: { draft.engineOverride = $0 ? model.settings.settings.defaultEngine : nil }
                ))
                if let override = draft.engineOverride {
                    EngineSelectionFields(selection: Binding(
                        get: { override },
                        set: { draft.engineOverride = $0 }
                    ))
                }
            } header: {
                Text("轉錄")
            }
        }
        .navigationTitle(isNew ? "新增模式" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存", systemImage: "checkmark", role: .confirm) { save() }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $showingSymbols) {
            SymbolPicker(selection: $draft.icon)
        }
        .alert("無法儲存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            try model.modes.save(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A grid of SF Symbols suited to modes.
struct SymbolPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    static let symbols = [
        "mic", "text.bubble", "sparkles", "message", "envelope", "list.bullet", "text.append",
        "globe", "doc.text", "note.text", "pencil", "pencil.and.scribble", "checklist",
        "lightbulb", "briefcase", "graduationcap", "book", "quote.bubble", "bubble.left.and.bubble.right",
        "person.2", "phone", "calendar", "cart", "heart", "star", "bolt", "brain", "wand.and.stars",
        "chevron.left.forwardslash.chevron.right", "terminal", "number", "character.book.closed",
        "translate", "megaphone", "hand.wave", "face.smiling", "paperplane", "tag", "flag", "house"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button {
                            selection = symbol
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.title2)
                                .frame(width: 56, height: 56)
                                .foregroundStyle(symbol == selection ? Color.white : Color.primary)
                                .background(
                                    symbol == selection ? Color.accentColor : Color.secondary.opacity(0.12),
                                    in: .rect(cornerRadius: 14)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
                .padding()
            }
            .navigationTitle("圖示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
