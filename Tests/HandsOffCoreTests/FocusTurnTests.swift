import Foundation
import Testing
@testable import HandsOffCore

@Suite struct FocusTurnTests {
    let me: Int32 = 10

    @Test func takesTheKeyboardStraightAwayWhenTheUserIsIdle() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(secondsSinceInput: 60)
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 60, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(store.holder()?.pid == me)
        #expect(store.waiters().isEmpty)
    }

    @Test func waitsUntilTheUserStopsTyping() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(secondsSinceInput: 0)
        let typingUntil = clock.now.addingTimeInterval(20)
        var queuedWhileTyping = false
        clock.onSleep = { c in
            if c.now < typingUntil { c.lastInput = c.now; queuedWhileTyping = queuedWhileTyping || !store.waiters().isEmpty }
        }
        let start = clock.now
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(queuedWhileTyping)
        #expect(clock.now.timeIntervalSince(start) >= 24.5)   // typing until just before 20 s, then 5 s quiet
        #expect(clock.now.timeIntervalSince(start) < 27)
    }

    @Test func waitsWhileTheUserHasAgentsOnHold() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock()
        try store.hold(until: clock.now.addingTimeInterval(30))
        let start = clock.now
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(clock.now.timeIntervalSince(start) >= 30)
    }

    @Test func waitsForAnotherAgentToFinish() throws {
        let (store, live) = makeStore(alive: [me, 20])
        let clock = FakeClock()
        #expect(try store.tryAcquire(holder(20)))
        let finishAt = clock.now.addingTimeInterval(12)
        clock.onSleep = { c in if c.now >= finishAt { live.kill(20) } }
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(store.holder()?.pid == me)
    }

    @Test func givesUpAfterMaxWaitAndLeavesTheQueue() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(secondsSinceInput: 0)
        clock.onSleep = { $0.lastInput = $0.now }   // never stops typing
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 30, environment: clock.environment)
        #expect(outcome == .gaveUp)
        #expect(store.holder() == nil)
        #expect(store.waiters().isEmpty)
    }

    @Test func reportsEachReasonForWaitingOnce() throws {
        let (store, live) = makeStore(alive: [me, 20])
        let clock = FakeClock(secondsSinceInput: 0)
        #expect(try store.tryAcquire(holder(20)))
        clock.onSleep = { c in
            let t = c.now.timeIntervalSince(Date(timeIntervalSince1970: 1_000_000))
            if t < 10 { c.lastInput = c.now }           // typing for 10 s
            if t >= 10 { live.kill(20) }                // then the other agent finishes
        }
        var reasons: [WaitReason] = []
        _ = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment) { reasons.append($0) }
        #expect(reasons == [.anotherAgent("repo-20"), .userActive])
    }

    @Test func noticesTheUserTouchingTheKeyboardDuringTheHold() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(40)
        #expect(userTouched(holdStarted: start, now: end, secondsSinceInput: 12))
        #expect(!userTouched(holdStarted: start, now: end, secondsSinceInput: 41))
    }
}
