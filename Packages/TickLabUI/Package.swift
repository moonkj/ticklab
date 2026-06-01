// swift-tools-version: 5.9
import PackageDescription

/// TickLabUI — 디자인 시스템 + 공통 컴포넌트 패키지.
/// @Model, SwiftData 의존 없음 — 순수 SwiftUI.
/// 앱 레이어와 분리해 컴포넌트 단독 Preview 가능.
let package = Package(
    name: "TickLabUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TickLabUI", targets: ["TickLabUI"]),
    ],
    targets: [
        .target(
            name: "TickLabUI",
            path: "Sources/TickLabUI"
        ),
    ]
)
