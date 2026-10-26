import AppKit
import HandsOffCore

/// The prompt under the menu bar item before a hold: who's asking, why, for how long, the countdown, Start and Not now.
/// It never takes keyboard focus or activates the app: it's a non-activating panel that can't become key, so typing
/// goes on in whatever app the user is in.
@MainActor final class PromptPanel {
    var onStart: (Int32) -> Void = { _ in }
    var onNotNow: () -> Void = {}

    private var panel: NSPanel?
    private var shown: (Prompt, Int)?
    private let countdown = NSTextField(labelWithString: "")
    private static let width: CGFloat = 340

    /// Shows or refreshes the prompt. `others` is how many agents wait behind it; `item` is the menu bar item's frame.
    func show(_ prompt: Prompt, others: Int, now: Date, below item: NSRect?) {
        let left = max(0, Int(prompt.startsAt.timeIntervalSince(now).rounded(.up)))
        countdown.stringValue = "Starts in \(left) s"
        if let shown, shown.0.pid == prompt.pid, shown.0.reason == prompt.reason, shown.0.label == prompt.label,
           shown.0.seconds == prompt.seconds, shown.1 == others, panel?.isVisible == true { return }
        shown = (prompt, others)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let content = makeContent(prompt, others: others)
        panel.contentView = content
        let size = content.fittingSize
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft(size: size, below: item))
        panel.orderFrontRegardless()
        panel.invalidateShadow()   // follow the rounded corners
    }

    func hide() {
        panel?.orderOut(nil)
        shown = nil
    }

    /// The window number, for screenshots.
    var windowNumber: Int? { panel?.isVisible == true ? panel?.windowNumber : nil }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func makeContent(_ prompt: Prompt, others: Int) -> NSView {
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 20, weight: .regular).applying(.init(paletteColors: [.systemOrange])))!)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let textWidth = Self.width - 16 - 28 - 10 - 16
        func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: text)
            l.font = font
            l.textColor = color
            l.preferredMaxLayoutWidth = textWidth
            return l
        }
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        var lines: [NSView] = [
            label("\(prompt.label) wants the keyboard", font: .boldSystemFont(ofSize: NSFont.systemFontSize)),
            label(prompt.reason, font: .systemFont(ofSize: NSFont.systemFontSize)),
        ]
        let duration = prompt.seconds.map { "For about \(Self.duration($0)). " } ?? ""
        lines.append(label(duration + "Typing or clicking restarts the countdown.", font: small, color: .secondaryLabelColor))
        if others > 0 {
            lines.append(label(others == 1 ? "1 more agent is waiting after this one." : "\(others) more agents are waiting after this one.",
                               font: small, color: .secondaryLabelColor))
        }
        let text = NSStackView(views: lines)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(6, after: lines[1])

        countdown.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        countdown.textColor = .systemOrange
        let notNow = FirstClickButton(title: "Not now", target: self, action: #selector(notNowClicked))
        let start = AccentButton(title: "Start", target: self, action: #selector(startClicked))
        start.tag = Int(prompt.pid)
        let buttons = NSStackView(views: [countdown, NSView(), notNow, start])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let top = NSStackView(views: [icon, text])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 10
        let all = NSStackView(views: [top, buttons])
        all.orientation = .vertical
        all.alignment = .leading
        all.spacing = 14
        all.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        all.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(all)
        NSLayoutConstraint.activate([
            all.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            all.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            all.topAnchor.constraint(equalTo: background.topAnchor),
            all.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            all.widthAnchor.constraint(equalToConstant: Self.width),
            buttons.widthAnchor.constraint(equalTo: all.widthAnchor, constant: -32),
            icon.widthAnchor.constraint(equalToConstant: 28),
            start.heightAnchor.constraint(equalTo: notNow.heightAnchor),
            start.widthAnchor.constraint(equalTo: notNow.widthAnchor, multiplier: 0.8),
        ])
        return background
    }

    /// Under the menu bar item, kept on its screen. `HANDSOFF_PROMPT_AT="x y"` (the top left, in AppKit coordinates)
    /// puts it somewhere else, so a test copy can show it on the virtual display.
    private func topLeft(size: NSSize, below item: NSRect?) -> NSPoint {
        if let at = ProcessInfo.processInfo.environment["HANDSOFF_PROMPT_AT"]?.split(separator: " ").compactMap({ Double($0) }), at.count == 2 {
            return NSPoint(x: at[0], y: at[1])
        }
        guard let item, let screen = NSScreen.screens.first(where: { $0.frame.intersects(item) }) ?? NSScreen.main else {
            return NSPoint(x: 100, y: (NSScreen.main?.visibleFrame.maxY ?? 800) - 8)
        }
        let x = min(max(item.minX, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        return NSPoint(x: x, y: item.minY - 6)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 90 { return "\(s) s" }
        return "\(Int((Double(s) / 60).rounded())) min"
    }

    @objc private func startClicked(_ sender: NSButton) {
        onStart(Int32(sender.tag))
    }

    @objc private func notNowClicked() {
        onNotNow()
    }
}

/// Answers the first click, even though its panel never becomes the key window.
private class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Start, in the accent colour. AppKit draws every button in a window that isn't key as inactive (grey), and this
/// panel never becomes key, so it draws its own background.
private final class AccentButton: FirstClickButton {
    convenience init(title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.white,
        ])
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = (bounds.height * 0.27).rounded()   // as the system draws Not now next to it
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.7 : 1).cgColor
        }
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }
}
