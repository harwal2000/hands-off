import Foundation

/// What the menu bar shows.
public enum Status: Equatable, Sendable {
    case idle
    /// Agents want the keyboard and will take it when the user pauses.
    case waiting([Waiter])
    /// The user asked agents to hold on.
    case onHold(until: Date, waiting: [Waiter])
    /// An agent has the keyboard. `holdEnds` is set when the user asked for a hold after it started.
    case holding(Holder, waiting: [Waiter], holdEnds: Date?)

    public static func read(from store: StateStore, now: Date) -> Status {
        let waiters = store.waiters()
        let holdEnds = store.holdEnds(now: now)
        if let h = store.holder() { return .holding(h, waiting: waiters.filter { $0.pid != h.pid }, holdEnds: holdEnds) }
        if let until = holdEnds { return .onHold(until: until, waiting: waiters) }
        if !waiters.isEmpty { return .waiting(waiters) }
        return .idle
    }

    /// The text next to the menu bar icon.
    public func menuBarTitle(now: Date) -> String {
        switch self {
        case .idle: return ""
        case .waiting: return "Agent needs keyboard"
        case .onHold(let until, _): return "Agents on hold \(Int((until.timeIntervalSince(now) / 60).rounded(.up)))m"
        case .holding(let h, _, _):
            let elapsed = now.timeIntervalSince(h.started)
            guard let seconds = h.seconds else { return "Hands off \(clock(elapsed))" }
            if elapsed < seconds { return "Hands off \(clock((seconds - elapsed).rounded(.up)))" }
            return "Hands off +\(clock(elapsed - seconds))"
        }
    }
}

/// `m:ss`, dropping the fraction of a second.
func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return "\(s / 60):" + String(format: "%02d", s % 60)
}
