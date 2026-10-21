import XCTest
@testable import Insomnia

/// What Settings and the README tell the user about the lid closing: the
/// built-in microphone and the one-time lid-close update.
final class LidCloseCopyTests: XCTestCase {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// Words joined by single spaces, so a wrapped paragraph reads as one line.
    private func flattened(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The dedicated lid-close destination view.
    private func lidSection() throws -> String {
        try read("Sources/Insomnia/UI/LidCloseSettingsView.swift")
    }

    func testMicrophoneNoteSaysTheMicIsDisconnectedAndWhatToUseInstead() {
        let note = SettingsView.microphoneNote
        XCTAssertTrue(note.contains("closing the lid disconnects the built-in microphone in hardware"), note)
        XCTAssertTrue(note.contains("AirPods or an external mic"), note)
    }

    /// The note sits right under the mute toggle, next to the other
    /// lid-close options.
    func testSettingsShowsTheMicrophoneNoteUnderTheMuteToggle() throws {
        let lid = try lidSection()
        let toggle = try XCTUnwrap(lid.range(of: #"L10n.string("Mute audio on lid close")"#))
        let note = try XCTUnwrap(lid.range(of: "Text(L10n.string(SettingsView.microphoneNote))"))
        XCTAssertLessThan(toggle.lowerBound, note.lowerBound)
    }

    func testReadmeExplainsTheMicrophone() throws {
        let readme = flattened(try read("README.md"))
        XCTAssertTrue(readme.contains("closing the lid disconnects the built-in microphone in hardware. Recording a meeting with the lid closed needs AirPods or an external mic"))
    }

    /// The update's notice also lives in Settings, for a user who has
    /// notifications off, until dismissed.
    func testSettingsShowsTheLidCloseUpdateNoticeUntilDismissed() throws {
        let lid = try lidSection()
        XCTAssertTrue(lid.contains("if let notice = manager.config.lidCloseDefaultsNotice"))
        XCTAssertTrue(lid.contains("Text(L10n.presentation(notice.settingsLine))"))
        XCTAssertTrue(lid.contains(#"Button(L10n.string("Dismiss")) { manager.dismissLidCloseNotice() }"#))
    }

    func testSettingsRetainsTheImmediateLowPowerFloorReevaluation() throws {
        let lid = try lidSection()
        XCTAssertTrue(lid.contains("manager.services?.reevaluateFloors()"))
    }
}
