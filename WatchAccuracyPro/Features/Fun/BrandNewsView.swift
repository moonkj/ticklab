import SwiftData
import SwiftUI

/// Sprint 7 (P3-11): 보유 브랜드 뉴스.
struct BrandNewsView: View {
    @Query private var watches: [Watch]
    @StateObject private var service = BrandNewsService.shared

    private var myBrands: [String] { Array(Set(watches.map(\.brand))) }

    var body: some View {
        Group {
            if service.isLoading && service.articles.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
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
        .task {
            await service.fetchNews(for: myBrands)
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
