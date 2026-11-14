import AppKit
import XCTest
@testable import Insomnia

/// Layout without a status item, a visible menu, or any live system services.
@MainActor
final class StatusMenuLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = LocalizationManager(language: .english)
    }

    override func tearDown() {
        _ = LocalizationManager(language: .english)
        super.tearDown()
    }

    private func menu(machine: String, help: String? = nil, error: String? = nil) -> NSMenu {
        let items = StatusMenu.items(
            sessionActive: false, sleepHeld: false, machine: machine, actions: nil,
            throttledBrowsers: [], error: error, screenOn: (false, true), machineToolTip: help
        )
        return StatusMenu.menu(
            items, target: nil, endSession: #selector(NSObject.description),
            settings: #selector(NSObject.description), quit: #selector(NSObject.description),
            relaunchBrowser: #selector(NSObject.description), stopWaitingForOutput: #selector(NSObject.description),
            toggleScreenOn: #selector(NSObject.description)
        )
    }

    func testMachineSummaryUsesTwoShortLinesAndOmitsUnknownValues() {
        XCTAssertEqual(
            StatusLines.machine(lidClosed: true, watts: 4.12, wifiSSID: "Office", batteryPercent: 82, isCharging: false),
            "Lid closed · 82%\n4.1 W · Wi-Fi: Office"
        )
        XCTAssertEqual(
            StatusLines.machine(lidClosed: false, watts: nil, wifiSSID: nil, batteryPercent: nil, isCharging: false),
            "Lid open"
        )
        XCTAssertEqual(
            StatusLines.machine(lidClosed: false, watts: nil, wifiSSID: nil, batteryPercent: 82, isCharging: true),
            "Lid open · 82% charging"
        )
    }

    func testRussianMenuKeepsRedactedWiFiCompactAndRetainsPermissionHelp() throws {
        _ = LocalizationManager(language: .russian)
        let ssid = WiFiStatusName.display(ssid: nil, locationAuthorized: false)
        let help = WiFiStatusName.toolTip(ssid: nil, locationAuthorized: false)
        XCTAssertEqual(ssid, "скрыто")
        XCTAssertTrue(try XCTUnwrap(help).contains("геопозиции"))
        let machine = StatusLines.machine(lidClosed: false, watts: -37.4, wifiSSID: ssid, batteryPercent: 84, isCharging: false)
        XCTAssertTrue(machine.hasPrefix("Крышка открыта · 84%\n"))
        XCTAssertTrue(machine.hasSuffix("Wi-Fi: скрыто"))
        let menu = menu(machine: machine, help: help)
        let entry = try XCTUnwrap(menu.items.first)
        XCTAssertEqual(entry.toolTip, help)
        XCTAssertEqual(entry.view?.toolTip, help)
        let label = try XCTUnwrap(entry.view?.subviews.first as? NSTextField)
        XCTAssertEqual(label.stringValue, machine)
        XCTAssertEqual(entry.accessibilityLabel(), machine)
        XCTAssertEqual(label.maximumNumberOfLines, 0)
        XCTAssertFalse(entry.isEnabled)
        XCTAssertLessThanOrEqual(menu.size.width, 195)
        let oneLine = StatusMenuLayout.statusView(text: "One line", isWarning: false).frame.height - 2 * StatusMenuLayout.verticalInset
        XCTAssertEqual(try XCTUnwrap(entry.view).frame.height - 2 * StatusMenuLayout.verticalInset, 2 * oneLine, accuracy: 1)
        print("Compact Russian menu: \(menu.size)")
    }

    func testLongSSIDAndRecoveryWarningWrapWithoutGrowingTheMenu() throws {
        let ssid = String(repeating: "LongNetworkName", count: 8)
        let machine = StatusLines.machine(lidClosed: false, watts: 4.1, wifiSSID: ssid, batteryPercent: 84, isCharging: false)
        let error = String(repeating: "Recovery still needs to restore the saved display brightness. ", count: 5)
        let menu = menu(machine: machine, error: error)
        XCTAssertLessThanOrEqual(menu.size.width, 195)
        let entries = menu.items.filter { $0.view != nil }
        XCTAssertEqual(entries.count, 2)
        for entry in entries {
            let view = try XCTUnwrap(entry.view)
            let label = try XCTUnwrap(view.subviews.first as? NSTextField)
            XCTAssertEqual(label.stringValue, entry.accessibilityLabel(), "diagnostics must stay complete")
            XCTAssertEqual(entry.toolTip, label.stringValue)
            XCTAssertGreaterThan(view.frame.height, 2 * StatusMenuLayout.verticalInset + 14)
            XCTAssertTrue(view.bounds.contains(label.frame))
        }
        XCTAssertTrue(try XCTUnwrap(entries.first?.accessibilityLabel()).contains(ssid))
        XCTAssertEqual(entries.last?.accessibilityLabel(), "⚠ \(error)")
    }

    func testPermissionHelpAppearsOnlyForARedactedName() {
        XCTAssertNotNil(WiFiStatusName.toolTip(ssid: nil, locationAuthorized: false))
        XCTAssertNotNil(WiFiStatusName.toolTip(ssid: "", locationAuthorized: false))
        XCTAssertNil(WiFiStatusName.toolTip(ssid: "Office", locationAuthorized: false))
        XCTAssertNil(WiFiStatusName.toolTip(ssid: nil, locationAuthorized: true))
    }

    func testNativeMenuIsInstalledOnlyWhileTracking() {
        let host = MenuHost()
        let menu = menu(machine: "Lid open")
        host.onClick = { [weak host] in XCTAssertTrue(host?.menu === menu) }
        StatusMenuLayout.popUp(menu, from: host)
        XCTAssertEqual(host.clicks, 1)
        XCTAssertNil(host.menu, "left clicks must return to the timer controls")
    }

    private final class MenuHost: StatusMenuHosting {
        var menu: NSMenu?
        var onClick: (() -> Void)?
        var clicks = 0
        func clickMenuButton() {
            clicks += 1
            onClick?()
        }
    }
}
