import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
protocol ScreenOnLidWatching: AnyObject {
    var isClosed: Bool { get }
    var onClosedImmediately: (() -> Void)? { get set }
    func start() -> Bool
    func stop()
}

extension LidObserver: ScreenOnLidWatching {}

/// Owns the app's temporary request to keep the display awake. Its lifetime
/// is independent of the journal-backed session until that session starts.
@MainActor
@Observable
final class ScreenOn {
    struct HandoffError: LocalizedError {
        var errorDescription: String? { L10n.string("Could not start the session while Screen On is active.") }
    }

    private let lid: any ScreenOnLidWatching
    private let acquire: () -> IOPMAssertionID?
    private let release: (IOPMAssertionID) -> Bool
    private var assertion: IOPMAssertionID?
    private(set) var warning: String?

    var isOn: Bool { assertion != nil }

    init(lid: any ScreenOnLidWatching, acquire: @escaping () -> IOPMAssertionID?, release: @escaping (IOPMAssertionID) -> Bool) {
        self.lid = lid
        self.acquire = acquire
        self.release = release
        lid.onClosedImmediately = { [weak self] in self?.lidClosed() }
    }

    static func live() -> ScreenOn {
        ScreenOn(lid: LidObserver(), acquire: {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Insomnia Screen On" as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                Log.error("Screen On: IOPMAssertionCreateWithName failed (\(result))")
                return nil
            }
            return id
        }, release: { id in
            let result = IOPMAssertionRelease(id)
            guard result == kIOReturnSuccess || result == kIOReturnNotFound else {
                Log.error("Screen On: IOPMAssertionRelease failed (\(result))")
                return false
            }
            return true
        })
    }

    func canToggle(sessionActive: Bool) -> Bool {
        isOn || (!sessionActive && !lid.isClosed)
    }

    /// expectedOn is the checkmark when the menu opened. A close can clear
    /// it during tracking, in which case the old action must not re-enable it.
    func toggle(expectedOn: Bool, sessionActive: Bool) {
        guard expectedOn == isOn else { return }
        if isOn {
            stop()
            return
        }
        guard canToggle(sessionActive: sessionActive) else { return }
        warning = nil
        guard lid.start() else {
            warning = L10n.string("Screen On needs to watch for lid closure.")
            return
        }
        // Recheck after registration so a close during setup is also seen.
        guard !lid.isClosed else {
            lid.stop()
            return
        }
        guard let id = acquire() else {
            lid.stop()
            warning = L10n.string("Could not turn on Screen On.")
            return
        }
        assertion = id
        if lid.isClosed { stop() }
    }

    @discardableResult
    func stop() -> Bool {
        guard isOn else { return true }
        guard releaseAssertion() else { return false }
        lid.stop()
        return true
    }

    private func lidClosed() {
        guard releaseAssertion() else { return }
        // Release the power assertion now. Tear down the notification port
        // after its callback returns, unless the user has turned the mode on again.
        Task { @MainActor [weak self] in
            guard let self, !isOn else { return }
            lid.stop()
        }
    }

    private func releaseAssertion() -> Bool {
        guard let assertion else { return true }
        guard release(assertion) else {
            warning = L10n.string("Could not turn off Screen On. Quit Insomnia to release it.")
            return false
        }
        self.assertion = nil
        warning = nil
        return true
    }

    isolated deinit {
        if let assertion { _ = release(assertion) }
        lid.stop()
    }
}
