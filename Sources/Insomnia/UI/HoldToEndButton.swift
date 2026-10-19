import SwiftUI

/// Press-and-hold "end session" control that sits to the right of the
/// countdown in the status item.
///
/// A ring draws around the glyph for `Motion.holdDuration` while the mouse
/// is down; only a completed ring ends the session. Releasing early, or
/// dragging away, springs the ring back with no action, so a stray click
/// while reaching for the menu bar clock cannot kill a session.
struct HoldToEndButton: View {
    let reduceMotion: Bool
    let action: () -> Void

    @State private var progress: CGFloat = 0
    /// Mouse is down and the ring is drawing.
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?

    private let ringDiameter: CGFloat = 18
    private let lineWidth: CGFloat = 1.6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color(brand: BrandPalette.violet), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .scaleEffect(holding && !reduceMotion ? 1.12 : 1)
        .animation(Motion.snappy(reduceMotion: reduceMotion), value: holding)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
        .overlay {
            HoldMouseSurface(onPress: {
                begin()
            }, onCancel: {
                release()
            }, onRelease: {
                release()
            })
        }
        .onDisappear { release() }
        .help("Hold to end the session")
        .accessibilityLabel("End session")
        .accessibilityHint("Press and hold")
        .accessibilityAction { action() }
    }

    /// Start drawing the ring and arm the completion.
    private func begin() {
        holding = true
        let duration = Motion.holdDuration
        withAnimation(.linear(duration: duration)) {
            progress = 1
        }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, holding else { return }
            fire()
        }
    }

    /// Released or dragged away before the ring closed: no action.
    private func release() {
        holdTask?.cancel()
        holdTask = nil
        holding = false
        withAnimation(Motion.snappy(reduceMotion: reduceMotion)) {
            progress = 0
        }
    }

    private func fire() {
        holdTask = nil
        holding = false
        action()
        // The view normally leaves with the session; if it stays (nothing to
        // end), the ring settles back so a second hold starts clean.
        withAnimation(Motion.snappy(reduceMotion: reduceMotion)) {
            progress = 0
        }
    }
}

/// Own the complete mouse sequence at the AppKit boundary. A cancelled press
/// stays consumed until mouse-up; it must never fall through to the status
/// button or be interpreted as a click on the extension editor.
struct HoldMouseSurface: NSViewRepresentable {
    let onPress: () -> Void
    let onCancel: () -> Void
    let onRelease: () -> Void

    func makeNSView(context: Context) -> HoldMouseView { HoldMouseView() }
    func updateNSView(_ view: HoldMouseView, context: Context) {
        view.onPress = onPress
        view.onCancel = onCancel
        view.onRelease = onRelease
    }
    static func dismantleNSView(_ view: HoldMouseView, coordinator: ()) {
        view.cancelPress()
    }
}

final class HoldMouseView: NSView {
    var onPress: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRelease: (() -> Void)?
    private var origin: NSPoint?
    private var cancelled = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        cancelPress()
        var ancestor = superview
        while let view = ancestor {
            if let host = view as? StatusHostingView {
                host.rightMouseDown(with: event)
                return
            }
            ancestor = view.superview
        }
        super.rightMouseDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        guard origin == nil else { return }
        origin = Self.screenPoint(event)
        cancelled = false
        onPress?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin, !cancelled else { return }
        let point = Self.screenPoint(event)
        if hypot(point.x - origin.x, point.y - origin.y) > 12 {
            cancelled = true
            onCancel?()
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard origin != nil else { return }
        origin = nil
        onRelease?()
    }
    private static func screenPoint(_ event: NSEvent) -> NSPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
    func cancelPress() {
        guard origin != nil else { return }
        origin = nil
        onCancel?()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelPress() }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// Status-bar windows can handle a press before SwiftUI's hosted responders.
/// Route the complete cross sequence before NSWindow/NSButton tracking starts.
/// Geometry comes from the laid-out native surface, never a hard-coded inset.
@MainActor
final class StatusHoldMouseRouter {
    private weak var host: NSView?
    private var captured: HoldMouseView?
    private var monitor: Any?

    init(host: NSView, installMonitor: Bool = true) {
        self.host = host
        if installMonitor {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.route(event) == true }
                return consumed ? nil : event
            }
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        captured?.cancelPress()
    }

    /// True means consumed, including the rest of a cancelled gesture.
    func route(_ event: NSEvent) -> Bool {
        if let captured {
            switch event.type {
            case .leftMouseDragged:
                if captured.window == nil { captured.cancelPress() }
                else { captured.mouseDragged(with: event) }
            case .leftMouseUp:
                captured.mouseUp(with: event)
                self.captured = nil
            case .rightMouseDown:
                captured.rightMouseDown(with: event)
            default: break
            }
            return true
        }
        guard event.type == .leftMouseDown || event.type == .rightMouseDown,
              let host, let window = host.window, let source = event.window,
              source.level == window.level else { return false }
        let point = source.convertPoint(toScreen: event.locationInWindow)
        func surface(in view: NSView) -> HoldMouseView? {
            guard !view.isHidden, view.alphaValue > 0 else { return nil }
            if let control = view as? HoldMouseView {
                let frame = window.convertToScreen(control.convert(control.bounds, to: nil)).intersection(window.frame)
                return frame.contains(point) ? control : nil
            }
            return view.subviews.lazy.compactMap { surface(in: $0) }.first
        }
        guard let control = surface(in: host) else { return false }
        if event.type == .rightMouseDown {
            control.rightMouseDown(with: event)
        } else {
            captured = control
            control.mouseDown(with: event)
        }
        return true
    }
}
