import AppKit
import HandsOffCore
import ServiceManagement

/// The menu bar item: says when an agent wants or has the keyboard, lets the user make agents wait, and owns
/// the virtual display.
@MainActor final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = StateStore.standard()
    private lazy var display = VirtualDisplayController(store: store)
    private let prompt = PromptPanel()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastRendered: (String, String)?
    private var lastItemFrame = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)   // already running
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        try? store.writeApp(pid: getpid())
        prompt.onStart = { [weak self] pid in self?.store.answerStart(pid: pid); self?.render() }
        prompt.onNotNow = { [weak self] in try? self?.store.sayNotNow(now: Date()); self?.render() }
        // HANDSOFF_VIRTUAL_DISPLAY=off: a second copy, run for testing next to the installed one, adds no display.
        if ProcessInfo.processInfo.environment["HANDSOFF_VIRTUAL_DISPLAY"] != "off" { display.turnOn() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.display.publish() }
        }
        // For README screenshots: `handsoff _open-menu <seconds>` opens the menu and closes it again.
        DistributedNotificationCenter.default().addObserver(forName: .init("com.harwal2000.handsoff.openMenu"), object: nil, queue: .main) { [weak self] note in
            let seconds = Double(note.object as? String ?? "") ?? 3
            MainActor.assumeIsolated { self?.openMenuBriefly(seconds: seconds) }
        }
        render()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.removeApp(pid: getpid())
        display.turnOff()
    }

    private func openMenuBriefly(seconds: Double) {
        let close = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem.menu?.cancelTracking() }
        }
        RunLoop.main.add(close, forMode: .eventTracking)
        statusItem.button?.performClick(nil)
    }

    // MARK: Menu bar item

    private func render() {
        let now = Date()
        let status = Status.read(from: store, now: now)
        let title = status.menuBarTitle(now: now)
        if case .asking(let p, let others) = status {
            prompt.show(p, others: others.count, now: now, below: statusItem.button?.window?.frame)
        } else {
            prompt.hide()
        }
        let (symbol, color): (String, NSColor?) = switch status {
        case .idle: ("hand.raised", nil)
        case .waiting, .asking: ("hand.raised", .systemOrange)
        case .onHold: ("pause.circle", nil)
        case .holding: ("hand.raised.fill", .systemRed)
        }
        let key = (symbol + (color?.description ?? ""), title)
        recordItemFrame()
        if let lastRendered, lastRendered == key { return }
        lastRendered = key

        guard let button = statusItem.button else { return }
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hands Off")
        if let color {
            image = image?.withSymbolConfiguration(.init(paletteColors: [color]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        button.image = image
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
        if let color {
            attributes[.foregroundColor] = color
            attributes[.font] = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        }
        button.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " " + title, attributes: attributes)
        button.toolTip = tooltip(status)
    }

    /// Where the menu bar item is, in CoreGraphics screen coordinates, for scripts that record it (README GIFs).
    private func recordItemFrame() {
        guard let window = statusItem.button?.window else { return }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let f = window.frame
        let text = "\(Int(f.minX)) \(Int(mainHeight - f.maxY)) \(Int(f.width)) \(Int(f.height))\n"
        guard text != lastItemFrame, f.height > 0 else { return }
        lastItemFrame = text
        try? text.write(to: store.directory.appending(path: "menubar-item.txt"), atomically: true, encoding: .utf8)
    }

    private func tooltip(_ status: Status) -> String {
        switch status {
        case .idle: "Hands Off: no agent needs the keyboard"
        case .waiting: "An agent wants the keyboard. It takes over when you stop typing for a few seconds."
        case .asking(let p, _): "\(p.label) wants the keyboard (\(p.reason)). It starts by itself unless you say Not now."
        case .onHold: "Agents are waiting until you let them continue"
        case .holding(let h, _, _): "Hands off: \(h.label) has the keyboard (\(h.reason))"
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        let status = Status.read(from: store, now: now)

        // Status lines can't be clicked, but they're the point of the menu. A disabled item is always drawn greyed
        // out, so they're plain labels instead (which also don't highlight under the pointer).
        func line(_ text: String, bold: Bool = false, indent: Int = 0) {
            let font = bold ? NSFont.boldSystemFont(ofSize: NSFont.systemFontSize) : NSFont.menuFont(ofSize: 0)
            let color: NSColor = bold || indent == 0 ? .labelColor : .secondaryLabelColor
            let label = NSTextField(labelWithAttributedString: NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
            let size = label.fittingSize
            let left = 14 + CGFloat(indent) * 12
            let view = NSView(frame: NSRect(x: 0, y: 0, width: left + size.width + 16, height: 22))
            label.frame = NSRect(x: left, y: (22 - size.height) / 2, width: size.width, height: size.height)
            view.addSubview(label)
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.view = view
            menu.addItem(item)
        }
        func waiting(_ ws: [Waiter]) {
            guard !ws.isEmpty else { return }
            line(ws.count == 1 ? "Waiting for the keyboard:" : "\(ws.count) agents waiting for the keyboard:")
            ws.forEach { line("\($0.label): \($0.reason)", indent: 1) }
        }

        switch status {
        case .idle:
            line("No agent needs the keyboard")
        case .waiting(let ws):
            line("An agent wants the keyboard", bold: true)
            line("It takes over once you stop typing and clicking for a few seconds.")
            ws.forEach { line("\($0.label): \($0.reason)", indent: 1) }
        case .onHold(let until, let notNow, let ws):
            if notNow {
                line("You said Not now. Asking again at \(until.formatted(date: .omitted, time: .shortened))", bold: true)
            } else {
                line("Agents are waiting until \(until.formatted(date: .omitted, time: .shortened))", bold: true)
            }
            waiting(ws)
        case .asking(let p, let ws):
            line("An agent is asking for the keyboard", bold: true)
            line("\(p.label): \(p.reason)", indent: 1)
            let left = max(0, Int(p.startsAt.timeIntervalSince(now).rounded(.up)))
            line("Starts in \(left) s unless you say Not now", indent: 1)
            waiting(ws)
        case .holding(let h, let ws, let holdEnds):
            line("Hands off: an agent has the keyboard", bold: true)
            line("\(h.label): \(h.reason)", indent: 1)
            let elapsed = Int(now.timeIntervalSince(h.started))
            line(h.seconds.map { "\(elapsed) s so far, expects about \(Int($0)) s" } ?? "\(elapsed) s so far", indent: 1)
            if holdEnds != nil { line("Your hold starts when it lets go.", indent: 1) }
            waiting(ws)
        }

        menu.addItem(.separator())
        if store.holdEnds(now: now) != nil {
            menu.addItem(action("Let agents continue", #selector(endHold)))
        } else {
            let hold = NSMenuItem(title: "Hold on, I'm typing", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, minutes) in [("For 5 minutes", 5), ("For 15 minutes", 15), ("For 1 hour", 60)] {
                let item = action(title, #selector(startHold(_:)))
                item.tag = minutes
                sub.addItem(item)
            }
            hold.submenu = sub
            menu.addItem(hold)
        }

        menu.addItem(.separator())
        if let d = store.display(), display.isOn {
            line("Virtual display: \(Int(d.appKit.width)) × \(Int(d.appKit.height)) @\(Int(d.scale))x")
            let apps = display.appsOnDisplay()
            line(apps.isEmpty ? "Nothing on it" : "On it: " + apps.joined(separator: ", "), indent: 1)
            menu.addItem(action("Turn off virtual display (its windows move to your screen)", #selector(toggleDisplay)))
        } else {
            line("Virtual display: off")
            menu.addItem(action("Turn on virtual display", #selector(toggleDisplay)))
        }

        menu.addItem(.separator())
        let confirm = action("Ask before each hold", #selector(toggleConfirm))
        confirm.state = store.settings().confirm ? .on : .off
        menu.addItem(confirm)
        let login = action("Open at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(action("Quit Hands Off", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func action(_ title: String, _ selector: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func startHold(_ sender: NSMenuItem) {
        try? store.hold(until: Date().addingTimeInterval(Double(sender.tag) * 60))
        render()
    }

    @objc private func endHold() {
        store.endHold()
        render()
    }

    @objc private func toggleConfirm() {
        try? store.setConfirm(!store.settings().confirm)
    }

    @objc private func toggleDisplay() {
        if display.isOn { display.turnOff() } else { display.turnOn() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
