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

    var state: EndHoldState? = nil
    @State private var localState = EndHoldState()
    private var hold: EndHoldState { state ?? localState }

    private let ringDiameter: CGFloat = 18
    private let lineWidth: CGFloat = 1.6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: hold.progress)
                .stroke(Color(brand: BrandPalette.violet), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .scaleEffect(hold.holding && !reduceMotion ? 1.12 : 1)
        .animation(Motion.snappy(reduceMotion: reduceMotion), value: hold.holding)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
        .overlay {
            HoldMouseSurface(onPress: { stillPressed in
                hold.begin(reduceMotion: reduceMotion, stillPressed: stillPressed, action: { action() })
            }, onCancel: {
                hold.cancel()
            }, onRelease: {
                hold.cancel()
            }, cancelOnRemoval: state == nil)
        }
        .onDisappear { if state == nil { hold.cancel() } }
        .help("Hold to end the session")
        .accessibilityLabel("End session")
        .accessibilityHint("Press and hold")
        .accessibilityAction { action() }
    }

}

/// Owned by the menu-bar model: snapshot/reparenting of SwiftUI/native views
/// must not cancel a physical press. Only release, movement, session end or
/// controller teardown cancel it.
@MainActor
@Observable
final class EndHoldState {
    private(set) var progress: CGFloat = 0
    private(set) var holding = false
    @ObservationIgnored private var task: Task<Void, Never>?
    private var reduceMotion = false

    func begin(reduceMotion: Bool, stillPressed: @escaping @MainActor () -> Bool, action: @escaping @MainActor () -> Void) {
        cancel()
        self.reduceMotion = reduceMotion
        holding = true
        withAnimation(.linear(duration: Motion.holdDuration)) { progress = 1 }
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Motion.holdDuration))
            guard !Task.isCancelled, holding else { return }
            guard stillPressed() else { cancel(); return }
            task = nil
            holding = false
            action()
            withAnimation(Motion.snappy(reduceMotion: reduceMotion)) { progress = 0 }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        holding = false
        withAnimation(Motion.snappy(reduceMotion: reduceMotion)) { progress = 0 }
    }

    isolated deinit { task?.cancel() }
}

/// Own the complete mouse sequence at the AppKit boundary. A cancelled press
/// stays consumed until mouse-up; it must never fall through to the status
/// button or be interpreted as a click on the extension editor.
struct HoldMouseSurface: NSViewRepresentable {
    let onPress: (@escaping @MainActor () -> Bool) -> Void
    let onCancel: () -> Void
    let onRelease: () -> Void
    var cancelOnRemoval = true

    func makeNSView(context: Context) -> HoldMouseView { HoldMouseView() }
    func updateNSView(_ view: HoldMouseView, context: Context) {
        view.onPress = { [weak view] in
            onPress { [weak view] in view?.canCompletePress == true }
        }
        view.cancelOnRemoval = cancelOnRemoval
        view.onCancel = onCancel
        view.onRelease = onRelease
    }
    static func dismantleNSView(_ view: HoldMouseView, coordinator: ()) {
        if view.cancelOnRemoval { view.cancelPress() }
    }
}

final class HoldMouseView: NSView {
    var onPress: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRelease: (() -> Void)?
    var cancelOnRemoval = true
    var completionCheck: (@MainActor () -> Bool)?
    var pressWithinThreshold: Bool { origin != nil && !cancelled }
    var canCompletePress: Bool { pressWithinThreshold && (completionCheck?() ?? true) }
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
        beginPress(at: Self.screenPoint(event))
    }
    override func mouseDragged(with event: NSEvent) {
        dragPress(to: Self.screenPoint(event))
    }
    func beginPress(at point: NSPoint) {
        guard origin == nil else { return }
        origin = point
        cancelled = false
        onPress?()
    }
    func dragPress(to point: NSPoint) {
        guard let origin, !cancelled else { return }
        if hypot(point.x - origin.x, point.y - origin.y) > 12 {
            cancelled = true
            onCancel?()
        }
    }
    override func mouseUp(with event: NSEvent) { releasePress() }
    func releasePress() {
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
        if newWindow == nil, cancelOnRemoval { cancelPress() }
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
    private let pointerLocation: @MainActor () -> NSPoint
    private let buttonIsDown: @MainActor () -> Bool
    private var poll: Timer?
    private let watchesPointer: Bool

    init(host: NSView, installMonitor: Bool = true, pointerLocation: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation }, buttonIsDown: @escaping @MainActor () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }) {
        self.host = host
        self.pointerLocation = pointerLocation
        self.buttonIsDown = buttonIsDown
        self.watchesPointer = installMonitor
        if installMonitor {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
                let consumed = MainActor.assumeIsolated { self?.route(event) == true }
                return consumed ? nil : event
            }
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        poll?.invalidate()
        captured?.cancelPress()
    }

    /// True means consumed, including the rest of a cancelled gesture.
    func route(_ event: NSEvent) -> Bool {
        if let captured {
            switch event.type {
            case .leftMouseDragged:
                captured.dragPress(to: pointerLocation())
            case .leftMouseUp:
                // A replica can deliver a synthetic click pair while the
                // physical button is still down. The pointer poll owns the
                // actual release in that case; don't abort a real hold.
                guard !buttonIsDown() else { return true }
                captured.releasePress()
                self.captured = nil
                stopPolling()
            case .leftMouseDown:
                captured.cancelPress()
                self.captured = nil
                stopPolling()
                return route(event)
            case .rightMouseDown:
                captured.rightMouseDown(with: event)
                stopPolling()
            default: break
            }
            return true
        }
        guard event.type == .leftMouseDown || event.type == .rightMouseDown,
              let host, let window = host.window, let source = event.window,
              source.level == window.level else { return false }
        // Status-bar replicants synthesize event.locationInWindow at the
        // window centre, regardless of the clicked region. Read the actual
        // pointer in screen coordinates before NSWindow tracks that event.
        let point = pointerLocation()
        func surface(in view: NSView) -> HoldMouseView? {
            guard !view.isHidden, view.alphaValue > 0 else { return nil }
            if let control = view as? HoldMouseView {
                let frame = window.convertToScreen(control.convert(control.bounds, to: nil)).intersection(window.frame)
                return frame.contains(point) ? control : nil
            }
            return view.subviews.lazy.compactMap { surface(in: $0) }.first
        }
        let found = surface(in: host)
        guard let control = found else { return false }
        if event.type == .rightMouseDown {
            control.rightMouseDown(with: event)
        } else {
            captured = control
            control.completionCheck = { [weak self, weak control] in
                guard let self, let control, self.buttonIsDown() else { return false }
                control.dragPress(to: self.pointerLocation())
                return control.pressWithinThreshold
            }
            if event.modifierFlags.contains(.control) { control.rightMouseDown(with: event) }
            else { control.beginPress(at: point); startPolling() }
        }
        return true
    }
    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    private func startPolling() {
        stopPolling()
        guard watchesPointer else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let captured = self.captured else { return }
                if !self.buttonIsDown() {
                    captured.releasePress()
                    self.stopPolling()
                } else {
                    captured.dragPress(to: self.pointerLocation())
                    if !captured.pressWithinThreshold { self.stopPolling() }
                }
            }
        }
        poll = timer
        RunLoop.main.add(timer, forMode: .common)
    }

}
