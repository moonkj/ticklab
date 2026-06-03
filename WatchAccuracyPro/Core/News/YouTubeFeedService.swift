import Foundation

/// 큐레이션 YouTube 영상 피드.
/// 영상 소스: Supabase Edge Function(youtube-videos) — 서버가 curated_channels 를 YouTube Data API v3 로
/// 조회하고 30분 캐시한 결과를 반환. (YouTube 가 공개 RSS feeds/videos.xml 을 차단해 2026-06-03 전환.)
/// 측정 데이터(A영역)와 무관한 B영역. 재생은 YouTube 앱/사파리.
@MainActor
final class YouTubeFeedService: ObservableObject {
    static let shared = YouTubeFeedService()

    @Published var videos: [YouTubeVideo] = []
    @Published var isLoading = false

    private var lastFetchAt: Date?
    private let cacheDuration: TimeInterval = 20 * 60   // 20분 클라 캐시(서버도 30분 캐시)

    struct YouTubeVideo: Identifiable {
        let id: String              // videoId
        let title: String
        let channelTitle: String
        let publishedAt: Date
        let thumbnailURL: URL?      // RSS 기본(미사용) — 폴백용
        var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
        /// 16:9 고화질(없을 수 있음 → mid 폴백). 4:3 잘림 방지.
        var thumbnailHigh: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg") }
        /// 16:9 항상 존재(320x180).
        var thumbnailMid: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }
    }

    /// Edge Function 에서 영상을 불러와 기기 언어 우선 표시(없으면 언어 무관 전체).
    func load(force: Bool = false) async {
        if !force, let last = lastFetchAt,
           Date().timeIntervalSince(last) < cacheDuration, !videos.isEmpty { return }
        isLoading = true
        defer { isLoading = false }

        let fetched = await CommunityService.shared.fetchCuratedVideos()
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        // 기기 언어 영상 우선. 해당 언어가 없으면 전체 노출(큐레이션이 한 언어에 몰려도 보이게).
        let langFiltered = fetched.filter { ($0.locale ?? "") == lang }
        let chosen = langFiltered.isEmpty ? fetched : langFiltered

        videos = chosen
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(60)
            .map { YouTubeVideo(id: $0.id, title: $0.title, channelTitle: $0.channelTitle,
                                publishedAt: $0.publishedAt, thumbnailURL: nil) }
        lastFetchAt = Date()
    }

    /// 입력(UCxxxx · @handle · 채널 URL)을 channel_id(UCxxxx)로 해석. 실패 시 nil.
    /// 핸들/URL은 공개 채널 페이지 HTML에서 channelId 추출(API 키 불필요). 운영자 1회 입력용.
    /// (채널 페이지 자체는 정상 응답 — 차단된 건 RSS feeds 엔드포인트뿐이라 이 경로는 유효.)
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
}
