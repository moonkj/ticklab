import SwiftUI

/// T-25: 두 시계의 측정 정확도를 나란히 비교. `WatchDetailView`에서 진입.
/// 측정 데이터(rate/beat error/amplitude/confidence)는 온디바이스 집계만 — 외부 전송 없음(Hard Rule 8).
struct CompareView: View {
    let left: Watch
    let right: Watch

    private struct Stats {
        let count: Int
        let avgRate: Double?
        let avgBeatError: Double?
        let avgAmplitude: Double?
        let avgConfidence: Int?
        let lastMeasured: Date?
    }

    private func stats(_ w: Watch) -> Stats {
        let ms = w.measurements
        guard !ms.isEmpty else {
            return Stats(count: 0, avgRate: nil, avgBeatError: nil,
                         avgAmplitude: nil, avgConfidence: nil, lastMeasured: nil)
        }
        let rates = ms.map(\.rateSecondsPerDay)
        let be = ms.map(\.beatErrorMs)
        let amps = ms.compactMap(\.amplitudeDegrees)
        let conf = ms.map(\.confidenceScore)
        return Stats(
            count: ms.count,
            avgRate: rates.reduce(0, +) / Double(rates.count),
            avgBeatError: be.reduce(0, +) / Double(be.count),
            avgAmplitude: amps.isEmpty ? nil : amps.reduce(0, +) / Double(amps.count),
            avgConfidence: Int((Double(conf.reduce(0, +)) / Double(conf.count)).rounded()),
            lastMeasured: ms.map(\.timestamp).max()
        )
    }

    /// "더 정확한 시계" = 평균 rate 절대값이 작은 쪽. 둘 다 측정 있어야 판정.
    private var moreAccurateIsLeft: Bool? {
        guard let l = stats(left).avgRate, let r = stats(right).avgRate, abs(l) != abs(r) else { return nil }
        return abs(l) < abs(r)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                column(left, isMoreAccurate: moreAccurateIsLeft == true)
                column(right, isMoreAccurate: moreAccurateIsLeft == false)
            }
            .padding(20)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "compare.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func column(_ watch: Watch, isMoreAccurate: Bool) -> some View {
        let s = stats(watch)
        return VStack(alignment: .leading, spacing: 0) {
            Text(watch.brand.uppercased())
                .font(AppTypography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(AppColors.ink3)
                .lineLimit(1)
            Text(watch.model)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(AppColors.ink0)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if isMoreAccurate {
                Text(String(localized: "compare.more_accurate"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.paper0)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(AppColors.success)
                    .clipShape(Capsule())
                    .padding(.top, 6)
            }

            if s.count == 0 {
                Text(String(localized: "compare.no_data"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.ink3)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    metric(String(localized: "compare.rate"),
                           s.avgRate.map { String(format: "%+.1f", $0) } ?? "—")
                    metric(String(localized: "compare.beat_error"),
                           s.avgBeatError.map { String(format: "%.1f ms", $0) } ?? "—")
                    metric(String(localized: "compare.amplitude"),
                           s.avgAmplitude.map { String(format: "%.0f°", $0) } ?? "—")
                    metric(String(localized: "compare.confidence"),
                           s.avgConfidence.map { "\($0)" } ?? "—")
                    metric(String(localized: "compare.last_measured"),
                           s.lastMeasured.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                }
                .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(16)
        .background(AppColors.paper1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isMoreAccurate ? AppColors.success.opacity(0.5) : AppColors.rule, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.ink2)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.ink0)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColors.rule).frame(height: 0.5)
        }
    }
}

#Preview {
    let w1 = Watch(brand: "Rolex", model: "Submariner", caliber: "Rolex_3135")
    let w2 = Watch(brand: "Tudor", model: "Black Bay 58", caliber: "Tudor_MT5602")
    return NavigationStack { CompareView(left: w1, right: w2) }
}
