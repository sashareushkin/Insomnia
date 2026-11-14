import AppKit

/// Injectable so menu tracking can be checked without adding a real status item.
@MainActor
protocol StatusMenuHosting: AnyObject {
    var menu: NSMenu? { get set }
    func clickMenuButton()
}

extension NSStatusItem: StatusMenuHosting {
    func clickMenuButton() { button?.performClick(nil) }
}

/// Bounded status text inside an otherwise native menu. Long diagnostics
/// wrap instead of setting the width of every action in the menu.
@MainActor
enum StatusMenuLayout {
    static let statusWidth: CGFloat = 195
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 5

    static func statusView(text: String, isWarning: Bool) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = isWarning ? .systemOrange : .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        let textWidth = statusWidth - 2 * horizontalInset
        label.preferredMaxLayoutWidth = textWidth
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)) ?? .zero
        let height = ceil(size.height)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: statusWidth, height: height + 2 * verticalInset))
        label.frame = NSRect(x: horizontalInset, y: verticalInset, width: textWidth, height: height)
        label.autoresizingMask = [.width]
        view.addSubview(label)
        return view
    }

    static func popUp(_ menu: NSMenu, from host: any StatusMenuHosting) {
        let previous = host.menu
        host.menu = menu
        // Use AppKit's native status-item positioning, then return left
        // clicks to the timer controls as soon as menu tracking ends.
        defer { host.menu = previous }
        host.clickMenuButton()
    }
}
