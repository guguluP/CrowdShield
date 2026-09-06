import Foundation

/// Addresses the brief's explicit "false alarm reduction" constraint
/// (TechNova Problem Statement, Section 5: Constraints) — the risk-scoring
/// engines (RiskPredictionEngine, FlowAnalysisEngine) already weight
/// multiple signals so a single noisy reading rarely produces a high score
/// on its own, but nothing previously stopped that score from firing an
/// alert the instant it crossed a threshold on just one tick, or from
/// re-firing every time a flickering condition briefly cleared and
/// reappeared.
///
/// This adds two independent layers on top of an already-computed
/// risk/issue signal, both keyed by a caller-supplied string (e.g.
/// `"stampede:MainEntrance"` or `"reverseMovement:GateC"`):
///
/// 1. **Persistence** — a condition must be observed on
///    `requiredConsecutiveTicks` consecutive calls before it's considered
///    real, not just noise. A single-tick spike that clears next tick never
///    reaches this bar.
/// 2. **Cooldown** — once an alert for a given key has actually fired, the
///    same key won't fire again for `cooldownInterval`, even if the
///    underlying condition flickers off and back on within that window.
///    Cooldown resets automatically once time has passed, so a
///    genuinely-ongoing or re-escalating situation is never permanently
///    suppressed — only rapid re-triggering is.
///
/// Deliberately stateless with respect to *what* the alert is about — it
/// only tracks keys and counts/timestamps, so both flow-issue alerts and
/// stampede/panic alerts can share one instance and one set of tuning
/// constants rather than duplicating this logic per call site (which is
/// what the previous per-function `alerts.prefix(N).contains { ... }`
/// checks amounted to).
final class AlertDebouncer {
    /// Ticks a condition must be seen on, consecutively, before it's
    /// eligible to fire. At the app's 3s simulation tick interval, 2 ticks
    /// means a condition must persist ~6s — long enough to reject a single
    /// noisy reading, short enough not to meaningfully delay a genuine
    /// fast-developing crush (the brief's "within the next few minutes"
    /// framing for crush prediction has ample margin above this).
    private let requiredConsecutiveTicks: Int

    /// Minimum time between two alerts sharing the same key, even if the
    /// condition clears and reappears in between. Tuned to be long enough
    /// to stop tick-to-tick flicker spam, short enough that a command
    /// operator isn't kept blind to a re-escalating situation for long.
    private let cooldownInterval: TimeInterval

    private var consecutiveHits: [String: Int] = [:]
    private var lastFiredAt: [String: Date] = [:]

    init(requiredConsecutiveTicks: Int = 2, cooldownInterval: TimeInterval = 90) {
        self.requiredConsecutiveTicks = requiredConsecutiveTicks
        self.cooldownInterval = cooldownInterval
    }

    /// Call once per tick for every key whose condition is CURRENTLY true
    /// this tick (i.e. only call this for zones/issues presently above
    /// whatever threshold the caller uses — don't call for keys that are
    /// currently fine). Returns true exactly when this observation should
    /// actually become a user-visible alert: the condition has now been
    /// seen `requiredConsecutiveTicks` times in a row AND the key isn't
    /// still in its post-fire cooldown window.
    ///
    /// Keys not passed in a given tick are treated as "condition absent
    /// this tick" and their consecutive-hit counter resets to 0 — a single
    /// clear tick breaks the streak, matching the intent that the
    /// condition must be *sustained*, not just frequent.
    func shouldFire(for key: String, at now: Date = Date()) -> Bool {
        let hits = (consecutiveHits[key] ?? 0) + 1
        consecutiveHits[key] = hits

        guard hits >= requiredConsecutiveTicks else { return false }

        if let last = lastFiredAt[key], now.timeIntervalSince(last) < cooldownInterval {
            return false
        }

        lastFiredAt[key] = now
        return true
    }

    /// Call once per tick with the full set of keys whose condition is
    /// true THIS tick, so keys absent from that set can have their streak
    /// reset. Scoped by `namespace` (a key prefix like `"flow:"` or
    /// `"stampede:"`) because multiple independent call sites share one
    /// AlertDebouncer instance but each only knows about its own subset of
    /// keys per tick — without scoping, one call site's reset would zero
    /// out streaks for conditions tracked by a different call site that
    /// simply weren't part of that particular call's active set, breaking
    /// persistence tracking for everything except whichever function ran
    /// last.
    func resetAbsentKeys(inNamespace namespace: String, currentlyActive: Set<String>) {
        for key in consecutiveHits.keys where key.hasPrefix(namespace) && !currentlyActive.contains(key) {
            consecutiveHits[key] = 0
        }
    }
}
