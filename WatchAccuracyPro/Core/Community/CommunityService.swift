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

    /// 익명 세션 보장. 토큰 없으면 가입, **만료(또는 임박)면 refresh 로 같은 uid 세션 갱신**,
    /// refresh 실패 시에만 신규 가입. (이전 버그: 만료 토큰을 그대로 재사용 → 403 "exp claim".)
    func ensureSignedIn() async {
        guard let token = accessToken, myUID != nil else {
            await signInAnonymously()
            return
        }
        if Self.isJWTExpired(token) {
            if !(await refreshSession()) { await signInAnonymously() }
        }
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
            // 차단한 작성자 제외.
            feed = posts.filter { !blockedUIDs.contains($0.authorUID) }
        } catch {
            lastError = error.localizedDescription
        }
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
        // 신고 즉시 로컬에서도 숨김.
        feed.removeAll { $0.id == post.id }
    }

    func block(authorOf post: Community.Post) async {
        await ensureSignedIn()
        blockedUIDs.insert(post.authorUID)
        defaults.set(Array(blockedUIDs), forKey: Keys.blocked)
        feed.removeAll { $0.authorUID == post.authorUID }
        guard let url = URL(string: "\(baseURL)/rest/v1/community_blocks") else { return }
        var req = authedRequest(url, method: "POST")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["blocked_uid": post.authorUID])
        _ = try? await URLSession.shared.data(for: req)
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
