import AppKit
import SwiftUI
import XCTest
@testable import Insomnia

/// Offscreen event fixtures only: no status item, power commands or app launch.
@MainActor
final class HoldMouseTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, x: CGFloat = 10) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 10), modifierFlags: [], timestamp: 0,
                          windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    func testShortPressAndDragAreConsumedWithoutRestart() {
        let view = HoldMouseView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        var presses = 0
        var cancels = 0
        var releases = 0
        view.onPress = { presses += 1 }
        view.onCancel = { cancels += 1 }
        view.onRelease = { releases += 1 }
        view.mouseDown(with: event(.leftMouseDown))
        view.mouseUp(with: event(.leftMouseUp))
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(cancels, 0)
        view.mouseDown(with: event(.leftMouseDown))
        view.mouseDragged(with: event(.leftMouseDragged, x: 22))
        XCTAssertEqual(cancels, 0, "12 pt is still inside the threshold")
        view.mouseDragged(with: event(.leftMouseDragged, x: 23))
        view.mouseDragged(with: event(.leftMouseDragged))
        view.mouseDown(with: event(.leftMouseDown))
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(presses, 2, "Returning inside cannot rearm this press")
        view.mouseUp(with: event(.leftMouseUp))
        view.mouseDown(with: event(.leftMouseDown))
        view.cancelPress()
        XCTAssertEqual(presses, 3)
        XCTAssertEqual(cancels, 2)
    }

    func testNativeSurfaceWinsHostingHitTestAfterResize() throws {
        let host = NSHostingView(rootView: HoldMouseSurface(onPress: {}, onCancel: {}, onRelease: {}).frame(width: 20, height: 20))
        host.frame = NSRect(x: 0, y: 0, width: 20, height: 24)
        let button = NSButton(frame: host.frame)
        button.addSubview(host)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = button
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        func surfaces(_ view: NSView) -> [HoldMouseView] {
            (view as? HoldMouseView).map { [$0] } ?? view.subviews.flatMap(surfaces)
        }
        let surface = try XCTUnwrap(surfaces(host).first)
        for width: CGFloat in [20, 180, 60] {
            host.frame.size.width = width
            host.layoutSubtreeIfNeeded()
            let point = surface.convert(NSPoint(x: 10, y: 10), to: host)
            XCTAssertTrue(host.hitTest(point) === surface)
            XCTAssertTrue(button.hitTest(point) === surface)
        }
    }

    func testHoldCompletionAndEarlyReleaseThroughHostedNativeSurface() async throws {
        var ended = 0
        let host = NSHostingView(rootView: HoldToEndButton(reduceMotion: true) { ended += 1 })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> HoldMouseView? {
            if let surface = view as? HoldMouseView { return surface }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let surface = try XCTUnwrap(find(host))
        surface.mouseDown(with: event(.leftMouseDown))
        surface.mouseUp(with: event(.leftMouseUp))
        try await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(ended, 0)
        surface.mouseDown(with: event(.leftMouseDown))
        surface.mouseDragged(with: event(.leftMouseDragged, x: 30))
        try await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(ended, 0)
        surface.mouseUp(with: event(.leftMouseUp))
        surface.mouseDown(with: event(.leftMouseDown))
        try await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(ended, 1)
        try await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(ended, 1, "One press can fire only once")
        surface.mouseUp(with: event(.leftMouseUp))
        window.contentView = nil
    }

    func testRouterUsesRealPointerWhenReplicaEventsReportTheWindowCentre() throws {
        let host = NSHostingView(rootView: HoldMouseSurface(onPress: {}, onCancel: {}, onRelease: {}).frame(width: 20, height: 20))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 100, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        let replica = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> HoldMouseView? {
            (view as? HoldMouseView) ?? view.subviews.lazy.compactMap { find($0) }.first
        }
        let surface = try XCTUnwrap(find(host))
        var presses = 0
        var cancels = 0
        var releases = 0
        surface.onPress = { presses += 1 }
        surface.onCancel = { cancels += 1 }
        surface.onRelease = { releases += 1 }
        var pointer = NSPoint.zero
        let router = StatusHoldMouseRouter(host: host, installMonitor: false, pointerLocation: { pointer })
        func mouse(_ type: NSEvent.EventType, point: NSPoint) -> NSEvent {
            pointer = replica.convertPoint(toScreen: point)
            // Mirror the real status bar: every mouse event reports the
            // replica centre, even when the pointer is over the cross.
            return NSEvent.mouseEvent(with: type, location: NSPoint(x: replica.frame.width / 2, y: replica.frame.height / 2), modifierFlags: [], timestamp: 0, windowNumber: replica.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        for width: CGFloat in [100, 160, 80] {
            window.setContentSize(NSSize(width: width, height: 24))
            replica.setFrame(window.frame, display: false)
            host.layoutSubtreeIfNeeded()
            let center = surface.convert(NSPoint(x: 10, y: 10), to: nil)
            XCTAssertFalse(router.route(mouse(.leftMouseDown, point: NSPoint(x: 1, y: 1))), "The eye/countdown must keep their usual route")
            XCTAssertTrue(router.route(mouse(.leftMouseDown, point: center)))
            XCTAssertTrue(router.route(mouse(.leftMouseDragged, point: NSPoint(x: center.x + 13, y: center.y))))
            XCTAssertTrue(router.route(mouse(.leftMouseDragged, point: center)))
            XCTAssertTrue(router.route(mouse(.leftMouseUp, point: center)))
        }
        XCTAssertEqual(presses, 3)
        XCTAssertEqual(cancels, 3)
        XCTAssertEqual(releases, 3)
        surface.removeFromSuperview()
        XCTAssertFalse(router.route(mouse(.leftMouseDown, point: NSPoint(x: 50, y: 10))), "Idle/removed surface cannot capture clicks")
    }

    func testVisibleCountdownReadsTheClockWhileLidRedrawIsPaused() async {
        let h = Harness()
        defer { h.home.destroy() }
        let manager = h.makeManager()
        await manager.start(duration: 3600)
        manager.pauseCountdown()
        XCTAssertFalse(manager.countdownTimerArmed)
        let frozen = manager.countdownText
        let session = manager.session
        h.clock.advance(5)
        XCTAssertEqual(manager.countdownText, frozen)
        XCTAssertEqual(manager.presentationCountdownText(), "0:59:55")
        h.clock.advance(2)
        XCTAssertEqual(manager.presentationCountdownText(), "0:59:53")
        XCTAssertFalse(manager.countdownTimerArmed, "Presentation must not resume the bag redraw timer")
        XCTAssertEqual(manager.session, session, "Rendering must not move the deadline")
        await manager.end(reason: .user)
        XCTAssertEqual(manager.presentationCountdownText(), "")
    }

    func testMenuEndIsOnlyActiveAndHasItsOwnSelector() {
        for active in [false, true] {
            let items = StatusMenu.items(sessionActive: active, sleepHeld: false, machine: nil, actions: nil, throttledBrowsers: [], error: nil)
            XCTAssertEqual(items.filter { $0.kind == .endSession }.count, active ? 1 : 0)
            XCTAssertEqual(Array(items.suffix(active ? 4 : 2)).map(\.kind), active ? [.endSession, .separator, .settings, .quit] : [.settings, .quit])
            let end = NSSelectorFromString("endSession")
            let other = #selector(NSObject.description)
            let menu = StatusMenu.menu(items, target: nil, endSession: end, settings: other, quit: other, relaunchBrowser: other, stopWaitingForOutput: other)
            let entry = menu.items.first { $0.title == StatusMenu.endSessionTitle }
            XCTAssertEqual(entry?.action, active ? end : nil)
        }
    }
}
