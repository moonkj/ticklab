import Foundation

/// 브랜드 식별/메타 상수 — 사용자 노출 표기에 산발한 hardcoded 값을 한 곳에서 관리.
/// 변경 시 화면 검수: WatchBoxView (EST.\(foundedYear)), CollectionView footer, ShareCardComposerView 워터마크 등.
enum BrandConstants {
    /// TickLab brand 설립/런칭 연도. 시계 산업 관례상 EST. 표기에 사용.
    /// 매년 다시 박지 않도록 별도 상수 — 변경 시 의도적인 brand event 때만.
    static let foundedYear: Int = 2026

    /// 사용자 노출 워터마크.
    static let displayName = "TickLab"

    /// 짧은 로고 글리프.
    static let monogram = "TL"

    /// EST. 표기 문자열 — "EST.2026" 처럼 합쳐서 사용.
    static var establishedTag: String { "EST.\(foundedYear)" }
}
