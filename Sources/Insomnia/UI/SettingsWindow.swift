import AppKit
import SwiftUI

/// The settings window, owned by AppKit instead of SwiftUI's `Settings` scene.
///
/// `LSUIElement` apps have no app menu and, most of the time, no key window.
/// `NSApp.sendAction(Selector(("showSettingsWindow:")))` walks the responder
/// chain looking for whoever SwiftUI registered for that action and finds
/// nobody, so the scene never opens. (Quit works from the same menu because
/// `NSApplication.terminate` needs no responder chain at all.) Holding the
/// window ourselves removes the private selector and the guesswork.
@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let content: () -> AnyView
    private var languageObserver: NSObjectProtocol?

    init(content: @escaping () -> AnyView) {
        self.content = content
        languageObserver = NotificationCenter.default.addObserver(
            forName: LocalizationManager.languageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.window?.title = L10n.string("Insomnia Settings")
            }
        }
    }

    isolated deinit {
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
    }

    /// Bring the window up, creating it the first time. An accessory app has
    /// to activate itself first or the window opens behind whatever is front.
    func show() {
        let window = window ?? make()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func make() -> NSWindow {
        let language = LocalizationManager.shared.language
        let host = NSHostingController(rootView: content().environment(\.locale, language.locale))
        let window = NSWindow(contentViewController: host)
        window.title = L10n.string("Insomnia Settings", language: language)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        // Closing settings must not deallocate the window: the status item
        // keeps a reference and reopens the same one.
        window.isReleasedWhenClosed = false
        let size = SettingsLayout.windowContentSize
        window.contentMinSize = NSSize(width: size.width, height: size.height)
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.isRestorable = false
        return window
    }
}
