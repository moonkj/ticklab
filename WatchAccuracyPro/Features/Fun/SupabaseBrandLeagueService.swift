import CryptoKit
import Foundation
import SwiftData
import UIKit

/// 글로벌 브랜드 리그 — Supabase REST API 클라이언트.
/// 각 기기가 착용 데이터를 익명으로 업로드하고 전체 집계를 수신.
@MainActor
final class SupabaseBrandLeagueService: ObservableObject {
    static let shared = SupabaseBrandLeagueService()

    // MARK: - Config

    private let baseURL = "https://tknicqhhgqfviuqczctl.supabase.co"
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRrbmljcWhoZ3Fmdml1cWN6Y3RsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4NDI1NzUsImV4cCI6MjA5NDQxODU3NX0.fwrT5Sl3H9PxHp5cKG6r80e_Wsc0KTHYcqFhdHYRfZs"

    // MARK: - State

    @Published var globalRanking: [GlobalBrandRow] = []
    @Published var isLoading = false
    @Published var lastError: String?

    var rankingCache: [String: (rows: [GlobalBrandRow], at: Date)] = [:]
    private let cacheMinutes: TimeInterval = 30 * 60

    // MARK: - Types

    struct GlobalBrandRow: Identifiable {
        var id: String { brand }
        let brand: String
        let totalCount: Int
    }

    // MARK: - Device hash (anonymous)

    var deviceHash: String {
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let data = Data(raw.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Period key helpers

    static func periodKey(type: String, date: Date = Date()) -> String {
        let cal = Calendar.current
        switch type {
        case "day":
            let c = cal.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        case "week":
            let year = cal.component(.yearForWeekOfYear, from: date)
            let week = cal.component(.weekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)
        case "month":
            let c = cal.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", c.year!, c.month!)
        case "year":
            return String(cal.component(.year, from: date))
        default:
            return ""
        }
    }

    // MARK: - Upload user's brand wear count

    /// 착용 기록 변경 시 호출 — 해당 기기의 브랜드별 착용 수를 Supabase 에 upsert.
    func uploadWearCount(brand: String, count: Int) {
        guard !brand.isEmpty, count > 0 else { return }
        let periodTypes = ["day", "week", "month", "year"]
        let hash = deviceHash
        Task {
            for pt in periodTypes {
                let pk = Self.periodKey(type: pt)
                await upsert(deviceHash: hash, brand: brand, periodType: pt, periodKey: pk, count: count)
            }
        }
    }

    private func upsert(deviceHash: String, brand: String, periodType: String, periodKey: String, count: Int) async {
        guard let url = URL(string: "\(baseURL)/rest/v1/brand_wear_stats?on_conflict=device_hash,brand,period_type,period_key") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "device_hash": deviceHash,
            "brand":       brand,
            "period_type": periodType,
            "period_key":  periodKey,
            "count":       count,
            "updated_at":  ISO8601DateFormatter().string(from: Date())
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Fetch global ranking

    func fetchRanking(periodType: String) async {
        let periodKey = Self.periodKey(type: periodType)
        let cacheKey = "\(periodType)_\(periodKey)"
        // 캐시 유효하면 재사용
        if let cached = rankingCache[cacheKey], Date().timeIntervalSince(cached.at) < cacheMinutes {
            globalRanking = cached.rows
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/get_brand_ranking") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        let body: [String: Any] = [
            "p_period_type": periodType,
            "p_period_key":  periodKey,
            "p_limit":       30
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let rows = try JSONDecoder().decode([[String: AnyCodable]].self, from: data)
            let parsed = rows.compactMap { dict -> GlobalBrandRow? in
                guard let brand = dict["brand"]?.value as? String,
                      let count = dict["total_count"]?.value else { return nil }
                let c: Int = {
                    if let i = count as? Int { return i }
                    if let s = count as? String { return Int(s) ?? 0 }
                    if let d = count as? Double { return Int(d) }
                    return 0
                }()
                return GlobalBrandRow(brand: brand, totalCount: c)
            }
            globalRanking = parsed.filter { $0.totalCount > 0 }
            rankingCache[cacheKey] = (rows: parsed, at: Date())
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sync: @Query wearLogs → Supabase (가장 신뢰할 수 있는 경로)

    /// BrandLeagueView 의 @Query wearLogs 를 직접 사용해 모든 브랜드 카운트를 Supabase 에 동기화.
    /// @Query 는 SwiftUI 가 관계를 올바르게 로드하므로 watch?.brand 가 항상 정확.
    /// BrandLeagueView 에서 직접 계산한 (brand, periodType, periodKey, count) 를 업로드.
    /// @Query 관계 traversal 이슈를 뷰 레벨에서 해결 후 primitives 만 전달받음.
    func uploadBrandCounts(_ counts: [(brand: String, type: String, key: String, count: Int)]) async {
        let hash = deviceHash
        for c in counts {
            await upsert(deviceHash: hash, brand: c.brand,
                         periodType: c.type, periodKey: c.key, count: c.count)
        }
        rankingCache.removeAll()
    }

    /// deprecated — 하위 호환용. 실제 업로드는 uploadBrandCounts 사용.
    func syncFromQueryWearLogs(_ wearLogs: [WearLog]) async {
        rankingCache.removeAll()
    }

    /// WearLogService 에서 호출 — @Query 없이 간단 업로드 (fallback).
    func syncAfterWearToggle(watch: Watch, context: ModelContext) {
        // BrandLeagueView 의 syncFromQueryWearLogs 가 더 정확하므로,
        // 여기서는 최소한의 신호만 보냄 — 캐시 무효화로 다음 BrandLeagueView fetch 를 강제.
        rankingCache.removeAll()
    }
}

// MARK: - AnyCodable helper

private struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self)    { value = i; return }
        if let d = try? c.decode(Double.self)  { value = d; return }
        if let s = try? c.decode(String.self)  { value = s; return }
        if let b = try? c.decode(Bool.self)    { value = b; return }
        value = NSNull()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let i as Int:    try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let b as Bool:   try c.encode(b)
        default:              try c.encodeNil()
        }
    }
}
