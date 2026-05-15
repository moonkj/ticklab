import SwiftUI

/// Editorial metric card — eyebrow + 큰 mono 숫자 + 단위 + 옵셔널 hint.
/// 디자인 mockup 의 MetricCard 와 동일.
struct MetricBadge: View {
    enum Tone { case neutral, success, warning, danger }

    let label: String
    let value: String
    let unit: String?
    let hint: String?
    let tone: Tone
    let big: Bool

    init(
        label: String,
        value: String,
        unit: String? = nil,
        hint: String? = nil,
        tone: Tone = .neutral,
        big: Bool = false
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.hint = hint
        self.tone = tone
        self.big = big
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: big ? 22 : 18, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(toneColor)
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                }
            }
            .padding(.top, big ? 6 : 2)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.ink3)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, big ? 14 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper0)
        // Round 176: VoiceOver — '라벨, 값, 단위' 한 번에.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)\(unit.map { " \($0)" } ?? "")")
        .accessibilityHint(hint ?? "")
    }

    private var toneColor: Color {
        switch tone {
        case .neutral: return AppColors.ink0
        case .success: return AppColors.success
        case .warning: return AppColors.warning
        case .danger:  return AppColors.danger
        }
    }
}

/// 4개 metric 을 2×2 grid 로 — 디자인 mockup 의 .metric-grid 와 동일.
/// 내부 셀은 hairline rule 로 분리.
struct MetricGrid: View {
    let cells: [MetricBadge]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<(cells.count + 1) / 2, id: \.self) { row in
                HStack(spacing: 0) {
                    cells[row * 2]
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(AppColors.rule).frame(width: 1)
                        }
                    if row * 2 + 1 < cells.count {
                        cells[row * 2 + 1]
                    }
                }
                .overlay(alignment: .bottom) {
                    if row * 2 + 2 < cells.count {
                        Rectangle().fill(AppColors.rule).frame(height: 1)
                    }
                }
            }
        }
        .background(AppColors.paper0)
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    VStack(spacing: 12) {
        MetricGrid(cells: [
            MetricBadge(label: "Rate", value: "+1.8", unit: "s/day", hint: "Within COSC", tone: .success, big: true),
            MetricBadge(label: "Beat Error", value: "0.32", unit: "ms", hint: "Excellent", tone: .success, big: true),
            MetricBadge(label: "Amplitude", value: "286", unit: "°", big: true),
            MetricBadge(label: "BPH", value: "28800", big: true)
        ])
    }
    .padding()
    .background(AppColors.paper0)
}
