import SwiftUI

/// Sprint 10 (P3-8): 컬렉션 총 가치 + ⓘ 투명성 팝업.
/// 구매가 입력된 시계만 집계, 기준 명시.
struct CollectionValueCard: View {
    let watches: [Watch]
    @State private var showingInfo = false
    /// 계산기준 시트 — 내용 높이에 맞춰 detent 동적 조정(문구 길이 변화 대응).
    @State private var sheetHeight: CGFloat = 360

    private var priceWatches: [Watch] { watches.filter { $0.purchasePrice != nil } }

    private var totalValue: Decimal {
        priceWatches.compactMap(\.purchasePrice).reduce(0, +)
    }

    private var lastUpdated: String {
        DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
    }

    private var formattedTotal: String {
        let currency = priceWatches.first?.purchaseCurrency ?? (Locale.current.currency?.identifier ?? "USD")
        // 사용자 요청: KRW 는 "1,234.5 만원" 형태(만 단위 · 천단위 콤마 · 소수 1자리).
        if currency == "KRW" {
            let manwon = NSDecimalNumber(decimal: totalValue).doubleValue / 10_000.0
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.minimumFractionDigits = 1
            fmt.maximumFractionDigits = 1
            let num = fmt.string(from: NSNumber(value: manwon)) ?? "0.0"
            return String(format: String(localized: "collection.value.manwon"), num)
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currency
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSDecimalNumber(decimal: totalValue)) ?? "—"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "collection.value.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.ink3)
                Text(formattedTotal)
                    // 타이포 SSOT: 숫자=monospaced 통일 (이전 rounded → mono).
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.ink0)
                Text(String(format: NSLocalizedString("collection.value.count", comment: ""),
                            priceWatches.count, watches.count))
                    .font(.caption)
                    .foregroundStyle(AppColors.ink3)
            }
            Spacer()
            Button {
                showingInfo = true
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingInfo) {
            valueInfoSheet
        }
    }

    private var valueInfoSheet: some View {
        VStack(spacing: 20) {
            Capsule().fill(AppColors.rule).frame(width: 36, height: 4).padding(.top, 10)

            Image(systemName: "info.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.accentDark)

            Text(String(localized: "collection.value.info.title"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.ink0)

            VStack(alignment: .leading, spacing: 12) {
                infoRow(icon: "clock", text: String(format: NSLocalizedString("collection.value.info.updated", comment: ""), lastUpdated))
                infoRow(icon: "tag", text: String(localized: "collection.value.info.source"))
                infoRow(icon: "checkmark.circle", text: String(format: NSLocalizedString("collection.value.info.count", comment: ""), priceWatches.count, watches.count))
                infoRow(icon: "exclamationmark.triangle", text: String(localized: "collection.value.info.disclaimer"))
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
        // 내용 높이 측정 → detent 에 반영(빈 공간 없이 문구 길이에 맞춤).
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { sheetHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in sheetHeight = h }
        })
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .background(AppColors.paper0.ignoresSafeArea())
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.accentDark)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
