import SwiftData
import SwiftUI

/// Sprint 4 (P2-17): TickLab Wrapped — 연간 리포트 슬라이드쇼.
struct WrappedView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int = 0
    @State private var data: WrappedReportData?

    private let year: Int

    init(year: Int = Calendar.current.component(.year, from: Date())) {
        self.year = year
    }

    var body: some View {
        ZStack {
            AppColors.primaryDeep.ignoresSafeArea()
            if let data {
                TabView(selection: $page) {
                    coverPage(data).tag(0)
                    wearsPage(data).tag(1)
                    watchPage(data).tag(2)
                    measurePage(data).tag(3)
                    closingPage(data).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            } else {
                ProgressView().tint(.white)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.system(size: 22))
                }
            }
        }
        .task {
            data = WrappedReportData.generate(year: year, context: context)
        }
    }

    // MARK: - Pages

    private func coverPage(_ d: WrappedReportData) -> some View {
        wrappedCard {
            VStack(spacing: 16) {
                Text("⌚").font(.system(size: 64))
                Text(String(format: NSLocalizedString("wrapped.cover.title", comment: ""), d.year))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text(String(localized: "wrapped.cover.subtitle"))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func wearsPage(_ d: WrappedReportData) -> some View {
        wrappedCard {
            VStack(spacing: 12) {
                statLabel(String(localized: "wrapped.wears.label"))
                bigNumber("\(d.totalWears)")
                Text(String(localized: "wrapped.wears.unit"))
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
                if d.highlightCount > 0 {
                    Divider().background(.white.opacity(0.3)).padding(.vertical, 4)
                    statLabel(String(localized: "wrapped.highlights.label"))
                    bigNumber("\(d.highlightCount)")
                }
                if let tag = d.topTag {
                    Divider().background(.white.opacity(0.3)).padding(.vertical, 4)
                    statLabel(String(localized: "wrapped.toptag.label"))
                    Text(tag)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func watchPage(_ d: WrappedReportData) -> some View {
        wrappedCard {
            VStack(spacing: 12) {
                if let most = d.mostWornWatch {
                    statLabel(String(localized: "wrapped.mostworn.label"))
                    Text("\(most.watch.brand)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(most.watch.model)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    bigNumber("\(most.count)")
                    Text(String(localized: "wrapped.wears.unit"))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                if d.newWatchesAdded > 0 {
                    Divider().background(.white.opacity(0.3)).padding(.vertical, 4)
                    statLabel(String(localized: "wrapped.newwatches.label"))
                    bigNumber("\(d.newWatchesAdded)")
                }
            }
        }
    }

    private func measurePage(_ d: WrappedReportData) -> some View {
        wrappedCard {
            VStack(spacing: 12) {
                statLabel(String(localized: "wrapped.measurements.label"))
                bigNumber("\(d.totalMeasurements)")
                if let avg = d.avgRateSecondsPerDay {
                    Divider().background(.white.opacity(0.3)).padding(.vertical, 4)
                    statLabel(String(localized: "wrapped.avgrate.label"))
                    Text(String(format: "%+.1f s/d", avg))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(avg.magnitude <= 6 ? AppColors.success : AppColors.warning)
                }
            }
        }
    }

    private func closingPage(_ d: WrappedReportData) -> some View {
        wrappedCard {
            VStack(spacing: 16) {
                Text("🎉").font(.system(size: 56))
                Text(String(format: NSLocalizedString("wrapped.closing.title", comment: ""), d.year + 1))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(String(localized: "wrapped.closing.subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Text("TickLab")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Helpers

    private func wrappedCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private func bigNumber(_ text: String) -> some View {
        Text(text)
            // 타이포 SSOT: 숫자=monospaced 통일 (이전 rounded → mono).
            .font(.system(size: 72, weight: .black, design: .monospaced))
            .foregroundStyle(.white)
    }

    private func statLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.6))
    }
}
