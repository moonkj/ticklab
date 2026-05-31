import SwiftData
import SwiftUI

/// Sprint 5 (P2-13): 시계별 TCO 카드 — 구매가 + 정비비 합산.
/// WatchDetail 재무 탭에서 표시. CostPerWearCard 와 함께 배치.
struct TCOCard: View {
    let watch: Watch
    @Query private var serviceLogs: [ServiceLog]

    init(watch: Watch) {
        self.watch = watch
        let watchID = watch.id
        _serviceLogs = Query(filter: #Predicate<ServiceLog> { $0.watch?.id == watchID })
    }

    private var totalServiceCost: Decimal {
        serviceLogs.compactMap(\.costAmount).reduce(0, +)
    }

    private var tco: Decimal? {
        guard let purchase = watch.purchasePrice else { return nil }
        return purchase + totalServiceCost
    }

    private var currencyCode: String {
        watch.purchaseCurrency ?? "KRW"
    }

    private func format(_ value: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currencyCode
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(AppColors.accentDark)
                Text(String(localized: "watch.tco.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.accentDark)
                Spacer()
            }

            if watch.purchasePrice == nil {
                Text(String(localized: "watch.tco.nudge"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    tcoColumn(
                        label: String(localized: "watch.tco.purchase"),
                        value: watch.purchasePrice.map { format($0) } ?? "—"
                    )
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink3)
                        .padding(.bottom, 4)
                    tcoColumn(
                        label: String(localized: "watch.tco.service"),
                        value: format(totalServiceCost)
                    )
                    Image(systemName: "equal")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink3)
                        .padding(.bottom, 4)
                    if let total = tco {
                        tcoColumn(
                            label: "TCO",
                            value: format(total),
                            isPrimary: true
                        )
                    }
                    Spacer(minLength: 0)
                }
                if totalServiceCost > 0 {
                    Text(String(format: NSLocalizedString("watch.tco.service_count", comment: ""), serviceLogs.filter { $0.costAmount != nil }.count))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink3)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tcoColumn(label: String, value: String, isPrimary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(AppColors.ink3)
            Text(value)
                .font(.system(size: isPrimary ? 18 : 14, weight: isPrimary ? .bold : .semibold))
                .foregroundStyle(isPrimary ? AppColors.accentDark : AppColors.ink0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
