import SwiftUI

struct EnergyView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppPreferences.self) private var preferences

    private var energyGroups: [ProcessGroupStats] {
        session.appGroups
            .filter { $0.energyNanojoulesDelta != nil }
            .sorted { ($0.energyNanojoulesDelta ?? 0) > ($1.energyNanojoulesDelta ?? 0) }
    }

    private var topGroup: ProcessGroupStats? {
        energyGroups.first(where: { ($0.energyNanojoulesDelta ?? 0) > 0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(title: "Energy")

                if let top = topGroup {
                    calloutCard(top)
                }

                if session.state != .active {
                    waitingState
                } else if energyGroups.isEmpty {
                    emptyState
                } else {
                    ledger
                }

                footnote
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
    }

    private func calloutCard(_ group: ProcessGroupStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProcessIconView(pid: group.pid ?? -1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Using the most energy right now")
                        .font(Typeface.label(11))
                        .foregroundStyle(Palette.inkSoft)
                    ProcessNameCell(name: group.name, bundleIdentifier: group.bundleIdentifier, font: Typeface.proseEmphasis(19))
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    MetricValue(
                        text: Formatters.watts(group.energyNanojoulesDelta, interval: preferences.sampleInterval),
                        font: Typeface.dataLarge(22),
                        color: Palette.ink
                    )
                    Text("drawn right now")
                        .font(Typeface.label(10.5))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            GaugeBar(fraction: topFraction(for: group), tint: Palette.accent)
        }
        .paperCard()
    }

    private func topFraction(for group: ProcessGroupStats) -> Double {
        guard let biggest = energyGroups.map({ $0.energyNanojoulesDelta ?? 0 }).max(), biggest > 0 else { return 0 }
        return Double(group.energyNanojoulesDelta ?? 0) / Double(biggest)
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerHeader {
                Text("App")
                    .font(Typeface.label(11))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text("Power draw")
                        .font(Typeface.label(11))
                        .foregroundStyle(Palette.inkSoft)
                    GlossaryGlyphButton(entry: MetricGlossary.energyWatts)
                }
                .frame(width: 118, alignment: .trailing)
            }

            // Lazy: only rows on screen are built and updated each sample.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(energyGroups) { group in
                    LedgerRow {
                        ProcessIconView(pid: group.pid ?? -1)
                        ProcessNameCell(
                            name: group.name,
                            bundleIdentifier: group.bundleIdentifier,
                            detail: group.processCount == 1 ? "1 process" : "\(group.processCount) processes",
                            font: Typeface.label(13)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        MetricValue(
                            text: Formatters.watts(group.energyNanojoulesDelta, interval: preferences.sampleInterval),
                            font: Typeface.data(12.5),
                            color: Palette.inkSoft
                        )
                        .frame(width: 106, alignment: .trailing)
                    }
                }
            }
        }
        .paperCard(padding: 8)
    }

    private var waitingState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Taking a reading\u{2026}")
                .font(Typeface.proseEmphasis(16))
                .foregroundStyle(Palette.ink)
            Text("Energy readings appear as soon as your Mac has been measured.")
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
        }
        .paperCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No energy readings available.")
                .font(Typeface.proseEmphasis(16))
                .foregroundStyle(Palette.ink)
            Text("Your Mac is not reporting per-app power draw at the moment.")
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
        }
        .paperCard()
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 6) {
            GlossaryGlyphButton(entry: MetricGlossary.energyWatts)
            Text("macOS reports power draw per app only on some Macs. On others it reports none (—) or 0 W.")
                .font(Typeface.prose(11.5))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}
