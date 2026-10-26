import Foundation
import Testing
@testable import HandsOffCore

/// Asking the user before each hold: the prompt, its 10 s countdown, Start, Not now, the queue and the off switch.
@Suite struct PromptTests {
    let me: Int32 = 10
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func elapsed(_ clock: FakeClock) -> Double { clock.now.timeIntervalSince(t0) }

    @Test func asksFirstAndStartsByItselfAfterTenSeconds() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        var asked: Prompt?
        clock.onSleep = { _ in asked = asked ?? store.asking() }
        var reasons: [WaitReason] = []
        let outcome = try waitForTurn(store: store, holder: holder(me, seconds: 40), idle: 5, maxWait: 600, environment: clock.environment) { reasons.append($0) }
        #expect(outcome == .acquired)
        #expect(asked == Prompt(reason: "typing test", label: "repo-10", pid: me, seconds: 40, startsAt: t0.addingTimeInterval(10)))
        #expect(reasons == [.asking])
        #expect(elapsed(clock) >= 10 && elapsed(clock) < 10.5)
        #expect(store.asking() == nil)
        #expect(store.holder()?.pid == me)
    }

    @Test func startGoesStraightAway() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        clock.onSleep = { c in if c.now.timeIntervalSince(self.t0) >= 3, store.asking() != nil { store.answerStart(pid: self.me) } }
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(elapsed(clock) >= 3 && elapsed(clock) < 3.5)
        #expect(store.asking() == nil)
    }

    @Test func notNowWaitsTwoMinutesThenAsksAgain() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        var saidNotNow = false
        var promptsSeen = 0, lastHadPrompt = false
        clock.onSleep = { c in
            let hasPrompt = store.asking() != nil
            if hasPrompt && !lastHadPrompt { promptsSeen += 1 }
            lastHadPrompt = hasPrompt
            if !saidNotNow, c.now.timeIntervalSince(self.t0) >= 3 { saidNotNow = true; try? store.sayNotNow(now: c.now) }
        }
        var reasons: [WaitReason] = []
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 1800, environment: clock.environment) { reasons.append($0) }
        #expect(outcome == .acquired)   // saying Not now doesn't fail the command
        #expect(promptsSeen == 2)
        #expect(reasons == [.asking, .notNow(until: t0.addingTimeInterval(3 + notNowSeconds)), .asking])
        #expect(elapsed(clock) >= 3 + 120 + 10 && elapsed(clock) < 3 + 120 + 10.5)
    }

    @Test func notNowIsAHoldTheMenuCanEnd() throws {
        let (store, _) = makeStore()
        try store.sayNotNow(now: t0)
        #expect(store.currentHold(now: t0) == UserHold(until: t0.addingTimeInterval(120), notNow: true))
        guard case .onHold(_, let notNow, _) = Status.read(from: store, now: t0) else { Issue.record("not on hold"); return }
        #expect(notNow)
        store.endHold()
        #expect(store.currentHold(now: t0) == nil)
    }

    @Test func typingDuringTheCountdownRestartsIt() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        var startsAtAfterTyping: Date?
        clock.onSleep = { c in
            let t = c.now.timeIntervalSince(self.t0)
            if t >= 4 && t < 4.25 { c.lastInput = c.now }                    // one key press, 4 s in
            if t >= 5 && startsAtAfterTyping == nil { startsAtAfterTyping = store.asking()?.startsAt }
        }
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(startsAtAfterTyping == t0.addingTimeInterval(14))   // the menu bar shows the new countdown
        #expect(elapsed(clock) >= 14 && elapsed(clock) < 14.5)
    }

    @Test func offSwitchTakesTheKeyboardWithoutAsking() throws {
        let (store, _) = makeStore(alive: [me])
        #expect(store.settings().confirm)   // on by default
        try store.setConfirm(false)
        #expect(!store.settings().confirm)
        let clock = FakeClock(canAsk: true)
        var asked = false
        clock.onSleep = { _ in asked = asked || store.asking() != nil }
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(!asked)
        #expect(elapsed(clock) == 0)
    }

    @Test func turningItOffDuringTheCountdownStartsTheHold() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        clock.onSleep = { c in if c.now.timeIntervalSince(self.t0) >= 2 { try? store.setConfirm(false) } }
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(elapsed(clock) < 2.5)
    }

    @Test func doesntAskWhenTheMenuBarAppIsntRunning() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        clock.canAsk = false
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(elapsed(clock) == 0)
    }

    @Test func asksAboutOneAgentAtATime() throws {
        let (store, live) = makeStore(alive: [me, 20])
        let clock = FakeClock(canAsk: true)
        #expect(try store.tryAsk(prompt(20)))
        #expect(try !store.tryAsk(prompt(me)))
        clock.onSleep = { c in
            // The other agent's prompt ends 5 s in and it takes the keyboard for 3 s.
            let t = c.now.timeIntervalSince(self.t0)
            if t >= 5 && t < 5.25 { store.endPrompt(pid: 20); _ = try? store.tryAcquire(holder(20)) }
            if t >= 8 { store.release(pid: 20); live.kill(20) }
        }
        var reasons: [WaitReason] = []
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment) { reasons.append($0) }
        #expect(outcome == .acquired)
        #expect(reasons == [.anotherPrompt("repo-20"), .anotherAgent("repo-20"), .asking])
        #expect(elapsed(clock) >= 18 && elapsed(clock) < 18.5)
    }

    @Test func aPromptLeftByADeadAgentIsIgnored() throws {
        let (store, live) = makeStore(alive: [me, 20])
        #expect(try store.tryAsk(prompt(20)))
        live.kill(20)
        #expect(store.asking() == nil)
        #expect(try store.tryAsk(prompt(me)))
        #expect(store.asking()?.pid == me)
    }

    @Test func holdOnDuringTheCountdownTakesThePromptAway() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        var promptDuringHold = false
        clock.onSleep = { c in
            let t = c.now.timeIntervalSince(self.t0)
            if t >= 2 && t < 2.25 { try? store.hold(until: c.now.addingTimeInterval(60)) }
            if t >= 3 && t < 60 { promptDuringHold = promptDuringHold || store.asking() != nil }
        }
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 600, environment: clock.environment)
        #expect(outcome == .acquired)
        #expect(!promptDuringHold)
        #expect(elapsed(clock) >= 72 && elapsed(clock) < 72.5)
    }

    @Test func givingUpTakesThePromptAway() throws {
        let (store, _) = makeStore(alive: [me])
        let clock = FakeClock(canAsk: true)
        clock.onSleep = { c in c.lastInput = c.now }   // types all the time, so the countdown never ends
        clock.lastInput = t0.addingTimeInterval(-60)
        let outcome = try waitForTurn(store: store, holder: holder(me), idle: 5, maxWait: 30, environment: clock.environment)
        #expect(outcome == .gaveUp)
        #expect(store.asking() == nil)
        #expect(store.waiters().isEmpty)
    }

    @Test func statusShowsThePromptAndWhoElseIsWaiting() throws {
        let (store, _) = makeStore(alive: [10, 20, 30])
        try store.addWaiter(Waiter(reason: "typing test", label: "repo-10", pid: 10, since: t0))
        try store.addWaiter(Waiter(reason: "screenshot", label: "repo-20", pid: 20, since: t0.addingTimeInterval(1)))
        try store.addWaiter(Waiter(reason: "menus", label: "repo-30", pid: 30, since: t0.addingTimeInterval(2)))
        let p = prompt(10)
        #expect(try store.tryAsk(p))
        let status = Status.read(from: store, now: t0)
        guard case .asking(let asked, let others) = status else { Issue.record("not asking: \(status)"); return }
        #expect(asked == p)
        #expect(others.map(\.pid) == [20, 30])
        #expect(status.menuBarTitle(now: t0.addingTimeInterval(1.5)) == "Agent starts in 0:09")
    }

    @Test func statusPutsTheHolderFirst() throws {
        let (store, _) = makeStore(alive: [10, 20])
        #expect(try store.tryAcquire(holder(10)))
        #expect(try store.tryAsk(prompt(20)))
        guard case .holding = Status.read(from: store, now: t0) else { Issue.record("not holding"); return }
    }

    @Test func startAnswersOnlyTheAgentItWasFor() {
        let (store, _) = makeStore()
        store.answerStart(pid: 20)
        #expect(!store.takeStart(pid: 10))
        #expect(store.takeStart(pid: 20))
        #expect(!store.takeStart(pid: 20))   // used up
    }

    @Test func knowsWhetherTheMenuBarAppIsRunning() throws {
        let (store, live) = makeStore(alive: [50])
        #expect(!store.appIsRunning())
        try store.writeApp(pid: 50)
        #expect(store.appIsRunning())
        live.kill(50)
        #expect(!store.appIsRunning())
    }

    func prompt(_ pid: Int32) -> Prompt {
        Prompt(reason: "typing test", label: "repo-\(pid)", pid: pid, seconds: nil, startsAt: t0.addingTimeInterval(10))
    }
}
