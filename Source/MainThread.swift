// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import Foundation

/// Main-thread guard for the bridge entry points Prebid Mobile drives from its own serial queue.
///
/// The Chartboost SDK's ad objects are UIKit views and the event listener contract promises
/// main-thread callbacks, so every entry point that creates an ad or reports a result must run on
/// main. Prebid does not guarantee that, so the entry point re-dispatches itself when needed.
enum MainThread {
    /// Returns `false` when already on the main thread, so the caller proceeds inline. Otherwise
    /// dispatches `work` to the main queue and returns `true`, and the caller must return.
    static func redispatchIfNeeded(_ work: @escaping () -> Void) -> Bool {
        if Thread.isMainThread {
            return false
        }
        DispatchQueue.main.async(execute: work)
        return true
    }
}
