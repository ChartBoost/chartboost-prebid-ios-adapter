// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import ChartboostSDK
import PrebidMobile
import UIKit

/// Plugin renderer that hands Chartboost-flagged Prebid bids to the Chartboost Monetization SDK.
///
/// Routing: for a winning bid, Prebid Mobile's `PrebidMobilePluginRegister` routes rendering
/// here only when `bid.ext.prebid.meta.rendererName` equals this plugin's `name`
/// ("Chartboost-iOS-SDK"; platform-specific — the Android plugin uses "Chartboost-Android-SDK"),
/// `bid.ext.prebid.meta.rendererVersion` equals this plugin's `version` exactly, and the bid's
/// format is one this plugin renders (banner, interstitial, or rewarded). A mismatch on any of
/// these falls back to Prebid's default renderer.
///
/// Registration (one-time, at app init):
/// ```swift
/// let renderer = ChartboostPrebidAdapter()
/// renderer.eventListener = myListener // optional
/// Prebid.registerPluginRenderer(renderer)
/// Chartboost.start(withAppID: "...", appSignature: "...") { _ in }
/// ```
@objcMembers
public final class ChartboostPrebidAdapter: NSObject, PrebidMobilePluginRenderer {
    /// Optional observer of the lifecycle of ads this renderer handles (set before
    /// registering). Distinct from Prebid's own per-ad-unit delegates; useful for
    /// confirming that a bid was rendered by Chartboost rather than Prebid's default
    /// renderer.
    public weak var eventListener: ChartboostPrebidAdapterEventListener?

    /// Public plugin name. Must match `bid.ext.prebid.meta.rendererName` stamped by the PBS
    /// adapter for iOS traffic. Platform-specific and stable: iOS advertises
    /// "Chartboost-iOS-SDK", Android "Chartboost-Android-SDK"; PBS picks from `device.os`.
    public static let pluginName = "Chartboost-iOS-SDK"

    /// Plugin version. The bid's `bid.ext.prebid.meta.rendererVersion` must equal this
    /// string exactly, and it matches the published release tag.
    public static let pluginVersion = "309.14.0"

    public var name: String { Self.pluginName }
    public var version: String { Self.pluginVersion }

    /// Dynamic data attached to the bid request as `ext.prebid.sdk.renderers[].data`.
    /// `Chartboost.bidderToken()` is fetched on every access — Prebid Mobile reads `data`
    /// per-auction, keeping the bidder token fresh without publisher-side intervention.
    /// The Prebid Server Chartboost adapter reads `bidderToken` from this and forwards
    /// it to the Chartboost exchange.
    public var data: [String: Any]? {
        var dict: [String: Any] = [:]
        if let token = Chartboost.bidderToken(), !token.isEmpty {
            dict["bidderToken"] = token
        }
        return dict.isEmpty ? nil : dict
    }

    // MARK: - Event delegate (no-op)

    // Prebid's plugin-event interface is identity-only: it exposes no required
    // billing/impression hook, and we define no custom event subtype. Impressions
    // and clicks already flow through the Chartboost interaction delegate
    // (trackImpression), so there is nothing to dispatch here. These protocol
    // methods therefore intentionally do nothing. Re-verify if a future Prebid
    // version adds a required event to this interface.
    public func registerEventDelegate(
        pluginEventDelegate: PluginEventDelegate,
        adUnitConfigFingerprint: String
    ) {}

    public func unregisterEventDelegate(
        pluginEventDelegate: PluginEventDelegate,
        adUnitConfigFingerprint: String
    ) {}

    // MARK: - Banner

    public func createBannerView(
        with frame: CGRect,
        bid: Bid,
        adConfiguration: AdUnitConfig,
        loadingDelegate: DisplayViewLoadingDelegate,
        interactionDelegate: DisplayViewInteractionDelegate
    ) -> (UIView & PrebidMobileDisplayViewProtocol)? {
        // Prebid has already selected us (rendererName/version matched), so this bid
        // is ours to own. Never return nil on a bad bid — that makes Prebid fall
        // back to its default renderer and paint the opaque payload as a spurious
        // billed impression. Return a shim that reports the failure terminally.
        guard let adm = bid.adm, !adm.isEmpty else {
            return ChartboostPrebidAdapterFailingDisplayView(
                error: ChartboostPrebidAdapterError.missingAdMarkup,
                loadingDelegate: loadingDelegate,
                eventListener: eventListener
            )
        }
        let negotiatedSize = Self.negotiatedBannerSize(bidSize: bid.size, adUnitSize: adConfiguration.adSize)
        // The Chartboost SDK renders only its fixed banner sizes, so snap the negotiated area down
        // to the largest fixed size that fits inside it. If the area is too small for even the
        // smallest fixed size, reject the bid rather than force a size that would clip — the slot
        // simply goes unfilled.
        guard let size = Self.mapToChartboostBannerSize(negotiatedSize) else {
            return ChartboostPrebidAdapterFailingDisplayView(
                error: ChartboostPrebidAdapterError.unsupportedBannerSize(negotiatedSize),
                loadingDelegate: loadingDelegate,
                eventListener: eventListener
            )
        }
        return ChartboostPrebidAdapterDisplayView(
            frame: CGRect(origin: frame.origin, size: size),
            size: size,
            adm: adm,
            location: adConfiguration.configId,
            loadingDelegate: loadingDelegate,
            interactionDelegate: interactionDelegate,
            eventListener: eventListener
        )
    }

    /// The banner area to snap: the bid's own size, or the size the auction was run for when the
    /// bid declared none.
    ///
    /// `Bid.size` is `.zero` when the bid carried no `w`/`h` — that means "unknown", not "zero-area
    /// slot", and bidders do omit them (Chartboost's own exchange does on banner bids). Treating it
    /// as an area drops a paying bid. `frame` can't stand in: PrebidMobile derives it from
    /// `bid.size`, so it is zero on exactly these bids.
    static func negotiatedBannerSize(bidSize: CGSize, adUnitSize: CGSize) -> CGSize {
        bidSize == .zero ? adUnitSize : bidSize
    }

    /// Snaps an auction-negotiated banner area to the largest Chartboost SDK `CHBBannerSize`
    /// that fits within it, or nil if none fit — in which case the caller rejects the bid and
    /// the slot goes unfilled (e.g. a 320x49 area is one point too short for the 320x50 standard
    /// banner, so nothing can be served).
    ///
    /// Candidates are ranked by area, largest first, so a slot large enough to hold several
    /// fixed sizes is filled by the biggest one it can contain. Both dimensions must fit: a
    /// candidate is eligible only when the area is at least as wide and as tall as it.
    static func mapToChartboostBannerSize(_ size: CGSize) -> CHBBannerSize? {
        // Largest area first: half page (300x600) > medium (300x250) > leaderboard (728x90) > standard (320x50).
        let candidates: [CHBBannerSize] = [
            CHBBannerSizeHalfPage,
            CHBBannerSizeMedium,
            CHBBannerSizeLeaderboard,
            CHBBannerSizeStandard,
        ]
        return candidates.first { size.width >= $0.width && size.height >= $0.height }
    }

    // MARK: - Interstitial / Rewarded

    public func createInterstitialController(
        bid: Bid,
        adConfiguration: AdUnitConfig,
        loadingDelegate: InterstitialControllerLoadingDelegate,
        interactionDelegate: InterstitialControllerInteractionDelegate
    ) -> PrebidMobileInterstitialControllerProtocol? {
        // Rewarded vs. plain interstitial use different Chartboost ad classes. Determined up front
        // so the failure path can report the right format.
        let isRewarded = Self.isRewardedAd(adConfiguration: adConfiguration)
        // As with banners: we've been selected, so fail terminally rather than
        // returning nil and letting Prebid render the payload as a spurious impression.
        guard let adm = bid.adm, !adm.isEmpty else {
            return ChartboostPrebidAdapterFailingInterstitialController(
                error: ChartboostPrebidAdapterError.missingAdMarkup,
                loadingDelegate: loadingDelegate,
                eventListener: eventListener,
                format: isRewarded ? .rewarded : .interstitial
            )
        }
        return ChartboostPrebidAdapterInterstitialController(
            adm: adm,
            location: adConfiguration.configId,
            isRewarded: isRewarded,
            loadingDelegate: loadingDelegate,
            interactionDelegate: interactionDelegate,
            eventListener: eventListener
        )
    }

    /// Whether a fullscreen bid should render as a Chartboost rewarded ad.
    ///
    /// The ad unit the publisher created is the authority: `RewardedAdUnit` marks its configuration
    /// rewarded, `InterstitialRenderingAdUnit` does not. The bid is not a reliable signal —
    /// `Bid.rewardedConfig` is read from an `ext.prebid.passthrough` entry that only exists when the
    /// Prebid Server stored request injects one, so keying on it renders a rewarded placement as a
    /// plain interstitial (no reward callback) whenever that server-side config is absent.
    static func isRewardedAd(adConfiguration: AdUnitConfig) -> Bool {
        adConfiguration.adConfiguration.isRewarded
    }
}
