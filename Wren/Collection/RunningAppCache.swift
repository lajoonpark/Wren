import AppKit
import Foundation

/// Resolves `NSRunningApplication` once per process instead of once per tick.
///
/// Both the lookup and the icon extraction are expensive relative to the
/// sample period, and neither changes for the life of a process:
/// `NSRunningApplication(processIdentifier:)` scans the LaunchServices
/// registration, `localizedName` makes a synchronous XPC round-trip to
/// LaunchServices, and `icon` reads file metadata off disk. Resolution runs
/// on the sampling queue instead of the main thread, so those round-trips
/// never block the UI: each PID is resolved at most once, with the icon
/// resolved eagerly on first sight and cached for `lifetime`. Views read the
/// cached icon with `icon(for:)` on the main thread, which never touches
/// LaunchServices.
///
/// Ageing out matters because macOS recycles PIDs: a stale entry could
/// otherwise describe an unrelated app. Evicting on every sample was the wrong
/// trade — the top-of-list pools churn constantly (transient workers enter and
/// leave), so per-sample eviction re-paid the full resolution cost for
/// returning PIDs on nearly every tick. Five minutes bounds the PID-reuse risk
/// while keeping re-resolution rare.
final class RunningAppCache: @unchecked Sendable {
    struct Entry: Sendable {
        var localizedName: String?
        var bundleIdentifier: String?
        var isApplication: Bool
    }

    static let shared = RunningAppCache()

    private let lock = NSLock()

    private struct Slot {
        /// Resolved metadata, or nil when the PID has no `NSRunningApplication`.
        var entry: Entry?
        /// Resolved eagerly on first sight, along with the metadata.
        var icon: NSImage?
        var lastSeen: Date
    }

    private static let lifetime: TimeInterval = 300

    private var cache: [Int32: Slot] = [:]

    /// Resolves app metadata, and on first sight the icon, for a process. Runs
    /// on the sampling queue for the batch's processes: `NSRunningApplication` is
    /// thread-safe for property reads, and an NSImage may be created on a
    /// background thread and handed to the main thread to draw - so the
    /// LaunchServices round-trip and icon read never touch the main thread.
    func entry(for pid: Int32) -> Entry? {
        guard pid > 0 else { return nil }
        lock.lock()
        if let slot = cache[pid] {
            cache[pid]?.lastSeen = Date()
            lock.unlock()
            return slot.entry
        }
        lock.unlock()

        let app = NSRunningApplication(processIdentifier: pid)
        let slot = Slot(
            entry: app.map { Entry(
                localizedName: $0.localizedName,
                bundleIdentifier: $0.bundleIdentifier,
                isApplication: $0.activationPolicy == .regular
            ) },
            icon: app?.icon,
            lastSeen: Date()
        )
        lock.lock()
        cache[pid] = slot
        lock.unlock()
        return slot.entry
    }

    /// Main-thread read of the icon already resolved by `entry(for:)`. Never
    /// performs a LaunchServices lookup, so a view body can call it freely.
    func icon(for pid: Int32) -> NSImage? {
        guard pid > 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return cache[pid]?.icon
    }

    /// Drops entries that have not been seen for `lifetime`. Callers keep the
    /// cache warm simply by asking for the PIDs they display.
    func prune() {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.lastSeen) <= Self.lifetime }
    }
}
