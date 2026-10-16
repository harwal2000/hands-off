import Foundation
import Testing
@testable import HandsOffCore

@Suite struct StatusTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func idleWhenNothingIsGoingOn() {
        let (store, _) = makeStore()
        #expect(Status.read(from: store, now: now) == .idle)
        #expect(Status.idle.menuBarTitle(now: now) == "")
    }

    @Test func waitingWhenAnAgentIsQueued() throws {
        let (store, _) = makeStore(alive: [10])
        try store.addWaiter(Waiter(reason: "keys", label: "quick-notes", pid: 10, since: now))
        let status = Status.read(from: store, now: now)
        #expect(status == .waiting([Waiter(reason: "keys", label: "quick-notes", pid: 10, since: now)]))
        #expect(status.menuBarTitle(now: now) == "Agent needs keyboard")
    }

    @Test func holdingCountsDownWhenTheAgentSaidHowLong() throws {
        let (store, _) = makeStore(alive: [10])
        #expect(try store.tryAcquire(holder(10, started: now, seconds: 40)))
        let status = Status.read(from: store, now: now)
        #expect(status.menuBarTitle(now: now.addingTimeInterval(8)) == "Hands off 0:32")
        // Past its estimate it counts up instead of showing a negative time.
        #expect(status.menuBarTitle(now: now.addingTimeInterval(65)) == "Hands off 1:05")
    }

    @Test func holdingCountsUpWithoutAnEstimate() throws {
        let (store, _) = makeStore(alive: [10])
        #expect(try store.tryAcquire(holder(10, started: now)))
        #expect(Status.read(from: store, now: now).menuBarTitle(now: now.addingTimeInterval(7)) == "Hands off 0:07")
    }

    @Test func holdingWinsOverAHoldTheUserAskedForLate() throws {
        let (store, _) = makeStore(alive: [10])
        #expect(try store.tryAcquire(holder(10, started: now)))
        try store.hold(until: now.addingTimeInterval(300))
        guard case .holding(_, _, let holdEnds) = Status.read(from: store, now: now) else { Issue.record("not holding"); return }
        #expect(holdEnds == now.addingTimeInterval(300))
    }

    @Test func onHoldShowsMinutesLeft() throws {
        let (store, _) = makeStore()
        try store.hold(until: now.addingTimeInterval(14 * 60 + 5))
        let status = Status.read(from: store, now: now)
        #expect(status.menuBarTitle(now: now) == "Agents on hold 15m")
    }
}
