import AppKit
import Observation
import XCTest
@testable import Insomnia

@MainActor
final class ScreenOnTests: XCTestCase {
    private final class Lid: ScreenOnLidWatching {
        var isClosed = false
        var onClosedImmediately: (() -> Void)?
        var isWatching = false
        var refusesStart = false
        var closesDuringStart = false

        func start() -> Bool {
            if closesDuringStart { isClosed = true }
            isWatching = !refusesStart
            return isWatching
        }

        func stop() { isWatching = false }

        func close() {
            isClosed = true
            if isWatching { onClosedImmediately?() }
        }
    }

    private final class Power {
        var acquisitions = 0
        var released: [UInt32] = []
        var refusesAcquire = false
        var refusesRelease = false

        func acquire() -> UInt32? {
            acquisitions += 1
            return refusesAcquire ? nil : 42
        }

        func release(_ id: UInt32) -> Bool {
            released.append(id)
            return !refusesRelease
        }
    }

    func testStandaloneToggleAndGuards() {
        let lid = Lid()
        let power = Power()
        let screen = ScreenOn(lid: lid, acquire: power.acquire, release: power.release)
        XCTAssertFalse(screen.canToggle(sessionActive: true))
        screen.toggle(expectedOn: false, sessionActive: true)
        lid.isClosed = true
        XCTAssertFalse(screen.canToggle(sessionActive: false))
        screen.toggle(expectedOn: false, sessionActive: false)
        XCTAssertEqual(power.acquisitions, 0)

        lid.isClosed = false
        screen.toggle(expectedOn: false, sessionActive: false)
        XCTAssertTrue(screen.isOn)
        XCTAssertTrue(lid.isWatching)
        screen.toggle(expectedOn: true, sessionActive: false)
        XCTAssertFalse(screen.isOn)
        XCTAssertFalse(lid.isWatching)
        XCTAssertEqual(power.released, [42])
    }

    func testFullCloseReleasesImmediatelyAndStaleMenuCannotReenableIt() {
        let lid = Lid()
        let power = Power()
        let screen = ScreenOn(lid: lid, acquire: power.acquire, release: power.release)
        screen.toggle(expectedOn: false, sessionActive: false)

        lid.close()
        XCTAssertFalse(screen.isOn)
        XCTAssertEqual(power.released, [42])
        lid.isClosed = false
        screen.toggle(expectedOn: true, sessionActive: false)
        XCTAssertFalse(screen.isOn)
        XCTAssertEqual(power.acquisitions, 1)
    }

    func testIndicatorObservesAcquisitionAndAutomaticLidRelease() {
        let lid = Lid()
        let power = Power()
        let screen = ScreenOn(lid: lid, acquire: power.acquire, release: power.release)
        let changed = Locked(false)
        withObservationTracking {
            _ = screen.isOn
        } onChange: {
            changed.value = true
        }

        screen.toggle(expectedOn: false, sessionActive: false)
        XCTAssertTrue(changed.value, "the menu bar must redraw when Screen On starts")
        XCTAssertTrue(screen.isOn)

        changed.value = false
        withObservationTracking {
            _ = screen.isOn
        } onChange: {
            changed.value = true
        }
        lid.close()
        XCTAssertTrue(changed.value, "a raw lid close must update the indicator without a menu click")
        XCTAssertFalse(screen.isOn)
    }

    func testIndicatorStaysOnWhenReleaseFailsAndUpdatesAfterRetry() {
        let power = Power()
        let screen = ScreenOn(lid: Lid(), acquire: power.acquire, release: power.release)
        screen.toggle(expectedOn: false, sessionActive: false)
        let changed = Locked(false)
        withObservationTracking {
            _ = screen.isOn
        } onChange: {
            changed.value = true
        }

        power.refusesRelease = true
        XCTAssertFalse(screen.stop())
        XCTAssertFalse(changed.value)
        XCTAssertTrue(screen.isOn, "the sun must remain while the display assertion is still held")
        power.refusesRelease = false
        XCTAssertTrue(screen.stop())
        XCTAssertTrue(changed.value)
        XCTAssertFalse(screen.isOn)
    }

    func testNoAssertionWithoutObserverOrIfLidClosesDuringSetup() {
        let lid = Lid()
        let power = Power()
        let screen = ScreenOn(lid: lid, acquire: power.acquire, release: power.release)
        lid.refusesStart = true
        screen.toggle(expectedOn: false, sessionActive: false)
        XCTAssertNotNil(screen.warning)
        XCTAssertEqual(power.acquisitions, 0)

        lid.refusesStart = false
        lid.closesDuringStart = true
        screen.toggle(expectedOn: false, sessionActive: false)
        XCTAssertFalse(lid.isWatching)
        XCTAssertFalse(screen.isOn)
        XCTAssertEqual(power.acquisitions, 0)
    }

    func testAcquisitionFailureLeavesItemUncheckedAndStopsWatching() {
        let lid = Lid()
        let power = Power()
        power.refusesAcquire = true
        let screen = ScreenOn(lid: lid, acquire: power.acquire, release: power.release)

        screen.toggle(expectedOn: false, sessionActive: false)

        XCTAssertFalse(screen.isOn)
        XCTAssertFalse(lid.isWatching)
        XCTAssertNotNil(screen.warning)
    }

    func testOnlyConfirmedSessionStartReleasesTheDisplay() async {
        let h = Harness()
        defer { h.home.destroy() }
        let power = Power()
        let screen = ScreenOn(lid: Lid(), acquire: power.acquire, release: power.release)
        let manager = h.makeManager(screenOn: screen)
        screen.toggle(expectedOn: false, sessionActive: manager.isActive)

        h.guardFake.throwOn = ["disablesleep 1"]
        await manager.start(duration: 3600)
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(screen.isOn)
        XCTAssertEqual(power.released, [])

        h.guardFake.throwOn = []
        await manager.start(duration: 3600)
        XCTAssertTrue(manager.isActive)
        XCTAssertFalse(screen.isOn)
        XCTAssertEqual(power.released, [42])
        XCTAssertFalse(screen.canToggle(sessionActive: manager.isActive))
        await manager.end(reason: .user)
        XCTAssertFalse(screen.isOn)
    }

    func testReleaseFailureUsesSessionRollbackAndCanBeRetried() async throws {
        let h = Harness()
        defer { h.home.destroy() }
        let power = Power()
        let screen = ScreenOn(lid: Lid(), acquire: power.acquire, release: power.release)
        let manager = h.makeManager(screenOn: screen)
        screen.toggle(expectedOn: false, sessionActive: false)
        power.refusesRelease = true

        await manager.start(duration: 3600)

        XCTAssertFalse(manager.isActive)
        XCTAssertFalse(h.guardFake.sleepDisabled)
        XCTAssertNil(try h.store.loadSession())
        XCTAssertTrue(screen.isOn)
        XCTAssertNotNil(screen.warning)
        power.refusesRelease = false
        screen.toggle(expectedOn: true, sessionActive: false)
        XCTAssertFalse(screen.isOn)
    }

    func testRestoringAnExistingSessionReleasesTheDisplay() async throws {
        let h = Harness()
        defer { h.home.destroy() }
        let power = Power()
        let screen = ScreenOn(lid: Lid(), acquire: power.acquire, release: power.release)
        let manager = h.makeManager(screenOn: screen)
        screen.toggle(expectedOn: false, sessionActive: false)
        try h.store.saveSession(Session(startedAt: h.clock.now, endsAt: h.clock.now.addingTimeInterval(3600)))

        await manager.reconcile()

        XCTAssertTrue(manager.isActive)
        XCTAssertFalse(screen.isOn)
        XCTAssertEqual(power.released, [42])
        await manager.end(reason: .user)
    }

    func testMenuUsesNativeCheckmarkAndEnablement() throws {
        let selector = NSSelectorFromString("menuToggleScreenOn:")
        for (isOn, enabled) in [(false, true), (true, true), (false, false)] {
            let items = StatusMenu.items(
                sessionActive: false, sleepHeld: false, machine: nil, actions: nil,
                throttledBrowsers: [], error: nil, screenOn: (isOn, enabled)
            )
            let menu = StatusMenu.menu(
                items, target: nil, endSession: selector, settings: selector, quit: selector,
                relaunchBrowser: selector, stopWaitingForOutput: selector, toggleScreenOn: selector
            )
            let item = try XCTUnwrap(menu.items.first { $0.title == L10n.string("Screen On") })
            XCTAssertEqual(item.state, isOn ? .on : .off)
            XCTAssertEqual(item.isEnabled, enabled)
        }
    }
}
