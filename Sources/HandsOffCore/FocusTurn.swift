import Foundation

/// What waiting for the keyboard depends on, so tests can run it on a fake clock.
public struct FocusEnvironment {
    public var now: () -> Date
    public var sleep: (Double) -> Void
    /// Seconds since the user last pressed a key or clicked (real hardware input only).
    public var secondsSinceInput: () -> Double
    /// Whether the menu bar app is there to show the prompt. Without it nobody could answer, so nobody is asked.
    public var canAsk: () -> Bool

    public init(now: @escaping () -> Date, sleep: @escaping (Double) -> Void, secondsSinceInput: @escaping () -> Double,
                canAsk: @escaping () -> Bool) {
        self.now = now; self.sleep = sleep; self.secondsSinceInput = secondsSinceInput; self.canAsk = canAsk
    }
}

public enum WaitOutcome: Equatable, Sendable { case acquired, gaveUp }

/// Why an agent is still waiting, reported each time it changes.
public enum WaitReason: Equatable, Sendable {
    case userHold(until: Date)
    /// The user answered Not now; the next agent in line asks again then.
    case notNow(until: Date)
    case anotherAgent(String)
    /// The user is being asked about another agent's turn.
    case anotherPrompt(String)
    case userActive
    /// The menu bar is asking the user; the hold starts when they click Start or the countdown ends.
    case asking
}

/// Queues for the keyboard and takes it once the user isn't holding agents, no other agent has it, and the user
/// hasn't pressed a key or clicked for `idle` seconds. Gives up after `maxWait` seconds.
///
/// Unless the user turned it off, it asks first: the menu bar shows a prompt with a countdown of `askFor` seconds, and
/// the hold starts when the user clicks Start or the countdown ends. A key press or click restarts the countdown, so a
/// hold never starts within `askFor` seconds of the user's last input. Not now puts agents on hold for a while.
public func waitForTurn(store: StateStore, holder: Holder, idle: Double, maxWait: Double, askFor: Double = 10,
                        environment env: FocusEnvironment, poll: Double = 0.25,
                        onWait: (WaitReason) -> Void = { _ in }) throws -> WaitOutcome {
    let start = env.now()
    try store.addWaiter(Waiter(reason: holder.reason, label: holder.label, pid: holder.pid, since: start))
    var prompt: Prompt?   // ours, while the user is being asked
    func dropPrompt() {
        guard prompt != nil else { return }
        store.endPrompt(pid: holder.pid)
        prompt = nil
    }
    defer {
        dropPrompt()
        store.removeWaiter(pid: holder.pid)
    }
    var lastReason: WaitReason?
    func waiting(_ reason: WaitReason) {
        if reason != lastReason { onWait(reason) }
        lastReason = reason
    }
    func acquire(_ now: Date) throws -> Bool {
        var h = holder
        h.started = now
        let acquired = try store.tryAcquire(h)
        dropPrompt()   // after taking the keyboard, so the menu bar goes straight from asking to "Hands off"
        return acquired
    }
    while true {
        let now = env.now()
        if let hold = store.currentHold(now: now) {
            dropPrompt()
            waiting(hold.notNow ? .notNow(until: hold.until) : .userHold(until: hold.until))
        } else if let other = store.holder(), other.pid != holder.pid {
            dropPrompt()
            waiting(.anotherAgent(other.label))
        } else if var asked = prompt {
            let sinceInput = env.secondsSinceInput()
            if sinceInput < askFor { asked.startsAt = max(asked.startsAt, now.addingTimeInterval(askFor - sinceInput)) }
            if store.takeStart(pid: holder.pid) || !store.settings().confirm || now >= asked.startsAt {
                if try acquire(now) { return .acquired }
            } else if asked != prompt {
                try store.updatePrompt(asked)
                prompt = asked
            }
        } else if env.secondsSinceInput() < idle {
            waiting(.userActive)
        } else if store.settings().confirm && env.canAsk() {
            let asked = Prompt(reason: holder.reason, label: holder.label, pid: holder.pid, seconds: holder.seconds,
                               startsAt: now.addingTimeInterval(askFor))
            if try store.tryAsk(asked) {
                prompt = asked
                waiting(.asking)
            } else if let other = store.asking() {
                waiting(.anotherPrompt(other.label))
            }
        } else if try acquire(now) {
            return .acquired
        }
        if now.timeIntervalSince(start) >= maxWait { return .gaveUp }
        env.sleep(poll)
    }
}

/// True when the user pressed a key or clicked after the hold started.
public func userTouched(holdStarted: Date, now: Date, secondsSinceInput: Double) -> Bool {
    secondsSinceInput < now.timeIntervalSince(holdStarted)
}
