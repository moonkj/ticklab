import SwiftData
import SwiftUI

/// Sprint 7 (P3-11): 보유 브랜드 뉴스.
struct BrandNewsView: View {
    @Query private var watches: [Watch]
    @StateObject private var service = BrandNewsService.shared
    /// Round 173 (사용자 보고): 최초 로딩 동안 스피너 보장.
    @State private var didFirstLoad = false

    private var myBrands: [String] { Array(Set(watches.map(\.brand))) }

    var body: some View {
        Group {
            if (service.isLoading || !didFirstLoad) && service.articles.isEmpty {
                // 스켈레톤 — 뉴스 행 모양 placeholder + shimmer.
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(0..<6, id: \.self) { _ in ListRowSkeleton(lines: 3) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .disabled(true)
            } else if service.articles.isEmpty {
                EmptyState(
                    icon: "newspaper",
                    title: String(localized: "news.empty.title"),
                    message: String(localized: "news.empty.body")
                )
            } else {
                List(service.articles) { article in
                    newsRow(article)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(String(localized: "news.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.paper0.ignoresSafeArea())
        .toolbarBackground(AppColors.paper0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await service.fetchNews(for: myBrands)
            didFirstLoad = true
        }
        .refreshable {
            await service.fetchNews(for: myBrands)
        }
    }

    private func newsRow(_ article: BrandNewsService.NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(article.sourceName)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(AppColors.accentDark)
                if let date = article.publishedAt {
                    Text("·").foregroundStyle(AppColors.ink3)
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.ink3)
                }
            }
            Text(article.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
                .lineLimit(3)
            if let url = article.link {
                Link(String(localized: "news.read_more"), destination: url)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.info)
            }
        }
        .padding(.vertical, 8)
    }
}
