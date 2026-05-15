import SwiftData
import SwiftUI

/// 저장된 SpecCard 목록 — 그리드 표시.
/// Settings 또는 Collection 에서 진입.
struct SpecCardListView: View {
    @Query(sort: \SpecCard.createdAt, order: .reverse) private var cards: [SpecCard]
    @State private var picked: SpecCard?

    var body: some View {
        ScrollView {
            if cards.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                    spacing: 12
                ) {
                    ForEach(cards) { card in
                        Button {
                            picked = card
                        } label: {
                            cardTile(card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "speccard.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picked) { card in
            SpecCardView(card: card)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.accent.opacity(0.5))
            Text(String(localized: "speccard.list.empty"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "speccard.list.empty.hint"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity)
    }

    private func cardTile(_ card: SpecCard) -> some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [AppColors.primaryDeep, AppColors.primary700],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                if let watch = card.watch {
                    if let img = PhotoCache.image(for: watch.id, data: watch.photoData) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        WatchSilhouette(watch: watch, size: 100)
                    }
                }
                if card.audioPath != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.accent)
                                .padding(6)
                                .background(.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                    .lineLimit(1)
                if !card.movement.isEmpty {
                    Text(card.movement)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.horizontal, 4)
        }
    }
}
