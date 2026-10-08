// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import ChartboostSDK
import PrebidMobile
import UIKit

/// Bridges a Chartboost interstitial or rewarded ad under Prebid's
/// `PrebidMobileInterstitialControllerProtocol`: loads the ADM via `cache(bidResponse:)`
/// and forwards the Chartboost delegate callbacks to Prebid's interstitial delegates.
///
/// Prebid has no separate rewarded controller protocol — the ad unit configuration decides
/// (see `ChartboostPrebidAdapter.isRewardedAd(adConfiguration:)`), and the reward is surfaced
/// through the optional `trackUserReward(_:_:)` callback on
/// `InterstitialControllerInteractionDelegate`.
final class ChartboostPrebidAdapterInterstitialController: NSObject, PrebidMobileInterstitialControllerProtocol {
    private weak var loadingDelegate: InterstitialControllerLoadingDelegate?
    private weak var interactionDelegate: InterstitialControllerInteractionDelegate?

    private let adm: String
    private let location: String
    private let isRewarded: Bool
    private let adFactory: ChartboostAdFactory
    private weak var eventListener: ChartboostPrebidAdapterEventListener?
    private var ad: ChartboostFullscreenAd?

    private var format: ChartboostPrebidAdapterAdFormat { isRewarded ? .rewarded : .interstitial }

    // Each Prebid forward fires at most once against duplicate SDK callbacks.
    private let loadLatch = SingleFireLatch()
    private let displayLatch = SingleFireLatch()
    private let impressionLatch = SingleFireLatch()
    private let rewardLatch = SingleFireLatch()

    // Forward-only lifecycle; out-of-order or duplicate entry points are rejected.
    // The Chartboost SDK delivers its callbacks on the main thread, loadAd hops to main before
    // touching state, and Prebid drives show from the main thread, so plain (unsynchronized)
    // state is safe here.
    private enum State { case idle, loading, ready, shown, done, failed }
    private var state: State = .idle

    init(
        adm: String,
        location: String,
        isRewarded: Bool,
        loadingDelegate: InterstitialControllerLoadingDelegate,
        interactionDelegate: InterstitialControllerInteractionDelegate,
        adFactory: ChartboostAdFactory = CHBAdFactory(),
        eventListener: ChartboostPrebidAdapterEventListener? = nil
    ) {
        self.adm = adm
        self.location = location
        self.isRewarded = isRewarded
        self.loadingDelegate = loadingDelegate
        self.interactionDelegate = interactionDelegate
        self.adFactory = adFactory
        self.eventListener = eventListener
        super.init()
    }

    // MARK: - PrebidMobileInterstitialControllerProtocol

    func loadAd() {
        if MainThread.redispatchIfNeeded({ [weak self] in self?.loadAd() }) {
            return
        }
        guard state == .idle else {
            Log.warn("ChartboostPrebid: ignoring loadAd in state \(state)")
            return
        }
        state = .loading
        // Rewarded vs. plain interstitial use different Chartboost ad classes; both
        // satisfy the same fullscreen contract once created.
        let ad: ChartboostFullscreenAd = isRewarded
            ? adFactory.makeRewarded(location: location, delegate: self)
            : adFactory.makeInterstitial(location: location, delegate: self)
        self.ad = ad
        ad.cache(bidResponse: adm)
    }

    func show() {
        guard state == .ready else {
            Log.warn("ChartboostPrebid: ignoring show in state \(state)")
            return
        }
        guard let viewController = interactionDelegate?
            .viewControllerForModalPresentation(fromInterstitialController: self) else {
            // No presenting VC (e.g. a transient presentation transition). Leave state
            // at .ready so a later show can retry; log so the miss is diagnosable.
            Log.warn("ChartboostPrebid: no view controller for presentation; ignoring show")
            return
        }
        state = .shown
        ad?.show(from: viewController)
    }

    // MARK: - Bridge mapping
    //
    // The CHB delegate methods below unwrap the SDK event objects and defer to these
    // handlers, which hold the Chartboost→Prebid mapping (kept free of SDK event types
    // so it can be unit-tested directly).

    func handleCacheResult(error: Error?) {
        guard state == .loading else { return }
        if let error {
            state = .failed
            loadingDelegate?.interstitialController(self, didFailWithError: error)
            eventListener?.onAdFailed?(format: format, error: error)
            return
        }
        state = .ready
        if loadLatch.fire() {
            loadingDelegate?.interstitialControllerDidLoadAd(self)
            eventListener?.onAdLoaded?(format: format)
        }
    }

    func handleShowResult(error: Error?) {
        guard state == .shown else { return }
        if let error {
            // Prebid has no terminal show-failed signal and must not bill, so we surface
            // nothing to Prebid on a show failure. But mark the controller terminal: the SDK
            // won't deliver didDismissAd for an ad that failed to show, so without this the
            // controller would linger at .shown and a late, spurious impression/click could
            // still slip past that guard. Report to our own observer for parity with the
            // load-failure path (handleCacheResult) — the observer is diagnostic, not billing.
            state = .failed
            eventListener?.onAdFailed?(format: format, error: error)
            return
        }
        if displayLatch.fire() {
            interactionDelegate?.interstitialControllerDidDisplay(self)
            eventListener?.onAdDisplayed?(format: format)
        }
    }

    func handleImpression() {
        guard state == .shown else { return }
        if impressionLatch.fire() {
            interactionDelegate?.trackImpression(forInterstitialController: self)
        }
    }

    func handleClick(error: Error?) {
        guard error == nil, state == .shown else { return }
        interactionDelegate?.interstitialControllerDidClickAd(self)
        eventListener?.onAdClicked?(format: format)
    }

    func handleDismiss() {
        guard state == .shown else { return }
        state = .done
        interactionDelegate?.interstitialControllerDidCloseAd(self)
        eventListener?.onAdDismissed?(format: format)
    }

    func handleReward(amount: Int) {
        guard state == .shown else { return }
        // Latched like the other forwards: a duplicate didEarnReward must not double-credit.
        guard rewardLatch.fire() else { return }
        // PrebidReward's value-taking init is internal; only the NSObject init is
        // public, so construct and populate the public properties.
        let reward = PrebidReward()
        reward.type = "chartboost"
        reward.count = NSNumber(value: amount)
        interactionDelegate?.trackUserReward?(self, reward)
        eventListener?.onUserEarnedReward?(format: format)
    }

    func handleExpiration() {
        // Logged no-op (the SDK logs the callback). A cached-but-unshown ad that
        // expires can no longer be shown, so mark it terminal; nothing bills because
        // no impression fires for an ad that never displayed.
        if state == .ready {
            state = .done
        }
    }
}

// MARK: - CHBInterstitialDelegate / CHBRewardedDelegate
//
// The Chartboost SDK delivers these callbacks on the main thread, so the handlers
// above forward to Prebid directly without re-dispatching.
//
// Both protocols inherit from CHBDismissableAdDelegate → CHBAdDelegate; CHBRewardedDelegate
// adds didEarnReward:. Conforming to both is safe — method names don't collide.

extension ChartboostPrebidAdapterInterstitialController: CHBInterstitialDelegate, CHBRewardedDelegate {
    func didCacheAd(_ event: CHBCacheEvent, error: CacheError?) {
        handleCacheResult(error: error)
    }

    func didShowAd(_ event: CHBShowEvent, error: ShowError?) {
        handleShowResult(error: error)
    }

    func didRecordImpression(_ event: CHBImpressionEvent) {
        handleImpression()
    }

    func didClickAd(_ event: CHBClickEvent, error: ClickError?) {
        handleClick(error: error)
    }

    func didDismissAd(_ event: CHBDismissEvent) {
        handleDismiss()
    }

    func didExpireAd(_ event: CHBExpirationEvent) {
        handleExpiration()
    }

    // CHBRewardedDelegate-only
    func didEarnReward(_ event: CHBRewardEvent) {
        handleReward(amount: event.reward)
    }
}
