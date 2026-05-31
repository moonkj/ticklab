import Foundation

/// Sprint 7 (P3-11): 보유 브랜드 뉴스 — RSS 파서.
/// 무료 공개 RSS 피드 사용 (외부 API 키 불필요).
/// 결과는 브랜드 키워드 필터링 후 최신 10개 반환.
@MainActor
final class BrandNewsService: ObservableObject {
    static let shared = BrandNewsService()

    @Published var articles: [NewsArticle] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private var lastFetchAt: Date?
    private let cacheDuration: TimeInterval = 30 * 60  // 30분 캐시

    struct NewsArticle: Identifiable {
        let id = UUID()
        let title: String
        let link: URL?
        let publishedAt: Date?
        let sourceName: String
    }

    // 시계 전문 RSS 피드 (공개 무료, 2026년 5월 검증)
    private let rssSources: [(name: String, url: String)] = [
        ("Monochrome", "https://monochrome-watches.com/feed"),
        ("aBlogtoWatch", "https://www.ablogtowatch.com/feed/"),
        ("WatchPro", "https://www.watchpro.com/feed/"),
    ]

    func fetchNews(for brands: [String] = []) async {
        // 캐시 유효하면 재사용 (기사가 있고 30분 이내)
        if let last = lastFetchAt,
           Date().timeIntervalSince(last) < cacheDuration,
           !articles.isEmpty { return }
        articles = []  // 리셋 후 새로 fetch

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        var all: [NewsArticle] = []
        for source in rssSources {
            guard let url = URL(string: source.url) else { continue }
            let items = await fetchRSS(url: url, sourceName: source.name)
            all.append(contentsOf: items)
        }

        // 시계 관련 기사만 표시 — 브랜드 매칭 없이 전체 시계 뉴스
        let watchKeywords = ["watch", "timepiece", "chronograph", "movement", "caliber",
                             "rolex", "omega", "seiko", "iwc", "patek", "audemars",
                             "tudor", "breitling", "tag heuer", "longines", "tissot",
                             "hamilton", "cartier", "jaeger", "panerai", "nomos",
                             "grand seiko", "zenith", "oris", "hublot", "strap",
                             "caseback", "dial", "bezel", "tourbillon", "mechanical",
                             "automatic", "quartz", "luxury"]
        let filtered = all.filter { article in
            let title = article.title.lowercased()
            return watchKeywords.contains { title.contains($0) }
        }

        // 날짜 역순 정렬, 최대 20개
        articles = filtered
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(20)
            .map { $0 }

        lastFetchAt = Date()
    }

    private func fetchRSS(url: URL, sourceName: String) async -> [NewsArticle] {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return parseRSS(data: data, sourceName: sourceName)
    }

    private func parseRSS(data: Data, sourceName: String) -> [NewsArticle] {
        let parser = RSSParser(data: data, sourceName: sourceName)
        parser.parse()
        return parser.articles
    }
}

// MARK: - RSS XML Parser

private final class RSSParser: NSObject, XMLParserDelegate {
    var articles: [BrandNewsService.NewsArticle] = []
    private let data: Data
    private let sourceName: String

    private var currentTitle = ""
    private var currentLink = ""
    private var currentDate = ""
    private var isInItem = false
    private var currentElement = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    init(data: Data, sourceName: String) {
        self.data = data; self.sourceName = sourceName
    }

    func parse() {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            isInItem = true; currentTitle = ""; currentLink = ""; currentDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link":  currentLink  += string
        case "pubDate": currentDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" {
            let url = URL(string: currentLink.trimmingCharacters(in: .whitespaces))
            let date = dateFormatter.date(from: currentDate.trimmingCharacters(in: .whitespaces))
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                articles.append(BrandNewsService.NewsArticle(
                    title: title, link: url, publishedAt: date, sourceName: sourceName
                ))
            }
            isInItem = false
        }
    }
}
