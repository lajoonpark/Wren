import SwiftUI

struct HistoryView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // One decimation per update feeds all five charts.
        let points = session.historyPoints.decimatedForDrawing()
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if points.isEmpty {
                    emptyState
                } else {
                    ChartCard(title: "Processor use", entry: MetricGlossary.cpu, note: "How busy your Mac has been. Spikes are normal; a line that stays near the top is worth a look.") {
                        CPUHistoryChart(points: points)
                            .frame(height: 130)
                    }
                    ChartCard(title: "Memory pressure", entry: MetricGlossary.memoryPressure, note: "The measure that actually matters for memory. As long as it stays near the bottom, your Mac has room.") {
                        PressureHistoryChart(points: points)
                            .frame(height: 130)
                    }
                    ChartCard(title: "Disk-backed memory (swap)", entry: MetricGlossary.swap, note: "Data macOS parked on your disk because RAM was busy. A flat line is fine; a steep climb means your Mac is short on memory.") {
                        SwapHistoryChart(points: points)
                            .frame(height: 130)
                    }
                    ChartCard(title: "Disk activity", entry: MetricGlossary.diskRead, note: "Files being read and written. Bursts usually mean something is opening, saving or being indexed.") {
                        ThroughputChart(points: points, keyPath: \.diskBytesPerSecond, tint: Palette.accent)
                            .frame(height: 130)
                    }
                    ChartCard(title: "Network activity", entry: MetricGlossary.networkDown, note: "Data coming in and going out. A hump here is usually a download, a call or a backup.") {
                        ThroughputChart(points: points, keyPath: \.networkBytesPerSecond, tint: Palette.accent)
                            .frame(height: 130)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
        .animation(Motion.respecting(Motion.drift, reduceMotion: reduceMotion), value: session.selectedWindow)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "History")
            HStack {
                Picker("Period", selection: Binding(
                    get: { session.selectedWindow },
                    set: { session.selectWindow($0) }
                )) {
                    ForEach(HistoryWindow.allCases, id: \.self) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Spacer()
                Text(periodNote)
                    .font(Typeface.prose(12.5))
                    .foregroundStyle(Palette.inkSoft)
            }
        }
    }

    private var periodNote: String {
        switch session.selectedWindow {
        case .fiveMinutes: return "Every reading, as it happened."
        case .thirtyMinutes: return "Averaged over ten-second windows."
        case .twoHours: return "Averaged over thirty-second windows."
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not enough history yet.")
                .font(Typeface.proseEmphasis(16))
                .foregroundStyle(Palette.ink)
            Text("Charts appear once your Mac has been watched for a few minutes. Leave the app open and they will fill in.")
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard()
    }
}

// MARK: - Card

private struct ChartCard<Content: View>: View {
    let title: String
    let entry: GlossaryEntry
    let note: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GlossaryLabel(entry: entry, title: title, font: Typeface.heading(13.5), tint: Palette.ink)
                Spacer()
            }
            content
            Text(note)
                .font(Typeface.prose(11.5))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard()
    }
}
