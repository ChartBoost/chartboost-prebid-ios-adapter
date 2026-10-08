// Copyright 2026-2026 Chartboost, Inc.
//
// Licensed under the MIT license.

import ChartboostSDK
import PrebidMobile

extension ChartboostPrebidAdapter {
    /// Mediation context passed to every CHB ad object so the Chartboost SDK
    /// records this traffic as Prebid-mediated rather than direct.
    ///
    /// The two version fields describe different things: `libraryVersion` is the
    /// host mediation library's runtime version (Prebid Mobile, which actually runs
    /// the auction), while `adapterVersion` is this plugin's own version. Keep them
    /// distinct — they are not the same value.
    static let mediationParam = CHBMediation(
        name: "Prebid",
        libraryVersion: Prebid.shared.version,
        adapterVersion: ChartboostPrebidAdapter.pluginVersion
    )
}
