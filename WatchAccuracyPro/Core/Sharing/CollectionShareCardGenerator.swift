import SwiftUI
import UIKit

/// 컬렉션 자랑 카드 (이미지) — 인스타 역유입. R6 비측정 바이럴.
/// 측정값 제외: 시계 수·브랜드·보유 연차 + 대표 사진 그리드 + TickLab 워터마크.
/// ImageRenderer 로 1회 렌더(탭 시) → 공유시트. ShareCardComposer 렌더 패턴 재사용.
enum CollectionShareCardGenerator {
    @MainActor
    static func generate(watches: [Watch], ownerName: String) -> URL? {
        let card = CollectionShareCard(watches: watches, ownerName: ownerName)
            .frame(width: 360)   // 높이는 콘텐츠에 맞춰 늘어남(최소 450) — TickLab 워터마크까지 항상 포함.
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3   // ~1080×1350
        renderer.isOpaque = true
        guard let img = renderer.uiImage, let data = img.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TickLab_Collection_Card.png")
        try? data.write(to: url)
        return url
    }
}

/// 공유 대상 래퍼 — sheet(item:) 용 Identifiable.
struct ShareCardItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController 래퍼 — 공유시트.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private struct CollectionShareCard: View {
    let watches: [Watch]
    let ownerName: String

    private var brands: Int { Set(watches.map(\.brand)).count }
    private var years: Int {
        let dates = watches.map { $0.purchaseDate ?? $0.createdAt }
        guard let earliest = dates.min() else { return 0 }
        return max(0, Calendar.current.dateComponents([.year], from: earliest, to: Date()).year ?? 0)
    }
    /// 사진 있는 시계 우선, 최대 6.
    private var gridWatches: [Watch] {
        let withPhoto = watches.filter { $0.photoData != nil }
        let without = watches.filter { $0.photoData == nil }
        return Array((withPhoto + without).prefix(6))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                // 프로필 아바타 — 컬렉터 정체성(있을 때만).
                if let data = UserProfile.photoData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.paper0, lineWidth: 2))
                }
                HStack(spacing: 6) {
                    Text(ownerName.isEmpty ? String(localized: "collection.sharecard.tagline") : ownerName)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.ink0)
                        .lineLimit(1)
                    if UserProfile.isDealer {
                        Text(String(localized: "profile.badge.dealer"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.primaryDeep)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(AppColors.accent).clipShape(Capsule())
                    }
                }
                Text(String(format: NSLocalizedString("collection.sharecard.stats", comment: ""),
                            watches.count, brands, years))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.ink2)
                // 보유 시작 연도(프로필) — 컬렉터 연차 강조.
                if !UserProfile.startYear.isEmpty {
                    Text(String(format: String(localized: "profile.since"), UserProfile.startYear))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.ink3)
                }
            }
            .padding(.top, 26)
            .padding(.bottom, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(gridWatches, id: \.id) { w in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(AppColors.paper2)
                        if let data = w.photoData, let ui = UIImage(data: data) {
                            Image(uiImage: ui).resizable().scaledToFill()
                        } else {
                            WatchSilhouette(watch: w, size: 48)
                        }
                    }
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "applewatch")
                Text("TickLab").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(AppColors.accentDark)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, minHeight: 450, alignment: .top)
        .background(
            LinearGradient(colors: [AppColors.accent50, AppColors.paper0],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}
