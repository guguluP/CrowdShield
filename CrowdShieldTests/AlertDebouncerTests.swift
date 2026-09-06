import XCTest
@testable import CrowdShield

final class AlertDebouncerTests: XCTestCase {

    // MARK: - Persistence threshold

    func test_singleTick_doesNotFire() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 2, cooldownInterval: 90)
        let now = Date()

        XCTAssertFalse(
            debouncer.shouldFire(for: "test:zoneA", at: now),
            "A condition seen only once should never fire — that's the whole point of requiring persistence."
        )
    }

    func test_consecutiveTicksReachingThreshold_fires() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 2, cooldownInterval: 90)
        let now = Date()

        _ = debouncer.shouldFire(for: "test:zoneA", at: now)
        let secondCall = debouncer.shouldFire(for: "test:zoneA", at: now.addingTimeInterval(3))

        XCTAssertTrue(secondCall, "Second consecutive observation should reach the threshold and fire.")
    }

    func test_higherThreshold_requiresMoreTicksBeforeFiring() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 4, cooldownInterval: 90)
        let now = Date()

        var fired = false
        for i in 0..<3 {
            fired = debouncer.shouldFire(for: "test:zoneA", at: now.addingTimeInterval(Double(i) * 3))
        }
        XCTAssertFalse(fired, "3 ticks should not satisfy a threshold of 4.")

        fired = debouncer.shouldFire(for: "test:zoneA", at: now.addingTimeInterval(9))
        XCTAssertTrue(fired, "The 4th consecutive tick should satisfy the threshold.")
    }

    // MARK: - Cooldown

    func test_secondFireWithinCooldown_isSuppressed() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 1, cooldownInterval: 90)
        let now = Date()

        XCTAssertTrue(debouncer.shouldFire(for: "test:zoneA", at: now), "First observation should fire immediately (threshold=1).")
        XCTAssertFalse(
            debouncer.shouldFire(for: "test:zoneA", at: now.addingTimeInterval(30)),
            "A repeat observation well within the 90s cooldown should be suppressed."
        )
    }

    func test_fireAfterCooldownExpires_firesAgain() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 1, cooldownInterval: 90)
        let now = Date()

        XCTAssertTrue(debouncer.shouldFire(for: "test:zoneA", at: now))
        XCTAssertTrue(
            debouncer.shouldFire(for: "test:zoneA", at: now.addingTimeInterval(91)),
            "Once the cooldown window has fully elapsed, the same key should be able to fire again."
        )
    }

    func test_cooldownIsPerKey_doesNotAffectOtherKeys() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 1, cooldownInterval: 90)
        let now = Date()

        XCTAssertTrue(debouncer.shouldFire(for: "test:zoneA", at: now))
        XCTAssertTrue(
            debouncer.shouldFire(for: "test:zoneB", at: now.addingTimeInterval(1)),
            "A different key's cooldown should be entirely independent of zoneA's."
        )
    }

    // MARK: - resetAbsentKeys / persistence semantics

    func test_gapInObservation_resetsStreak() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 2, cooldownInterval: 90)
        let now = Date()

        _ = debouncer.shouldFire(for: "test:zoneA", at: now)
        // Simulate the condition clearing for one tick: caller does NOT
        // call shouldFire for this key, and instead calls resetAbsentKeys
        // with zoneA excluded from the currently-active set — exactly how
        // CrowdSimulationService's promotion functions behave.
        debouncer.resetAbsentKeys(inNamespace: "test:", currentlyActive: [])

        let fired = debouncer.shouldFire(for: "test:zoneA", at: now.addingTimeInterval(6))
        XCTAssertFalse(
            fired,
            "After a reset, the streak should restart from zero — this observation is only the 1st again, not the 3rd."
        )
    }

    /// Regression test for a real bug introduced and fixed during this
    /// project's development: CrowdSimulationService has two independent
    /// call sites (flow-issue promotion and stampede/panic promotion) that
    /// share ONE AlertDebouncer instance. The original resetAbsentKeys
    /// implementation had no namespace scoping, so calling it from one
    /// call site with only that site's active keys would incorrectly zero
    /// out streaks for keys tracked by the OTHER call site (which simply
    /// weren't part of that particular call's active set, not genuinely
    /// absent). This test locks in the fix: namespace scoping ensures each
    /// call site's reset only ever touches its own keys.
    func test_resetAbsentKeys_doesNotAffectOtherNamespaces() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 2, cooldownInterval: 90)
        let now = Date()

        // Build up a 1-tick streak on a "stampede:" key.
        _ = debouncer.shouldFire(for: "stampede:MainEntrance", at: now)

        // A completely different call site resets ITS OWN "flow:" namespace,
        // with an empty active set (as if no flow issues exist this tick).
        // This must NOT touch the "stampede:" key's streak.
        debouncer.resetAbsentKeys(inNamespace: "flow:", currentlyActive: [])

        // If the bug were present, the stampede streak would have been
        // wiped by the flow: namespace's reset call, and this second
        // observation would only be "1st again" rather than reaching the
        // threshold of 2. With the fix, it correctly continues the streak.
        let fired = debouncer.shouldFire(for: "stampede:MainEntrance", at: now.addingTimeInterval(3))
        XCTAssertTrue(
            fired,
            "A reset scoped to a different namespace must not reset this key's streak — this is the exact bug that was found and fixed during development."
        )
    }

    func test_resetAbsentKeys_onlyResetsKeysMatchingItsOwnNamespace() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 2, cooldownInterval: 90)
        let now = Date()

        _ = debouncer.shouldFire(for: "panic:GateC", at: now)
        _ = debouncer.shouldFire(for: "stampede:GateC", at: now)

        // Reset only the "panic:" namespace, with GateC absent from the
        // active set this tick.
        debouncer.resetAbsentKeys(inNamespace: "panic:", currentlyActive: [])

        let panicFired = debouncer.shouldFire(for: "panic:GateC", at: now.addingTimeInterval(3))
        let stampedeFired = debouncer.shouldFire(for: "stampede:GateC", at: now.addingTimeInterval(3))

        XCTAssertFalse(panicFired, "panic:GateC's streak was reset (it's in the panic: namespace and was absent), so this should only be its 1st hit again.")
        XCTAssertTrue(stampedeFired, "stampede:GateC is a different namespace and was never touched by the panic: reset — its streak should continue normally to the 2nd hit and fire.")
    }

    func test_keyStillActive_resetDoesNotClearItsStreak() {
        let debouncer = AlertDebouncer(requiredConsecutiveTicks: 3, cooldownInterval: 90)
        let now = Date()

        _ = debouncer.shouldFire(for: "flow:GateA", at: now)
        // GateA is STILL active this tick — it should be included in
        // currentlyActive, and its streak should be preserved.
        debouncer.resetAbsentKeys(inNamespace: "flow:", currentlyActive: ["flow:GateA"])

        _ = debouncer.shouldFire(for: "flow:GateA", at: now.addingTimeInterval(3))
        let fired = debouncer.shouldFire(for: "flow:GateA", at: now.addingTimeInterval(6))

        XCTAssertTrue(fired, "A key correctly marked as still-active in resetAbsentKeys should keep accumulating its streak normally, reaching the 3-tick threshold.")
    }
}
