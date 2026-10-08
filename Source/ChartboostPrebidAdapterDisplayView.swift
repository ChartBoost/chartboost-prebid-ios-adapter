// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import ChartboostSDK
import PrebidMobile
import UIKit

/// Hosts a Chartboost banner, loads it with the winning bid's ADM, and bridges the
/// Chartboost SDK delegate callbacks to Prebid's loading/interaction delegates.
final class ChartboostPrebidAdapterDisplayView: UIView, PrebidMobileDisplayViewProtocol {
    // Weak refs — Prebid owns the delegates' lifecycle; we must not retain.
    private weak var loadingDelegate: DisplayViewLoadingDelegate?
    private weak var interactionDelegate: DisplayViewInteractionDelegate?

    private let adm: String
    private let location: String
    private let bannerSize: CHBBannerSize
    private let adFactory: ChartboostAdFactory
    private var banner: ChartboostBannerAd?

    private weak var eventListener: ChartboostPrebidAdapterEventListener?

    // Each Prebid forward fires at most once: a banner's show/impression callbacks
    // can arrive more than once.
    private let loadLatch = SingleFireLatch()
    private let displayLatch = SingleFireLatch()
    private let impressionLatch = SingleFireLatch()

    // Forward-only lifecycle; out-of-order or duplicate entry points are rejected.
    // The Chartboost SDK delivers its callbacks on the main thread and loadAd hops to the
    // main thread before touching state, so plain (unsynchronized) state is safe here.
    private enum State { case idle, loading, ready, failed }
    private var state: State = .idle

    init(
        frame: CGRect,
        size: CHBBannerSize,
        adm: String,
        location: String,
        loadingDelegate: DisplayViewLoadingDelegate,
        interactionDelegate: DisplayViewInteractionDelegate,
        adFactory: ChartboostAdFactory = CHBAdFactory(),
        eventListener: ChartboostPrebidAdapterEventListener? = nil
    ) {
        self.adm = adm
        self.location = location
        self.bannerSize = size
        self.loadingDelegate = loadingDelegate
        self.interactionDelegate = interactionDelegate
        self.adFactory = adFactory
        self.eventListener = eventListener
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - PrebidMobileDisplayViewProtocol

    /// Invoked by Prebid after the view is returned from `createBannerView`.
    /// Per protocol contract: must call `loadingDelegate` once load completes or fails.
    func loadAd() {
        if MainThread.redispatchIfNeeded({ [weak self] in self?.loadAd() }) {
            return
        }
        guard state == .idle else {
            Log.warn("ChartboostPrebid: ignoring loadAd in state \(state)")
            return
        }
        state = .loading
        let banner = adFactory.makeBanner(size: bannerSize, location: location, delegate: self)
        self.banner = banner

        let adView = banner.adView
        addSubview(adView)
        adView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            adView.centerXAnchor.constraint(equalTo: centerXAnchor),
            adView.centerYAnchor.constraint(equalTo: centerYAnchor),
            adView.widthAnchor.constraint(equalToConstant: bannerSize.width),
            adView.heightAnchor.constraint(equalToConstant: bannerSize.height),
        ])

        // External-bidding entry point: hand the winning ADM to the Chartboost SDK.
        banner.cache(bidResponse: adm)
    }

    // MARK: - Bridge mapping
    //
    // The CHBBannerDelegate methods below unwrap the SDK event objects and defer to
    // these handlers, which hold the actual Chartboost→Prebid mapping. Keeping the
    // mapping free of SDK event types is what lets it be unit-tested directly.

    func handleCacheResult(error: Error?) {
        guard state == .loading else { return }
        if let error {
            state = .failed
            loadingDelegate?.displayView(self, didFailWithError: error)
            eventListener?.onAdFailed?(format: .banner, error: error)
            return
        }
        // A banner renders inline via show(from:), and the SDK requires a non-nil VC
        // (used for click-through presentation). Without one there is no clean way to
        // render, so fail the load rather than report a load we can't display.
        guard let viewController = interactionDelegate?.viewControllerForModalPresentation(fromDisplayView: self) else {
            state = .failed
            let failure = ChartboostPrebidAdapterError.missingPresentingViewController
            loadingDelegate?.displayView(self, didFailWithError: failure)
            eventListener?.onAdFailed?(format: .banner, error: failure)
            return
        }
        state = .ready
        // Report "loaded" on cache success, not on show — the show callback can fire
        // repeatedly, and Prebid treats a banner as ready once cached.
        if loadLatch.fire() {
            loadingDelegate?.displayViewDidLoadAd(self)
            eventListener?.onAdLoaded?(format: .banner)
        }
        banner?.show(from: viewController)
    }

    func handleShow(error: Error?) {
        // The banner has no Prebid "displayed" forward, but the event listener observes it.
        guard state == .ready else { return }
        if let error {
            // The SDK can deliver didShowAd twice for a banner: a success followed by a late
            // error that occurs after the ad was already shown. Only a failure before the ad
            // displays is terminal — surface it and block a spurious later impression/click.
            // A post-display error must not retract a shown ad or block its legitimate
            // impression/click, so ignore it once the display has fired.
            guard !displayLatch.fired else { return }
            state = .failed
            eventListener?.onAdFailed?(format: .banner, error: error)
            return
        }
        // Fire once on the first successful show; the show callback can repeat.
        if displayLatch.fire() {
            eventListener?.onAdDisplayed?(format: .banner)
        }
    }

    func handleImpression() {
        guard state == .ready else { return }
        // Billable impression — Prebid uses this to fire `burl` and the PBS event ping.
        if impressionLatch.fire() {
            interactionDelegate?.trackImpression(forDisplayView: self)
        }
    }

    func handleClick(error: Error?) {
        guard error == nil, state == .ready else { return }
        // No Prebid interaction-delegate call on click. The Chartboost SDK opens a
        // click-through either in-app (SKStoreProductViewController / SFSafariViewController)
        // or by leaving the app (UIApplication.open), and didClickAd fires before the
        // destination is known — but Prebid's banner delegate only exposes
        // destination-specific callbacks (didLeaveApp vs willPresentModal/didDismissModal),
        // so neither can be reported correctly yet. A Monetization SDK signal planned for
        // 9.15 will distinguish the two; until then we surface the click to our own observer
        // only.
        eventListener?.onAdClicked?(format: .banner)
    }

    func handleExpiration() {
        // Expiration is a logged no-op (the SDK logs the callback). We forward nothing
        // to Prebid, and a later show() on the expired ad fires no impression — so no
        // billable event for an ad that never displayed.
    }
}

// MARK: - CHBBannerDelegate
//
// The Chartboost SDK delivers these callbacks on the main thread, so the handlers
// above forward to Prebid directly without re-dispatching.

extension ChartboostPrebidAdapterDisplayView: CHBBannerDelegate {
    func didCacheAd(_ event: CHBCacheEvent, error: CacheError?) {
        handleCacheResult(error: error)
    }

    func didShowAd(_ event: CHBShowEvent, error: ShowError?) {
        // "Loaded" was already reported to Prebid on cache success; this only drives the
        // event listener's onAdDisplayed. A show-time failure has no terminal Prebid
        // signal and must not bill.
        handleShow(error: error)
    }

    func didRecordImpression(_ event: CHBImpressionEvent) {
        handleImpression()
    }

    func didClickAd(_ event: CHBClickEvent, error: ClickError?) {
        handleClick(error: error)
    }

    func didExpireAd(_ event: CHBExpirationEvent) {
        handleExpiration()
    }
}
