import XCTest
@testable import WatchAccuracyPro

/// YouTube 영상 피드 — 비디오 URL 파생값 + 채널ID 해석(UCxxxx 패스스루). 네트워크 없음.
final class YouTubeFeedTests: XCTestCase {

    func test_video_urls() {
        let v = YouTubeFeedService.YouTubeVideo(
            id: "abc123XYZ", title: "리뷰", channelTitle: "WatchTV",
            publishedAt: Date(), thumbnailURL: nil)
        XCTAssertEqual(v.watchURL?.absoluteString, "https://www.youtube.com/watch?v=abc123XYZ")
        XCTAssertEqual(v.thumbnailHigh?.absoluteString, "https://i.ytimg.com/vi/abc123XYZ/maxresdefault.jpg")
        XCTAssertEqual(v.thumbnailMid?.absoluteString, "https://i.ytimg.com/vi/abc123XYZ/mqdefault.jpg")
        XCTAssertEqual(v.id, "abc123XYZ")
    }

    func test_resolve_channel_id_passthrough() async {
        // 이미 UCxxxx(UC + 20자 이상)면 네트워크 없이 그대로 반환.
        let id = "UCabcdefghij1234567890"
        let resolved = await YouTubeFeedService.resolveChannelID(from: id)
        XCTAssertEqual(resolved, id)
    }

    func test_resolve_channel_id_empty_returns_nil() async {
        let resolved = await YouTubeFeedService.resolveChannelID(from: "   ")
        XCTAssertNil(resolved)
    }
}
