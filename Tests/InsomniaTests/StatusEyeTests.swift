import SwiftUI
import XCTest
@testable import Insomnia

@MainActor
final class StatusEyeTests: XCTestCase {
    private func render(running: Bool, screenOn: Bool, scheme: ColorScheme, reduceMotion: Bool) throws -> IconPixels {
        let renderer = ImageRenderer(content:
            StatusEyeView(isRunning: running, isScreenOn: screenOn, reduceMotion: reduceMotion)
                .environment(\.colorScheme, scheme)
        )
        renderer.scale = 2
        return IconPixels(try XCTUnwrap(renderer.cgImage))
    }

    func testIdleSessionAndScreenOnAreDistinctAtMenuBarSizeInBothThemes() throws {
        for scheme in [ColorScheme.light, .dark] {
            for reduceMotion in [false, true] {
                let idle = try render(running: false, screenOn: false, scheme: scheme, reduceMotion: reduceMotion)
                let session = try render(running: true, screenOn: false, scheme: scheme, reduceMotion: reduceMotion)
                let screen = try render(running: false, screenOn: true, scheme: scheme, reduceMotion: reduceMotion)
                let both = try render(running: true, screenOn: true, scheme: scheme, reduceMotion: reduceMotion)
                for image in [idle, session, screen] {
                    XCTAssertEqual(image.width, 40)
                    XCTAssertEqual(image.height, 40, "changing the mode must not resize the status item")
                }
                XCTAssertGreaterThan(idle.differences(from: session, tolerance: 20), 50)
                XCTAssertGreaterThan(session.differences(from: screen, tolerance: 20), 20)
                XCTAssertEqual(screen.differences(from: both, tolerance: 20), 0)
                var badgePixels = 0
                for y in 28..<40 {
                    for x in 28..<40 where screen.alpha(x, y) > session.alpha(x, y) + 0.2 {
                        badgePixels += 1
                    }
                }
                XCTAssertGreaterThan(badgePixels, 15, "Screen On adds a visible sun below the open eye")
            }
        }
    }

    func testEyeAndSunUseTheSystemForegroundInBothThemes() throws {
        for scheme in [ColorScheme.light, .dark] {
            let image = try render(running: false, screenOn: true, scheme: scheme, reduceMotion: true)
            var visible = 0
            var readable = 0
            for y in 0..<image.height {
                for x in 0..<image.width where image.alpha(x, y) > 0.5 {
                    visible += 1
                    let luminance = image.luminance(x, y)
                    if scheme == .dark ? luminance > 0.8 : luminance < 0.2 { readable += 1 }
                }
            }
            XCTAssertGreaterThan(visible, 100)
            XCTAssertEqual(readable, visible, "both the eye and sun must follow the light/dark system label colour")
        }
    }
}
