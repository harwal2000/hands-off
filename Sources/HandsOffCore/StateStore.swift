import Foundation

/// The files the menu bar app and the command-line tool share. Every write is atomic; anything left behind by a
/// process that has died is ignored.
public struct StateStore: Sendable {
    public let directory: URL
    let isAlive: @Sendable (Int32) -> Bool

    public init(directory: URL, isAlive: @escaping @Sendable (Int32) -> Bool = processIsAlive) {
        self.directory = directory
        self.isAlive = isAlive
    }

    /// `~/Library/Application Support/Hands Off`, or `$HANDSOFF_STATE_DIR`.
    public static func standard() -> StateStore {
        if let dir = ProcessInfo.processInfo.environment["HANDSOFF_STATE_DIR"], !dir.isEmpty {
            return StateStore(directory: URL(filePath: dir, directoryHint: .isDirectory))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StateStore(directory: support.appending(path: "Hands Off", directoryHint: .isDirectory))
    }

    var lockFile: URL { directory.appending(path: "keyboard.lock") }
    var waitingDirectory: URL { directory.appending(path: "waiting", directoryHint: .isDirectory) }
    var holdFile: URL { directory.appending(path: "hold.json") }
    var displayFile: URL { directory.appending(path: "display.json") }
    var promptFile: URL { directory.appending(path: "prompt.json") }
    var settingsFile: URL { directory.appending(path: "settings.json") }
    var appFile: URL { directory.appending(path: "app.json") }
    func startFile(pid: Int32) -> URL { directory.appending(path: "start-\(pid)") }

    // MARK: Keyboard lock

    /// The live holder, if any.
    public func holder() -> Holder? {
        guard let h: Holder = read(lockFile), isAlive(h.pid) else { return nil }
        return h
    }

    /// Takes the keyboard if nobody alive holds it.
    public func tryAcquire(_ holder: Holder) throws -> Bool {
        try tryLock(lockFile, holder, pid: holder.pid)
    }

    /// Creates `file` holding `value` unless a live process already owns it. The file is a hard link to a fully
    /// written one, so it appears atomically with its contents.
    private func tryLock<T: Encodable>(_ file: URL, _ value: T, pid: Int32) throws -> Bool {
        try ensureDirectory()
        let temp = directory.appending(path: ".lock-\(pid)-\(UUID().uuidString)")
        try JSONEncoder.handsOff.encode(value).write(to: temp)
        defer { unlink(temp.path) }
        for _ in 0..<2 {
            if link(temp.path, file.path) == 0 { return true }
            guard errno == EEXIST, removeStale(file) else { return false }
        }
        return false
    }

    private struct Owner: Decodable { var pid: Int32 }

    /// Removes a lock left by a dead process. Moves it aside first, so two agents clearing the same stale lock
    /// can't delete a fresh one; puts back anything that turns out to be alive.
    private func removeStale(_ file: URL) -> Bool {
        guard let current: Owner = read(file), !isAlive(current.pid) else { return false }
        let aside = directory.appending(path: ".stale-\(getpid())-\(UUID().uuidString)")
        guard rename(file.path, aside.path) == 0 else { return true }   // someone else moved it: try again
        defer { unlink(aside.path) }
        if let moved: Owner = read(aside), isAlive(moved.pid) {
            _ = link(aside.path, file.path)
            return false
        }
        return true
    }

    public func release(pid: Int32) {
        guard let h: Holder = read(lockFile), h.pid == pid else { return }
        unlink(lockFile.path)
    }

    // MARK: Asking first

    /// The live prompt, if an agent is asking.
    public func asking() -> Prompt? {
        guard let p: Prompt = read(promptFile), isAlive(p.pid) else { return nil }
        return p
    }

    /// Shows `prompt` unless another live agent is asking.
    public func tryAsk(_ prompt: Prompt) throws -> Bool {
        try tryLock(promptFile, prompt, pid: prompt.pid)
    }

    /// Changes the asking agent's own prompt (a new countdown).
    public func updatePrompt(_ prompt: Prompt) throws {
        guard asking()?.pid == prompt.pid else { return }
        try JSONEncoder.handsOff.encode(prompt).write(to: promptFile, options: .atomic)
    }

    public func endPrompt(pid: Int32) {
        unlink(startFile(pid: pid).path)
        guard let p: Prompt = read(promptFile), p.pid == pid else { return }
        unlink(promptFile.path)
    }

    /// The user clicked Start on this agent's prompt.
    public func answerStart(pid: Int32) {
        guard (read(promptFile) as Prompt?)?.pid == pid else { return }   // too late: it has started or gone
        try? ensureDirectory()
        FileManager.default.createFile(atPath: startFile(pid: pid).path, contents: nil)
    }

    /// True once after the user clicked Start for this agent.
    public func takeStart(pid: Int32) -> Bool {
        unlink(startFile(pid: pid).path) == 0
    }

    /// The user clicked Not now: agents wait `notNowSeconds`, then the next one asks again.
    public func sayNotNow(now: Date) throws {
        try writeHold(UserHold(until: now.addingTimeInterval(notNowSeconds), notNow: true))
    }

    public func settings() -> Settings { read(settingsFile) ?? Settings() }

    public func setConfirm(_ on: Bool) throws {
        var s = settings()
        s.confirm = on
        try ensureDirectory()
        try JSONEncoder.handsOff.encode(s).write(to: settingsFile, options: .atomic)
    }

    // MARK: Menu bar app

    private struct App: Codable { var pid: Int32 }

    /// The menu bar app says it's running (and so can show the prompt).
    public func writeApp(pid: Int32) throws {
        try ensureDirectory()
        try JSONEncoder.handsOff.encode(App(pid: pid)).write(to: appFile, options: .atomic)
    }

    public func removeApp(pid: Int32) {
        guard let a: App = read(appFile), a.pid == pid else { return }
        unlink(appFile.path)
    }

    public func appIsRunning() -> Bool {
        guard let a: App = read(appFile) else { return false }
        return isAlive(a.pid)
    }

    // MARK: Queue

    public func addWaiter(_ waiter: Waiter) throws {
        try FileManager.default.createDirectory(at: waitingDirectory, withIntermediateDirectories: true)
        try JSONEncoder.handsOff.encode(waiter).write(to: waitingDirectory.appending(path: "\(waiter.pid).json"), options: .atomic)
    }

    public func removeWaiter(pid: Int32) {
        unlink(waitingDirectory.appending(path: "\(pid).json").path)
    }

    /// Live waiters, oldest first.
    public func waiters() -> [Waiter] {
        let files = (try? FileManager.default.contentsOfDirectory(at: waitingDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { (url: URL) -> Waiter? in read(url) }
            .filter { isAlive($0.pid) }
            .sorted { $0.since < $1.since }
    }

    // MARK: "Hold on, I'm typing"

    public func hold(until: Date) throws {
        try writeHold(UserHold(until: until))
    }

    private func writeHold(_ hold: UserHold) throws {
        try ensureDirectory()
        try JSONEncoder.handsOff.encode(hold).write(to: holdFile, options: .atomic)
    }

    public func endHold() { unlink(holdFile.path) }

    /// The user's hold, while it's on.
    public func currentHold(now: Date) -> UserHold? {
        guard let h: UserHold = read(holdFile), h.until > now else { return nil }
        return h
    }

    /// When the user's hold ends, if one is on.
    public func holdEnds(now: Date) -> Date? { currentHold(now: now)?.until }

    // MARK: Virtual display

    public func writeDisplay(_ info: DisplayInfo) throws {
        try ensureDirectory()
        try JSONEncoder.handsOff.encode(info).write(to: displayFile, options: .atomic)
    }

    public func removeDisplay(pid: Int32) {
        guard let d: DisplayInfo = read(displayFile), d.pid == pid else { return }
        unlink(displayFile.path)
    }

    public func display() -> DisplayInfo? {
        guard let d: DisplayInfo = read(displayFile), isAlive(d.pid) else { return nil }
        return d
    }

    // MARK: Helpers

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.handsOff.decode(T.self, from: data)
    }
}

/// How long Not now makes agents wait before asking again.
public let notNowSeconds: Double = 120

/// True while a process with this ID exists (EPERM: it exists but belongs to someone else).
public func processIsAlive(_ pid: Int32) -> Bool {
    pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
}

extension JSONEncoder {
    static var handsOff: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var handsOff: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
