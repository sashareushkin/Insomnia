import Foundation
import Observation

/// Live machine status shown in the right-click menu. The system layer
/// (lid, battery, network, freeze, browser throttle) provides the real
/// object; the UI only ever talks to this protocol.
@MainActor
protocol StatusSource: AnyObject, Observable {
    var lidClosed: Bool { get }
    var batteryPercent: Int? { get }
    var isCharging: Bool { get }
    var wifiSSID: String? { get }
    /// Length of the most recent network outage, nil if none this session.
    var lastGap: TimeInterval? { get }
    var frozenCount: Int { get }
    var dockerPaused: Bool { get }
    /// Browsers running without the occlusion flags.
    var throttledBrowsers: [ThrottledBrowser] { get }
    /// Why each browser's last relaunch did not happen, ordered by
    /// bundle id; one menu warning line each.
    var relaunchProblems: [String] { get }
    /// Why a hotspot join was skipped this session, if one was, and for
    /// which SSID.
    var hotspotPasswordReport: HotspotPasswordReport? { get }

    /// Called when the menu opens; observers refresh anything not pushed.
    func refreshOnDemand()
    /// The part of that refresh that needs no awaiting, so a caller that has
    /// to read the status right now still gets it fresh.
    func refreshInstant()
    /// Battery draw read on demand from AppleSmartBattery. Never polled.
    func instantWatts() -> Double?
    /// Relaunch the browser the user confirmed, as the menu item named it.
    func relaunchUnthrottled(_ browser: ThrottledBrowser)
}

/// Stand-in until the system layer is plugged in. Reports nothing.
@MainActor
@Observable
final class PlaceholderStatus: StatusSource {
    var lidClosed: Bool = false
    var batteryPercent: Int? = nil
    var isCharging: Bool = false
    var wifiSSID: String? = nil
    var lastGap: TimeInterval? = nil
    var frozenCount: Int = 0
    var dockerPaused: Bool = false
    var throttledBrowsers: [ThrottledBrowser] = []
    var relaunchProblems: [String] = []
    var hotspotPasswordReport: HotspotPasswordReport? = nil

    init() {}

    func refreshOnDemand() {}
    func refreshInstant() {}
    func instantWatts() -> Double? { nil }
    func relaunchUnthrottled(_ browser: ThrottledBrowser) {}
}

/// Pure formatting for the menu's status block, kept out of the views so
/// it can be tested.
enum StatusLines {
    /// "Lid: closed · 4.1 W · Wi-Fi: iPhone". Unknown parts are omitted.
    static func machine(lidClosed: Bool, watts: Double?, wifiSSID: String?, batteryPercent: Int?, isCharging: Bool) -> String {
        var parts: [String] = [L10n.format("Lid: %@", L10n.string(lidClosed ? "closed" : "open"))]
        if let w = watts {
            parts.append(L10n.format("%.1f W", w))
        }
        if let p = batteryPercent {
            parts.append(L10n.format(isCharging ? "%d%% charging" : "%d%%", p))
        }
        if let ssid = wifiSSID, !ssid.isEmpty {
            parts.append(L10n.format("Wi-Fi: %@", ssid))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "3 apps frozen · Docker paused", or nil when nothing is held.
    static func actions(frozenCount: Int, dockerPaused: Bool, lastGap: TimeInterval?) -> String? {
        var parts: [String] = []
        if frozenCount > 0 {
            parts.append(L10n.plural("appsFrozen", count: frozenCount))
        }
        if dockerPaused {
            parts.append(L10n.string("Docker paused"))
        }
        if let gap = lastGap, gap > 0 {
            parts.append(L10n.format("last gap %d s", Int(gap.rounded())))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// "⚠ Chrome is throttled" / "⚠ Chrome and Arc are throttled".
    static func throttleWarning(_ browsers: [String]) -> String? {
        guard !browsers.isEmpty else { return nil }
        let names: String
        switch browsers.count {
        case 1: names = browsers[0]
        case 2: names = L10n.format("%@ and %@", browsers[0], browsers[1])
        default: names = L10n.format("%@, and %@", browsers.dropLast().joined(separator: ", "), browsers.last!)
        }
        return browsers.count == 1
            ? L10n.format("\u{26A0} %@ is throttled", names)
            : L10n.format("\u{26A0} %@ are throttled", names)
    }
}

/// The one line about sleep, read from the journal
/// (`RuntimeState.sleepDisabledByUs`) rather than inferred from the presence
/// of a session. The journal records what Insomnia asked pmset to do; it is
/// not live proof, so the line never promises the lid is safe to close.
/// Pure so it can be tested.
enum SleepHeldLine {
    struct Line: Equatable {
        let text: String
        let isWarning: Bool
    }

    static func line(sessionActive: Bool, sleepHeld: Bool) -> Line? {
        switch (sessionActive, sleepHeld) {
        case (true, true):
            Line(text: L10n.string("Sleep held per journal \u{2014} not verified live"), isWarning: false)
        case (true, false):
            Line(text: L10n.string("Sleep is not held \u{2014} this session is not keeping the Mac awake"), isWarning: true)
        case (false, true):
            Line(text: L10n.string("Sleep still held with no session"), isWarning: true)
        case (false, false):
            nil
        }
    }
}

/// macOS hides Wi-Fi network names until Location is allowed; say so rather
/// than reporting no network at all.
enum WiFiStatusName {
    static func display(ssid: String?, locationAuthorized: Bool) -> String? {
        if let ssid, !ssid.isEmpty { return ssid }
        return locationAuthorized ? nil : L10n.string("on (name hidden until Location is allowed)")
    }
}

/// Short label for a duration: "30m", "2h", "3d". Used by the preset list in
/// Settings.
func chipLabel(for seconds: TimeInterval) -> String {
    SessionMath.formatRemaining(seconds).replacingOccurrences(of: " ", with: "")
}
