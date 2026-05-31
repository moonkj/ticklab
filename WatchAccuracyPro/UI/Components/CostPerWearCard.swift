import SwiftData
import SwiftUI

/// Sprint 1 (P2-12 ROI): 착용당 비용 카드 — 구매가 ÷ 누적 착용 일수.
/// 구매가 미입력 시 "구매가를 입력하면 가성비를 알 수 있어요" 넛지 표시.
struct CostPerWearCard: View {
    let watch: Watch
    @Environment(\.modelContext) private var context

    private var wearCount: Int { WearLogService.wearCount(for: watch, in: context) }

    private var costPerWear: Decimal? {
        guard let price = watch.purchasePrice, wearCount > 0 else { return nil }
        return price / Decimal(wearCount)
    }

    private var currencyFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = watch.purchaseCurrency ?? Locale.current.currency?.identifier ?? "USD"
        f.maximumFractionDigits = 0
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(AppColors.accentDark)
                Text(String(localized: "watch.roi.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.accentDark)
                Spacer()
            }
            if watch.purchasePrice == nil {
                Text(String(localized: "watch.roi.nudge"))
                    .font(.callout)
                    .foregroundStyle(AppColors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if wearCount == 0 {
                Text(String(localized: "watch.roi.empty"))
                    .font(.callout)
                    .foregroundStyle(AppColors.ink2)
            } else if let cpw = costPerWear {
                let nsNumber = NSDecimalNumber(decimal: cpw)
                Text(currencyFormatter.string(from: nsNumber) ?? "—")
                    .font(.title.bold())
                    .foregroundStyle(AppColors.ink0)
                Text(String(format: NSLocalizedString("watch.roi.subtitle", comment: ""), wearCount))
                    .font(.caption)
                    .foregroundStyle(AppColors.ink2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
