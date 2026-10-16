import Foundation
import Testing
@testable import HandsOffCore

@Suite struct StateStoreTests {
    @Test func takesAFreeKeyboard() throws {
        let (store, _) = makeStore(alive: [10])
        #expect(try store.tryAcquire(holder(10)))
        #expect(store.holder()?.pid == 10)
    }

    @Test func refusesWhileSomeoneAliveHoldsIt() throws {
        let (store, _) = makeStore(alive: [10, 20])
        #expect(try store.tryAcquire(holder(10)))
        #expect(try !store.tryAcquire(holder(20)))
        #expect(store.holder()?.pid == 10)
    }

    @Test func takesOverFromAHolderThatDied() throws {
        let (store, live) = makeStore(alive: [10, 20])
        #expect(try store.tryAcquire(holder(10)))
        live.kill(10)
        #expect(store.holder() == nil)
        #expect(try store.tryAcquire(holder(20)))
        #expect(store.holder()?.pid == 20)
    }

    @Test func onlyTheHolderReleases() throws {
        let (store, _) = makeStore(alive: [10, 20])
        #expect(try store.tryAcquire(holder(10)))
        store.release(pid: 20)
        #expect(store.holder()?.pid == 10)
        store.release(pid: 10)
        #expect(store.holder() == nil)
    }

    @Test func listsLiveWaitersOldestFirst() throws {
        let (store, live) = makeStore(alive: [10, 20, 30])
        let t = Date(timeIntervalSince1970: 1_000_000)
        try store.addWaiter(Waiter(reason: "b", label: "b", pid: 20, since: t.addingTimeInterval(5)))
        try store.addWaiter(Waiter(reason: "a", label: "a", pid: 10, since: t))
        try store.addWaiter(Waiter(reason: "c", label: "c", pid: 30, since: t.addingTimeInterval(9)))
        live.kill(30)
        #expect(store.waiters().map(\.pid) == [10, 20])
        store.removeWaiter(pid: 10)
        #expect(store.waiters().map(\.pid) == [20])
    }

    @Test func holdLastsUntilItEnds() throws {
        let (store, _) = makeStore()
        let now = Date(timeIntervalSince1970: 1_000_000)
        try store.hold(until: now.addingTimeInterval(300))
        #expect(store.holdEnds(now: now) == now.addingTimeInterval(300))
        #expect(store.holdEnds(now: now.addingTimeInterval(301)) == nil)
        try store.hold(until: now.addingTimeInterval(300))
        store.endHold()
        #expect(store.holdEnds(now: now) == nil)
    }

    @Test func displayIsOnlyReportedWhileItsAppRuns() throws {
        let (store, live) = makeStore(alive: [10])
        let info = DisplayInfo(id: 11, pid: 10, scale: 2,
                               cg: Rect(x: 1728, y: 1117, width: 1440, height: 900),
                               appKit: Rect(x: 1728, y: -900, width: 1440, height: 900))
        try store.writeDisplay(info)
        #expect(store.display() == info)
        live.kill(10)
        #expect(store.display() == nil)
    }
}
