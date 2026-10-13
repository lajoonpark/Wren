import SwiftUI

struct AppsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var pendingGroup: ProcessGroupStats?
    @State private var quitError: String?
    @State private var rows: [ProcessGroupStats] = []

    typealias SortKey = AppsSortKey

    private var sortKey: SortKey {
        get { router.appsSortKey }
        nonmutating set { router.appsSortKey = newValue }
    }

    private var sortAscending: Bool {
        get { router.appsSortAscending }
        nonmutating set { router.appsSortAscending = newValue }
    }

    /// Sorted only when a new batch arrives (see `recomputeRows`), never from
    /// `body` — sorting per render made every layout pass re-sort the ledger.
    private func sortedGroups() -> [ProcessGroupStats] {
        let groups = session.appGroups
        switch sortKey {
        case .name:
            return groups.sorted { sortAscending ? $0.name < $1.name : $0.name > $1.name }
        case .cpu:
            return groups.sorted { sortAscending ? $0.cpuPercent < $1.cpuPercent : $0.cpuPercent > $1.cpuPercent }
        case .memory:
            return groups.sorted { sortAscending ? $0.memoryBytes < $1.memoryBytes : $0.memoryBytes > $1.memoryBytes }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(title: "What's using your Mac")

                if session.state != .active {
                    waitingState
                } else if session.appGroups.isEmpty {
                    emptyState
                } else {
                    Text("Every app is grouped together with the pieces it runs underneath, so the list reads the way you think about your Mac.")
                        .font(Typeface.prose(13))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    ledger
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
        .onAppear { recomputeRows() }
        .onChange(of: session.appGroups) { _, _ in recomputeRows() }
        .onChange(of: sortKey) { _, _ in recomputeRows() }
        .onChange(of: sortAscending) { _, _ in recomputeRows() }
        .alert("Quit \(pendingGroup?.name ?? "")?", isPresented: Binding(
            get: { pendingGroup != nil || quitError != nil },
            set: { if !$0 { pendingGroup = nil; quitError = nil } }
        )) {
            if quitError != nil {
                Button("OK", role: .cancel) { quitError = nil }
            } else {
                Button("Cancel", role: .cancel) { pendingGroup = nil }
                Button("Quit", role: .destructive) {
                    if let group = pendingGroup {
                        ProcessActions.quit(group: group) { error in
                            quitError = error
                        }
                    }
                    pendingGroup = nil
                }
            }
        } message: {
            if quitError != nil {
                Text("The system could not quit this process.")
            } else {
                Text("Unfinished work in \(pendingGroup?.name ?? "") may be lost.")
            }
        }
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerHeader {
                SortableHeader(title: "App", entry: MetricGlossary.processes, isActive: sortKey == .name, isAscending: sortAscending) {
                    toggle(.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SortableHeader(title: "CPU", entry: MetricGlossary.cpuApp, isActive: sortKey == .cpu, isAscending: sortAscending, width: 74) {
                    toggle(.cpu)
                }
                SortableHeader(title: "Memory", entry: MetricGlossary.memoryApp, isActive: sortKey == .memory, isAscending: sortAscending, width: 96) {
                    toggle(.memory)
                }
                Text(" ")
                    .frame(width: 62)
            }

            ForEach(rows) { group in
                AppRow(group: group) {
                    pendingGroup = group
                }
                .equatable()
            }
        }
        .paperCard(padding: 8)
    }

    /// Rows snap to their new rank: reordering happens on nearly every sample,
    /// and animating per-sample churn keeps the render loop redrawing at
    /// display refresh (see `Motion`). A row that has just arrived fades
    /// itself in via `AppRow`; one that leaves simply goes.
    private func recomputeRows() {
        rows = sortedGroups()
    }

    private var waitingState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Taking a reading\u{2026}")
                .font(Typeface.proseEmphasis(16))
                .foregroundStyle(Palette.ink)
            Text("Your apps appear as soon as your Mac has been measured.")
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
        }
        .paperCard()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No apps to show yet.")
                .font(Typeface.proseEmphasis(16))
                .foregroundStyle(Palette.ink)
            Text("The list fills in as soon as your Mac has been measured.")
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
        }
        .paperCard()
    }

    private func toggle(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = (key == .name)
        }
    }
}

private struct AppRow: View, Equatable {
    let group: ProcessGroupStats
    let onQuit: () -> Void

    /// Identity is the group alone. `onQuit` is a closure, so without this
    /// SwiftUI sees every row as new on every sample and re-lays-out the whole
    /// ledger even when only a few rows actually moved.
    static func == (lhs: AppRow, rhs: AppRow) -> Bool {
        lhs.group == rhs.group
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        LedgerRow {
            ProcessIconView(pid: group.pid ?? -1)

            ProcessNameCell(
                name: group.name,
                bundleIdentifier: group.bundleIdentifier,
                detail: caption,
                font: Typeface.label(13)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            MetricValue(text: Formatters.percent(group.cpuPercent), font: Typeface.data(12.5))
                .frame(width: 62, alignment: .trailing)
            MetricValue(text: Formatters.bytes(group.memoryBytes), font: Typeface.data(12.5), color: Palette.inkSoft)
                .frame(width: 84, alignment: .trailing)

            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .font(Typeface.label(11))
                .foregroundStyle(Palette.health(.potentialProblem))
                .padding(.init(top: 3, leading: 8, bottom: 3, trailing: 8))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.health(.potentialProblem).opacity(isHovering ? 0.14 : 0))
                )
                .frame(width: 54)
                .opacity(isHovering ? 1 : 0)
                .disabled(ProcessActions.isProtected(group: group))
                .help(ProcessActions.isProtected(group: group) ? "This app can't be quit from here." : "Quit \(group.name)")
                .accessibilityHidden(!isHovering)
        }
        .onHover { hovering in
            withAnimation(Motion.reveal) { isHovering = hovering }
        }
    }

    private var caption: String {
        var parts: [String] = []
        parts.append(group.processCount == 1 ? "1 process" : "\(group.processCount) processes")
        if group.isApplication { parts.append("App") }
        return parts.joined(separator: "  \u{00B7}  ")
    }
}
