// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChartboostPrebidAdapter",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "ChartboostPrebidAdapter",
            targets: ["ChartboostPrebidAdapter"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/prebid/prebid-mobile-ios.git", "3.4.0"..<"3.5.0"),
        .package(url: "https://github.com/ChartBoost/chartboost-monetization-ios-sdk", .upToNextMinor(from: "9.14.0")),
    ],
    targets: [
        .target(
            name: "ChartboostPrebidAdapter",
            dependencies: [
                .product(name: "PrebidMobile", package: "prebid-mobile-ios"),
                .product(name: "ChartboostSDK", package: "chartboost-monetization-ios-sdk")
            ],
            path: "Source"
        ),
    ]
)
