import KVoiceKit
import SwiftUI

struct ModesView: View {
    @Environment(AppModel.self) private var model
    @State private var newMode: Mode?
    @State private var confirmingReset = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.modes.modes) { mode in
                        NavigationLink(value: mode.id) {
                            ModeRow(mode: mode, isActive: mode.id == model.modes.activeModeID)
                        }
                        .swipeActions(edge: .leading) {
                            Button("使用", systemImage: "checkmark.circle") {
                                try? model.modes.setActiveMode(id: mode.id)
                            }
                            .tint(.accentColor)
                        }
                        .deleteDisabled(mode.isBuiltIn)
                    }
                    .onMove { source, destination in
                        perform { try model.modes.move(fromOffsets: source, toOffset: destination) }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { model.modes.modes[$0].id }
                        perform { for id in ids { try model.modes.delete(id: id) } }
                    }
                } footer: {
                    Text("鍵盤上會顯示前三個，就是你的三個個性。點進去可以改名字和提詞；「Smart」只用 Gemini Smart 整理，其他個性會再照提詞改寫一次。按住右側可以拖曳換順序。")
                }

                Section {
                    Button("重設內建模式", systemImage: "arrow.counterclockwise", role: .destructive) {
                        confirmingReset = true
                    }
                }
            }
            .navigationTitle("模式")
            .navigationDestination(for: UUID.self) { id in
                if let mode = model.modes.mode(id: id) {
                    ModeEditorView(mode: mode, isNew: false)
                }
            }
            .sheet(item: $newMode) { mode in
                NavigationStack {
                    ModeEditorView(mode: mode, isNew: true)
                }
            }
            .confirmationDialog(
                "要重設內建模式嗎？", isPresented: $confirmingReset, titleVisibility: .visible
            ) {
                Button("重設", role: .destructive) { perform { try model.modes.resetBuiltIns() } }
            } message: {
                Text("你對內建模式的修改會被還原成原始內容。自訂模式會保留。")
            }
            .alert("無法儲存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

struct ModeRow: View {
    let mode: Mode
    let isActive: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.icon)
                .font(.title3)
                .foregroundStyle(isActive ? Color.white : Color.accentColor)
                .frame(width: 40, height: 40)
                .background(isActive ? Color.accentColor : Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                Text("使用中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [mode.usesAI ? "AI" : "純聽寫"]
        parts.append(mode.language.map(LanguageOptions.name(for:)) ?? "任何語言")
        if mode.translateToEnglish { parts.append("翻成英文") }
        if !mode.isBuiltIn { parts.append("自訂") }
        return parts.joined(separator: " · ")
    }
}
