// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import ChartboostSDK
import UIKit

/// The banner operations the display-view bridge needs from a Chartboost banner.
protocol ChartboostBannerAd: AnyObject {
    /// The banner's view, added to the host `PrebidMobileDisplayViewProtocol` view.
    var adView: UIView { get }
    func cache(bidResponse: String)
    func show(from viewController: UIViewController)
}

/// The fullscreen operations the interstitial/rewarded bridge needs.
protocol ChartboostFullscreenAd: AnyObject {
    func cache(bidResponse: String)
    func show(from viewController: UIViewController)
}

/// Creates Chartboost SDK ad objects for the bridges. Injected so tests can swap in
/// fakes; the production implementation builds real ads with the Prebid mediation param.
protocol ChartboostAdFactory {
    func makeBanner(size: CHBBannerSize, location: String, delegate: CHBBannerDelegate) -> ChartboostBannerAd
    func makeInterstitial(location: String, delegate: CHBInterstitialDelegate) -> ChartboostFullscreenAd
    func makeRewarded(location: String, delegate: CHBRewardedDelegate) -> ChartboostFullscreenAd
}

/// Production factory: builds real Chartboost SDK ads, each tagged with the Prebid
/// mediation param so this traffic is attributed as Prebid-mediated.
struct CHBAdFactory: ChartboostAdFactory {
    func makeBanner(size: CHBBannerSize, location: String, delegate: CHBBannerDelegate) -> ChartboostBannerAd {
        CHBBanner(
            size: size,
            location: location,
            mediation: ChartboostPrebidAdapter.mediationParam,
            delegate: delegate
        )
    }

    func makeInterstitial(location: String, delegate: CHBInterstitialDelegate) -> ChartboostFullscreenAd {
        CHBInterstitial(
            location: location,
            mediation: ChartboostPrebidAdapter.mediationParam,
            delegate: delegate
        )
    }

    func makeRewarded(location: String, delegate: CHBRewardedDelegate) -> ChartboostFullscreenAd {
        CHBRewarded(
            location: location,
            mediation: ChartboostPrebidAdapter.mediationParam,
            delegate: delegate
        )
    }
}

// The concrete Chartboost ads already expose cache(bidResponse:)/show(from:); the
// conformances just name the subset the bridges depend on.
extension CHBBanner: ChartboostBannerAd {
    var adView: UIView { self }
}

extension CHBInterstitial: ChartboostFullscreenAd {}

extension CHBRewarded: ChartboostFullscreenAd {}
