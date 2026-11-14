import AppKit
import SwiftUI
import XCTest
@testable import Insomnia

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testWindowUsesRequestedSizeAndMaterialToolbar() {
        let settings = SettingsWindow { AnyView(EmptyView()) }
        let window = settings.make()
        let expectedFrameSize = NSSize(width: 800, height: 480)
        let expectedContentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: expectedFrameSize)
        ).size

        XCTAssertEqual(window.frame.size, expectedFrameSize)
        XCTAssertEqual(window.contentMinSize, expectedContentSize)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.title, L10n.string(SettingsSection.general.titleKey, language: LocalizationManager.shared.language))
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertNotNil(window.toolbar)
    }

    func testSidebarUsesRequestedWidthAndSmallerSymbols() {
        XCTAssertEqual(SettingsLayout.sidebarColumnWidth, 208)
        XCTAssertEqual(SettingsLayout.sidebarSymbolSize, 10)
    }

    func testExistingWindowFollowsApplicationAppearanceChanges() throws {
        let app = NSApplication.shared
        let previous = app.appearance
        defer { app.appearance = previous }
        let settings = SettingsWindow { AnyView(EmptyView()) }
        let window = settings.make()
        XCTAssertNil(window.appearance, "Settings must inherit the system appearance")
        let content = try XCTUnwrap(window.contentView)
        XCTAssertNil(content.appearance)

        // Only this test process changes appearance; macOS preferences stay intact.
        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            app.appearance = try XCTUnwrap(NSAppearance(named: name))
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
            XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
        }
    }
}
