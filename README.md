# Chartboost Prebid Adapter

A Prebid Mobile plugin renderer that hands Chartboost-flagged winning bids to the Chartboost
Monetization SDK for rendering, instead of Prebid's default renderer.

## Minimum Requirements

| Component | Version |
| --------- | ------- |
| Prebid Mobile SDK | See [Package.swift](Package.swift) |
| iOS | 15.0+ |
| Xcode | 15.0+ |

The Chartboost Monetization SDK is pinned and resolved by this package (see [Integration](#integration)), so you don't select its version.

## How it works

For a winning bid, Prebid Mobile routes rendering to this plugin only when all of these hold:

1. `ext.prebid.meta.rendererName` matches the plugin's name (`Chartboost-iOS-SDK`).
2. `ext.prebid.meta.rendererVersion` matches the plugin's version exactly, byte for byte.
3. The bid's format is one this plugin renders — banner, interstitial, or rewarded.

On a match, the plugin builds a Chartboost `CHBBanner` / `CHBInterstitial` / `CHBRewarded`, hands it the
bid's `adm` via `cache(bidResponse:)`, and renders. A mismatch on any of these falls back to Prebid's
default renderer.

## Integration

The adapter is distributed through **Swift Package Manager only** (CocoaPods is not supported). Its
`Package.swift` declares the Chartboost Monetization SDK and Prebid Mobile as dependencies, so adding this
one package resolves all three — you do not add them separately.

Add the package:

```
https://github.com/ChartBoost/chartboost-prebid-ios-adapter
```

Then add `-ObjC` to your app target's **Other Linker Flags** (Build Settings).

Register the renderer once before initializing Prebid:

```swift
import ChartboostPrebidAdapter
import ChartboostSDK
import PrebidMobile

Prebid.registerPluginRenderer(ChartboostPrebidAdapter())
try? Prebid.initializeSDK(serverURL: "https://<your-pbs-host>/openrtb2/auction")
Chartboost.start(withAppID: "<your-app-id>", appSignature: "<your-app-signature>") { _ in }
```

Then load a Prebid rendering ad unit as usual (`BannerView` / `InterstitialRenderingAdUnit` /
`RewardedAdUnit`); a Chartboost-flagged bid routes to this plugin automatically. No per-ad-unit Chartboost
code is required.

### Lifecycle events (optional)

Assign a `ChartboostPrebidAdapterEventListener` to the renderer's `eventListener` before registering to
observe the lifecycle of ads this renderer handled (loaded / displayed / clicked / failed for all formats,
plus dismissed / reward for fullscreen) — independently of Prebid's own delegates.

## Known limitations

### Banner clicks do not pause auto-refresh

Prebid Mobile pauses a banner's auto-refresh timer while a click-through is on screen, driven by its
interaction-delegate callbacks (`willPresentModal` / `didLeaveApp`). This adapter does not emit those
callbacks on a click: the Chartboost SDK reports a click *before* the click-through destination is known
(an in-app modal such as `SKStoreProductViewController`/`SFSafariViewController`, or leaving the app via
the browser), and Prebid exposes only destination-specific callbacks — so neither can be reported
correctly. As a result, a banner may auto-refresh while a click-through it opened is still on screen. A
Monetization SDK signal planned for a future release will distinguish the two destinations so the correct
callback can be wired.

## Consent and privacy

This adapter does not collect, store, or forward any consent signals. GDPR, US Privacy (CCPA), COPPA, and
GPP are owned by the Chartboost Monetization SDK, which collects these signals if available from your consent
management platform. Configure your regulatory signals before loading ads, exactly as you would for any other
Chartboost integration; see the [Monetization SDK's documentation](https://docs.chartboost.com/en/monetization/) for how. Plugin-rendered ads render through
that same SDK instance, so its consent state applies to them as well.

## Versioning

The adapter version encodes the Prebid Mobile major and the Chartboost Monetization version it targets — for
example, `309.14.0` corresponds to Prebid 3.x and Monetization 9.14. The Prebid Server adapter echoes this
value back from the request, so the client-registered version and the server-stamped version match by
construction — no shared constant or lock-step release. A new adapter is cut on Monetization major/minor
releases.

See [Package.swift](Package.swift) for the full range of compatible Prebid Mobile versions.

## License

Refer to our [LICENSE](https://github.com/ChartBoost/chartboost-prebid-ios-adapter/blob/main/LICENSE) file for more information.
