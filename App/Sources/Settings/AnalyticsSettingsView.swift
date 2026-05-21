import SwiftUI

/// Settings tab that shows local reading stats and the master
/// opt-in toggle.
struct AnalyticsSettingsView: View {
    @Bindable var stats: ReadingStats = .shared

    var body: some View {
        Form {
            Section {
                Toggle("Record reading stats on this Mac", isOn: $stats.isEnabled)
            } header: {
                Text("Privacy")
            } footer: {
                Text("All stats are stored locally in your user defaults. Nothing leaves this Mac — ReadAloudTTS has no analytics endpoint.")
                    .foregroundStyle(.secondary)
            }

            if stats.isEnabled {
                Section("Today") {
                    statRow("Words read", value: "\(stats.todayWords)")
                    statRow("Time", value: format(seconds: stats.todaySeconds))
                }

                Section("All time") {
                    statRow("Words read", value: "\(stats.totalWords)")
                    statRow("Time", value: format(seconds: stats.totalSeconds))
                    statRow("Words / minute", value: String(format: "%.0f", stats.wordsPerMinute))
                    statRow("Current streak", value: stats.currentStreak == 1 ? "1 day" : "\(stats.currentStreak) days")
                }

                Section {
                    Button("Reset counters", role: .destructive) {
                        stats.resetCounters()
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analytics are off")
                            .font(ReadAloudTTSFont.serif(16))
                        Text("Turn on the toggle above to start recording time spent and words read.")
                            .font(ReadAloudTTSFont.ui(12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func statRow(_ label: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
        } label: {
            Text(label)
        }
    }

    private func format(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}
