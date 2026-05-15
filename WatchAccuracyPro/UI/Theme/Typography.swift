import SwiftUI

/// TickLab editorial typography.
/// - 디자인 mockup 은 Fraunces (italic display) 와 Inter, JetBrains Mono 사용.
/// - iOS 시스템 글꼴 매핑:
///     · Fraunces → New York (.serif, italic)  — 한글은 자동으로 Apple SD Gothic Neo
///     · Inter    → SF Pro (.default)
///     · JetBrains Mono → SF Mono (.monospaced)
enum AppTypography {
    // Display — editorial "italic" 헤드라인
    static let display: Font     = .system(.largeTitle, design: .serif).italic().weight(.medium)
    static let displaySmall: Font = .system(.title, design: .serif).italic().weight(.medium)

    // Serif heading (non-italic)
    static let title: Font       = .system(.title2, design: .serif).weight(.medium)
    static let headline: Font    = .system(.headline, design: .serif).weight(.medium)
    static let serifBody: Font   = .system(.body, design: .serif)

    // Sans body
    static let body: Font        = .system(.body, design: .default)
    static let bodySmall: Font   = .system(.subheadline, design: .default)
    static let caption: Font     = .system(.caption, design: .default)

    // Eyebrow — uppercase letter-spaced label
    static let eyebrow: Font     = .system(.caption2, design: .default).weight(.semibold)

    // Mono (numbers + labels)
    static let mono: Font        = .system(.body, design: .monospaced)
    static let monoSmall: Font   = .system(.caption, design: .monospaced)
    static let monoMetric: Font  = .system(.title, design: .monospaced).weight(.medium)
    static let monoMetricLarge: Font = .system(.largeTitle, design: .monospaced).weight(.medium)

    // 기존 호환
    static let largeTitle: Font  = display
}

/// "EYEBROW · 18px label" 자주 쓰는 모티프 — 작은 회색 대문자.
struct EyebrowLabel: View {
    let text: String
    var number: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let number {
                Text(number)
                    .font(AppTypography.monoSmall)
                    .foregroundStyle(AppColors.ink3)
            }
            Rectangle()
                .fill(AppColors.ruleStrong)
                .frame(width: 18, height: 1)
            Text(text.uppercased())
                .font(AppTypography.eyebrow)
                .tracking(2.5)
                .foregroundStyle(AppColors.ink2)
        }
    }
}

/// 섹션 헤더 — "01 · LATEST READING / Latest reading" 패턴.
struct SectionHeading: View {
    let number: String?
    let eyebrow: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel(text: eyebrow, number: number)
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.ink0)
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
        }
    }
}
