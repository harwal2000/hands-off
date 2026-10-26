import Foundation
@testable import HandsOffCore

/// A state folder in a fresh temp directory, with process liveness under the test's control.
func makeStore(alive: Set<Int32> = []) -> (StateStore, LiveSet) {
    let dir = FileManager.default.temporaryDirectory.appending(path: "handsoff-tests-\(UUID().uuidString)")
    let live = LiveSet(alive)
    return (StateStore(directory: dir, isAlive: { live.contains($0) }), live)
}

final class LiveSet: @unchecked Sendable {
    private var pids: Set<Int32>
    init(_ pids: Set<Int32>) { self.pids = pids }
    func contains(_ pid: Int32) -> Bool { pids.contains(pid) }
    func kill(_ pid: Int32) { pids.remove(pid) }
    func add(_ pid: Int32) { pids.insert(pid) }
}

/// Time that moves only when the code under test sleeps. `lastInput` is when the user last pressed a key or clicked.
/// `canAsk` is whether the menu bar app is there to show the prompt (off by default, so tests about waiting aren't
/// about the prompt too).
final class FakeClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var lastInput: Date
    var canAsk: Bool
    var onSleep: (FakeClock) -> Void = { _ in }
    init(secondsSinceInput: Double = 3600, canAsk: Bool = false) {
        lastInput = now.addingTimeInterval(-secondsSinceInput)
        self.canAsk = canAsk
    }

    var environment: FocusEnvironment {
        FocusEnvironment(
            now: { self.now },
            sleep: { self.now = self.now.addingTimeInterval($0); self.onSleep(self) },
            secondsSinceInput: { self.now.timeIntervalSince(self.lastInput) },
            canAsk: { self.canAsk }
        )
    }
}

func holder(_ pid: Int32, _ reason: String = "typing test", started: Date = Date(timeIntervalSince1970: 1_000_000), seconds: Double? = nil) -> Holder {
    Holder(reason: reason, label: "repo-\(pid)", pid: pid, started: started, seconds: seconds)
}
