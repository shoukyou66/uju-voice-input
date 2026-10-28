import KVoiceKit
import SwiftUI

/// The on-device diagnostics log (no transcripts or keys, only lengths and
/// flags) and the Toggle Dictation start strategy, for TestFlight testing.
struct DiagnosticsView: View {
    @State private var entries: [DiagnosticsLog.Entry] = []
    @State private var strategy = ToggleStartStrategy.current()

    var body: some View {
        List {
            Section {
                Picker("啟動方式", selection: $strategy) {
                    Text("立即回傳").tag(ToggleStartStrategy.returnImmediately)
                    Text("持續到停止").tag(ToggleStartStrategy.holdUntilStopped)
                }
                .onChange(of: strategy) { _, value in ToggleStartStrategy.set(value) }
            } header: {
                Text("切換聽寫")
            } footer: {
                Text("「持續到停止」會讓捷徑在錄音期間保持執行，以防 iOS 只把麥克風借給執行中的捷徑。")
            }

            Section("紀錄（最新在前）") {
                if entries.isEmpty {
                    Text("空白").foregroundStyle(.secondary)
                }
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.category) · \(entry.date.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.message).font(.callout.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("全部拷貝", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = entries.map(Self.line).joined(separator: "\n")
                }
                Button("清除", systemImage: "trash", role: .destructive) {
                    DiagnosticsLog.shared.clear()
                    reload()
                }
            }
        }
        .refreshable { reload() }
        .onAppear { reload() }
    }

    private func reload() {
        entries = DiagnosticsLog.shared.read().reversed()
    }

    private static func line(_ entry: DiagnosticsLog.Entry) -> String {
        "\(entry.date.formatted(.iso8601)) [\(entry.category)] \(entry.message)"
    }
}
