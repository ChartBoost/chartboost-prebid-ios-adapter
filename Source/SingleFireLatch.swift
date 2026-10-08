// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

/// A one-shot latch: `fire()` returns `true` exactly once, `false` thereafter.
///
/// Chartboost SDK callbacks that map to a Prebid forward (loaded, displayed,
/// impression) must fire at most once even if the SDK delivers a duplicate — a
/// banner's show callback in particular can fire more than once.
///
/// No synchronization: every caller is a Chartboost SDK delegate callback, and the
/// SDK marshals those to the main queue at the bridge boundary (CHBBanner /
/// CHBInterstitial / CHBRewarded dispatch their delegate calls on the main queue), so
/// the latch is only ever touched on the main thread.
final class SingleFireLatch {
    private var hasFired = false

    /// Whether `fire()` has already latched. Read-only — observing this never latches.
    var fired: Bool { hasFired }

    /// Returns `true` the first time it is called, `false` on every later call.
    func fire() -> Bool {
        if hasFired {
            return false
        }
        hasFired = true
        return true
    }
}
