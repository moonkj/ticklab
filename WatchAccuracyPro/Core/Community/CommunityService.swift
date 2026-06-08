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
            if !applyAuth(data) { lastError = String(localized: "community.error.anon_auth_parse") }
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
            let ok = applyAuth(data)
            // 로그인 = 계정 동기화: 로컬에 프로필이 있으면 이 Apple 계정으로 업로드(편집 내용을 Apple 신원에 고정),
            //   비어있으면(재설치 직후) 서버에서 복원. 익명 세션에서 편집한 프로필이 Apple 로그인 시 유실되는 문제 대응.
            if ok { await syncOrRestoreProfileOnLogin() }
            return ok
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
        await syncFollowing()
        await heartbeat()
    }

    /// 진행 중인 팔로우 토글 쓰기 수 — >0 이면 syncFollowing 이 덮어쓰지 않음(낙관적 상태 클로버 방지).
    private var followWritesInFlight = 0

    /// 내 팔로잉 목록을 서버에서 동기화 — 로컬 followedUIDs 캐시를 최신화.
    /// (재설치·익명 uid 변경·교차 기기 후 팔로잉 목록의 '팔로잉' 체크표시가 빠지던 문제 해소.)
    func syncFollowing() async {
        await ensureSignedIn()
        // 토글 POST/DELETE 가 아직 서버에 반영 안 됐을 때 syncFollowing 이 옛 서버상태로 덮어써
        //   방금 누른 팔로우가 되돌아가는 race 방지 — 진행 중이면 동기화 스킵.
        guard followWritesInFlight == 0 else { return }
        guard let uid = myUID,
              let url = URL(string: "\(baseURL)/rest/v1/community_follows?select=followed_uid&follower_uid=eq.\(uid)&limit=1000"),
              let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let serverFollows = Set(rows.compactMap { $0["followed_uid"] as? String })
        followedUIDs = serverFollows
        defaults.set(Array(serverFollows), forKey: Keys.followed)
    }

    /// 특정 브랜드 게시물만 — 브랜드 칩 탭 시(같은 브랜드 모아보기). 차단 작성자 제외.
    /// 화이트리스트(내 컬렉션 브랜드)에서만 태깅되므로 입력은 안전한 메타 수준.
    func fetchPostsByBrand(_ brand: String) async -> [Community.Post] {
        await ensureSignedIn()
        let trimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/rest/v1/community_posts?select=*&status=eq.approved&brand=eq.\(enc)&order=created_at.desc&limit=60") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Post].self, from: data) else { return [] }
        return arr.filter { !blockedUIDs.contains($0.authorUID) }
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
            var dict: [String: Any] = ["post_id": post.id]
            if defaults.bool(forKey: "ticklab.admin.actingAsTickLab") {
                dict["author_name"] = "TickLab"
            } else {
                let n = (defaults.string(forKey: "ticklab.profile.name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                dict["author_name"] = n.isEmpty ? "Collector" : n
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: dict)
            _ = try? await URLSession.shared.data(for: req)
            // 좋아요 목록 아바타 — 내 대표사진 경로를 best-effort 로 기록.
            // 별도 PATCH 라 컬럼(author_avatar_path) 미배포여도 좋아요 자체는 안 깨진다(조용히 무시).
            if let uid = myUID,
               let avatarPath = defaults.string(forKey: "ticklab.profile.avatarPath"), !avatarPath.isEmpty,
               !defaults.bool(forKey: "ticklab.admin.actingAsTickLab"),
               let patchURL = URL(string: "\(baseURL)/rest/v1/community_likes?post_id=eq.\(post.id)&uid=eq.\(uid)") {
                var preq = authedRequest(patchURL, method: "PATCH")
                preq.httpBody = try? JSONSerialization.data(withJSONObject: ["author_avatar_path": avatarPath])
                _ = try? await URLSession.shared.data(for: preq)
            }
        }
    }

    /// 특정 작성자의 공개 게시물(프로필 그리드용) — 최신순.
    func fetchPostsByAuthor(uid: String) async -> [Community.Post] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?select=*&author_uid=eq.\(uid)&status=eq.approved&order=created_at.desc&limit=60") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Post].self, from: data) else { return [] }
        return arr
    }

    /// Round 172: 커뮤니티 배지용 내 활동 통계. 내 글 + 받은 좋아요/댓글 합산. (준 좋아요·팔로잉은 로컬에서 별도.)
    func fetchMyStats() async -> Community.MyStats {
        await ensureSignedIn()
        guard let uid = myUID else { return Community.MyStats(postCount: 0, likesReceived: 0, commentsReceived: 0) }
        let posts = await fetchPostsByAuthor(uid: uid)
        let likes = posts.reduce(0) { $0 + $1.likeCount }
        let comments = posts.reduce(0) { $0 + ($1.commentCount ?? 0) }
        // 팔로워(나를 팔로우한 사람) 수 — community_follows 카운트.
        let followers = await countRows(table: "community_follows", selectCol: "follower_uid",
                                        filter: "followed_uid=eq.\(uid)")
        return Community.MyStats(postCount: posts.count, likesReceived: likes,
                                 commentsReceived: comments, followerCount: followers)
    }

    /// 내 표시 이름(로컬 저장). 없으면 nil.
    var myDisplayName: String? {
        let n = (defaults.string(forKey: "ticklab.profile.name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? nil : n
    }

    /// 인스타식 프로필 카운트 — 게시물/팔로워(나를 팔로우)/팔로잉(내가 팔로우). 임의 uid.
    func fetchProfileCounts(uid: String) async -> (posts: Int, followers: Int, following: Int) {
        await ensureSignedIn()
        async let posts = countRows(table: "community_posts", selectCol: "id",
                                    filter: "author_uid=eq.\(uid)&status=eq.approved")
        async let followers = countRows(table: "community_follows", selectCol: "follower_uid",
                                        filter: "followed_uid=eq.\(uid)")
        async let following = countRows(table: "community_follows", selectCol: "followed_uid",
                                        filter: "follower_uid=eq.\(uid)")
        return (await posts, await followers, await following)
    }

    /// 팔로워/팔로잉 목록 — community_follows 는 uid만 보관하므로, 닉네임·아바타는 각 uid의
    /// 최근 게시물(community_posts)에서 해석한다(단일 in 쿼리). 게시물 없는 사용자는 익명 표시.
    /// followers=true → 나를 팔로우한 사람들, false → 내가 팔로우한 사람들.
    func fetchFollowList(uid: String, followers: Bool) async -> [Community.Liker] {
        await ensureSignedIn()
        // 1) 관계 테이블에서 상대 uid 수집(순서 유지).
        let selectCol = followers ? "follower_uid" : "followed_uid"
        let filter = followers ? "followed_uid=eq.\(uid)" : "follower_uid=eq.\(uid)"
        guard let relURL = URL(string: "\(baseURL)/rest/v1/community_follows?select=\(selectCol)&\(filter)&order=created_at.desc&limit=500"),
              let (relData, _) = try? await URLSession.shared.data(for: authedRequest(relURL, method: "GET")),
              let rows = try? JSONSerialization.jsonObject(with: relData) as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        let relUIDs = rows.compactMap { $0[selectCol] as? String }
            .filter { !blockedUIDs.contains($0) && seen.insert($0).inserted }
        guard !relUIDs.isEmpty else { return [] }
        // 2) uid → 최근 게시물에서 닉네임·아바타 해석(단일 in 쿼리). 게시물 없는 uid 는 익명.
        var nameByUID: [String: (name: String?, avatar: String?)] = [:]
        let csv = relUIDs.joined(separator: ",")
        if let pURL = URL(string: "\(baseURL)/rest/v1/community_posts?select=author_uid,author_name,author_avatar_path&author_uid=in.(\(csv))&status=eq.approved&order=created_at.desc"),
           let (pData, _) = try? await URLSession.shared.data(for: authedRequest(pURL, method: "GET")),
           let pRows = try? JSONSerialization.jsonObject(with: pData) as? [[String: Any]] {
            for row in pRows {
                guard let u = row["author_uid"] as? String, nameByUID[u] == nil else { continue }
                nameByUID[u] = (row["author_name"] as? String, row["author_avatar_path"] as? String)
            }
        }
        // 3) 관계 순서 유지하며 Liker 구성.
        return relUIDs.map { u in
            let info = nameByUID[u]
            return Community.Liker(uid: u, authorName: info?.name, authorAvatarPath: info?.avatar)
        }
    }

    /// 게시물 라이커 목록(인스타 "누가 좋아요") — 차단 작성자 제외. likes 전체 읽기 RLS 필요.
    func fetchLikers(postID: String) async -> [Community.Liker] {
        await ensureSignedIn()
        // select=* — author_name 컬럼 미배포(community_likers.sql 전)여도 400 안 나고 목록은 채워짐.
        guard let url = URL(string: "\(baseURL)/rest/v1/community_likes?select=*&post_id=eq.\(postID)&order=created_at.desc&limit=200") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Liker].self, from: data) else { return [] }
        return arr.filter { !blockedUIDs.contains($0.uid) }
    }

    private func adjustLocalLike(_ id: String, delta: Int) {
        guard let idx = feed.firstIndex(where: { $0.id == id }) else { return }
        feed[idx].likeCount = max(0, feed[idx].likeCount + delta)
    }

    /// 댓글 추가/삭제 시 피드 카드의 댓글 수 즉시 보정(트리거 결과를 기다리지 않음).
    func adjustLocalCommentCount(_ id: String, delta: Int) {
        guard let idx = feed.firstIndex(where: { $0.id == id }) else { return }
        feed[idx].commentCount = max(0, (feed[idx].commentCount ?? 0) + delta)
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

    // MARK: - Channel Suggestions (사용자 → 운영자 제안)

    /// 사용자: 추천 채널 주소 제출. 익명 세션도 가능(본인 uid INSERT).
    @discardableResult
    func submitChannelSuggestion(url: String, note: String?) async -> Bool {
        await ensureSignedIn()
        guard let endpoint = URL(string: "\(baseURL)/rest/v1/channel_suggestions") else { return false }
        var req = authedRequest(endpoint, method: "POST")
        var body: [String: Any] = ["url": url]
        if let n = note, !n.isEmpty { body["note"] = n }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 운영자: 제안 목록(최신순).
    func fetchChannelSuggestions() async -> [Community.ChannelSuggestion] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/channel_suggestions?select=*&order=created_at.desc&limit=200") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.ChannelSuggestion].self, from: data) else { return [] }
        return arr
    }

    /// 운영자: 제안 삭제(처리 완료).
    @discardableResult
    func deleteChannelSuggestion(id: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/channel_suggestions?id=eq.\(id)") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE")),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - App Feedback (사용자 → 운영자, 인앱 피드백)

    /// 사용자: 피드백 제출. 익명 세션도 가능(본인 uid INSERT). mailto 대체(Round 175).
    @discardableResult
    func submitFeedback(type: String, message: String, appVersion: String?) async -> Bool {
        await ensureSignedIn()
        guard let endpoint = URL(string: "\(baseURL)/rest/v1/app_feedback") else { return false }
        var req = authedRequest(endpoint, method: "POST")
        var body: [String: Any] = ["type": type, "message": message]
        if let v = appVersion, !v.isEmpty { body["app_version"] = v }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 운영자: 피드백 목록(최신순).
    func fetchFeedback() async -> [Community.Feedback] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/app_feedback?select=*&order=created_at.desc&limit=200") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Feedback].self, from: data) else { return [] }
        return arr
    }

    /// 운영자: 피드백 삭제(처리 완료).
    @discardableResult
    func deleteFeedback(id: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/app_feedback?id=eq.\(id)") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE")),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - Curated YouTube Channels (운영자 큐레이션 — 영상 피드)

    /// Edge Function(youtube-videos) — 서버가 curated_channels 를 YouTube Data API 로 조회·캐시한 최신 영상.
    /// YouTube 공개 RSS(feeds/videos.xml) 차단(2026-06-03) 이후 영상 소스. 앱은 Supabase 도메인만 호출.
    func fetchCuratedVideos() async -> [Community.CuratedVideo] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/functions/v1/youtube-videos") else { return [] }
        guard let (data, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let arr = try? Self.decoder.decode([Community.CuratedVideo].self, from: data) else { return [] }
        return arr
    }

    /// 활성 채널 — locale 매칭. 호출 측에서 비면 'en' 폴백. 모든 사용자 읽기.
    func fetchCuratedChannels(locale: String) async -> [Community.CuratedChannel] {
        await ensureSignedIn()
        guard let enc = locale.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/rest/v1/curated_channels?select=*&locale=eq.\(enc)&active=eq.true&order=sort_order.asc") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.CuratedChannel].self, from: data) else { return [] }
        return arr
    }

    /// 언어 무관 — 활성 채널 전체. 호출 측 locale 폴백용(기기 언어 채널이 없을 때).
    func fetchActiveCuratedChannels() async -> [Community.CuratedChannel] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/curated_channels?select=*&active=eq.true&order=sort_order.asc") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.CuratedChannel].self, from: data) else { return [] }
        return arr
    }

    /// 운영자 편집용 — active/locale 무관 전체.
    func fetchAllCuratedChannels() async -> [Community.CuratedChannel] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/curated_channels?select=*&order=locale.asc,sort_order.asc") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.CuratedChannel].self, from: data) else { return [] }
        return arr
    }

    @discardableResult
    func addCuratedChannel(channelID: String, title: String, thumbnailURL: String?,
                           locale: String, category: String?, sortOrder: Int) async -> Bool {
        await ensureSignedIn()
        // on_conflict=channel_id,locale + merge-duplicates → 이미 있으면 갱신(중복 409 방지).
        guard let url = URL(string: "\(baseURL)/rest/v1/curated_channels?on_conflict=channel_id,locale") else { return false }
        var req = authedRequest(url, method: "POST")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = ["channel_id": channelID, "title": title, "locale": locale, "sort_order": sortOrder, "active": true]
        if let t = thumbnailURL, !t.isEmpty { body["thumbnail_url"] = t }
        if let c = category, !c.isEmpty { body["category"] = c }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { lastError = String(localized: "community.error.network"); return false }
        if (200...299).contains(http.statusCode) { lastError = nil; return true }
        // 404=테이블 없음(SQL 미배포), 401/403=admin RLS, 409=중복(channel_id+locale).
        let msg = String(data: data, encoding: .utf8) ?? ""
        lastError = String(localized: "community.error.http_failure") + " \(http.statusCode) · \(msg.prefix(160))"
        return false
    }

    @discardableResult
    func updateCuratedChannel(id: String, channelID: String, title: String, thumbnailURL: String?,
                              locale: String, category: String?, sortOrder: Int, active: Bool) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/curated_channels?id=eq.\(id)") else { return false }
        var req = authedRequest(url, method: "PATCH")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "channel_id": channelID, "title": title,
            "thumbnail_url": (thumbnailURL?.isEmpty == false ? thumbnailURL! : NSNull()) as Any,
            "locale": locale, "category": (category?.isEmpty == false ? category! : NSNull()) as Any,
            "sort_order": sortOrder, "active": active
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    @discardableResult
    func deleteCuratedChannel(id: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/curated_channels?id=eq.\(id)") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE")),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - Profile / Nickname (서버 등록 + 중복 검사)

    /// 닉네임이 **다른 사용자**에게 선점됐는지(대소문자 무시). 본인 것은 제외. 비어있으면 false.
    /// 레지스트리(community_profiles) + 기존 글 author_name(레지스트리 도입 전 사용분) 양쪽 조회.
    func isNicknameTaken(_ name: String) async -> Bool {
        await ensureSignedIn()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = myUID,
              let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return false }
        func anyRow(_ urlString: String) async -> Bool {
            guard let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
            return !arr.isEmpty
        }
        if await anyRow("\(baseURL)/rest/v1/community_profiles?select=uid&display_name=ilike.\(enc)&uid=neq.\(uid)&limit=1") { return true }
        if await anyRow("\(baseURL)/rest/v1/community_posts?select=author_uid&author_name=ilike.\(enc)&author_uid=neq.\(uid)&limit=1") { return true }
        return false
    }

    /// 닉네임을 서버 프로필에 등록(uid PK upsert) — 레지스트리화. 실패해도 로컬 저장은 유지.
    @discardableResult
    func registerNickname(_ name: String) async -> Bool {
        await ensureSignedIn()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, myUID != nil,
              let url = URL(string: "\(baseURL)/rest/v1/community_profiles?on_conflict=uid") else { return false }
        var req = authedRequest(url, method: "POST")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["display_name": trimmed])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - Profile sync (서버 동기화 + 로그인 복원)
    // 프로필(이름·사진·소개 등)은 로컬 UserDefaults 가 1차 저장소지만, 재설치/기기변경 후
    //   로그인하면 복원되도록 community_profiles(uid PK)에 동기화하고 로그인 시 되읽는다.

    struct ProfileSnapshot {
        var displayName: String?; var avatarPath: String?; var bio: String?
        var startYear: String?; var favBrands: String?; var repBrand: String?; var isDealer: Bool?
    }

    /// 로컬 프로필 사진을 Storage 에 업로드하고 avatarPath 반환·저장. 게시 안 해도 아바타가 서버에 남게 한다.
    @discardableResult
    func uploadProfileAvatarIfNeeded() async -> String? {
        await ensureSignedIn()
        guard let uid = myUID,
              let raw = defaults.data(forKey: "ticklab.profile.photoData"), !raw.isEmpty else {
            return defaults.string(forKey: "ticklab.profile.avatarPath")
        }
        let avatarData = EXIFStripper.optimizedForUpload(raw, maxDimension: 320)
        let checksum = avatarData.prefix(512).reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        let avatarPath = "\(uid)/avatar-\(avatarData.count)-\(checksum).jpg"
        if defaults.string(forKey: "ticklab.profile.avatarPath") == avatarPath { return avatarPath }
        if await uploadAvatar(data: avatarData, path: avatarPath) {
            defaults.set(avatarPath, forKey: "ticklab.profile.avatarPath")
            return avatarPath
        }
        return defaults.string(forKey: "ticklab.profile.avatarPath")
    }

    /// 프로필 전체를 community_profiles(uid PK)에 upsert. 미배포 컬럼은 graceful 제거 재시도(profile_sync.sql).
    @discardableResult
    func syncProfile() async -> Bool {
        await ensureSignedIn()
        guard myUID != nil,
              let url = URL(string: "\(baseURL)/rest/v1/community_profiles?on_conflict=uid") else { return false }
        let avatarPath = await uploadProfileAvatarIfNeeded()
        let name = (defaults.string(forKey: "ticklab.profile.name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var full: [String: Any] = ["display_name": name.isEmpty ? "Collector" : name,
                                    "is_dealer": defaults.bool(forKey: "ticklab.profile.isDealer")]
        if let p = avatarPath, !p.isEmpty { full["avatar_path"] = p }
        func add(_ col: String, _ defKey: String) {
            let v = (defaults.string(forKey: defKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { full[col] = v }
        }
        add("bio", "ticklab.profile.bio")
        add("start_year", "ticklab.profile.startYear")
        add("fav_brands", "ticklab.profile.brands")
        add("rep_brand", "ticklab.profile.repBrand")
        if await postProfileRow(url, full) { return true }
        // 확장 컬럼 미배포(PGRST204) 시 스키마 기본(display_name/avatar_path/bio)만 재시도.
        return await postProfileRow(url, full.filter { ["display_name", "avatar_path", "bio"].contains($0.key) })
    }

    private func postProfileRow(_ url: URL, _ body: [String: Any]) async -> Bool {
        var req = authedRequest(url, method: "POST")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 서버에서 내 프로필 조회 — community_profiles 우선, 빈 필드는 최근 내 게시물에서 보강.
    func fetchMyProfile() async -> ProfileSnapshot? {
        await ensureSignedIn()
        guard let uid = myUID else { return nil }
        var s = ProfileSnapshot()
        if let url = URL(string: "\(baseURL)/rest/v1/community_profiles?select=*&uid=eq.\(uid)&limit=1"),
           let (d, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], let row = arr.first {
            s.displayName = row["display_name"] as? String
            s.avatarPath = row["avatar_path"] as? String
            s.bio = row["bio"] as? String
            s.startYear = row["start_year"] as? String
            s.favBrands = row["fav_brands"] as? String
            s.repBrand = row["rep_brand"] as? String
            s.isDealer = row["is_dealer"] as? Bool
        }
        // 프로필 행에 없는 필드 보강 — 내 최근 게시물 스냅샷(author_*).
        if let url = URL(string: "\(baseURL)/rest/v1/community_posts?select=author_name,author_avatar_path,author_bio,author_start_year,author_fav_brands,author_rep_brand&author_uid=eq.\(uid)&order=created_at.desc&limit=1"),
           let (d, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]], let row = arr.first {
            func coalesce(_ cur: String?, _ key: String) -> String? {
                if let c = cur, !c.isEmpty { return c }
                let v = row[key] as? String
                return (v?.isEmpty == false) ? v : cur
            }
            s.displayName = coalesce(s.displayName, "author_name")
            s.avatarPath = coalesce(s.avatarPath, "author_avatar_path")
            s.bio = coalesce(s.bio, "author_bio")
            s.startYear = coalesce(s.startYear, "author_start_year")
            s.favBrands = coalesce(s.favBrands, "author_fav_brands")
            s.repBrand = coalesce(s.repBrand, "author_rep_brand")
        }
        let empty = (s.displayName ?? "").isEmpty && (s.avatarPath ?? "").isEmpty && (s.bio ?? "").isEmpty
        return empty ? nil : s
    }

    /// Apple 로그인 직후 — 로컬 프로필이 있으면 이 계정에 업로드(최신 편집 보존), 없으면 서버에서 복원.
    /// 익명 세션에서 편집 → Apple 로그인 시 다른 uid 의 옛 프로필로 덮이던 문제 대응.
    func syncOrRestoreProfileOnLogin() async {
        let hasLocalName = !((defaults.string(forKey: "ticklab.profile.name") ?? "")
                                .trimmingCharacters(in: .whitespaces).isEmpty)
        let hasLocalPhoto = defaults.data(forKey: "ticklab.profile.photoData") != nil
        if hasLocalName || hasLocalPhoto {
            await syncProfile()            // 로컬(최신)을 이 Apple 계정에 업로드
        } else {
            // 로컬이 비어있을 때만(재설치/기기변경) 서버에서 복원 — restoreProfileIfNeeded 가
            //   시작연도·브랜드·대표메이커·소개·아바타까지 전부 채운다(needAny 확장). 로컬에 이름/사진이
            //   있으면 복원을 매 로그인 돌리지 않는다 — 사용자가 비운 필드를 서버 옛값으로 되살리거나
            //   불필요한 네트워크 호출을 하지 않기 위함.
            await restoreProfileIfNeeded()
        }
    }

    /// 로그인/실행 시 — 로컬 프로필의 빈 필드를 서버에서 복원(+아바타 다운로드). 로컬에 있으면 보존(덮어쓰지 않음).
    func restoreProfileIfNeeded() async {
        let d = defaults
        func emptyLocal(_ k: String) -> Bool { (d.string(forKey: k) ?? "").isEmpty }
        let needName = emptyLocal("ticklab.profile.name")
        let needPhoto = d.data(forKey: "ticklab.profile.photoData") == nil
        // 비어있는 필드가 하나라도 있으면 서버에서 보강(merge). 이름/사진만 보고 일찍 끝내면
        //   시작연도·좋아하는 브랜드·대표 메이커·소개가 영영 복원 안 되던 문제 수정.
        let needAny = needName || needPhoto
            || emptyLocal("ticklab.profile.bio")
            || emptyLocal("ticklab.profile.startYear")
            || emptyLocal("ticklab.profile.brands")
            || emptyLocal("ticklab.profile.repBrand")
        guard needAny else { return }   // 모든 필드 이미 채워짐 — 네트워크 호출 생략
        guard let p = await fetchMyProfile() else { return }
        if needName, let n = p.displayName, !n.isEmpty { d.set(n, forKey: "ticklab.profile.name") }
        if let v = p.bio, !v.isEmpty, emptyLocal("ticklab.profile.bio") { d.set(v, forKey: "ticklab.profile.bio") }
        if let v = p.startYear, !v.isEmpty, emptyLocal("ticklab.profile.startYear") { d.set(v, forKey: "ticklab.profile.startYear") }
        if let v = p.favBrands, !v.isEmpty, emptyLocal("ticklab.profile.brands") { d.set(v, forKey: "ticklab.profile.brands") }
        if let v = p.repBrand, !v.isEmpty, emptyLocal("ticklab.profile.repBrand") { d.set(v, forKey: "ticklab.profile.repBrand") }
        if let dealer = p.isDealer, dealer, !d.bool(forKey: "ticklab.profile.isDealer") { d.set(true, forKey: "ticklab.profile.isDealer") }
        if let path = p.avatarPath, !path.isEmpty {
            d.set(path, forKey: "ticklab.profile.avatarPath")
            if needPhoto, let img = await downloadStorageData(path: path) { d.set(img, forKey: "ticklab.profile.photoData") }
        }
    }

    /// Storage 공개 URL 에서 바이트 다운로드(아바타 복원용).
    private func downloadStorageData(path: String) async -> Data? {
        guard let url = imageURL(for: path) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    // MARK: - Activity Notifications (인앱 — 내 글 좋아요 · 새 팔로워)

    /// 마지막으로 알림을 확인한 시각. 미확인 판정 기준.
    var lastNotifSeen: Date { (defaults.object(forKey: Keys.notifSeen) as? Date) ?? .distantPast }
    /// 종 아이콘 탭(알림 열람) 시 호출 — 현재 시각으로 갱신해 배지 클리어.
    func markNotificationsSeen() { defaults.set(Date(), forKey: Keys.notifSeen) }

    /// 내 게시물 좋아요(본인 제외) + 내 글 댓글(본인 제외) + 새 팔로워 이벤트를 최신순으로.
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
            // 2b) 내 글 댓글(본인 제외) — 참여 사다리 복구. community_comments 미배포 시 빈 결과로 안전.
            struct CommentRow: Decodable { let id: String; let post_id: String; let uid: String; let created_at: Date }
            if let url = URL(string: "\(baseURL)/rest/v1/community_comments?select=id,post_id,uid,created_at&post_id=in.(\(ids))&uid=neq.\(uid)&status=eq.visible&order=created_at.desc&limit=50"),
               let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
               let rows = try? Self.decoder.decode([CommentRow].self, from: data) {
                for r in rows where !blockedUIDs.contains(r.uid) {   // 차단 작성자 댓글 알림 제외
                    events.append(.init(id: "comment-\(r.id)",
                                        kind: .comment, postImagePath: pathByID[r.post_id] ?? nil, createdAt: r.created_at))
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

    // MARK: - Comments (커뮤니티 댓글)

    /// 게시물 댓글(오름차순) — 차단한 작성자 댓글 제외.
    func fetchComments(postID: String) async -> [Community.Comment] {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_comments?select=*&post_id=eq.\(postID)&status=eq.visible&order=created_at.asc&limit=300") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let arr = try? Self.decoder.decode([Community.Comment].self, from: data) else { return [] }
        return arr.filter { !blockedUIDs.contains($0.uid) }
    }

    /// 댓글 작성. 작성자명은 운영 ID면 TickLab, 아니면 프로필명/Collector.
    @discardableResult
    func addComment(to post: Community.Post, body: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_comments") else { return false }
        var req = authedRequest(url, method: "POST")
        var dict: [String: Any] = ["post_id": post.id, "body": body]
        if defaults.bool(forKey: "ticklab.admin.actingAsTickLab") {
            dict["author_name"] = "TickLab"
        } else {
            let n = (defaults.string(forKey: "ticklab.profile.name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            dict["author_name"] = n.isEmpty ? "Collector" : n
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: dict)
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// 댓글 삭제(본인 또는 운영자 — RLS).
    @discardableResult
    func deleteComment(_ id: String) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_comments?id=eq.\(id)") else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE")),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
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
        // 쓰기 진행 중 표시 — 이 사이 syncFollowing 이 끼어들어 낙관적 상태를 덮어쓰지 않게.
        followWritesInFlight += 1
        defer { followWritesInFlight -= 1 }
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
        await ensureSignedIn()   // Round 173 (감사 P1): 토큰 만료 시 RLS 인증 실패로 서버 글 잔존 방지.
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?id=eq.\(post.id)") else { return }
        _ = try? await URLSession.shared.data(for: authedRequest(url, method: "DELETE"))
        feed.removeAll { $0.id == post.id }
    }

    // MARK: - Upload (Storage + insert)

    enum UploadError: Error { case notSignedIn, storageFailed, dailyLimit }

    /// 크롭·검열 통과한 JPEG 를 업로드. 성공 시 피드 갱신.
    /// 게시. imageData nil 이면 **글-전용 게시**(사진 없음, caption 필수). Round 171.
    /// `brand`: 내 컬렉션 브랜드 화이트리스트에서 선택된 메타(시세·모델명 금지). nil = 미선택.
    /// `themeID`: 위클리 테마 귀속(선택). 신규 컬럼 미배포 시 안전하게 무시(서버 거절 대비 graceful).
    func uploadPost(imageData: Data?, brand: String?, caption: String? = nil, themeID: String? = nil) async throws {
        lastError = nil
        guard canPostToday else { throw UploadError.dailyLimit }
        // 글-전용은 캡션이 반드시 있어야 (빈 게시 방지).
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if imageData == nil && trimmedCaption.isEmpty {
            lastError = String(localized: "community.error.text_only_empty")
            throw UploadError.storageFailed
        }
        await ensureSignedIn()
        guard let uid = myUID else {
            lastError = String(localized: "community.error.anon_signin_failed")
            throw UploadError.notSignedIn
        }

        // 1) Storage 업로드 — 사진 있을 때만. 글-전용이면 path nil.
        var path: String? = nil
        if let imageData {
            let optimized = EXIFStripper.optimizedForUpload(imageData)   // 긴 변 1080px 상한(이미 작으면 원본) — 서버 용량 절약
            let p = "\(uid)/\(UUID().uuidString).jpg"
            guard let storageURL = URL(string: "\(baseURL)/storage/v1/object/community/\(p)") else {
                throw UploadError.storageFailed
            }
            var up = URLRequest(url: storageURL)
            up.httpMethod = "POST"
            up.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            up.setValue(anonKey, forHTTPHeaderField: "apikey")
            up.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
            // upload(for:from:) 가 body 를 from: 으로 보냄 — httpBody 중복 설정 제거.
            let (upData, resp) = try await URLSession.shared.upload(for: up, from: optimized)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                lastError = "storage \(http.statusCode): \(String(data: upData, encoding: .utf8) ?? "")"
                throw UploadError.storageFailed
            }
            path = p
        }
        // 2) posts insert (author_uid 는 서버 default auth.uid()).
        guard let insertURL = URL(string: "\(baseURL)/rest/v1/community_posts") else {
            throw UploadError.storageFailed
        }
        var ins = authedRequest(insertURL, method: "POST")
        ins.setValue("return=representation", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = [:]
        if let path { body["image_path"] = path }   // 글-전용이면 image_path 미포함(서버 NULL)
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
        // Round 171: 닉네임 옆 장착 뱃지(이모지). 미장착이면 미포함(서버 NULL).
        let equippedBadge = (defaults.string(forKey: "ticklab.profile.equippedBadge") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !equippedBadge.isEmpty { body["author_badge"] = equippedBadge }
        // Round 174: 아바타 하단 대표 시계 메이커 — 명시 선택(repBrand) 우선, 없으면 좋아하는 브랜드 1순위.
        // ⚠️ author_rep_brand 컬럼은 docs/community/APPLY_PENDING.sql 먼저 배포돼야 함(미배포 시 insert 거절).
        let explicitRep = (defaults.string(forKey: "ticklab.profile.repBrand") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstFav = (defaults.string(forKey: "ticklab.profile.brands") ?? "")
            .split(separator: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let repBrand = explicitRep.isEmpty ? firstFav : explicitRep
        if !repBrand.isEmpty { body["author_rep_brand"] = repBrand }
        // 대표사진(프로필 아바타) — EXIF strip 된 photoData 를 내용 고유 경로로 1회 업로드 후 첨부.
        // 이게 없으면 피드 헤더에 본인 사진이 안 뜨고 이니셜만 보임(v1.1.0 버그 수정).
        if let raw = defaults.data(forKey: "ticklab.profile.photoData"), !raw.isEmpty {
            let avatarData = EXIFStripper.optimizedForUpload(raw, maxDimension: 320)   // 아바타는 32pt 표시 → 320px면 충분
            let checksum = avatarData.prefix(512).reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
            let avatarPath = "\(uid)/avatar-\(avatarData.count)-\(checksum).jpg"
            var uploaded = (defaults.string(forKey: "ticklab.profile.avatarPath") == avatarPath)
            if !uploaded {
                uploaded = await uploadAvatar(data: avatarData, path: avatarPath)
                if uploaded { defaults.set(avatarPath, forKey: "ticklab.profile.avatarPath") }
            }
            // 업로드 확정된 경우에만 첨부(실패 시 깨진 URL 대신 이니셜 폴백 유지).
            if uploaded { body["author_avatar_path"] = avatarPath }
        }
        if let caption {
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { body["caption"] = String(trimmed.prefix(CommunityTextModerator.maxLength)) }
        }
        // 컬렉터 프로필 스냅샷(프로필 탭 노출) — 소개·시작연도·좋아하는 브랜드.
        // 운영(TickLab) 계정 제외, 소개·브랜드는 욕설 필터 통과분만. 컬럼 미배포 시 아래 재시도에서 strip.
        if !defaults.bool(forKey: "ticklab.admin.actingAsTickLab") {
            let bio = (defaults.string(forKey: "ticklab.profile.bio") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !bio.isEmpty, !CommunityTextModerator.containsProfanity(bio) {
                body["author_bio"] = String(bio.prefix(300))
            }
            let startYear = (defaults.string(forKey: "ticklab.profile.startYear") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !startYear.isEmpty { body["author_start_year"] = String(startYear.prefix(10)) }
            let favBrands = (defaults.string(forKey: "ticklab.profile.brands") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !favBrands.isEmpty, !CommunityTextModerator.containsProfanity(favBrands) {
                body["author_fav_brands"] = String(favBrands.prefix(120))
            }
        }
        // 위클리 테마 귀속(선택) — theme_id 컬럼. 미배포 시 insert 가 거절될 수 있어 아래에서 1회 재시도.
        if let themeID, !themeID.isEmpty { body["theme_id"] = themeID }

        ins.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var (insData, insResp) = try await URLSession.shared.data(for: ins)
        // 서버 거절(하루1장 트리거·RLS·미존재 컬럼 등)을 더 이상 조용히 삼키지 않는다.
        if let http = insResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var msg = String(data: insData, encoding: .utf8) ?? ""
            // graceful degrade: theme_id 컬럼 미배포(weekly_theme.sql 전)면 그 컬럼만 빼고 1회 재시도.
            // (PostgREST: 미존재 컬럼은 PGRST204 / "column ... does not exist".)
            let optionalCols = ["theme_id", "author_bio", "author_start_year", "author_fav_brands"]
            let hasOptional = optionalCols.contains { body[$0] != nil }
            if hasOptional, (msg.contains("PGRST204") || optionalCols.contains { msg.contains($0) }) {
                for c in optionalCols { body.removeValue(forKey: c) }
                ins.httpBody = try? JSONSerialization.data(withJSONObject: body)
                (insData, insResp) = try await URLSession.shared.data(for: ins)
                msg = String(data: insData, encoding: .utf8) ?? ""
            }
            if let http2 = insResp as? HTTPURLResponse, !(200...299).contains(http2.statusCode) {
                lastError = "insert \(http2.statusCode): \(msg)"
                if msg.contains("daily_post_limit") { throw UploadError.dailyLimit }
                throw UploadError.storageFailed
            }
        }
        markPostedToday()
        await loadFeed()
    }

    /// 프로필 대표사진을 community 스토리지에 업로드(내용 고유 경로 → INSERT). 409(이미 존재)는 정상.
    /// 별도 UPDATE 정책 불필요 — 경로가 내용 해시라 같은 사진은 같은 경로(재업로드 안 함).
    private func uploadAvatar(data: Data, path: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/storage/v1/object/community/\(path)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await URLSession.shared.upload(for: req, from: data),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode) || http.statusCode == 409
    }

    /// 본인 글 캡션 수정 — posts_update_own RLS(author_uid = auth.uid()) 필요.
    /// 검열은 호출 측(편집 화면)에서 선통과시킴.
    @discardableResult
    func updateMyPost(_ post: Community.Post, caption: String) async -> Bool {
        await ensureSignedIn()
        guard let uid = myUID, post.authorUID == uid else { lastError = "not owner"; return false }
        guard let url = URL(string: "\(baseURL)/rest/v1/community_posts?id=eq.\(post.id)") else { return false }
        var req = authedRequest(url, method: "PATCH")
        let capped = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CommunityTextModerator.maxLength))
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["caption": (capped.isEmpty ? NSNull() : capped) as Any])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { lastError = String(localized: "community.error.network"); return false }
        if !(200...299).contains(http.statusCode) {
            lastError = "update \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(120) ?? "")"
            return false
        }
        await loadFeed()
        return true
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

    /// 앱 접속 1회 기록 — community_access_log INSERT(서버 default uid/created_at).
    /// 접속 누계 집계용. 테이블 미배포(access_log.sql 전)면 조용히 실패(graceful).
    func logAccess() async {
        await ensureSignedIn()
        // 세션 없으면(미로그인) RLS(uid=auth.uid())에 막혀 무조건 실패 → 헛된 요청 스킵.
        //   (Apple 전용 전환으로 자동 익명가입 없음 — 접속 누계는 로그인 사용자 기준 집계.)
        guard isSignedIn else { return }
        guard let url = URL(string: "\(baseURL)/rest/v1/community_access_log") else { return }
        var req = authedRequest(url, method: "POST")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [String: Any]())
        _ = try? await URLSession.shared.data(for: req)
    }

    /// 운영 통계. 전체/오늘 게시물은 public 읽기로 동작, 활동 사용자·접속 누계는 admin RLS 테이블 필요.
    func fetchOpsStats() async -> Community.OpsStats {
        await ensureSignedIn()
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let now = Date()
        let startToday = cal.startOfDay(for: now)
        let startWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? startToday
        let startMonth = cal.dateInterval(of: .month, for: now)?.start ?? startToday
        let todayISO = iso.string(from: startToday)
        let activeCutoff = iso.string(from: now.addingTimeInterval(-120))
        async let total = countRows(table: "community_posts", selectCol: "id", filter: "status=eq.approved")
        async let today = countRows(table: "community_posts", selectCol: "id",
                                    filter: "status=eq.approved&created_at=gte.\(todayISO)")
        async let active = countRows(table: "community_presence", selectCol: "uid",
                                     filter: "last_seen=gte.\(activeCutoff)")
        // 접속 누계 — community_access_log created_at 윈도우별 카운트(미배포 시 0).
        async let accToday = countRows(table: "community_access_log", selectCol: "id",
                                       filter: "created_at=gte.\(todayISO)")
        async let accWeek = countRows(table: "community_access_log", selectCol: "id",
                                      filter: "created_at=gte.\(iso.string(from: startWeek))")
        async let accMonth = countRows(table: "community_access_log", selectCol: "id",
                                       filter: "created_at=gte.\(iso.string(from: startMonth))")
        async let accTotal = countRows(table: "community_access_log", selectCol: "id", filter: "id=gte.0")
        return Community.OpsStats(
            activeUsers: await active, todayPosts: await today, totalPosts: await total,
            todayAccess: await accToday, weekAccess: await accWeek,
            monthAccess: await accMonth, totalAccess: await accTotal
        )
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

    // MARK: - Weekly Theme Challenge (위클리 테마)

    /// 현재 활성 위클리 테마 1건 (active + 기간 내 + kind='theme'). 모든 사용자.
    /// `theme_title` 컬럼/`kind` 컬럼 미배포 시 안전하게 nil (graceful degrade — 서버 SQL 미배포 환경).
    func fetchActiveTheme() async -> Community.Theme? {
        await ensureSignedIn()
        let nowISO = ISO8601DateFormatter().string(from: Date())
        // select 에 theme_title 명시 — 컬럼 없으면 PostgREST 가 400 → 빈 결과로 처리(아래 try? 가 흡수).
        guard let url = URL(string: "\(baseURL)/rest/v1/community_announcements?select=id,theme_title,body,starts_at,ends_at&kind=eq.theme&active=eq.true&starts_at=lte.\(nowISO)&ends_at=gte.\(nowISO)&order=created_at.desc&limit=1") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(for: authedRequest(url, method: "GET")),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let arr = try? Self.decoder.decode([Community.Theme].self, from: data) else { return nil }
        // 빈 title 은 무효(테마로 취급 안 함).
        return arr.first(where: { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    /// 운영자: 위클리 테마 발행 (admin insert RLS). 기존 공지 테이블 재사용 — kind='theme'.
    /// `weekly_theme.sql` 배포 전이면 신규 컬럼 거절로 실패할 수 있음(클라는 false 반환).
    @discardableResult
    func postWeeklyTheme(title: String, body: String?, startsAt: Date, endsAt: Date) async -> Bool {
        await ensureSignedIn()
        guard let url = URL(string: "\(baseURL)/rest/v1/community_announcements") else { return false }
        var req = authedRequest(url, method: "POST")
        let iso = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "kind": "theme",
            "theme_title": title,
            // body 는 NOT NULL 이므로 비어도 최소 title 을 채워 둠(스키마 호환).
            "body": (body?.isEmpty == false ? body! : title),
            "starts_at": iso.string(from: startsAt),
            "ends_at": iso.string(from: endsAt),
            "active": true
        ]
        if body == nil { dict["body"] = title }
        req.httpBody = try? JSONSerialization.data(withJSONObject: dict)
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
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

    /// Storage 공개 URL (approved 사진). 글-전용 게시(path nil)면 nil → 호출부가 이미지 영역 생략.
    func imageURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "\(baseURL)/storage/v1/object/public/community/\(path)")
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
