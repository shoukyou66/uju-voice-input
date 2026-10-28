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
                    Text("模式會把你說的話整理成完成的格式。向右滑可啟用某個模式；內建模式可以編輯與重設。")
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新增模式", systemImage: "plus") {
                        newMode = Mode(name: "", icon: "text.bubble", instructions: "")
                    }
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
