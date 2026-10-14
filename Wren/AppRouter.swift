import Foundation
import Observation

enum AppTab: String, Sendable {
    case overview, apps, energy, history, advanced, wiki, settings
}

enum AppsSortKey: Sendable { case name, cpu, memory }

/// Where a "What is this?" click wants the wiki to land. Identified so that
/// clicking the same process twice still re-focuses the wiki.
struct WikiRequest: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String?
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .overview
    var wikiRequest: WikiRequest?
    /// The request the wiki last acted on, so re-opening the tab doesn't
    /// replay an old "What is this?" over the reader's own browsing.
    var handledWikiRequestID: UUID?

    // Per-tab choices live here rather than in view `@State`: only the
    // selected tab is kept in the hierarchy, and these should survive a
    // trip to another tab.
    var appsSortKey: AppsSortKey = .cpu
    var appsSortAscending = false
    var advancedSortAscending = false
    var wikiQuery = ""
    var wikiPinnedEntryID: String?
    var wikiFallback: ProcessFallback?

    func openWiki(forName name: String, bundleIdentifier: String? = nil) {
        wikiRequest = WikiRequest(name: name, bundleIdentifier: bundleIdentifier)
        selectedTab = .wiki
    }
}
