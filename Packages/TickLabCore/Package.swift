// swift-tools-version: 5.9
import PackageDescription

/// TickLabCore — DSP, 측정 알고리즘, 유틸리티 패키지.
/// @Model, SwiftUI 의존 없음 — 순수 Swift.
/// 독립 단위 테스트 가능.
let package = Package(
    name: "TickLabCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TickLabCore", targets: ["TickLabCore"]),
    ],
    targets: [
        .target(
            name: "TickLabCore",
            path: "Sources/TickLabCore"
        ),
        .testTarget(
            name: "TickLabCoreTests",
            dependencies: ["TickLabCore"],
            path: "Tests/TickLabCoreTests"
        ),
    ]
)
