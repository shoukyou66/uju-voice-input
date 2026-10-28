import KVoiceKit
import SwiftUI

/// The custom vocabulary sent with Gemini smart transcription: terms as
/// removable chips, and a field that adds one or several at once.
struct VocabularyView: View {
    @Environment(AppModel.self) private var model
    @State private var entry = ""

    private var terms: [String] { Self.unique(model.settings.settings.vocabulary ?? []) }

    var body: some View {
        Form {
            Section {
                TextField("例如：雷姆、甘雨、ComfyUI", text: $entry, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("加入", systemImage: "plus.circle.fill", action: add)
                    .disabled(Self.split(entry).isEmpty)
            } footer: {
                Text("可以一次打好幾個詞，用換行、「、」或「，」隔開。WAN2.2 這種詞本身有點，所以不用「.」分隔。")
            }

            Section {
                if terms.isEmpty {
                    Text("還沒有詞。把常被聽錯的人名、軟體名稱、專業用語加進來。")
                        .foregroundStyle(.secondary)
                } else {
                    ChipFlowLayout(spacing: 8) {
                        ForEach(terms, id: \.self) { term in
                            chip(term)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("已加入 \(terms.count) 個詞")
            } footer: {
                Text("放詞就好，不用放句子。大約 100 個以內效果最好，最多 1,000 個。")
            }
        }
        .navigationTitle("自訂字典")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ term: String) -> some View {
        HStack(spacing: 4) {
            Text(term)
                .font(.callout)
                .lineLimit(1)
            Button {
                remove(term)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("刪除 \(term)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15), in: .capsule)
    }

    private func add() {
        let added = Self.split(entry)
        guard !added.isEmpty else { return }
        model.settings.settings.vocabulary = Self.unique(terms + added)
        entry = ""
    }

    private func remove(_ term: String) {
        model.settings.settings.vocabulary = terms.filter { $0 != term }
    }

    /// Terms typed or pasted together. Not split on "." (WAN2.2) or spaces
    /// (Claude Code).
    static func split(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n\r、，,；;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func unique(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Lays chips out left to right, wrapping to new rows.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
