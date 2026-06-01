import Foundation

/// 큐레이션 YouTube 영상 피드 — 운영자가 등록한 채널(curated_channels)의 신규 영상을
/// 각 채널 공개 RSS(Atom)로 직접 수집·병합. API 키·할당량 불필요. 재생은 YouTube 앱/사파리.
/// 측정 데이터(A영역)와 무관한 B영역. youtube.com 직접 호출이라 CommunityService(Supabase) 와 분리.
@MainActor
final class YouTubeFeedService: ObservableObject {
    static let shared = YouTubeFeedService()

    @Published var videos: [YouTubeVideo] = []
    @Published var isLoading = false

    private var lastFetchAt: Date?
    private let cacheDuration: TimeInterval = 20 * 60   // 20분 캐시

    struct YouTubeVideo: Identifiable {
        let id: String              // videoId
        let title: String
        let channelTitle: String
        let publishedAt: Date
        let thumbnailURL: URL?
        var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
    }

    /// 사용자 언어 채널을 불러와 RSS 병합. 비면 en 폴백.
    func load(force: Bool = false) async {
        if !force, let last = lastFetchAt,
           Date().timeIntervalSince(last) < cacheDuration, !videos.isEmpty { return }
        isLoading = true
        defer { isLoading = false }

        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        var channels = await CommunityService.shared.fetchCuratedChannels(locale: lang)
        if channels.isEmpty, lang != "en" {
            channels = await CommunityService.shared.fetchCuratedChannels(locale: "en")
        }
        let active = channels.filter { $0.active }.sorted { $0.sortOrder < $1.sortOrder }
        guard !active.isEmpty else { videos = []; lastFetchAt = Date(); return }

        var all: [YouTubeVideo] = []
        await withTaskGroup(of: [YouTubeVideo].self) { group in
            for ch in active {
                let cid = ch.channelID, title = ch.title
                group.addTask { await Self.fetchChannelRSS(channelID: cid, channelTitle: title) }
            }
            for await items in group { all.append(contentsOf: items) }
        }
        videos = all
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(60)
            .map { $0 }
        lastFetchAt = Date()
    }

    /// 입력(UCxxxx · @handle · 채널 URL)을 RSS용 channel_id(UCxxxx)로 해석. 실패 시 nil.
    /// 핸들/URL은 공개 채널 페이지 HTML에서 channelId 추출(API 키 불필요). 운영자 1회 입력용.
    nonisolated static func resolveChannelID(from raw: String) async -> String? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        // 이미 UCxxxx
        if input.range(of: "^UC[A-Za-z0-9_-]{20,}$", options: .regularExpression) != nil {
            return input
        }
        // URL/핸들 → 채널 페이지
        let pageURLString: String
        if input.hasPrefix("http") {
            pageURLString = input
        } else if input.hasPrefix("@") {
            pageURLString = "https://www.youtube.com/\(input)"
        } else {
            pageURLString = "https://www.youtube.com/@\(input)"
        }
        guard let url = URL(string: pageURLString) else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        // "channelId":"UC..." 또는 canonical .../channel/UC...
        for pattern in ["\"channelId\":\"UC[A-Za-z0-9_-]+\"", "channel/UC[A-Za-z0-9_-]+"] {
            if let r = html.range(of: pattern, options: .regularExpression) {
                if let idRange = html[r].range(of: "UC[A-Za-z0-9_-]+", options: .regularExpression) {
                    return String(html[r][idRange])
                }
            }
        }
        return nil
    }

    /// 채널 RSS 1건 수집(Atom). 실패하면 빈 배열(다른 채널은 계속).
    nonisolated static func fetchChannelRSS(channelID: String, channelTitle: String) async -> [YouTubeVideo] {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
        let parser = YouTubeRSSParser(data: data, fallbackChannel: channelTitle)
        parser.parse()
        return parser.videos
    }
}

// MARK: - Atom RSS 파서 (YouTube feeds/videos.xml)

private final class YouTubeRSSParser: NSObject, XMLParserDelegate {
    private(set) var videos: [YouTubeFeedService.YouTubeVideo] = []
    private let data: Data
    private let fallbackChannel: String

    private var inEntry = false
    private var inAuthor = false
    private var element = ""
    private var videoID = ""
    private var title = ""
    private var published = ""
    private var channelName = ""
    private var thumbnail = ""

    private let iso = ISO8601DateFormatter()

    init(data: Data, fallbackChannel: String) {
        self.data = data
        self.fallbackChannel = fallbackChannel
    }

    func parse() {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        element = elementName
        switch elementName {
        case "entry":
            inEntry = true
            videoID = ""; title = ""; published = ""; channelName = ""; thumbnail = ""
        case "author":
            inAuthor = true
        case "media:thumbnail":
            if inEntry, thumbnail.isEmpty, let u = attributeDict["url"] { thumbnail = u }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        switch element {
        case "yt:videoId": videoID += string
        case "title":      title += string
        case "published":  published += string
        case "name":       if inAuthor { channelName += string }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "author":
            inAuthor = false
        case "entry":
            let vid = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !vid.isEmpty, !t.isEmpty {
                let date = iso.date(from: published.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .distantPast
                let thumb = thumbnail.isEmpty
                    ? "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg" : thumbnail
                let ch = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
                videos.append(.init(
                    id: vid, title: t,
                    channelTitle: ch.isEmpty ? fallbackChannel : ch,
                    publishedAt: date,
                    thumbnailURL: URL(string: thumb)
                ))
            }
            inEntry = false
        default:
            break
        }
        element = ""
    }
}
