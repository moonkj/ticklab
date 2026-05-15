import SwiftUI

/// 디자인 SSOT styles.css `.tl-cosc-bar` port.
/// Range -12 ~ +12 s/d, COSC zone (-4 ~ +6) success-tinted band, current rate marker.
struct COSCBar: View {
    let rate: Double
    var showLegend: Bool = true

    private let minR: Double = -12
    private let maxR: Double = 12
    private let coscLo: Double = -4
    private let coscHi: Double = 6

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let pct = clamp((rate - minR) / (maxR - minR), 0, 1)
                let lo = (coscLo - minR) / (maxR - minR)
                let hi = (coscHi - minR) / (maxR - minR)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.paper2)
                        .frame(height: 8)
                        .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
                    Rectangle()
                        .fill(AppColors.success.opacity(0.24))
                        .frame(width: w * (hi - lo), height: 8)
                        .offset(x: w * lo)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(AppColors.success).frame(width: 2, height: 12)
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(AppColors.success).frame(width: 2, height: 12)
                        }
                    // UX 감사: needle color → accent (success 영역 위에서도 명확).
                    Rectangle()
                        .fill(AppColors.accentDark)
                        .frame(width: 4, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .offset(x: w * pct - 2, y: -3)
                }
            }
            .frame(height: 14)
            if showLegend {
                HStack {
                    Text("−12")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                    Spacer()
                    Text("COSC −4 ~ +6")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.success)
                    Spacer()
                    Text("+12")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                }
            }
        }
        // Round 170: VoiceOver — rate 와 COSC range 안/밖 명시.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coscAccessibilityLabel)
    }

    private var coscAccessibilityLabel: String {
        let inRange = rate >= coscLo && rate <= coscHi
        let status = inRange
            ? String(localized: "result.cosc.in")
            : String(localized: "result.cosc.out")
        return "Rate \(String(format: "%.1f", rate)) s/d, COSC \(status)"
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.min(hi, Swift.max(lo, v))
    }
}

#Preview {
    VStack(spacing: 20) {
        COSCBar(rate: 5.2)
        COSCBar(rate: -2.1)
        COSCBar(rate: 9.8)
        COSCBar(rate: -8.0, showLegend: false)
    }
    .padding()
    .background(AppColors.paper0)
}
