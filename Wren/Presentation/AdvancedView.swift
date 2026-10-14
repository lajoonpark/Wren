import SwiftUI

struct AdvancedView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var processSortAscending: Bool {
        get { router.advancedSortAscending }
        nonmutating set { router.advancedSortAscending = newValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let snapshot = session.current {
                    Text("The raw numbers behind the Overview. Every name here can be clicked for a plain-English explanation.")
                        .font(Typeface.prose(13))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    metricSection(
                        "Processor",
                        rows: [
                            (MetricGlossary.cpu, Formatters.percent(snapshot.cpu.totalUsedPercent)),
                            (MetricGlossary.cpuUserSystem, "\(Formatters.percent(snapshot.cpu.userPercent)) / \(Formatters.percent(snapshot.cpu.systemPercent))"),
                            (MetricGlossary.cpuIdle, Formatters.percent(snapshot.cpu.idlePercent)),
                            (MetricGlossary.uptime, Formatters.duration(snapshot.uptime)),
                        ]
                    )

                    metricSection(
                        "Memory",
                        rows: [
                            (MetricGlossary.memory, Formatters.bytes(snapshot.memory.usedBytes)),
                            (MetricGlossary.freeMemory, Formatters.bytes(snapshot.memory.freeBytes)),
                            (MetricGlossary.activeMemory, Formatters.bytes(snapshot.memory.activeBytes)),
                            (MetricGlossary.inactiveMemory, Formatters.bytes(snapshot.memory.inactiveBytes)),
                            (MetricGlossary.wiredMemory, Formatters.bytes(snapshot.memory.wiredBytes)),
                            (MetricGlossary.compressedMemory, Formatters.bytes(snapshot.memory.compressedBytes)),
                            (MetricGlossary.purgeableMemory, Formatters.bytes(snapshot.memory.purgeableBytes)),
                            (MetricGlossary.internalMemory, Formatters.bytes(snapshot.memory.internalBytes)),
                            (MetricGlossary.externalMemory, Formatters.bytes(snapshot.memory.externalBytes)),
                            (MetricGlossary.memoryPressure, pressureLabel(snapshot.memory.pressure)),
                            (MetricGlossary.swap, Formatters.bytes(snapshot.memory.swapUsedBytes)),
                            (MetricGlossary.swapTotal, Formatters.bytes(snapshot.memory.swapTotalBytes)),
                        ]
                    )

                    metricSection(
                        "Disk and network",
                        rows: [
                            (MetricGlossary.diskRead, Formatters.rate(snapshot.disk.bytesPerSecondIn)),
                            (MetricGlossary.diskWrite, Formatters.rate(snapshot.disk.bytesPerSecondOut)),
                            (MetricGlossary.networkDown, Formatters.rate(snapshot.network.bytesPerSecondIn)),
                            (MetricGlossary.networkUp, Formatters.rate(snapshot.network.bytesPerSecondOut)),
                        ]
                    )

                    metricSection(
                        "Power and heat",
                        rows: powerRows(snapshot)
                    )

                    processTable
                } else {
                    Text("Measuring\u{2026}")
                        .font(Typeface.prose(15))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .paperCard()
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
        .animation(Motion.respecting(Motion.drift, reduceMotion: reduceMotion), value: processSortAscending)
    }

    // MARK: - Metric sections

    private func metricSection(_ title: String, rows: [(GlossaryEntry, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: title)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    MetricRow(entry: row.0, value: row.1, showRule: index > 0)
                }
            }
            .paperCard(padding: 6)
        }
    }

    private func powerRows(_ snapshot: SystemSnapshot) -> [(GlossaryEntry, String)] {
        var rows: [(GlossaryEntry, String)] = [
            (MetricGlossary.thermalState, snapshot.thermal.description),
            (MetricGlossary.lowPowerMode, snapshot.lowPowerMode ? "On" : "Off"),
        ]
        if let battery = snapshot.battery {
            rows.append((MetricGlossary.battery, "\(battery.percent)%"))
            rows.append((MetricGlossary.charging, battery.isCharging ? "Yes" : "No"))
            rows.append((MetricGlossary.powerSource, battery.isOnAC ? "Power adapter" : "Battery"))
        }
        return rows
    }

    private func pressureLabel(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .urgent: return "Urgent"
        case .critical: return "Critical"
        case .unknown: return "Unavailable"
        }
    }

    // MARK: - Processes

    private var sortedProcesses: [ProcessSnapshot] {
        let processes = session.processes
        return processSortAscending
            ? processes.sorted { $0.cpuPercent < $1.cpuPercent }
            : processes.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private var processTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(title: "Processes")
            VStack(alignment: .leading, spacing: 0) {
                LedgerHeader {
                    HStack(spacing: 4) {
                        Text("PID")
                            .font(Typeface.label(11))
                            .foregroundStyle(Palette.inkSoft)
                        GlossaryGlyphButton(entry: MetricGlossary.pid)
                    }
                    .frame(width: 64, alignment: .trailing)
                    Text("Name")
                        .font(Typeface.label(11))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SortableHeader(title: "CPU", entry: MetricGlossary.cpuApp, isActive: true, isAscending: processSortAscending, width: 74) {
                        processSortAscending.toggle()
                    }
                    HStack(spacing: 4) {
                        Text("Memory")
                            .font(Typeface.label(11))
                            .foregroundStyle(Palette.inkSoft)
                        GlossaryGlyphButton(entry: MetricGlossary.residentMemory)
                    }
                    .frame(width: 110, alignment: .trailing)
                }

                // Lazy: only rows on screen are built and updated each sample.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedProcesses) { process in
                        LedgerRow {
                            Text("\(process.id)")
                                .font(Typeface.data(11.5))
                                .monospacedDigit()
                                .foregroundStyle(Palette.inkSoft)
                                .frame(width: 52, alignment: .trailing)
                            ProcessNameCell(name: process.name, bundleIdentifier: process.bundleIdentifier)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            MetricValue(text: Formatters.percent(process.cpuPercent), font: Typeface.data(12))
                                .frame(width: 62, alignment: .trailing)
                            MetricValue(text: Formatters.bytes(process.memoryBytes), font: Typeface.data(12), color: Palette.inkSoft)
                                .frame(width: 98, alignment: .trailing)
                        }
                    }
                }
            }
            .paperCard(padding: 8)
        }
    }
}

private struct MetricRow: View {
    let entry: GlossaryEntry
    let value: String
    let showRule: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showRule {
                Rectangle()
                    .fill(Palette.rule)
                    .frame(height: 1)
                    .padding(.leading, 12)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                GlossaryLabel(entry: entry, font: Typeface.label(12.5), tint: Palette.ink)
                Spacer(minLength: 16)
                MetricValue(text: value, font: Typeface.data(12.5), color: Palette.ink)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
        }
    }
}

extension ProcessInfo.ThermalState {
    var description: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
