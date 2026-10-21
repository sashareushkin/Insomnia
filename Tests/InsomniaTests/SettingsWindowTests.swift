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
        XCTAssertEqual(window.title, L10n.string(SettingsSection.general.titleKey))
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertNotNil(window.toolbar)
    }

    func testSidebarUsesRequestedWidthAndSmallerSymbols() {
        XCTAssertEqual(SettingsLayout.sidebarColumnWidth, 208)
        XCTAssertEqual(SettingsLayout.sidebarSymbolSize, 10)
    }
}
