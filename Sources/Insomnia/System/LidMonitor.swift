import Foundation
import Observation

enum LidDirection: String, Equatable {
    case unknown, stationary, opening, closing
}

struct LidState: Equatable {
    let angle: Double
    let direction: LidDirection
    let speed: Double
    let timestamp: Date
}

/// A median of three rejects a lone spike. The motion anchor accumulates
/// small steps so slow movement can still exceed the 1° sensor jitter.
struct LidMotionFilter {
    private var samples: [Double] = []
    private var anchor: (angle: Double, time: TimeInterval)?
    private var lastSampleTime: TimeInterval?
    private var direction: LidDirection = .unknown
    private var speed: Double = 0
    private var lastMotion: TimeInterval?

    mutating func push(_ angle: Double, at uptime: TimeInterval, timestamp: Date) -> LidState? {
        guard (0...180).contains(angle) else {
            self = Self()
            return nil
        }
        if let lastSampleTime, uptime <= lastSampleTime || uptime - lastSampleTime > 0.3 {
            self = Self()
        }
        lastSampleTime = uptime
        samples.append(angle)
        guard samples.count == 3 else { return nil }
        let filtered = samples.sorted()[1]
        samples.removeFirst()

        if let anchor {
            let delta = filtered - anchor.angle
            if abs(delta) >= 2 {
                direction = delta > 0 ? .opening : .closing
                speed = delta / (uptime - anchor.time)
                lastMotion = uptime
                self.anchor = (filtered, uptime)
            } else if uptime - (lastMotion ?? anchor.time) >= 0.25 {
                direction = .stationary
                speed = 0
            }
        } else {
            anchor = (filtered, uptime)
        }
        return LidState(angle: filtered, direction: direction, speed: speed, timestamp: timestamp)
    }
}

enum LidMonitorStatus: Equatable {
    case stopped, waiting, suspended, available, unavailable(LidReadError)
}

struct LidDiagnostics: Equatable {
    var status: LidMonitorStatus = .stopped
    var state: LidState?
    var readingsPerSecond: Double?
    var changesPerSecond: Double?
    var readErrors = 0
    var lastRead: Date?
}

@MainActor
@Observable
final class LidMonitor {
    private(set) var diagnostics = LidDiagnostics()
    @ObservationIgnored var onSample: ((LidState?) -> Void)?
    @ObservationIgnored private let source: any LidAngleReading
    @ObservationIgnored private let wait: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var filter = LidMotionFilter()
    @ObservationIgnored private var latest = LidDiagnostics()
    @ObservationIgnored private var previousReading: Double?
    @ObservationIgnored private var windowStart: TimeInterval?
    @ObservationIgnored private var reads = 0
    @ObservationIgnored private var changes = 0
    @ObservationIgnored private var lastPublish: TimeInterval = 0

    init(
        source: any LidAngleReading = HIDLidAngleSource(),
        wait: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0, tolerance: .milliseconds(3))
        }
    ) {
        self.source = source
        self.wait = wait
    }

    func start() {
        guard !running else { return }
        running = true
        updateStatus(.waiting)
        let previous = worker
        worker = Task { [weak self, source, wait] in
            await previous?.value
            while !Task.isCancelled {
                let result = await source.read()
                guard !Task.isCancelled, let interval = self?.consume(result) else { break }
                do {
                    try await wait(interval)
                } catch {
                    break
                }
            }
            await source.close()
        }
    }

    @discardableResult
    func stop(suspended: Bool = false) -> Task<Void, Never>? {
        running = false
        worker?.cancel()
        invalidateReadings()
        updateStatus(suspended ? .suspended : .stopped)
        return worker
    }

    private func consume(_ result: Result<Double, LidReadError>) -> Duration {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        switch result {
        case let .success(angle) where (0...180).contains(angle):
            latest.lastRead = now
            if windowStart == nil { windowStart = uptime }
            reads += 1
            if let previousReading, previousReading != angle { changes += 1 }
            previousReading = angle
            if let start = windowStart, uptime - start >= 1 {
                latest.readingsPerSecond = Double(reads - 1) / (uptime - start)
                latest.changesPerSecond = Double(changes) / (uptime - start)
                windowStart = uptime
                reads = 1
                changes = 0
            }
            latest.state = filter.push(angle, at: uptime, timestamp: now)
            updateStatus(.available, uptime: uptime)
            onSample?(latest.state)
            return .milliseconds(25)
        case .success:
            return readFailed(.invalidReport)
        case let .failure(error):
            return readFailed(error)
        }
    }

    private func readFailed(_ error: LidReadError) -> Duration {
        if error != .notFound { latest.readErrors += 1 }
        invalidateReadings()
        updateStatus(.unavailable(error))
        return .seconds(2)
    }

    private func invalidateReadings() {
        filter = LidMotionFilter()
        latest.state = nil
        latest.readingsPerSecond = nil
        latest.changesPerSecond = nil
        previousReading = nil
        windowStart = nil
        reads = 0
        changes = 0
        onSample?(nil)
    }

    private func updateStatus(_ status: LidMonitorStatus, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let changed = latest.status != status
        latest.status = status
        if changed { Log.info("lid angle sensor: \(status)") }
        // Publish UI updates at 4 Hz. Automation receives each filtered sample.
        if changed || uptime - lastPublish >= 0.25 {
            lastPublish = uptime
            diagnostics = latest
        }
    }
}
