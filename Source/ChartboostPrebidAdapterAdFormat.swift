// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

/// The ad format a lifecycle callback refers to.
@objc public enum ChartboostPrebidAdapterAdFormat: Int {
    /// An inline banner ad.
    case banner
    /// A fullscreen interstitial ad.
    case interstitial
    /// A fullscreen rewarded ad.
    case rewarded
}
