import KVoiceKit
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var records: [HistoryRecord] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.day) { section in
                    Section(section.title) {
                        ForEach(section.records) { record in
                            NavigationLink(value: record) {
                                HistoryRow(record: record)
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { section.records[$0] })
                        }
                    }
                }
            }
            .overlay {
                if loaded && records.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView(
                            "還沒有聽寫紀錄", systemImage: "clock.arrow.circlepath",
                            description: Text(model.history == nil
                                              ? "此裝置無法使用歷史紀錄。"
                                              : "你的聽寫會顯示在這裡，包含錄音和逐字稿。")
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationTitle("歷史紀錄")
            .navigationDestination(for: HistoryRecord.self) { record in
                HistoryDetailView(record: record)
            }
            .searchable(text: $query, prompt: "搜尋逐字稿")
            .task(id: TaskKey(query: query, revision: model.historyRevision)) {
                await load()
            }
        }
    }

    private struct TaskKey: Equatable {
        var query: String
        var revision: Int
    }

    private struct DaySection {
        var day: Date
        var title: String
        var records: [HistoryRecord]
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = "今天"
            } else if calendar.isDateInYesterday(day) {
                title = "昨天"
            } else {
                title = day.formatted(.dateTime.weekday(.wide).month().day())
            }
            return DaySection(day: day, title: title, records: grouped[day] ?? [])
        }
    }

    private func load() async {
        guard let history = model.history else {
            loaded = true
            return
        }
        // Debounce typing.
        if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
        guard !Task.isCancelled else { return }
        records = (try? await history.search(query)) ?? []
        loaded = true
    }

    private func delete(_ doomed: [HistoryRecord]) {
        records.removeAll { record in doomed.contains { $0.id == record.id } }
        Task {
            for record in doomed { try? await model.history?.delete(id: record.id) }
            model.historyChanged()
        }
    }
}

struct HistoryRow: View {
    let record: HistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch record.status {
            case .done:
                Text(record.formattedText)
                    .lineLimit(2)
            case .pending:
                Label("等待轉錄", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("未轉錄：\(record.failureMessage ?? "failed")", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(record.modeName)
                Text("·")
                Text(record.date, style: .time)
                if record.audioFileName != nil {
                    Image(systemName: "waveform").accessibilityLabel("有錄音")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
