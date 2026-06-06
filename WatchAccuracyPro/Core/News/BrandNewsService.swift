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

        // 빠른 로딩: RSS 피드들을 **병렬**로 받고, **도착하는 대로** 화면 갱신(첫 피드 오면 바로 보임,
        //   나머지는 이어서 채워짐). 이전엔 모든 피드를 순차로 다 받은 뒤에야 표시 → 매우 느렸음.
        var all: [NewsArticle] = []
        await withTaskGroup(of: [NewsArticle].self) { group in
            for source in rssSources {
                guard let url = URL(string: source.url) else { continue }
                group.addTask { await self.fetchRSS(url: url, sourceName: source.name) }
            }
            for await items in group {
                all.append(contentsOf: items)
                articles = Self.curate(all)   // 도착할 때마다 필터·정렬·상위 20개 갱신
            }
        }
        lastFetchAt = Date()
    }

    /// 시계 관련 기사만 필터 → 날짜 역순 정렬 → 상위 20개. (점진 표시에서 매 피드 도착 시 재적용.)
    private static func curate(_ all: [NewsArticle]) -> [NewsArticle] {
        let watchKeywords = ["watch", "timepiece", "chronograph", "movement", "caliber",
                             "rolex", "omega", "seiko", "iwc", "patek", "audemars",
                             "tudor", "breitling", "tag heuer", "longines", "tissot",
                             "hamilton", "cartier", "jaeger", "panerai", "nomos",
                             "grand seiko", "zenith", "oris", "hublot", "strap",
                             "caseback", "dial", "bezel", "tourbillon", "mechanical",
                             "automatic", "quartz", "luxury"]
        return all
            .filter { article in
                let title = article.title.lowercased()
                return watchKeywords.contains { title.contains($0) }
            }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            .prefix(20)
            .map { $0 }
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
