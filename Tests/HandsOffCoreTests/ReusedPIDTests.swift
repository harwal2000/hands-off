import Foundation
import Testing
@testable import HandsOffCore

/// After a restart the system hands out low process IDs again, so a file left behind by an agent can name a PID that now
/// belongs to some unrelated process that runs for days. These tests stand in for such a file: they use this test
/// process's own PID (alive) on a file dated before the process started.
@Suite struct ReusedPIDTests {
    let me = getpid()
    let beforeIStarted = Date(timeIntervalSinceNow: -86_400)

    func realStore() -> StateStore {
        StateStore(directory: FileManager.default.temporaryDirectory.appending(path: "handsoff-tests-\(UUID().uuidString)"))
    }

    func backdate(_ file: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: beforeIStarted], ofItemAtPath: file.path)
    }

    @Test func aProcessIsAliveOnlyForFilesWrittenAfterItStarted() {
        #expect(processIsAlive(me, wroteAt: Date()))
        #expect(!processIsAlive(me, wroteAt: beforeIStarted))
        #expect(!processIsAlive(999_999, wroteAt: Date()))   // above the highest PID macOS gives out
    }

    @Test func ignoresAWaiterWhosePIDNowBelongsToAnotherProcess() throws {
        let store = realStore()
        try store.addWaiter(Waiter(reason: "Screenshot", label: "my-app", pid: me, since: beforeIStarted))
        #expect(store.waiters().map(\.pid) == [me])
        try backdate(store.waitingDirectory.appending(path: "\(me).json"))
        #expect(store.waiters().isEmpty)
    }

    @Test func takesTheKeyboardFromAHolderWhosePIDNowBelongsToAnotherProcess() throws {
        let store = realStore()
        #expect(try store.tryAcquire(holder(me)))
        try backdate(store.lockFile)
        #expect(store.holder() == nil)
        #expect(try store.tryAcquire(holder(me, "a new hold")))
        #expect(store.holder()?.reason == "a new hold")
    }

    @Test func ignoresAPromptAppAndDisplayWhosePIDNowBelongsToAnotherProcess() throws {
        let store = realStore()
        #expect(try store.tryAsk(Prompt(reason: "r", label: "l", pid: me, seconds: nil, startsAt: Date())))
        try store.writeApp(pid: me)
        let frame = Rect(x: 0, y: 0, width: 100, height: 100)
        try store.writeDisplay(DisplayInfo(id: 5, pid: me, scale: 2, cg: frame, appKit: frame))
        #expect(store.asking() != nil && store.appIsRunning() && store.display() != nil)

        for file in [store.promptFile, store.appFile, store.displayFile] { try backdate(file) }
        #expect(store.asking() == nil)
        #expect(!store.appIsRunning())
        #expect(store.display() == nil)
    }
}
