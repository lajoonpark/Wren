import SwiftUI

/// The wiki: a searchable, browsable explanation of the processes people see
/// and don't recognise. Reached from its own tab, or jumped to from a
/// "What is this?" button on a process row.
struct WikiView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrollTargetID: String?

    private var query: String {
        get { router.wikiQuery }
        nonmutating set { router.wikiQuery = newValue }
    }

    private var pinnedEntryID: String? {
        get { router.wikiPinnedEntryID }
        nonmutating set { router.wikiPinnedEntryID = newValue }
    }

    private var fallback: ProcessFallback? {
        get { router.wikiFallback }
        nonmutating set { router.wikiFallback = newValue }
    }

    private var results: [ProcessGlossarySearch.Match] {
        ProcessGlossarySearch.search(query)
    }

    private var displayedEntry: ProcessGlossaryEntry? {
        // A fallback supersedes the list entirely — otherwise the list would
        // highlight an entry we are not actually showing.
        guard fallback == nil else { return nil }
        if let pinnedEntryID, let pinned = ProcessGlossary.all.first(where: { $0.id == pinnedEntryID }) {
            return pinned
        }
        return results.first?.entry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(title: "The wiki")
            Text("Plain-English explanations for the things running on your Mac. Search by name, by part of a name, or just by what is going wrong.")
                .font(Typeface.prose(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            WikiSearchField(text: Binding(get: { query }, set: { query = $0 }))

            HStack(alignment: .top, spacing: 16) {
                listPane
                    .frame(width: 268)
                detailPane
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(Palette.paper)
        .animation(Motion.respecting(Motion.drift, reduceMotion: reduceMotion), value: displayedEntry?.id)
        .animation(Motion.respecting(Motion.drift, reduceMotion: reduceMotion), value: results.count)
        .onAppear {
            if router.wikiRequest?.id != router.handledWikiRequestID {
                handleRequest()
            }
        }
        .onChange(of: router.wikiRequest?.id) {
            pinnedEntryID = nil
            fallback = nil
            handleRequest()
        }
        .onChange(of: query) {
            pinnedEntryID = nil
            fallback = nil
        }
    }

    // MARK: - List

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            LedgerHeader {
                Text(query.isEmpty ? "All \(results.count) entries" : results.isEmpty ? "No matches" : "\(results.count) matching")
                    .font(Typeface.label(11))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if results.isEmpty {
                emptyResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { match in
                                WikiListRow(
                                    entry: match.entry,
                                    isSelected: match.entry.id == displayedEntry?.id
                                ) {
                                    pinnedEntryID = match.entry.id
                                    fallback = nil
                                }
                                .id(match.entry.id)
                            }
                        }
                    }
                    .onChange(of: scrollTargetID) {
                        guard let scrollTargetID else { return }
                        withAnimation(Motion.respecting(Motion.drift, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(scrollTargetID, anchor: .center)
                        }
                        self.scrollTargetID = nil
                    }
                }
            }
        }
        .background(Palette.paperCard)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.rule, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing here yet for that.")
                .font(Typeface.proseEmphasis(15))
                .foregroundStyle(Palette.ink)
            Text("This is a growing list, so the process you are after may not be written up yet. Try a shorter word, or just part of the name.")
                .font(Typeface.prose(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        ScrollView {
            if let fallback {
                FallbackCard(fallback: fallback)
            } else if let entry = displayedEntry {
                ProcessDetailCard(entry: entry)
            } else {
                pickSomething
            }
        }
    }

    private var pickSomething: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick a process on the left.")
                .font(Typeface.proseEmphasis(15))
                .foregroundStyle(Palette.ink)
            Text("Or type something in the box above — a name, part of a name, or what your Mac is doing.")
                .font(Typeface.prose(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard()
    }

    private func handleRequest() {
        guard let request = router.wikiRequest else { return }
        router.handledWikiRequestID = request.id
        query = ""
        if let entry = ProcessGlossarySearch.bestMatch(forName: request.name, bundleIdentifier: request.bundleIdentifier) {
            pinnedEntryID = entry.id
            fallback = nil
            scrollTargetID = entry.id
        } else {
            pinnedEntryID = nil
            fallback = ProcessFallback(name: request.name, bundleIdentifier: request.bundleIdentifier)
        }
    }
}

// MARK: - Requesting an explanation

/// What we can honestly say about a process that has no wiki entry.
struct ProcessFallback: Sendable {
    let name: String
    let bundleIdentifier: String?

    var guessedCategory: ProcessCategory? {
        ProcessGlossary.guessedCategory(forName: name, bundleIdentifier: bundleIdentifier)
    }
}

// MARK: - Rows and cards

private struct WikiListRow: View {
    let entry: ProcessGlossaryEntry
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            LedgerRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(Typeface.label(12.5))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(entry.category.rawValue)
                        .font(Typeface.label(10))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                (isSelected ? Palette.accent.opacity(0.12) : (isHovering ? Palette.ink.opacity(0.045) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.reveal) { isHovering = hovering }
        }
    }
}

struct ProcessDetailCard: View {
    let entry: ProcessGlossaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(Typeface.proseEmphasis(20))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.summary)
                    .font(Typeface.prose(15))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                CategoryChip(category: entry.category)
                SafetyChip(safeToQuit: entry.safeToQuit)
            }

            Text(entry.detail)
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Palette.rule)
                .frame(height: 1)

            Text(entry.safeToQuit.note)
                .font(Typeface.prose(13))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.aliases.isEmpty {
                MetaRow(label: "Also called", values: entry.aliases)
            }
            if !entry.knownFor.isEmpty {
                MetaRow(label: "Known for", values: entry.knownFor)
            }
            if !entry.bundleIdentifiers.isEmpty {
                MetaRow(label: "Identifier", values: entry.bundleIdentifiers, monospaced: true)
            }
        }
        .paperCard()
    }
}

private struct MetaRow: View {
    let label: String
    let values: [String]
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typeface.eyebrow())
                .tracking(1.1)
                .foregroundStyle(Palette.inkSoft)
            Text(values.joined(separator: "  ·  "))
                .font(monospaced ? Typeface.data(11) : Typeface.prose(12.5))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CategoryChip: View {
    let category: ProcessCategory

    var body: some View {
        Text(category.rawValue)
            .font(Typeface.label(11))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Palette.ink.opacity(0.07))
            )
            .overlay(
                Capsule().strokeBorder(Palette.rule, lineWidth: 1)
            )
            .help(category.blurb)
            .accessibilityLabel(category.rawValue)
            .accessibilityHint(category.blurb)
    }
}

private struct SafetyChip: View {
    let safeToQuit: SafeToQuit

    var body: some View {
        Text(safeToQuit.rawValue)
            .font(Typeface.label(11))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel(safeToQuit.rawValue)
            .accessibilityHint(safeToQuit.note)
    }

    private var tint: Color {
        switch safeToQuit {
        case .safe: return Palette.health(.normal)
        case .depends: return Palette.health(.moderateLoad)
        case .leaveAlone: return Palette.health(.potentialProblem)
        }
    }
}

/// The honest "we don't have this one" state. Never guesses at a name it
/// doesn't know, but still says what little it can.
struct FallbackCard: View {
    let fallback: ProcessFallback

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(fallback.name)
                    .font(Typeface.proseEmphasis(20))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("We don't have this one written up yet.")
                    .font(Typeface.prose(15))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let category = fallback.guessedCategory {
                VStack(alignment: .leading, spacing: 6) {
                    CategoryChip(category: category)
                    Text("Our guess only — it is not confirmed.")
                        .font(Typeface.prose(12.5))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(generalAdvice)
                .font(Typeface.prose(13.5))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if let bundleIdentifier = fallback.bundleIdentifier {
                MetaRow(label: "Identifier", values: [bundleIdentifier], monospaced: true)
            }
        }
        .paperCard()
    }

    private var generalAdvice: String {
        switch fallback.guessedCategory {
        case .thirdParty, .developer:
            return "This looks like part of something you installed. If you know which app it belongs to, quitting that app is the safest way to stop it. If you don't recognise it at all, it is worth checking what installed it before deleting anything."
        case .appleApp, .macOSCore, .backgroundTask, .security, .sync, .network, .media, .hardware:
            return "This looks like part of something Apple made, so it is very unlikely to be dangerous. If it is using a lot of processor or memory, quitting the app it belongs to is usually enough — macOS will start it again when it is needed."
        case nil:
            return "There is not enough here to say what this is. As a rule of thumb, names that are all lowercase and end in a 'd' are background services macOS runs for itself, and are not worth quitting. Anything you can match to an app you opened is safe to quit along with that app."
        }
    }
}

struct WikiSearchField: View {
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkSoft)

            TextField("Search — try \"tabs\", \"fan loud\", or \"fileproviderd\"", text: $text)
                .textFieldStyle(.plain)
                .font(Typeface.prose(14))
                .foregroundStyle(Palette.ink)
                .focused($isFocused)
                .accessibilityLabel("Search the wiki")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkSoft.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.paperCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(isFocused ? Palette.accent.opacity(0.5) : Palette.rule, lineWidth: 1)
        )
    }
}
