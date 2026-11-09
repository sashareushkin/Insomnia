import Foundation
import XCTest
@testable import Insomnia

private actor MockLidAngleSource: LidAngleReading {
    private var reports: [Result<Double, LidReadError>]
    private let exhausted = AsyncGate()
    private(set) var closes = 0

    init(_ reports: [Result<Double, LidReadError>] = []) { self.reports = reports }

    func read() async -> Result<Double, LidReadError> {
        guard !reports.isEmpty else {
            await exhausted.wait()
            return .failure(.notFound)
        }
        return reports.removeFirst()
    }

    func close() { closes += 1 }
    func waitForExhaustion() async { await exhausted.waitUntilStarted() }
    func release() async { await exhausted.open() }
}

final class LidAngleTests: XCTestCase {
    func testReportDecoderAcceptsOnlyTheObservedLayoutAndRange() {
        XCTAssertEqual(HIDLidAngleSource.decode([1, 112, 0]), .success(112))
        XCTAssertEqual(HIDLidAngleSource.decode([1, 0, 0]), .success(0))
        for bytes: [UInt8] in [[0, 112, 0], [1, 112], [1, 112, 1], [1, 112, 0, 0], [1, 181, 0]] {
            XCTAssertEqual(HIDLidAngleSource.decode(bytes[...]), .failure(.invalidReport))
        }
    }

    func testThresholdConfigDefaultsAndRejectsInvalidStoredPairs() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(Config.self, from: Data(#"{"defaultPreset":600}"#.utf8))
        XCTAssertFalse(old.lidAngleEnabled)
        XCTAssertEqual(old.lidAngleThresholds, LidAngleThresholds(close: 30, open: 45))
        XCTAssertEqual(old.defaultPreset, 600)
        var config = old
        config.lidAngleEnabled = true
        config.lidAngleThresholds = LidAngleThresholds(close: 35, open: 55)
        XCTAssertEqual(try decoder.decode(Config.self, from: JSONEncoder().encode(config)), config)
        for payload in [
            #"{"lidAngleEnabled":true,"lidAngleThresholds":{"close":45,"open":30}}"#,
            #"{"lidAngleEnabled":true,"lidAngleThresholds":{"close":-1,"open":45}}"#,
            #"{"lidAngleEnabled":true,"lidAngleThresholds":{"close":30,"open":31}}"#,
            #"{"lidAngleEnabled":true,"lidAngleThresholds":{"close":30,"open":"45"}}"#,
        ] {
            let invalid = try decoder.decode(Config.self, from: Data(payload.utf8))
            XCTAssertFalse(invalid.lidAngleEnabled)
            XCTAssertEqual(invalid.lidAngleThresholds, LidAngleThresholds())
        }
    }

    func testSlowTravelAndFastCrossingsWithJitterAndSingleSpikes() {
        var filter = LidMotionFilter()
        var crossings = LidThresholdCrossings()
        var time = 0.0
        func feed(_ angles: [Double]) -> [LidThresholdCrossings.Crossing] {
            angles.compactMap { angle in
                time += 0.03
                guard let state = filter.push(angle, at: time, timestamp: Date()) else { return nil }
                return crossings.update(state, thresholds: LidAngleThresholds())
            }
        }

        XCTAssertEqual(feed([48, 48, 48, 1, 48, 47, 48]), [])
        XCTAssertEqual(feed([44, 38, 34, 33, 32, 31, 30, 29, 28]), [.close])
        XCTAssertEqual(feed([29, 30, 29, 31, 30, 30, 29]), [])
        XCTAssertEqual(feed([34, 48, 61]), [.open])
        XCTAssertEqual(feed([45, 44, 45, 46, 45, 44, 45]), [])
        XCTAssertEqual(feed([25, 1]), [.close])
    }

    func testInvalidInputAndGapsRebaseMotionWithoutInventingDirection() {
        var filter = LidMotionFilter()
        let date = Date()
        XCTAssertNil(filter.push(100, at: 1, timestamp: date))
        XCTAssertNil(filter.push(90, at: 1.03, timestamp: date))
        XCTAssertEqual(filter.push(80, at: 1.06, timestamp: date)?.direction, .unknown)
        XCTAssertEqual(filter.push(50, at: 1.09, timestamp: date)?.direction, .closing)
        XCTAssertNil(filter.push(.nan, at: 1.12, timestamp: date))
        XCTAssertNil(filter.push(20, at: 1.15, timestamp: date))
        XCTAssertNil(filter.push(20, at: 1.18, timestamp: date))
        XCTAssertEqual(filter.push(20, at: 1.21, timestamp: date)?.direction, .unknown)
        XCTAssertNil(filter.push(120, at: 3, timestamp: date))
        XCTAssertNil(filter.push(120, at: 3.03, timestamp: date))
        XCTAssertEqual(filter.push(120, at: 3.06, timestamp: date)?.direction, .unknown)
    }

    @MainActor
    func testMonitorReconnectsWithFreshEvidenceAndReleasesSource() async {
        let source = MockLidAngleSource([
            .failure(.notFound), .success(100), .success(100), .success(100),
            .failure(.readFailed(-1)), .success(15), .success(15), .success(15),
            .success(400), .success(10), .success(10), .success(10),
        ])
        let monitor = LidMonitor(source: source, wait: { _ in })
        var samples: [LidState?] = []
        monitor.onSample = { samples.append($0) }
        monitor.start()
        await source.waitForExhaustion()
        XCTAssertEqual(samples.compactMap { $0 }.map(\.angle), [100, 15, 10])
        XCTAssertEqual(samples.compactMap { $0 }.map(\.direction), [.unknown, .unknown, .unknown])
        let cleanup = monitor.stop(suspended: true)
        XCTAssertEqual(monitor.diagnostics.status, .suspended)
        XCTAssertEqual(monitor.diagnostics.readErrors, 2)
        XCTAssertNil(monitor.diagnostics.state)
        XCTAssertNotNil(monitor.diagnostics.lastRead)
        await source.release()
        await cleanup?.value
        let closes = await source.closes
        XCTAssertEqual(closes, 1)
    }

    @MainActor
    func testAutomaticSessionUsesDefaultTimerAndExistingRestoration() async throws {
        try await withAutomation { harness, manager, automation in
            manager.config.defaultPreset = 600
            send(20, .unknown, to: automation)
            send(15, .closing, to: automation)
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)
            close(automation)
            await automation.waitForOperation()
            XCTAssertEqual(manager.session?.remaining(at: harness.clock.now), 600)
            XCTAssertTrue(try XCTUnwrap(harness.store.loadState()).sleepDisabledByUs)
            XCTAssertEqual(harness.backstop.arms, 1)

            send(40, .stationary, to: automation)
            XCTAssertTrue(manager.isActive)
            open(automation)
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)
            XCTAssertNil(try harness.store.loadSession())
            XCTAssertFalse(try XCTUnwrap(harness.store.loadState()).sleepDisabledByUs)
            XCTAssertEqual(harness.guardFake.calls.filter { $0.hasPrefix("disablesleep") }, ["disablesleep 1", "disablesleep 0"])
        }
    }

    @MainActor
    func testManualStartAndExtensionAreProtectedAndManualEndRearmsOnNewCrossing() async {
        await withAutomation { harness, manager, automation in
            await manager.start(duration: 600)
            close(automation)
            open(automation)
            await automation.waitForOperation()
            XCTAssertTrue(manager.isActive)
            await manager.end(reason: .user)
            send(29, .closing, to: automation)
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)

            close(automation)
            await automation.waitForOperation()
            XCTAssertTrue(manager.isActive)
            await manager.extend(by: 600)
            open(automation)
            await automation.waitForOperation()
            XCTAssertTrue(manager.isActive)
            XCTAssertEqual(harness.guardFake.calls.filter { $0 == "disablesleep 1" }.count, 2)
            await manager.end(reason: .user)
        }
    }

    @MainActor
    func testSensorLossCannotTriggerStartOrEndUntilThereIsNewMotion() async {
        await withAutomation { _, manager, automation in
            send(100, .stationary, to: automation)
            automation.accept(nil)
            send(20, .closing, to: automation)
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)
            send(100, .stationary, to: automation)
            send(20, .closing, to: automation, age: 1)
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)

            close(automation)
            await automation.waitForOperation()
            automation.accept(nil)
            send(90, .opening, to: automation)
            await automation.waitForOperation()
            XCTAssertTrue(manager.isActive)
            open(automation)
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)
        }
    }

    @MainActor
    func testAutomaticStartDoesNotReplaceASessionOnDiskAwaitingReconcile() async throws {
        try await withAutomation { harness, manager, automation in
            let existing = Session(startedAt: harness.clock.now, endsAt: harness.clock.now.addingTimeInterval(600))
            try harness.store.saveSession(existing)

            close(automation)
            await automation.waitForOperation()

            XCTAssertFalse(manager.isActive)
            XCTAssertEqual(try harness.store.loadSession(), existing)
            XCTAssertEqual(harness.backstop.arms, 0)
            XCTAssertFalse(harness.guardFake.calls.contains("disablesleep 1"))
        }
    }

    @MainActor
    func testLossWhileBackstopArmsRollsBackBeforeChangingSleep() async throws {
        try await withAutomation { harness, manager, automation in
            let gate = AsyncGate()
            harness.backstop.armGate = gate
            close(automation)
            await gate.waitUntilStarted()
            automation.accept(nil)
            await gate.open()
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)
            XCTAssertNil(try harness.store.loadSession())
            XCTAssertFalse(try XCTUnwrap(harness.store.loadState()).sleepDisabledByUs)
            XCTAssertFalse(harness.guardFake.calls.contains("disablesleep 1"))
        }
    }

    @MainActor
    func testOpeningDuringAnInFlightStartRestoresAsSoonAsStartFinishes() async {
        await withAutomation { harness, manager, automation in
            let gate = AsyncGate()
            harness.guardFake.sleepGate = gate
            close(automation)
            await gate.waitUntilStarted()
            open(automation)
            await gate.open()
            await automation.waitForOperation()
            XCTAssertFalse(manager.isActive)
            XCTAssertEqual(harness.guardFake.calls.filter { $0.hasPrefix("disablesleep") }, ["disablesleep 1", "disablesleep 0"])
        }
    }

    @MainActor
    func testManualStartWinsWhenAnAutomaticStartIsStillQueued() async {
        await withAutomation { _, manager, automation in
            close(automation)
            await manager.start(duration: 600)
            await automation.waitForOperation()
            open(automation)
            await automation.waitForOperation()
            XCTAssertTrue(manager.isActive)
            await manager.end(reason: .user)
        }
    }

    @MainActor
    func testDisableOrSleepInvalidatesAQueuedCrossingAndDiagnosticsCanRunAlone() async {
        await withAutomation { harness, manager, automation in
            close(automation)
            automation.setSleeping(true)
            await automation.waitForOperation()
            XCTAssertEqual(automation.monitor.diagnostics.status, .suspended)
            automation.setSleeping(false)
            close(automation)
            manager.config.lidAngleEnabled = false
            await automation.waitForOperation()
            XCTAssertEqual(automation.monitor.diagnostics.status, .stopped)

            automation.setDiagnosticsEnabled(true)
            close(automation)
            await automation.waitForOperation()
            XCTAssertEqual(automation.monitor.diagnostics.status, .waiting)
            XCTAssertFalse(manager.isActive)
            XCTAssertFalse(harness.guardFake.calls.contains("disablesleep 1"))
        }
    }

    @MainActor
    private func withAutomation(
        _ test: (Harness, SessionManager, LidAutomationController) async throws -> Void
    ) async rethrows {
        let harness = Harness()
        defer { harness.home.destroy() }
        let manager = harness.makeManager()
        let source = MockLidAngleSource()
        let automation = LidAutomationController(manager: manager, monitor: LidMonitor(source: source))
        manager.lidAutomation = automation
        manager.config.lidAngleEnabled = true
        automation.didReconcile()
        do {
            try await test(harness, manager, automation)
        } catch {
            let cleanup = automation.setTerminating(true)
            await source.release()
            await cleanup?.value
            throw error
        }
        let cleanup = automation.setTerminating(true)
        await source.release()
        await cleanup?.value
    }

    @MainActor
    private func send(_ angle: Double, _ direction: LidDirection, to automation: LidAutomationController, age: TimeInterval = 0) {
        automation.accept(LidState(angle: angle, direction: direction, speed: 0, timestamp: Date(),
                                   uptime: ProcessInfo.processInfo.systemUptime - age))
    }

    @MainActor
    private func close(_ automation: LidAutomationController) {
        send(90, .stationary, to: automation)
        send(29, .closing, to: automation)
    }

    @MainActor
    private func open(_ automation: LidAutomationController) {
        send(20, .stationary, to: automation)
        send(47, .opening, to: automation)
    }
}
