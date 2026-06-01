import Foundation
import UIKit

/// 커뮤니티 익명 사진 피드 — Supabase REST/Storage/Auth 클라이언트.
/// 익명 표시지만 검열·차단·소유권을 위해 Supabase **Anonymous Auth** 의 안정 uid 보유.
/// `docs/community/schema.sql` / `docs/community/PLAN.md` 대응. 백엔드 미배포 시 호출은 무해히 실패.
/// 기존 `SupabaseBrandLeagueService` REST 패턴을 따른다.
@MainActor
final class CommunityService: ObservableObject {
    static let shared = CommunityService()
    private init() {
        accessToken = defaults.string(forKey: Keys.token)
        refreshToken = defaults.string(forKey: Keys.refresh)
        myUID = defaults.string(forKey: Keys.uid)
        if let arr = defaults.array(forKey: Keys.liked) as? [String] { likedPostIDs = Set(arr) }
        if let arr = defaults.array(forKey: Keys.blocked) as? [String] { blockedUIDs = Set(arr) }
        if let arr = defaults.array(forKey: Keys.followed) as? [String] { followedUIDs = Set(arr) }
        if let arr = defaults.array(forKey: Keys.bookmarked) as? [String] { bookmarkedPostIDs = Set(arr) }
    }

    private let baseURL = Secrets.supabaseURL
    private let anonKey = Secrets.supabaseAnonKey
    private let defaults = UserDefaults.standard

    // MARK: - Published state
    @Published private(set) var feed: [Community.Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var likedPostIDs: Set<String> = []
    @Published private(set) var blockedUIDs: Set<String> = []
    @Published private(set) var followedUIDs: Set<String> = []
    @Published private(set) var bookmarkedPostIDs: Set<String> = []
    /// 저장(스크랩) 탭에 보여줄 게시물 — loadSavedPosts() 로 채움.
    @Published private(set) var savedFeed: [Community.Post] = []

    private(set) var myUID: String?
    private var accessToken: String?
    private var refreshToken: String?

    private enum Keys {
        static let token = "ticklab.community.token"
        static let refresh = "ticklab.community.refresh"
        static let uid = "ticklab.community.uid"
        static let eula = "ticklab.community.eulaAccepted"
        static let viewerTerms = "ticklab.community.viewerTermsAccepted"
        static let lastPost = "ticklab.community.lastPostDate"
        static let liked = "ticklab.community.likedIDs"
        static let blocked = "ticklab.community.blockedUIDs"
        static let followed = "ticklab.community.followedUIDs"
        static let bookmarked = "ticklab.community.bookmarkedIDs"
        static let notifSeen = "ticklab.community.notifSeenAt"
    }

    // MARK: - EULA (UGC 의무 — zero tolerance 동의)
    /// 게시(post) 동의.
    var hasAcceptedEULA: Bool { defaults.bool(forKey: Keys.eula) }
    func acceptEULA() { defaults.set(true, forKey: Keys.eula) }
    /// 뷰어(소비) 동의 — App Store 1.2: UGC를 *보는* 사용자도 약관·신고 동의 필요(Round 3).
    /// 동의 전엔 피드 로드/익명가입을 하지 않는다.
    var hasAcceptedViewerTerms: Bool { defaults.bool(forKey: Keys.viewerTerms) }
    func acceptViewerTerms() { defaults.set(true, forKey: Keys.viewerTerms) }

    // MARK: - 하루 1장 (서버 트리거가 강제, 클라는 사전 가드 + UX)
    var canPostToday: Bool {
        #if DEBUG
        return true   // 개발/테스트 빌드: 하루 1장 제한 해제 (서버 trg_daily_limit 도 임시 drop 필요)
        #else
        guard let last = defaults.object(forKey: Keys.lastPost) as? Date else { return true }
        return !Calendar.current.isDateInToday(last)
        #endif
    }
    private func markPostedToday() { defaults.set(Date(), forKey: Keys.lastPost) }

    // MARK: - Anonymous auth

    /// 세션 유지 보장 — **기존 세션이 있으면** 만료 시 refresh. 세션이 없으면 아무것도 안 함.
    /// 신원 전환(Apple 전용): 더 이상 자동 익명 가입하지 않는다. 로그인은 UI 게이트가 유도.
    /// (만료 토큰 재사용 → 403 "exp claim" 버그는 refresh 로 방지.)
    func ensureSignedIn() async {
        guard let token = accessToken, myUID != nil else { return }
        if Self.isJWTExpired(token) { _ = await refreshSession() }
    }

    private func signInAnonymously() async {
        // Supabase Anonymous Sign-in (gotrue). 콘솔에서 Anonymous 활성화 필요.
        // NOTE(배포검증): gotrue 버전에 따라 엔드포인트 차이 가능 — /auth/v1/signup (빈 바디).
        guard let url = URL(string: "\(baseURL)/auth/v1/signup") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = "{}".data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if !applyAuth(data) { lastError = "익명 가입 응답 파싱 실패" }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// refresh_token 으로 access_token 갱신(같은 익명 uid 유지). 성공 시 true.
    private func refreshSession() async -> Bool {
        guard let rt = refreshToken,
              let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=refresh_token") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return false }
            return applyAuth(data)
        } catch { return false }
    }

    /// gotrue 응답(access/refresh/user) 캐시 적용. 성공 시 true.
    @discardableResult
    private func applyAuth(_ data: Data) -> Bool {
        struct AuthResp: Decodable {
            let access_token: String?
            let refresh_token: String?
            struct User: Decodable { let id: String }
            let user: User?
        }
        guard let resp = try? JSONDecoder().decode(AuthResp.self, from: data),
              let token = resp.access_token, let uid = resp.user?.id else { return false }
        accessToken = token
        refreshToken = resp.refresh_token
        myUID = uid
        defaults.set(token, forKey: Keys.token)
        defaults.set(uid, forKey: Keys.uid)
        if let rt = resp.refresh_token { defaults.set(rt, forKey: Keys.refresh) }
        return true
    }

    /// JWT `exp` 가 지났는지(60s 버퍼). 디코드 실패 시 만료로 간주(안전 측).
    static func isJWTExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return true }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? Double else { return true }
        return Date().timeIntervalSince1970 >= (exp - 60)
    }

    /// JWT payload 디코드(base64url). 실패 시 nil.
    static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 익명 세션 여부(`is_anonymous` 클레임). 신원 전환 후 익명 토큰은 비로그인 취급.
    static func isAnonymousJWT(_ jwt: String) -> Bool {
        (decodeJWTPayload(jwt)?["is_anonymous"] as? Bool) ?? false
    }

    // MARK: - Sign in with Apple (신원 전환: 익명 → 공개 프로필)

    /// 진짜 로그인(Apple) 세션 보유 여부. **익명 세션(is_anonymous)은 비로그인 취급** —
    /// 신원 전환 전 캐시된 익명 토큰이 게이트를 우회하던 버그 방지.
    var isSignedIn: Bool {
        guard let token = accessToken, myUID != nil else { return false }
        return !Self.isAnonymousJWT(token)
    }

    /// 네이티브 Sign in with Apple 의 identity token 을 Supabase 와 교환(영구 계정·같은 uid 유지).
    /// 콘솔에서 Apple provider 활성화 필요. 성공 시 true.
    func signInWithApple(idToken: String, rawNonce: String) async -> Bool {
        lastError = nil
        guard let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=id_token") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "provider": "apple", "id_token": idToken, "nonce": rawNonce
        ])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                lastError = "apple signin \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")"
                return false
            }
            return applyAuth(data)
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// 로그아웃 — 세션 토큰 폐기. (게시물 소유권은 서버 uid 기준이라 재로그인 시 복원.)
    func signOut() {
        accessToken = nil
        refreshToken = nil
        myUID = nil
        defaults.removeObject(forKey: Keys.token)
        defaults.removeObject(forKey: Keys.refresh)
        defaults.removeObject(forKey: Keys.uid)
    }

    /// 인증 헤더 부착 (세션 토큰 우선, 없으면 anon 키).
    private func authedRequest(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    // MARK: - Feed

    func loadFeed() async {
        await ensureSignedIn()
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        let query = "select=*&status=eq.approved&order=created_at.desc&limit=60"
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?\(query)") else { return }
        let req = authedRequest(url, method: "GET")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let posts = try Self.decoder.decode([Community.Post].self, from: data)
            // 자기차단 자동 해제(과거 버그 자가치유) — 본인 uid 가 차단목록에 있으면 본인 글이 사라짐.
            if let uid = myUID, blockedUIDs.contains(uid) {
                blockedUIDs.remove(uid)
                defaults.set(Array(blockedUIDs), forKey: Keys.blocked)
            }
            // 차단한 작성자 제외.
            feed = posts.filter { !blockedUIDs.contains($0.authorUID) }
        } catch {
            lastError = error.localizedDescription
        }
        await heartbeat()
    }

    // MARK: - Like (멱등 — PK(post_id, uid))

    func isLiked(_ post: Community.Post) -> Bool { likedPostIDs.contains(post.id) }

    func toggleLike(_ post: Community.Post) async {
        await ensureSignedIn()
        let liked = likedPostIDs.contains(post.id)
        // 낙관적 UI.
        if liked {
            likedPostIDs.remove(post.id)
            adjustLocalLike(post.id, delta: -1)
        } else {
            likedPostIDs.insert(post.id)
            adjustLocalLike(post.id, delta: +1)
        }
        persistLiked()

        if liked {
            // DELETE /community_likes?post_id=eq.&uid=eq.
            guard let uid = myUID,
                  let url = URL(string: "\(baseURL)/rest/v1/community_likes?post_id=eq.\(post.id)&uid=eq.\(uid)") else { return }
            _ = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE"))
        } else {
            guard let url = URL(string: "\(baseURL)/rest/v1/community_likes") else { return }
            var req = authedRequest(url, method: "POST")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["post_id": post.id])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func adjustLocalLike(_ id: String, delta: Int) {
        guard let idx = feed.firstIndex(where: { $0.id == id }) else { return }
        feed[idx].likeCount = max(0, feed[idx].likeCount + delta)
    }
    private func persistLiked() { defaults.set(Array(likedPostIDs), forKey: Keys.liked) }

    // MARK: - Report / Block (UGC 의무)

    func report(_ post: Community.Post, reason: Community.ReportReason) async {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_reports") else { return }
        var req = authedRequest(url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "post_id": post.id, "reason": reason.rawValue
        ])
        _ = try? await URLSession.shared.data(for: req)
        // 신고해도 글은 계속 표시(사용자 요청). 안 보이게 하려면 차단(block), 다수 신고 시 서버 트리거가 자동 숨김.
    }

    func block(authorOf post: Community.Post) async {
        await ensureSignedIn()
        guard post.authorUID != myUID else { return }   // 본인은 차단 불가(자기차단 시 본인 글이 피드에서 사라짐)
        blockedUIDs.insert(post.authorUID)
        defaults.set(Array(blockedUIDs), forKey: Keys.blocked)
        feed.removeAll { $0.authorUID == post.authorUID }
        guard let url = URL(string: "\(baseURL)/rest/v1/community_blocks") else { return }
        var req = authedRequest(url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["blocked_uid": post.authorUID])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// 차단 해제 — 로컬 목록·서버(community_blocks)에서 제거 후 피드 재로딩(해제한 작성자 글 복귀).
    func unblock(_ uid: String) async {
        await ensureSignedIn()
        blockedUIDs.remove(uid)
        defaults.set(Array(blockedUIDs), forKey: Keys.blocked)
        if let url = URL(string: "\(baseURL)/rest/v1/community_blocks?blocked_uid=eq.\(uid)") {
            _ = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE"))
        }
        await loadFeed()
    }

    // MARK: - Activity Notifications (인앱 — 내 글 좋아요 · 새 팔로워)

    /// 마지막으로 알림을 확인한 시각. 미확인 판정 기준.
    var lastNotifSeen: Date { (defaults.object(forKey: Keys.notifSeen) as? Date) ?? .distantPast }
    /// 종 아이콘 탭(알림 열람) 시 호출 — 현재 시각으로 갱신해 배지 클리어.
    func markNotificationsSeen() { defaults.set(Date(), forKey: Keys.notifSeen) }

    /// 내 게시물 좋아요(본인 제외) + 새 팔로워 이벤트를 최신순으로. 댓글은 미구현이라 제외.
    func fetchNotifications() async -> [Community.Notice] {
        await ensureSignedIn()
        guard let uid = myUID else { return [] }
        var events: [Community.Notice] = []
        // 1) 내 게시물 id·썸네일 경로
        struct PostRow: Decodable { let id: String; let image_path: String? }
        var pathByID: [String: String?] = [:]
        if let url = URL(string: "\(baseURL)/rest/v1/community_posts?select=id,image_path&author_uid=eq.\(uid)"),
           let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
           let rows = try? Self.decoder.decode([PostRow].self, from: data) {
            for r in rows { pathByID[r.id] = r.image_path }
        }
        // 2) 내 글 좋아요(본인 제외)
        if !pathByID.isEmpty {
            let ids = Array(pathByID.keys).joined(separator: ",")
            struct LikeRow: Decodable { let post_id: String; let created_at: Date }
            if let url = URL(string: "\(baseURL)/rest/v1/community_likes?select=post_id,created_at&post_id=in.(\(ids))&uid=neq.\(uid)&order=created_at.desc&limit=50"),
               let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
               let rows = try? Self.decoder.decode([LikeRow].self, from: data) {
                for r in rows {
                    events.append(.init(id: "like-\(r.post_id)-\(Int(r.created_at.timeIntervalSince1970))",
                                        kind: .like, postImagePath: pathByID[r.post_id] ?? nil, createdAt: r.created_at))
                }
            }
        }
        // 3) 새 팔로워
        struct FollowRow: Decodable { let created_at: Date }
        if let url = URL(string: "\(baseURL)/rest/v1/community_follows?select=created_at&followed_uid=eq.\(uid)&order=created_at.desc&limit=50"),
           let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
           let rows = try? Self.decoder.decode([FollowRow].self, from: data) {
            for r in rows {
                events.append(.init(id: "follow-\(Int(r.created_at.timeIntervalSince1970))",
                                    kind: .follow, postImagePath: nil, createdAt: r.created_at))
            }
        }
        return events.sorted { $0.createdAt > $1.createdAt }
    }

    /// 미확인 알림 수(컬렉션 종 배지).
    func unseenNotificationCount() async -> Int {
        let seen = lastNotifSeen
        return (await fetchNotifications()).filter { $0.createdAt > seen }.count
    }

    // MARK: - Follow (신원 전환)

    func isFollowing(_ authorUID: String) -> Bool { followedUIDs.contains(authorUID) }

    /// 작성자 팔로우 토글. 로그인 필요(호출 측 게이트). 본인은 무시.
    func toggleFollow(_ authorUID: String) async {
        guard authorUID != myUID else { return }
        await ensureSignedIn()
        let following = followedUIDs.contains(authorUID)
        if following { followedUIDs.remove(authorUID) } else { followedUIDs.insert(authorUID) }
        defaults.set(Array(followedUIDs), forKey: Keys.followed)
        if following {
            guard let uid = myUID,
                  let url = URL(string: "\(baseURL)/rest/v1/community_follows?follower_uid=eq.\(uid)&followed_uid=eq.\(authorUID)") else { return }
            _ = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE"))
        } else {
            guard let url = URL(string: "\(baseURL)/rest/v1/community_follows") else { return }
            var req = authedRequest(url, method: "POST")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["followed_uid": authorUID])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Bookmark / 스크랩

    func isBookmarked(_ post: Community.Post) -> Bool { bookmarkedPostIDs.contains(post.id) }

    func toggleBookmark(_ post: Community.Post) async {
        await ensureSignedIn()
        let saved = bookmarkedPostIDs.contains(post.id)
        if saved { bookmarkedPostIDs.remove(post.id) } else { bookmarkedPostIDs.insert(post.id) }
        defaults.set(Array(bookmarkedPostIDs), forKey: Keys.bookmarked)
        if saved {
            savedFeed.removeAll { $0.id == post.id }
            guard let uid = myUID,
                  let url = URL(string: "\(baseURL)/rest/v1/community_bookmarks?uid=eq.\(uid)&post_id=eq.\(post.id)") else { return }
            _ = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE"))
        } else {
            guard let url = URL(string: "\(baseURL)/rest/v1/community_bookmarks") else { return }
            var req = authedRequest(url, method: "POST")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["post_id": post.id])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    /// 저장(스크랩)한 게시물 로드 — bookmark id 목록으로 posts in.() 조회.
    func loadSavedPosts() async {
        await ensureSignedIn()
        guard !bookmarkedPostIDs.isEmpty else { savedFeed = []; return }
        let ids = bookmarkedPostIDs.joined(separator: ",")
        let query = "select=*&id=in.(\(ids))&order=created_at.desc"
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?\(query)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(for: authedRequest(url, method: "GET"))
            savedFeed = try Self.decoder.decode([Community.Post].self, from: data)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteMyPost(_ post: Community.Post) async {
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?id=eq.\(post.id)") else { return }
        _ = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE"))
        feed.removeAll { $0.id == post.id }
    }

    // MARK: - Upload (Storage + insert)

    enum UploadError: Error { case notSignedIn, storageFailed, dailyLimit }

    /// 크롭·검열 통과한 JPEG 를 업로드. 성공 시 피드 갱신.
    func uploadPost(imageData: Data, brand: String?, caption: String? = nil) async throws {
        lastError = nil
        guard canPostToday else { throw UploadError.dailyLimit }
        await ensureSignedIn()
        guard let uid = myUID else {
            lastError = "익명 로그인 실패 — Supabase Anonymous Sign-in 확인 필요"
            throw UploadError.notSignedIn
        }

        let path = "\(uid)/\(UUID().uuidString).jpg"
        // 1) Storage 업로드.
        guard let storageURL = URL(string: "\(baseURL)/storage/v1/object/community/\(path)") else {
            throw UploadError.storageFailed
        }
        var up = URLRequest(url: storageURL)
        up.httpMethod = "POST"
        up.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        up.setValue(anonKey, forHTTPHeaderField: "apikey")
        up.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        // upload(for:from:) 가 body 를 from: 으로 보냄 — httpBody 중복 설정 제거.
        let (upData, resp) = try await URLSession.shared.upload(for: up, from: imageData)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            lastError = "storage \(http.statusCode): \(String(data: upData, encoding: .utf8) ?? "")"
            throw UploadError.storageFailed
        }
        // 2) posts insert (author_uid 는 서버 default auth.uid()).
        guard let insertURL = URL(string: "\(baseURL)/rest/v1/community_posts") else {
            throw UploadError.storageFailed
        }
        var ins = authedRequest(insertURL, method: "POST")
        ins.setValue("return=representation", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = ["image_path": path]
        if let brand, !brand.isEmpty { body["brand"] = brand }
        // 작성자 표시명(공개 프로필). 운영 ID(관리자) 활성 시 "TickLab" 으로 고정 게시.
        // ⚠️ 클라이언트 표시/편의용 — 위조 방지는 서버 RLS(admin_users)로 "TickLab" 사용을
        //    admin uid 로 제한해야 함. docs/community/admin_rls.sql 참고.
        if defaults.bool(forKey: "ticklab.admin.actingAsTickLab") {
            body["author_name"] = "TickLab"
        } else {
            let authorName = (defaults.string(forKey: "ticklab.profile.name") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            body["author_name"] = authorName.isEmpty ? "Collector" : authorName
        }
        if let caption {
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { body["caption"] = String(trimmed.prefix(CommunityTextModerator.maxLength)) }
        }
        ins.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (insData, insResp) = try await URLSession.shared.data(for: ins)
        // 서버 거절(하루1장 트리거·RLS·미존재 컬럼 등)을 더 이상 조용히 삼키지 않는다.
        if let http = insResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: insData, encoding: .utf8) ?? ""
            lastError = "insert \(http.statusCode): \(msg)"
            if msg.contains("daily_post_limit") { throw UploadError.dailyLimit }
            throw UploadError.storageFailed
        }
        markPostedToday()
        await loadFeed()
    }

    // MARK: - 운영 대시보드 (관리자)

    /// presence 하트비트 — 커뮤니티 활동 시 community_presence(uid PK) UPSERT.
    /// "현재 활동 사용자" 근사치용. (진짜 실시간 동시접속 presence 는 Realtime 필요 — 활동 기반 근사)
    func heartbeat() async {
        await ensureSignedIn()
        guard let uid = myUID, let url = URL(string: "\(baseURL)/rest/v1/community_presence") else { return }
        var req = authedRequest(url, method: "POST")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        let nowISO = ISO8601DateFormatter().string(from: Date())
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["uid": uid, "last_seen": nowISO])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// 운영 통계. 전체/오늘 게시물은 public 읽기로 동작, 활동 사용자는 presence 테이블 필요.
    func fetchOpsStats() async -> Community.OpsStats {
        await ensureSignedIn()
        let todayISO = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        let activeCutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))
        async let total = countRows(table: "community_posts", selectCol: "id", filter: "status=eq.approved")
        async let today = countRows(table: "community_posts", selectCol: "id",
                                    filter: "status=eq.approved&created_at=gte.\(todayISO)")
        async let active = countRows(table: "community_presence", selectCol: "uid",
                                     filter: "last_seen=gte.\(activeCutoff)")
        return Community.OpsStats(activeUsers: await active, todayPosts: await today, totalPosts: await total)
    }

    /// 신고 목록 (admin SELECT RLS 필요 — 미배포 시 빈 배열).
    func fetchReports() async -> [Community.AdminReport] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_reports?select=post_id,reason,created_at&order=created_at.desc&limit=200") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let reports = try? Self.decoder.decode([Community.AdminReport].self, from: data) else { return [] }
        return reports
    }

    /// 신고된 게시물 본문 조회 (admin SELECT RLS 필요 — 숨김/차단 글 포함해 확인).
    func fetchReportedPosts(ids: [String]) async -> [Community.Post] {
        await ensureSignedIn()
        guard !ids.isEmpty,
              let url = URL(string: "\(baseURL)/rest/v1/community_posts?select=*&id=in.(\(ids.joined(separator: ",")))") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let posts = try? Self.decoder.decode([Community.Post].self, from: data) else { return [] }
        return posts
    }

    /// 신고 총 건수 (admin RLS 필요 — 미배포 시 0). 관리자 배지 알림용.
    func fetchReportCount() async -> Int {
        await ensureSignedIn()
        return await countRows(table: "community_reports", selectCol: "id", filter: "")
    }

    // MARK: - 공지 / 경고 (관리자)

    /// 공지 발송 (admin insert RLS 필요). 노출 기간 starts~ends.
    @discardableResult
    func postAnnouncement(body: String, startsAt: Date, endsAt: Date) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_announcements") else { return false }
        var req = authedRequest(url, method: "POST")
        let iso = ISO8601DateFormatter()
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "body": body, "starts_at": iso.string(from: startsAt), "ends_at": iso.string(from: endsAt), "active": true
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 공지 수정 (기간·내용·활성). admin update RLS.
    @discardableResult
    func updateAnnouncement(id: String, body: String, startsAt: Date, endsAt: Date, active: Bool) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_announcements?id=eq.\(id)") else { return false }
        var req = authedRequest(url, method: "PATCH")
        let iso = ISO8601DateFormatter()
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "body": body, "starts_at": iso.string(from: startsAt), "ends_at": iso.string(from: endsAt), "active": active
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 공지 삭제 (admin DELETE RLS 필요).
    @discardableResult
    func deleteAnnouncement(id: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_announcements?id=eq.\(id)") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE")),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 공지 전체 목록 (admin — 편집용).
    func fetchAnnouncements() async -> [Community.Announcement] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_announcements?select=*&order=created_at.desc&limit=50") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Announcement].self, from: data) else { return [] }
        return arr
    }

    /// 현재 노출할 활성 공지 1건 (active + 기간 내). 모든 사용자.
    func fetchActiveAnnouncement() async -> Community.Announcement? {
        await ensureSignedIn()
        let nowISO = ISO8601DateFormatter().string(from: Date())
        guard let url = URL(string: "\(baseURL)/rest/v1/community_announcements?select=*&active=eq.true&starts_at=lte.\(nowISO)&ends_at=gte.\(nowISO)&order=created_at.desc&limit=1") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Announcement].self, from: data) else { return nil }
        return arr.first
    }

    /// 특정 사용자에게 경고 발송 (admin insert RLS 필요).
    @discardableResult
    func sendWarning(toUID uid: String, message: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_warnings") else { return false }
        var req = authedRequest(url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["target_uid": uid, "message": message])
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 내 미확인 경고 (본인 select RLS).
    func fetchMyWarnings() async -> [Community.Warning] {
        await ensureSignedIn()
        guard let uid = myUID,
              let url = URL(string: "\(baseURL)/rest/v1/community_warnings?select=*&target_uid=eq.\(uid)&seen=eq.false&order=created_at.desc") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Warning].self, from: data) else { return [] }
        return arr
    }

    /// 경고 확인 처리(seen=true).
    func markWarningsSeen(_ ids: [String]) async {
        await ensureSignedIn()
        for id in ids {
            guard let url = URL(string: "\(baseURL)/rest/v1/community_warnings?id=eq.\(id)") else { continue }
            var req = authedRequest(url, method: "PATCH")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["seen": true])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    /// 게시물 숨김 (admin UPDATE RLS 필요).
    @discardableResult
    func adminHidePost(_ postID: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?id=eq.\(postID)") else { return false }
        var req = authedRequest(url, method: "PATCH")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "hidden"])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 게시물 영구 삭제 (admin DELETE RLS 필요). 로컬 피드에서도 제거.
    @discardableResult
    func adminDeletePost(_ post: Community.Post) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?id=eq.\(post.id)") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE")),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
        feed.removeAll { $0.id == post.id }
        return true
    }

    /// PostgREST count=exact → Content-Range 헤더의 total 파싱.
    private func countRows(table: String, selectCol: String, filter: String) async -> Int {
        guard let url = URL(string: "\(baseURL)/rest/v1/\(table)?select=\(selectCol)&limit=1&\(filter)") else { return 0 }
        var req = authedRequest(url, method: "GET")
        req.setValue("count=exact", forHTTPHeaderField: "Prefer")
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last.flatMap({ Int($0) }) else { return 0 }
        return total
    }

    // MARK: - Helpers

    /// Storage 공개 URL (approved 사진).
    func imageURL(for path: String) -> URL? {
        URL(string: "\(baseURL)/storage/v1/object/public/community/\(path)")
    }

    /// PostgREST timestamptz 파싱 — 마이크로초/타임존 변형 허용.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = isoFrac.date(from: s) ?? iso.date(from: s) { return date }
            return Date()
        }
        return d
    }()
}
