import AppKit
import HandsOffCore

enum CLI {
    static let usage = """
    Hands Off: agents test on a virtual display and take turns with the keyboard.

    Usage:
      handsoff focus [options] -- <command> [args…]
          Waits until you're not typing (and nobody else has the keyboard), asks you from the menu bar
          (it starts by itself after 10 s; Not now makes agents wait 2 minutes, then asks again), shows
          "Hands off" in the menu bar, runs the command, then lets go. Wrap anything that takes keyboard
          focus or posts key events. Several steps: handsoff focus -- sh -c '…'
          --reason <text>   what it's doing, shown in the menu bar (default: the command)
          --seconds <n>     how long it expects to need, for the countdown
          --idle <n>        seconds without a key press or click before taking over (default 5)
          --wait <n>        give up after this many seconds of waiting (default 1800)
          --label <text>    who is asking (default: the git repo and branch)
          --allow-input     don't fail when the user presses a key or clicks during the hold
          Exits with the command's status, or 75 when waiting gave up or the user pressed a key or
          clicked during the hold (results may be wrong: run it again).

      handsoff display [--appkit | --cg]
          The virtual display's frame as JSON, or "x y width height" in AppKit (NSWindow, y up from the
          main display's bottom) or CoreGraphics (y down from its top) coordinates. Starts the app if needed.

      handsoff screenshot <file.png>
          Captures the virtual display only, never your screens (needs Screen Recording for the terminal).

      handsoff status          What the menu bar shows (including a prompt that's waiting for an answer).
      handsoff config confirm on|off
          Whether to ask before each hold (on by default; also in the menu: "Ask before each hold").
      handsoff hold [minutes]  Make agents wait (default 15 minutes), like the menu's "Hold on, I'm typing".
      handsoff resume          End the hold.
      handsoff quit-app        Quit the menu bar app (turns the virtual display off).
    """

    static func run(_ args: [String]) -> Int32 {
        let rest = Array(args.dropFirst())
        switch args[0] {
        case "focus": return focus(rest)
        case "display": return display(rest)
        case "screenshot": return screenshot(rest)
        case "status": return status()
        case "hold": return hold(rest)
        case "config": return config(rest)
        case "resume": StateStore.standard().endHold(); print("Agents can take the keyboard again."); return 0
        case "quit-app": return quitApp()
        case "_open-menu":   // undocumented: for README screenshots (wrap it in handsoff focus: a menu takes the keyboard)
            DistributedNotificationCenter.default().postNotificationName(.init("com.harwal2000.handsoff.openMenu"), object: args.dropFirst().first, userInfo: nil, deliverImmediately: true)
            return 0
        case "help", "-h", "--help": print(usage); return 0
        default: return fail("unknown command \"\(args[0])\"\n\n\(usage)", code: 2)
        }
    }

    static func fail(_ message: String, code: Int32 = 1) -> Int32 {
        FileHandle.standardError.write(Data("handsoff: \(message)\n".utf8))
        return code
    }

    static func note(_ message: String) {
        FileHandle.standardError.write(Data("handsoff: \(message)\n".utf8))
    }

    // MARK: focus

    static func focus(_ args: [String]) -> Int32 {
        var reason: String?, seconds: Double?, idle = 5.0, maxWait = 1800.0, label: String?, allowInput = false
        var i = 0
        func value() -> String? { i += 1; return i < args.count ? args[i] : nil }
        while i < args.count, args[i] != "--" {
            switch args[i] {
            case "--reason": reason = value()
            case "--seconds": seconds = value().flatMap(Double.init)
            case "--idle": idle = value().flatMap(Double.init) ?? idle
            case "--wait": maxWait = value().flatMap(Double.init) ?? maxWait
            case "--label": label = value()
            case "--allow-input": allowInput = true
            default: return fail("focus: unknown option \(args[i]) (put the command after --)", code: 2)
            }
            i += 1
        }
        let command = Array(args.dropFirst(i + 1))
        guard i < args.count, !command.isEmpty else { return fail("focus: put the command after --, e.g. handsoff focus -- make ui-test", code: 2) }

        let store = StateStore.standard()
        let me = getpid()
        // Nested call (a wrapped script calls handsoff focus again): the outer call already has the keyboard.
        if let outer = ProcessInfo.processInfo.environment["HANDSOFF_HOLDER"].flatMap(Int32.init), store.holder()?.pid == outer {
            return Child.run(command, holder: outer)
        }

        if AppBundle.launch(), store.settings().confirm {
            // A menu bar app that's only just starting can't ask yet: give it a moment rather than skip the prompt.
            for _ in 0..<15 where !store.appIsRunning() { Thread.sleep(forTimeInterval: 0.2) }
        }
        let holder = Holder(reason: reason ?? command.joined(separator: " "), label: label ?? defaultLabel(),
                            pid: me, started: Date(), seconds: seconds)
        Cleanup.install(store: store, pid: me)

        let environment = FocusEnvironment(now: Date.init, sleep: { Thread.sleep(forTimeInterval: $0) },
                                           secondsSinceInput: secondsSinceUserInput, canAsk: store.appIsRunning)
        let outcome: WaitOutcome
        do {
            outcome = try waitForTurn(store: store, holder: holder, idle: idle, maxWait: maxWait, environment: environment) { reason in
                switch reason {
                case .userHold(let until): note("waiting: the user asked agents to hold on until \(until.formatted(date: .omitted, time: .shortened))")
                case .notNow(let until): note("waiting: the user said Not now; asking again at \(until.formatted(date: .omitted, time: .standard))")
                case .anotherAgent(let label): note("waiting: \(label) has the keyboard")
                case .anotherPrompt(let label): note("waiting: the user is being asked about \(label)'s turn")
                case .userActive: note("waiting: the user is typing or clicking (takes over after \(Int(idle)) s without)")
                case .asking: note("asking the user first: starts in 10 s unless they say Not now (keys and clicks restart the countdown)")
                }
            }
        } catch {
            return fail("couldn't write to \(store.directory.path): \(error.localizedDescription)")
        }
        guard outcome == .acquired else {
            return fail("gave up waiting for the keyboard after \(Int(maxWait)) s; try again later", code: 75)
        }
        let started = store.holder()?.started ?? Date()
        note("you have the keyboard: \(holder.reason)")
        let status = Child.run(command, holder: me)
        let touched = userTouched(holdStarted: started, now: Date(), secondsSinceInput: secondsSinceUserInput())
        store.release(pid: me)
        if touched && !allowInput {
            return fail("""
            the user pressed a key or clicked while you had the keyboard, so focus may have moved and \
            what the command saw (screenshots, key events, focus) may be wrong. Run it again. \
            (The command itself exited with \(status).)
            """, code: 75)
        }
        return status
    }

    /// "<repo> · <branch>" from git, or the folder's name.
    static func defaultLabel() -> String {
        func git(_ args: String...) -> String? {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(filePath: "/usr/bin/git")
            p.arguments = args
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            p.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return p.terminationStatus == 0 && !out.isEmpty ? out : nil
        }
        let folder = URL(filePath: FileManager.default.currentDirectoryPath).lastPathComponent
        guard let top = git("rev-parse", "--show-toplevel") else { return folder }
        let repo = URL(filePath: top).lastPathComponent
        if let branch = git("branch", "--show-current") { return "\(repo) · \(branch)" }
        return repo
    }

    // MARK: display, screenshot

    static func waitForDisplay() -> DisplayInfo? {
        let store = StateStore.standard()
        if let d = store.display() { return d }
        guard AppBundle.launch() else { return nil }
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.2)
            if let d = store.display() { return d }
        }
        return nil
    }

    static let noDisplay = "the virtual display isn't on. Open Hands Off.app (and check its menu: the display may be turned off)."

    static func display(_ args: [String]) -> Int32 {
        guard let d = waitForDisplay() else { return fail(noDisplay) }
        func plain(_ r: Rect) -> String { [r.x, r.y, r.width, r.height].map { String(Int($0)) }.joined(separator: " ") }
        switch args.first {
        case "--appkit": print(plain(d.appKit))
        case "--cg": print(plain(d.cg))
        case nil: print(String(decoding: try! JSONEncoder.pretty.encode(d), as: UTF8.self))
        default: return fail("display: unknown option \(args[0])", code: 2)
        }
        return 0
    }

    static func screenshot(_ args: [String]) -> Int32 {
        guard let path = args.first else { return fail("screenshot: give a file, e.g. handsoff screenshot /tmp/shot.png", code: 2) }
        guard let d = waitForDisplay() else { return fail(noDisplay) }
        guard let index = activeDisplays().firstIndex(of: d.id) else { return fail("the virtual display isn't active") }
        let p = Process()
        p.executableURL = URL(filePath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-D", String(index + 1), path]
        do { try p.run() } catch { return fail("couldn't run screencapture: \(error.localizedDescription)") }
        p.waitUntilExit()
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: path) else {
            return fail("screencapture failed; the terminal running this needs Screen Recording permission (System Settings → Privacy & Security)")
        }
        print(path)
        return 0
    }

    static func quitApp() -> Int32 {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: AppBundle.identifier)
        apps.forEach { $0.terminate() }
        for _ in 0..<50 where apps.contains(where: { !$0.isTerminated }) { Thread.sleep(forTimeInterval: 0.1) }
        return 0
    }

    // MARK: status, hold

    static func status() -> Int32 {
        let store = StateStore.standard()
        let now = Date()
        switch Status.read(from: store, now: now) {
        case .idle: print("No agent needs the keyboard.")
        case .waiting(let ws): print("Waiting for the keyboard:"); ws.forEach { print("  \($0.label): \($0.reason)") }
        case .onHold(let until, let notNow, let ws):
            if notNow {
                print("The user said Not now. Agents wait until \(until.formatted(date: .omitted, time: .standard)), then the next one asks again.")
            } else {
                print("Agents are on hold until \(until.formatted(date: .omitted, time: .shortened)).")
            }
            ws.forEach { print("  waiting: \($0.label): \($0.reason)") }
        case .asking(let p, let ws):
            let expected = p.seconds.map { ", about \(Int($0)) s" } ?? ""
            let left = max(0, Int(p.startsAt.timeIntervalSince(now).rounded(.up)))
            print("Asking the user: \(p.label) wants the keyboard (\(p.reason)\(expected)). Starts in \(left) s unless they say Not now.")
            ws.forEach { print("  waiting: \($0.label): \($0.reason)") }
        case .holding(let h, let ws, _):
            let elapsed = Int(now.timeIntervalSince(h.started))
            let expected = h.seconds.map { ", expects about \(Int($0)) s" } ?? ""
            print("Hands off: \(h.label) has the keyboard (\(h.reason)), \(elapsed) s so far\(expected). Menu bar: \(Status.read(from: store, now: now).menuBarTitle(now: now))")
            ws.forEach { print("  waiting: \($0.label): \($0.reason)") }
        }
        print("Asks before each hold: \(store.settings().confirm ? "on" : "off") (handsoff config confirm on|off)")
        if let d = store.display() {
            print("Virtual display \(d.id): \(Int(d.appKit.width))×\(Int(d.appKit.height)) @\(Int(d.scale))x at AppKit (\(Int(d.appKit.x)), \(Int(d.appKit.y)))")
        } else {
            print("Virtual display: off (Hands Off.app isn't running or the display is turned off).")
        }
        return 0
    }

    static func hold(_ args: [String]) -> Int32 {
        let minutes = args.first.flatMap(Double.init) ?? 15
        let until = Date().addingTimeInterval(minutes * 60)
        do { try StateStore.standard().hold(until: until) } catch { return fail(error.localizedDescription) }
        print("Agents will wait until \(until.formatted(date: .omitted, time: .shortened)) (handsoff resume to end it).")
        return 0
    }

    static func config(_ args: [String]) -> Int32 {
        let store = StateStore.standard()
        switch (args.first, args.dropFirst().first) {
        case (nil, _), ("confirm", nil):
            print("confirm \(store.settings().confirm ? "on" : "off")   (ask before each hold)")
            return 0
        case ("confirm", let value?) where ["on", "off"].contains(value):
            do { try store.setConfirm(value == "on") } catch { return fail(error.localizedDescription) }
            print(value == "on" ? "Hands Off asks before each hold." : "Hands Off no longer asks before each hold.")
            return 0
        default:
            return fail("config: use handsoff config confirm on|off", code: 2)
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
