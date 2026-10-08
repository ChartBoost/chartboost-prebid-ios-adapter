// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import CoreGraphics
import Foundation

enum ChartboostPrebidAdapterError: LocalizedError {
    /// The winning bid carried an empty or invalid ADM.
    case missingAdMarkup
    /// The Chartboost SDK was not started when a load was attempted (kept for Android parity, not currently used).
    case sdkNotStarted
    /// The bid's format is not one this plugin renders (kept for Android parity, not currently used).
    case unsupportedAdFormat
    /// The banner size is not one the Chartboost SDK supports.
    case unsupportedBannerSize(CGSize)
    /// No view controller was available to present the banner and its click-throughs.
    case missingPresentingViewController

    var errorDescription: String? {
        switch self {
        case .missingAdMarkup:
            // Aligns with Android: the Android adapter emits the identical string
            // (ChartboostErrorMapper.admInvalid) for this case.
            return "Empty or invalid ADM for a Chartboost-flagged bid"
        case .sdkNotStarted:
            return "Chartboost SDK has not been started. Call Chartboost.start(...) before loading ads."
        case .unsupportedAdFormat:
            return "Unsupported ad format for a Chartboost-flagged bid"
        case .missingPresentingViewController:
            return "Could not obtain a view controller to present the Chartboost banner"
        case .unsupportedBannerSize(let size):
            return "Unsupported banner size \(Int(size.width))x\(Int(size.height)) for a Chartboost-flagged bid. Supported sizes: 320x50, 300x250, 728x90, 300x600."
        }
    }
}
