import AppKit
import SwiftUI
import XCTest
@testable import Insomnia

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testWindowUsesRequestedSizeAndTransparentTitlebar() {
        let settings = SettingsWindow { AnyView(EmptyView()) }
        let window = settings.make()
        let expectedSize = NSSize(width: 800, height: 480)

        XCTAssertEqual(window.contentMinSize, expectedSize)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, expectedSize)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.toolbarStyle, .unified)
    }

    func testSidebarUsesRequestedWidthAndSmallerSymbols() {
        XCTAssertEqual(SettingsLayout.sidebarColumnWidth, 280)
        XCTAssertEqual(SettingsLayout.sidebarSymbolSize, 10)
    }
}
