import Foundation

/// What waiting for the keyboard depends on, so tests can run it on a fake clock.
public struct FocusEnvironment {
    public var now: () -> Date
    public var sleep: (Double) -> Void
    /// Seconds since the user last pressed a key or clicked (real hardware input only).
    public var secondsSinceInput: () -> Double

    public init(now: @escaping () -> Date, sleep: @escaping (Double) -> Void, secondsSinceInput: @escaping () -> Double) {
        self.now = now; self.sleep = sleep; self.secondsSinceInput = secondsSinceInput
    }
}

public enum WaitOutcome: Equatable, Sendable { case acquired, gaveUp }

/// Why an agent is still waiting, reported each time it changes.
public enum WaitReason: Equatable, Sendable {
    case userHold(until: Date)
    case anotherAgent(String)
    case userActive
}

/// Queues for the keyboard and takes it once the user isn't holding agents, no other agent has it, and the user
/// hasn't pressed a key or clicked for `idle` seconds. Gives up after `maxWait` seconds.
public func waitForTurn(store: StateStore, holder: Holder, idle: Double, maxWait: Double,
                        environment env: FocusEnvironment, poll: Double = 0.25,
                        onWait: (WaitReason) -> Void = { _ in }) throws -> WaitOutcome {
    let start = env.now()
    try store.addWaiter(Waiter(reason: holder.reason, label: holder.label, pid: holder.pid, since: start))
    defer { store.removeWaiter(pid: holder.pid) }
    var lastReason: WaitReason?
    func waiting(_ reason: WaitReason) {
        if reason != lastReason { onWait(reason) }
        lastReason = reason
    }
    while true {
        let now = env.now()
        if let until = store.holdEnds(now: now) {
            waiting(.userHold(until: until))
        } else if let other = store.holder(), other.pid != holder.pid {
            waiting(.anotherAgent(other.label))
        } else if env.secondsSinceInput() < idle {
            waiting(.userActive)
        } else {
            var h = holder
            h.started = now
            if try store.tryAcquire(h) { return .acquired }
        }
        if now.timeIntervalSince(start) >= maxWait { return .gaveUp }
        env.sleep(poll)
    }
}

/// True when the user pressed a key or clicked after the hold started.
public func userTouched(holdStarted: Date, now: Date, secondsSinceInput: Double) -> Bool {
    secondsSinceInput < now.timeIntervalSince(holdStarted)
}
