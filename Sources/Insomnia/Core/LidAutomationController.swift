import Foundation
import Observation

/// Owns the angle observer for the app, including the time between sessions.
@MainActor
@Observable
final class LidAutomationController {
    let monitor: LidMonitor
    private(set) var diagnosticsEnabled = false

    @ObservationIgnored private weak var manager: SessionManager?
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var terminating = false
    @ObservationIgnored private var crossings = LidThresholdCrossings()
    @ObservationIgnored private var lastReading: LidState?
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var readingRevision = 0
    @ObservationIgnored private var ownershipRevision = 0
    @ObservationIgnored private var ownedStart: Date?
    @ObservationIgnored private var operation: Task<Void, Never>?

    init(manager: SessionManager, monitor: LidMonitor = LidMonitor()) {
        self.manager = manager
        self.monitor = monitor
        monitor.onSample = { [weak self] state in self?.accept(state) }
    }

    func didReconcile() {
        ready = true
        updateMonitoring()
    }

    func configChanged(from old: Config) {
        guard let config = manager?.config else { return }
        guard old.lidAngleEnabled != config.lidAngleEnabled ||
                old.lidAngleThresholds != config.lidAngleThresholds else { return }
        resetEvidence()
        if !config.lidAngleEnabled { manualOverride() }
        updateMonitoring()
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsEnabled = enabled
        updateMonitoring()
    }

    func setSleeping(_ sleeping: Bool) {
        self.sleeping = sleeping
        updateMonitoring()
    }

    @discardableResult
    func setTerminating(_ terminating: Bool) -> Task<Void, Never>? {
        self.terminating = terminating
        return updateMonitoring()
    }

    func manualOverride() {
        ownershipRevision += 1
        ownedStart = nil
        resetEvidence()
    }

    @discardableResult
    private func updateMonitoring() -> Task<Void, Never>? {
        let requested = diagnosticsEnabled || manager?.config.lidAngleEnabled == true
        if ready, requested, !sleeping, !terminating {
            monitor.start()
            return nil
        }
        return monitor.stop(suspended: requested && sleeping && !terminating)
    }

    private func resetEvidence() {
        readingRevision += 1
        crossings = LidThresholdCrossings()
        lastReading = nil
        stopRequested = false
    }

    func accept(_ state: LidState?) {
        guard let state, state.isCurrent, let manager, ready, !sleeping, !terminating, manager.config.lidAngleEnabled else {
            if lastReading != nil { resetEvidence() }
            return
        }
        let thresholds = manager.config.lidAngleThresholds
        lastReading = state
        if ownedStart != manager.session?.startedAt { ownedStart = nil }
        if state.angle <= Double(thresholds.open - 2) { stopRequested = false }

        switch crossings.update(state, thresholds: thresholds) {
        case .close where manager.session == nil && operation == nil:
            startSession(manager, state: state)
        case .open where ownedStart != nil || operation != nil:
            Log.info("lid angle opening threshold reached at \(state.angle)° (\(Self.logTime(state.timestamp)))")
            stopRequested = true
            endIfRequested(manager)
        default:
            break
        }
    }

    private func startSession(_ manager: SessionManager, state: LidState) {
        Log.info("lid angle closing threshold reached at \(state.angle)° (\(Self.logTime(state.timestamp)))")
        let reading = readingRevision
        let ownership = ownershipRevision
        operation = Task { [weak self, weak manager] in
            guard let self, let manager else { return }
            let start = await manager.startFromLidAngle {
                guard self.readingRevision == reading, !self.stopRequested,
                      let sample = self.lastReading, sample.isCurrent else { return false }
                return sample.angle < Double(manager.config.lidAngleThresholds.open)
            }
            self.operation = nil
            if self.ownershipRevision == ownership, start != nil {
                self.ownedStart = start
                Log.info("lid angle automation started session (\(Self.logTime(Date())))")
                self.endIfRequested(manager)
            }
        }
    }

    private func endIfRequested(_ manager: SessionManager) {
        guard operation == nil, stopRequested, let ownedStart, manager.session?.startedAt == ownedStart else { return }
        operation = Task { [weak self, weak manager] in
            guard let self, let manager else { return }
            defer { self.operation = nil }
            guard self.stopRequested, self.lastReading?.isCurrent == true,
                  self.ownedStart == ownedStart, manager.session?.startedAt == ownedStart else { return }
            self.ownedStart = nil
            self.stopRequested = false
            let outcome = await manager.end(reason: .lidAngle)
            Log.info("lid angle automation end outcome: \(outcome) (\(Self.logTime(Date())))")
        }
    }

    private static func logTime(_ date: Date) -> String {
        date.formatted(.iso8601.time(includingFractionalSeconds: true))
    }

    /// Used by tests to await both a start and any end it schedules.
    func waitForOperation() async {
        while let operation { await operation.value }
    }
}

struct LidThresholdCrossings {
    enum Crossing: Equatable { case close, open }

    private var closeArmed = false
    private var openArmed = false

    mutating func update(_ state: LidState, thresholds: LidAngleThresholds) -> Crossing? {
        let close = Double(thresholds.close)
        let open = Double(thresholds.open)
        if state.angle >= close + 2 { closeArmed = true }
        if state.angle <= open - 2 { openArmed = true }
        if closeArmed, state.angle <= close, state.direction == .closing {
            closeArmed = false
            return .close
        }
        if openArmed, state.angle >= open, state.direction == .opening {
            openArmed = false
            return .open
        }
        return nil
    }
}
