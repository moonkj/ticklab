import SwiftData
import SwiftUI

/// Sprint 13 (F1, Doyoon+수집가): 자세별 편차 워크벤치.
/// 측정들을 6자세(DU/DD/CU/CD/PL/PR)별로 그룹핑해 자세별 평균 rate + 최대편차(δ) 표시.
/// 워치메이커 정비 판정 핵심 지표. read-only — 신규 측정/모델 없음.
struct PositionalDeltaView: View {
    let watch: Watch

    private struct PositionStat: Identifiable {
        let position: Position
        let avgRate: Double
        let count: Int
        var id: String { position.rawValue }
    }

    private var stats: [PositionStat] {
        // unknown 제외, 자세별 평균 rate 집계
        var grouped: [Position: [Double]] = [:]
        for m in watch.measurements {
            let pos = m.metadata.position
            guard pos != .unknown else { continue }
            grouped[pos, default: []].append(m.rateSecondsPerDay)
        }
        return grouped.compactMap { pos, rates in
            guard !rates.isEmpty else { return nil }
            return PositionStat(position: pos, avgRate: rates.reduce(0,+)/Double(rates.count), count: rates.count)
        }
        .sorted { $0.position.rawValue < $1.position.rawValue }
    }

    /// 최대 편차 δ = max(avg) - min(avg). 워치메이커 기준: <8 우수, <15 양호, ≥15 정비.
    private var delta: Double? {
        let avgs = stats.map(\.avgRate)
        guard avgs.count >= 2, let mx = avgs.max(), let mn = avgs.min() else { return nil }
        return mx - mn
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if stats.count < 2 {
                    emptyState
                } else {
                    deltaCard
                    positionTable
                    methodologyCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "positional.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var deltaCard: some View {
        let d = delta ?? 0
        let (tone, label): (Color, String) = {
            if d < 8 { return (AppColors.success, String(localized: "positional.grade.excellent")) }
            if d < 15 { return (AppColors.warning, String(localized: "positional.grade.good")) }
            return (AppColors.danger, String(localized: "positional.grade.service"))
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "positional.delta.title"))
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(AppColors.accentDark)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", d))
                    // 타이포 SSOT: 숫자=monospaced 통일 (이전 rounded → mono).
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(tone)
                Text("s/d")
                    .font(.system(size: 14)).foregroundStyle(AppColors.ink2)
                Spacer()
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tone.opacity(0.12)).clipShape(Capsule())
            }
            Text(String(localized: "positional.delta.hint"))
                .font(.caption).foregroundStyle(AppColors.ink3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var positionTable: some View {
        VStack(spacing: 0) {
            ForEach(stats) { stat in
                HStack {
                    Text(stat.position.rawValue)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.accentDark)
                        .frame(width: 44, alignment: .leading)
                    Text(stat.position.localizedName)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink2)
                    Spacer()
                    Text(String(format: "%+.1f s/d", stat.avgRate))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.ink0)
                    Text("(\(stat.count))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                        .frame(width: 32, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                if stat.id != stats.last?.id {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var methodologyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(AppColors.info)
            Text(String(localized: "positional.methodology"))
                .font(.system(size: 12)).foregroundStyle(AppColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppColors.info.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        EmptyState(
            icon: "rotate.3d",
            title: String(localized: "positional.empty.title"),
            message: String(localized: "positional.empty.body")
        )
    }
}
