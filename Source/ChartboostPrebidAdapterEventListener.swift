// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import Foundation

/// Observes the lifecycle of ads that the Chartboost renderer specifically handled,
/// independently of Prebid's own per-ad-unit delegates. Assign it to
/// `ChartboostPrebidAdapter.eventListener` before registering the renderer.
///
/// All callbacks run on the main thread. `onAdDismissed` and `onUserEarnedReward` are
/// fullscreen-only and never fire for banners. Every method is optional.
@objc public protocol ChartboostPrebidAdapterEventListener: AnyObject {
    @objc optional func onAdLoaded(format: ChartboostPrebidAdapterAdFormat)
    @objc optional func onAdDisplayed(format: ChartboostPrebidAdapterAdFormat)
    @objc optional func onAdClicked(format: ChartboostPrebidAdapterAdFormat)
    @objc optional func onAdFailed(format: ChartboostPrebidAdapterAdFormat, error: Error)
    @objc optional func onAdDismissed(format: ChartboostPrebidAdapterAdFormat)
    @objc optional func onUserEarnedReward(format: ChartboostPrebidAdapterAdFormat)
}
