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

    // MARK: Keyboard lock

    /// The live holder, if any.
    public func holder() -> Holder? {
        guard let h: Holder = read(lockFile), isAlive(h.pid) else { return nil }
        return h
    }

    /// Takes the keyboard if nobody alive holds it. The lock is a hard link to a fully written file, so it appears
    /// atomically with its contents.
    public func tryAcquire(_ holder: Holder) throws -> Bool {
        try ensureDirectory()
        let temp = directory.appending(path: ".lock-\(holder.pid)-\(UUID().uuidString)")
        try JSONEncoder.handsOff.encode(holder).write(to: temp)
        defer { unlink(temp.path) }
        for _ in 0..<2 {
            if link(temp.path, lockFile.path) == 0 { return true }
            guard errno == EEXIST, removeStaleLock() else { return false }
        }
        return false
    }

    /// Removes a lock left by a dead process. Moves it aside first, so two agents clearing the same stale lock
    /// can't delete a fresh one; puts back anything that turns out to be alive.
    private func removeStaleLock() -> Bool {
        guard let current: Holder = read(lockFile), !isAlive(current.pid) else { return false }
        let aside = directory.appending(path: ".stale-\(getpid())-\(UUID().uuidString)")
        guard rename(lockFile.path, aside.path) == 0 else { return true }   // someone else moved it: try again
        defer { unlink(aside.path) }
        if let moved: Holder = read(aside), isAlive(moved.pid) {
            _ = link(aside.path, lockFile.path)
            return false
        }
        return true
    }

    public func release(pid: Int32) {
        guard let h: Holder = read(lockFile), h.pid == pid else { return }
        unlink(lockFile.path)
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

    private struct Hold: Codable { var until: Date }

    public func hold(until: Date) throws {
        try ensureDirectory()
        try JSONEncoder.handsOff.encode(Hold(until: until)).write(to: holdFile, options: .atomic)
    }

    public func endHold() { unlink(holdFile.path) }

    /// When the user's hold ends, if one is on.
    public func holdEnds(now: Date) -> Date? {
        guard let h: Hold = read(holdFile), h.until > now else { return nil }
        return h.until
    }

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
