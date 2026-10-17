import Foundation
import Observation

struct MetricsBatch: Sendable {
    let snapshot: SystemSnapshot
    let processes: [ProcessSnapshot]
    let interpreted: InterpretedHealth
    /// Windowed history for the selected `HistoryWindow`.
    let historyPoints: [HistoryPoint]
    /// The five-minute slice, which the overview traces always show regardless
    /// of the selected window. Already computed to interpret the sample, so it
    /// ships alongside instead of being re-derived on the main thread.
    let recentPoints: [HistoryPoint]
}

@MainActor
@Observable
final class AppSession {
    var state: MeasurementState = .idle
    var current: SystemSnapshot?
    var processes: [ProcessSnapshot] = []
    var appGroups: [ProcessGroupStats] = []
    var interpreted: InterpretedHealth?
    var historyPoints: [HistoryPoint] = []
    var recentPoints: [HistoryPoint] = []
    var selectedWindow: HistoryWindow = .thirtyMinutes
    private(set) var isPaused = false

    /// Slow-changing surface for the menu bar label. The label draws only from
    /// these, never from `current`/`interpreted`: every change to a status
    /// item's content makes AppKit re-measure it (`_adjustLength`), re-render
    /// it and re-snapshot it into a bitmap, so a metrics string that moved on
    /// every sample made the menu bar redraw on every sample. The health tint
    /// stays live because a level change is rare and worth showing at once.
    private(set) var menuBarLevel: HealthLevel?
    private(set) var menuBarSnapshot: SystemSnapshot?
    private var lastMenuBarRefresh = Date.distantPast

    /// How often the menu bar numbers move: glanceable, not live.
    static let menuBarRefresh: TimeInterval = 15

    /// Sampling interval while the main window is off screen. Runtime-only:
    /// never written to `AppPreferences`, so it can never be persisted.
    static let backgroundSampleInterval: TimeInterval = 20

    let preferences: AppPreferences

    private let engine = MetricsEngine()
    private var readHolds: Set<UUID> = []
    private var isWindowVisible = true

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.selectedWindow = preferences.historyWindow
    }

    var cpuPercent: Double {
        current?.cpu.totalUsedPercent ?? 0
    }

    var usedBytes: UInt64 {
        current?.memory.usedBytes ?? 0
    }

    /// True while the reader is mid-read: a row under the pointer or an open
    /// glossary card. Publishing stops so nothing moves under them.
    var isReadHeld: Bool {
        !readHolds.isEmpty
    }

    func start() {
        guard state == .idle else { return }
        state = .measuring
        runEngine()
    }

    func stop() {
        engine.stop()
        state = .idle
    }

    func togglePaused() {
        isPaused.toggle()
        if isPaused {
            engine.stop()
        } else {
            runEngine()
        }
    }

    /// Holders are keyed per view and clear themselves when they disappear, so
    /// a row or card that leaves the hierarchy can never freeze the app.
    func setReadHold(_ id: UUID, _ held: Bool) {
        if held {
            readHolds.insert(id)
        } else {
            readHolds.remove(id)
        }
    }

    /// The interval the engine should run at right now: the user's choice
    /// while the window is visible, the slow background rate otherwise.
    private var effectiveSampleInterval: TimeInterval {
        isWindowVisible ? preferences.sampleInterval : Self.backgroundSampleInterval
    }

    /// Called by the window-visibility observer. While the window is off screen
    /// Wren samples far less often, so a hidden window costs almost nothing.
    func setWindowVisible(_ visible: Bool) {
        guard visible != isWindowVisible else { return }
        isWindowVisible = visible
        engine.setInterval(effectiveSampleInterval)
    }

    func setSampleInterval(_ interval: TimeInterval) {
        engine.setInterval(isWindowVisible ? interval : Self.backgroundSampleInterval)
    }

    func selectWindow(_ window: HistoryWindow) {
        selectedWindow = window
        engine.setHistoryWindow(window)
        if state == .active {
            historyPoints = engine.history(for: window)
        }
    }

    private func runEngine() {
        engine.setHistoryWindow(selectedWindow)
        engine.start(interval: effectiveSampleInterval) { [weak self] batch in
            Task { @MainActor [weak self] in
                self?.publish(batch)
            }
        }
    }

    private func publish(_ batch: MetricsBatch) {
        guard !isPaused && !isReadHeld else { return }
        current = batch.snapshot
        processes = batch.processes
        appGroups = ProcessGrouping.buildGroups(from: processes)
        interpreted = batch.interpreted
        historyPoints = batch.historyPoints
        recentPoints = batch.recentPoints
        updateMenuBar(with: batch)
        state = .active
    }

    private func updateMenuBar(with batch: MetricsBatch) {
        let level = batch.interpreted.level
        if level != menuBarLevel {
            menuBarLevel = level
        }
        let now = batch.snapshot.timestamp
        guard now.timeIntervalSince(lastMenuBarRefresh) >= Self.menuBarRefresh else { return }
        lastMenuBarRefresh = now
        menuBarSnapshot = batch.snapshot
    }
}

/// Runs sampling on a dedicated utility queue. Owns the timer and collectors.
private final class MetricsEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "metrics.collection", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 2
    private var historyWindow: HistoryWindow = .thirtyMinutes

    private let systemCollector = SystemMetricsCollector()
    private let ioCollector = IOMetricsCollector()
    private let powerCollector = PowerMetricsCollector()
    private let processCollector = ProcessMetricsCollector()
    private let store = MetricsHistoryStore()
    private let interpreter = HealthInterpreter()

    private var onBatch: (@Sendable (MetricsBatch) -> Void)?
    private var lastSampleTime: Date?
    private var isCollecting = false
    private var tickCount = 0
    private var cachedDisk: IORate?
    private var cachedNetwork: IORate?
    private var cachedPower: (thermal: ProcessInfo.ThermalState, lowPowerMode: Bool, battery: BatteryInfo?)?

    /// The IOKit registry scan, the network interface walk and the power-source
    /// read are the most expensive parts of a tick and change slowly, so refresh
    /// them every few ticks instead of on every sample. The rate collectors
    /// measure deltas from their previous call, so a skipped call simply makes the
    /// next rate span the longer window.
    private static let slowRefreshEvery = 3

    func start(interval: TimeInterval, onBatch: @escaping @Sendable (MetricsBatch) -> Void) {
        self.interval = interval
        self.onBatch = onBatch
        scheduleTimer(interval: interval)
    }

    func setInterval(_ interval: TimeInterval) {
        self.interval = interval
        // While stopped (paused), just remember the interval; the next start
        // schedules with it. Otherwise changing the interval would resume sampling.
        if timer != nil {
            scheduleTimer(interval: interval)
        }
    }

    func setHistoryWindow(_ window: HistoryWindow) {
        historyWindow = window
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func history(for window: HistoryWindow) -> [HistoryPoint] {
        store.points(for: window)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in
            self?.tick(now: Date())
        }
        timer = source
        source.resume()
    }

    private func tick(now: Date) {
        guard !isCollecting else { return }
        isCollecting = true
        defer { isCollecting = false }

        tickCount += 1
        // Refresh the expensive reads every few ticks, and always until we have a
        // usable baseline. In between, reuse the last values.
        let refreshSlow = tickCount % Self.slowRefreshEvery == 0
            || cachedDisk == nil || cachedNetwork == nil || cachedPower == nil

        let cpu = systemCollector.cpuCounters()
        if refreshSlow {
            if let disk = ioCollector.diskRate(at: now) { cachedDisk = disk }
            if let network = ioCollector.networkRate(at: now) { cachedNetwork = network }
            cachedPower = powerCollector.read()
        }
        let processesLimit = processCollector.processSnapshots(now: now)

        guard let cpu,
              let disk = cachedDisk,
              let network = cachedNetwork,
              let power = cachedPower,
              let processesLimit else {
            lastSampleTime = now
            return
        }

        let memory = systemCollector.memoryCounters()
        lastSampleTime = now

        let snapshot = SystemSnapshot(
            timestamp: now,
            uptime: ProcessInfo.processInfo.systemUptime,
            cpu: cpu,
            memory: memory,
            disk: disk,
            network: network,
            thermal: power.thermal,
            battery: power.battery,
            lowPowerMode: power.lowPowerMode
        )

        let processes = ProcessMetricsCollector.applyingAppMetadata(to: Self.topProcesses(from: processesLimit))

        let point = HistoryPoint(
            timestamp: now,
            cpuUsedPercent: cpu.totalUsedPercent,
            pressureRaw: memory.pressure.rawValue,
            swapUsedBytes: memory.swapUsedBytes,
            diskBytesPerSecond: disk.bytesPerSecondIn + disk.bytesPerSecondOut,
            networkBytesPerSecond: network.bytesPerSecondIn + network.bytesPerSecondOut
        )
        store.append(point)

        let fiveMinuteHistory = store.points(for: .fiveMinutes)
        let windowHistory = historyWindow == .fiveMinutes
            ? fiveMinuteHistory
            : store.points(for: historyWindow)
        let interpreted = interpreter.interpret(current: snapshot, processes: processes, history: fiveMinuteHistory)

        guard let onBatch else { return }
        onBatch(MetricsBatch(
            snapshot: snapshot,
            processes: processes,
            interpreted: interpreted,
            historyPoints: windowHistory,
            recentPoints: fiveMinuteHistory
        ))
    }

    /// Keep the top 25 by CPU and top 25 by memory, merged, for presentation.
    private static func topProcesses(from all: [ProcessSnapshot]) -> [ProcessSnapshot] {
        var byCPUSet = Set<Int32>()
        var merged: [ProcessSnapshot] = []
        for process in all.sorted(by: { $0.cpuPercent > $1.cpuPercent }).prefix(25) {
            byCPUSet.insert(process.id)
            merged.append(process)
        }
        for process in all.sorted(by: { $0.memoryBytes > $1.memoryBytes }).prefix(25) where !byCPUSet.contains(process.id) {
            merged.append(process)
        }
        return merged
    }
}
