// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import PrebidMobile
import UIKit

/// Banner shim that reports a terminal load failure instead of rendering.
final class ChartboostPrebidAdapterFailingDisplayView: UIView, PrebidMobileDisplayViewProtocol {
    private weak var loadingDelegate: DisplayViewLoadingDelegate?
    private weak var eventListener: ChartboostPrebidAdapterEventListener?
    private let error: Error

    init(
        error: Error,
        loadingDelegate: DisplayViewLoadingDelegate,
        eventListener: ChartboostPrebidAdapterEventListener? = nil
    ) {
        self.error = error
        self.loadingDelegate = loadingDelegate
        self.eventListener = eventListener
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func loadAd() {
        if MainThread.redispatchIfNeeded({ [weak self] in self?.loadAd() }) {
            return
        }
        loadingDelegate?.displayView(self, didFailWithError: error)
        eventListener?.onAdFailed?(format: .banner, error: error)
    }
}

/// Interstitial/rewarded shim that reports a terminal load failure instead of loading.
final class ChartboostPrebidAdapterFailingInterstitialController: NSObject, PrebidMobileInterstitialControllerProtocol {
    private weak var loadingDelegate: InterstitialControllerLoadingDelegate?
    private weak var eventListener: ChartboostPrebidAdapterEventListener?
    private let error: Error
    private let format: ChartboostPrebidAdapterAdFormat

    init(
        error: Error,
        loadingDelegate: InterstitialControllerLoadingDelegate,
        eventListener: ChartboostPrebidAdapterEventListener? = nil,
        format: ChartboostPrebidAdapterAdFormat = .interstitial
    ) {
        self.error = error
        self.loadingDelegate = loadingDelegate
        self.eventListener = eventListener
        self.format = format
        super.init()
    }

    func loadAd() {
        if MainThread.redispatchIfNeeded({ [weak self] in self?.loadAd() }) {
            return
        }
        loadingDelegate?.interstitialController(self, didFailWithError: error)
        eventListener?.onAdFailed?(format: format, error: error)
    }

    func show() {
        // Never loads, so there is nothing to show.
    }
}
