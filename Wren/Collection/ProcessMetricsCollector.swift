import AppKit
import Darwin
import Foundation

struct ProcessCPUSample: Equatable {
    let pid: Int32
    let totalTicks: UInt64
}

enum EnergyDelta {
    static func nanojoules(previous: UInt64?, current: UInt64?) -> UInt64? {
        guard let previous, let current, current >= previous else { return nil }
        return current - previous
    }
}

enum CPUPercent {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Fraction of one core (as a percentage) used by `current` since `previous`.
    /// Returns nil when there is no baseline or the interval is unusable.
    static func percent(previous: ProcessCPUSample?, current: ProcessCPUSample, interval: TimeInterval) -> Double? {
        guard let previous, interval > 0, current.totalTicks >= previous.totalTicks else { return nil }
        let delta = current.totalTicks - previous.totalTicks
        let seconds = (Double(delta) * Double(timebase.numer)) / (Double(timebase.denom) * 1_000_000_000)
        let coresUsed = seconds / interval
        return min(max(coresUsed * 100, 0), 100)
    }
}

/// Samples every process on the machine, twice over: a cheap pass that ranks
/// everyone, then an expensive pass that only touches the handful we will show.
///
/// `proc_pidinfo` is cheap enough to run across all PIDs. `proc_pidpath` and
/// `proc_pid_rusage` are not — running them for 500+ processes every tick was
/// the single largest cost in the collection path. The UI only ever shows the
/// top 25 by CPU and the top 25 by memory, so detail is fetched for a small
/// candidate pool and everything else is never touched.
final class ProcessMetricsCollector: @unchecked Sendable {
    /// Cheap data: everything `proc_pidinfo` reports in one call.
    private struct RawSample {
        let pid: Int32
        let userTicks: UInt64
        let systemTicks: UInt64
        let residentBytes: UInt64
        let parentPid: Int32?
    }

    /// Expensive data, fetched only for the candidate pool.
    private struct DetailSample {
        let path: String
        let footprintBytes: UInt64?
        let energyNanojoules: UInt64?
    }

    private struct ProcessPreviousSample: Equatable {
        let totalTicks: UInt64
        let energyNanojoules: UInt64?
    }

    private var previousSamples: [Int32: ProcessPreviousSample] = [:]
    private var previousTime: Date?

    /// The UI shows 25 by CPU and 25 by memory. The memory pool is deliberately
    /// larger: the cheap pass can only rank by resident size, while the number
    /// on screen is the physical footprint, and the two can order differently.
    private static let cpuPoolSize = 25
    private static let memoryPoolSize = 40

    /// Returns nil on the first call so the caller can discard the baseline sample.
    func processSnapshots(now: Date) -> [ProcessSnapshot]? {
        let cheap = Self.collectCheapSamples()
        var details: [Int32: DetailSample] = [:]
        defer {
            previousSamples = Dictionary(uniqueKeysWithValues: cheap.map {
                ($0.pid, ProcessPreviousSample(
                    totalTicks: $0.userTicks + $0.systemTicks,
                    energyNanojoules: details[$0.pid]?.energyNanojoules
                ))
            })
            previousTime = now
        }

        guard let previousTime, !previousSamples.isEmpty else { return nil }
        let interval = now.timeIntervalSince(previousTime)
        guard interval > 0 else { return nil }

        let pool = Self.candidatePIDs(from: cheap, previous: previousSamples, interval: interval)
        details = Self.collectDetails(for: pool)

        let cheapByPID = Dictionary(uniqueKeysWithValues: cheap.map { ($0.pid, $0) })
        return pool.sorted().compactMap { pid -> ProcessSnapshot? in
            guard let raw = cheapByPID[pid] else { return nil }
            let previous = previousSamples[raw.pid]
            let currentSample = ProcessCPUSample(pid: raw.pid, totalTicks: raw.userTicks + raw.systemTicks)
            let previousSample = previous.map { ProcessCPUSample(pid: raw.pid, totalTicks: $0.totalTicks) }
            let percent = CPUPercent.percent(previous: previousSample, current: currentSample, interval: interval) ?? 0
            let detail = details[raw.pid]
            return ProcessSnapshot(
                id: raw.pid,
                name: Self.pathBaseName(detail?.path ?? ""),
                bundleIdentifier: nil,
                parentPid: raw.parentPid,
                cpuPercent: percent,
                residentBytes: raw.residentBytes,
                footprintBytes: detail?.footprintBytes,
                energyNanojoulesDelta: EnergyDelta.nanojoules(previous: previous?.energyNanojoules, current: detail?.energyNanojoules),
                isApplication: false
            )
        }
    }

    /// Applies AppKit metadata (display name, bundle ID, is-application) to a batch of
    /// snapshots. Runs on the sampling queue so the LaunchServices lookup and the
    /// icon read stay off the main thread: `NSRunningApplication` is thread-safe for
    /// property reads, and an NSImage may be created off-main for later main-thread
    /// drawing.
    static func applyingAppMetadata(to processes: [ProcessSnapshot]) -> [ProcessSnapshot] {
        let cache = RunningAppCache.shared
        cache.prune()
        return processes.map { process in
            let app = cache.entry(for: process.id)
            return ProcessSnapshot(
                id: process.id,
                name: app?.localizedName ?? process.name,
                bundleIdentifier: app?.bundleIdentifier,
                parentPid: process.parentPid,
                cpuPercent: process.cpuPercent,
                residentBytes: process.residentBytes,
                footprintBytes: process.footprintBytes,
                energyNanojoulesDelta: process.energyNanojoulesDelta,
                isApplication: app?.isApplication ?? false
            )
        }
    }

    /// Cheap pass: one `proc_pidinfo` per PID, no path or rusage lookups.
    private static func collectCheapSamples() -> [RawSample] {
        // `proc_listpids` takes and returns byte counts, not element counts.
        let byteCapacity = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCapacity > 0 else { return [] }
        var buffer = [Int32](repeating: 0, count: Int(byteCapacity) / MemoryLayout<Int32>.size)
        guard !buffer.isEmpty else { return [] }

        let byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &buffer, Int32(buffer.count * MemoryLayout<Int32>.size)
        )
        guard byteCount > 0 else { return [] }
        let count = min(Int(byteCount) / MemoryLayout<Int32>.size, buffer.count)

        var samples: [RawSample] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let pid = buffer[i]
            guard pid > 0 else { continue }
            guard let info = taskAllInfo(for: pid) else { continue }
            samples.append(RawSample(
                pid: pid,
                userTicks: info.ptinfo.pti_total_user,
                systemTicks: info.ptinfo.pti_total_system,
                residentBytes: info.ptinfo.pti_resident_size,
                parentPid: Int32(info.pbsd.pbi_ppid)
            ))
        }
        return samples
    }

    /// Ranks everyone with data the cheap pass already has, then keeps the union
    /// of the top CPU and top memory candidates.
    private static func candidatePIDs(from cheap: [RawSample], previous: [Int32: ProcessPreviousSample], interval: TimeInterval) -> Set<Int32> {
        var selected = Set<Int32>()
        selected.reserveCapacity(cpuPoolSize + memoryPoolSize)

        if interval > 0 {
            var byCPU: [(pid: Int32, percent: Double)] = []
            byCPU.reserveCapacity(cheap.count)
            for raw in cheap {
                let previousSample = previous[raw.pid].map { ProcessCPUSample(pid: raw.pid, totalTicks: $0.totalTicks) }
                let percent = CPUPercent.percent(
                    previous: previousSample,
                    current: ProcessCPUSample(pid: raw.pid, totalTicks: raw.userTicks + raw.systemTicks),
                    interval: interval
                ) ?? 0
                byCPU.append((raw.pid, percent))
            }
            for entry in topK(byCPU, cpuPoolSize, by: { $0.percent > $1.percent }) {
                selected.insert(entry.pid)
            }
        }

        for raw in topK(cheap, memoryPoolSize, by: { $0.residentBytes > $1.residentBytes }) {
            selected.insert(raw.pid)
        }
        return selected
    }

    /// The `k` highest-ranked elements without sorting the whole input.
    ///
    /// `sorted(by:).prefix(k)` ranks every element and copies the result, twice
    /// per tick across every PID on the machine. `best` holds at most `k`
    /// survivors ranked best-first, so the common case is a single comparison
    /// that rejects the candidate outright.
    ///
    /// Internal rather than private so the selection contract stays pinned down
    /// by `TopKSelectionTests`.
    static func topK<T>(_ input: [T], _ k: Int, by isBetter: (T, T) -> Bool) -> [T] {
        guard k > 0 else { return [] }
        var best: [T] = []
        best.reserveCapacity(min(k, input.count))
        for element in input {
            if best.count == k, !isBetter(element, best[k - 1]) { continue }
            let position = best.firstIndex(where: { isBetter(element, $0) }) ?? best.count
            best.insert(element, at: position)
            if best.count > k { best.removeLast() }
        }
        return best
    }

    private static func collectDetails(for pids: Set<Int32>) -> [Int32: DetailSample] {
        var details: [Int32: DetailSample] = [:]
        details.reserveCapacity(pids.count)
        for pid in pids {
            let rusage = rusageSample(for: pid)
            details[pid] = DetailSample(
                path: executablePath(for: pid),
                footprintBytes: rusage.footprintBytes,
                energyNanojoules: rusage.energyNanojoules
            )
        }
        return details
    }

    private static func taskAllInfo(for pid: Int32) -> proc_taskallinfo? {
        var info = proc_taskallinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, Int32(MemoryLayout<proc_taskallinfo>.size))
        guard size == MemoryLayout<proc_taskallinfo>.size else { return nil }
        return info
    }

    /// Reads the process's physical footprint and lifetime energy in one
    /// `proc_pid_rusage` call, or nils when the platform does not report them
    /// (protected processes, unsupported builds). Uses a caller-allocated
    /// struct buffer; the `void**` import style is avoided because some
    /// macOS builds return an unreadable kernel pointer from it.
    private static func rusageSample(for pid: Int32) -> (footprintBytes: UInt64?, energyNanojoules: UInt64?) {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            let slot = unsafeBitCast(pointer, to: UnsafeMutablePointer<rusage_info_t?>.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_V6, slot)
        }
        guard result == 0 else { return (nil, nil) }
        return (info.ri_phys_footprint, info.ri_energy_nj)
    }

    private static func executablePath(for pid: Int32) -> String {
        var path = [CChar](repeating: 0, count: 4096)
        let size = proc_pidpath(pid, &path, UInt32(path.count))
        guard size > 0, let string = String(validatingUTF8: path) else { return "" }
        return string
    }

    private static func pathBaseName(_ path: String) -> String {
        if path.isEmpty { return "System process" }
        return (path as NSString).lastPathComponent
    }
}
