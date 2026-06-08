import Foundation
import SwiftData

/// Sprint 4 (P2-17): TickLab Wrapped 연간 리포트 데이터 계산.
/// 뷰 독립 — 순수 데이터 레이어. UI 는 WrappedView 에서 담당.
///
/// Round 174 (UX 재설계): Spotify Wrapped 급 스토리텔링을 위해 페르소나 도출 항목 추가.
/// - 컬렉터: brandCount / 컬렉션 가치 변화 → newWatchesAdded(영입)
/// - 데이터 너드: totalWearDays / busiestMonth / topWeekday / longestStreak
/// - 워치메이커: bestAccuracyWatch / coscPassCount / avgRate
/// - 캐주얼: highlightCount / topTag / tagBreakdown
/// SwiftData @Model 스키마는 변경 금지 — 전부 읽기 집계.
@MainActor
struct WrappedReportData {
    let year: Int
    let totalWears: Int
    let mostWornWatch: (watch: Watch, count: Int)?
    let leastWornWatch: (watch: Watch, count: Int)?
    let totalMeasurements: Int
    let avgRateSecondsPerDay: Double?
    let newWatchesAdded: Int
    let topTag: String?
    let highlightCount: Int

    // MARK: - Round 174 신규 집계 필드 (읽기 전용)

    /// 올해 착용 기록이 있는 고유한 날의 수 (= "시계 찬 날").
    let totalWearDays: Int
    /// 가장 많이 착용한 브랜드 (다양성/취향 시그널). (brand, count).
    let topBrand: (name: String, count: Int)?
    /// 올해 착용 기록에 등장한 고유 브랜드 수.
    let brandCount: Int
    /// 가장 자주 착용한 요일 (1=일 ... 7=토, Calendar.component(.weekday)) + 그 횟수.
    let topWeekday: (weekday: Int, count: Int)?
    /// 가장 바빴던 달 (1...12) + 그 달 착용 횟수.
    let busiestMonth: (month: Int, count: Int)?
    /// 가장 길게 이어진 연속 착용일(streak) 길이.
    let longestStreak: Int
    /// 가장 정확했던 시계 — 측정 평균 rate 의 절댓값이 가장 작은 시계. (watch, avgRate).
    let bestAccuracyWatch: (watch: Watch, avgRate: Double)?
    /// COSC 밴드(-4 ~ +6 s/d) 안에 든 측정 건수.
    let coscPassCount: Int
    /// 태그별 착용 횟수 — 상위 비중 시각화용. 내림차순 정렬.
    let tagBreakdown: [(tag: String, count: Int)]

    // MARK: - 스트림 D: 측정 품질 (읽기 전용 집계)

    /// 올해 측정품질 점수(0~100). confidence 평균과 COSC 통과율을 가중 합산.
    /// 측정이 없으면 nil. (measurementQualityScore = 0.6·avgConfidence + 0.4·(coscPass%))
    let measurementQualityScore: Int?
    /// 연간 정확도 개선(s/d) — 전반기 평균 |rate| − 후반기 평균 |rate|. +면 개선(오차 감소).
    /// 양쪽 반기 모두 측정이 있어야 산출, 아니면 nil.
    let accuracyImprovement: Double?

    static func generate(year: Int, context: ModelContext) -> WrappedReportData {
        let cal = Calendar.current
        guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return empty(year: year)
        }

        // 착용 기록
        let wearDesc = FetchDescriptor<WearLog>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let wears = (try? context.fetch(wearDesc)) ?? []
        let totalWears = wears.count

        // 시계별 착용 수
        var wearByWatch: [UUID: (Watch, Int)] = [:]
        for log in wears {
            guard let w = log.watch else { continue }
            wearByWatch[w.id] = (w, (wearByWatch[w.id]?.1 ?? 0) + 1)
        }
        // 동률 시 deterministic — id 2차 정렬(딕셔너리 순서 불안정으로 결과가 매번 바뀌던 문제).
        let sorted = wearByWatch.values.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id.uuidString < $1.0.id.uuidString }
        let mostWorn  = sorted.first.map { (watch: $0.0, count: $0.1) }
        let leastWorn = sorted.last.map  { (watch: $0.0, count: $0.1) }

        // 측정
        let measDesc = FetchDescriptor<WatchMeasurement>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
        )
        let meas = (try? context.fetch(measDesc)) ?? []
        let avgRate: Double? = meas.isEmpty ? nil
            : meas.map(\.rateSecondsPerDay).reduce(0, +) / Double(meas.count)

        // 신규 시계
        let watchDesc = FetchDescriptor<Watch>(predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end })
        let newWatches = (try? context.fetchCount(watchDesc)) ?? 0

        // 태그 집계
        let allTags = wears.flatMap { $0.tags }
        let tagCounts = Dictionary(allTags.map { ($0, 1) }, uniquingKeysWith: +)
        let topTag = tagCounts.max(by: { $0.value < $1.value })?.key
        let tagBreakdown = tagCounts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        // 하이라이트
        let highlights = wears.filter { $0.isHighlight }.count

        // MARK: - 데이터 너드 집계

        // 고유 착용일 (date 는 startOfDay 로 normalize 되어 저장됨).
        let wearDates = Set(wears.map { cal.startOfDay(for: $0.date) })
        let totalWearDays = wearDates.count

        // 요일별 — 1(일)...7(토).
        var weekdayCounts: [Int: Int] = [:]
        for log in wears {
            let wd = cal.component(.weekday, from: log.date)
            weekdayCounts[wd, default: 0] += 1
        }
        let topWeekday = weekdayCounts.max(by: { $0.value < $1.value }).map { (weekday: $0.key, count: $0.value) }

        // 월별 — 1...12.
        var monthCounts: [Int: Int] = [:]
        for log in wears {
            let m = cal.component(.month, from: log.date)
            monthCounts[m, default: 0] += 1
        }
        let busiestMonth = monthCounts.max(by: { $0.value < $1.value }).map { (month: $0.key, count: $0.value) }

        // 최장 연속 착용일 streak.
        let longestStreak = Self.longestConsecutiveRun(dates: wearDates, calendar: cal)

        // MARK: - 컬렉터 집계 (브랜드 다양성)

        var brandCounts: [String: Int] = [:]
        for (_, value) in wearByWatch {
            let brand = value.0.brand
            brandCounts[brand, default: 0] += value.1
        }
        let topBrand = brandCounts.max(by: { $0.value < $1.value }).map { (name: $0.key, count: $0.value) }
        let brandCount = brandCounts.count

        // MARK: - 워치메이커 집계 (정확도)

        // 시계별 평균 rate → 절댓값 최소 = 가장 정확한 시계.
        var rateByWatch: [UUID: (Watch, [Double])] = [:]
        for m in meas {
            guard let w = m.watch else { continue }
            rateByWatch[w.id, default: (w, [])].1.append(m.rateSecondsPerDay)
        }
        let avgByWatch: [(watch: Watch, avgRate: Double)] = rateByWatch.values.map {
            (watch: $0.0, avgRate: $0.1.reduce(0, +) / Double($0.1.count))
        }
        // 동률(|avgRate| 같음) 시 deterministic — id 2차(딕셔너리 순서 불안정으로 결과 흔들림 방지).
        let bestAccuracy = avgByWatch.min { a, b in
            let da = abs(a.avgRate), db = abs(b.avgRate)
            return da != db ? da < db : a.watch.id.uuidString < b.watch.id.uuidString
        }

        // COSC 밴드(-4 ~ +6 s/d) 통과 측정 건수. (UI/Components/COSCBar SSOT 와 동일 범위.)
        let coscPassCount = meas.filter { $0.rateSecondsPerDay >= -4 && $0.rateSecondsPerDay <= 6 }.count

        // MARK: - 스트림 D: 측정 품질 점수 + 연간 정확도 개선

        // 품질 점수: confidence 평균(0~100) 60% + COSC 통과율(0~100) 40%. 측정 없으면 nil.
        let qualityScore: Int? = {
            guard !meas.isEmpty else { return nil }
            let avgConfidence = Double(meas.map(\.confidenceScore).reduce(0, +)) / Double(meas.count)
            let coscRate = Double(coscPassCount) / Double(meas.count) * 100.0
            let score = 0.6 * avgConfidence + 0.4 * coscRate
            return Int(min(100, max(0, score.rounded())))
        }()

        // 정확도 개선: 올해를 시간순 정렬해 전반/후반 반으로 나눠 평균 |rate| 차이.
        let accuracyImprovement: Double? = {
            let sortedMeas = meas.sorted { $0.timestamp < $1.timestamp }
            guard sortedMeas.count >= 4 else { return nil }
            let mid = sortedMeas.count / 2
            let firstHalf = sortedMeas.prefix(mid)
            let secondHalf = sortedMeas.suffix(sortedMeas.count - mid)
            guard !firstHalf.isEmpty, !secondHalf.isEmpty else { return nil }
            let firstAbs = firstHalf.map { abs($0.rateSecondsPerDay) }.reduce(0, +) / Double(firstHalf.count)
            let secondAbs = secondHalf.map { abs($0.rateSecondsPerDay) }.reduce(0, +) / Double(secondHalf.count)
            return firstAbs - secondAbs   // + 면 오차 감소 = 개선.
        }()

        return WrappedReportData(
            year: year,
            totalWears: totalWears,
            mostWornWatch: mostWorn,
            leastWornWatch: leastWorn,
            totalMeasurements: meas.count,
            avgRateSecondsPerDay: avgRate,
            newWatchesAdded: newWatches,
            topTag: topTag,
            highlightCount: highlights,
            totalWearDays: totalWearDays,
            topBrand: topBrand,
            brandCount: brandCount,
            topWeekday: topWeekday,
            busiestMonth: busiestMonth,
            longestStreak: longestStreak,
            bestAccuracyWatch: bestAccuracy,
            coscPassCount: coscPassCount,
            tagBreakdown: tagBreakdown,
            measurementQualityScore: qualityScore,
            accuracyImprovement: accuracyImprovement
        )
    }

    /// 날짜 집합에서 가장 긴 "연속된 하루 간격" run 길이를 계산. (정렬 후 1일 차이 누적.)
    private static func longestConsecutiveRun(dates: Set<Date>, calendar: Calendar) -> Int {
        guard !dates.isEmpty else { return 0 }
        let sorted = dates.sorted()
        var longest = 1
        var current = 1
        for i in 1..<sorted.count {
            let gap = calendar.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            if gap == 1 {
                current += 1
                longest = max(longest, current)
            } else if gap == 0 {
                continue   // 같은 날 중복 — run 유지.
            } else {
                current = 1
            }
        }
        return longest
    }

    private static func empty(year: Int) -> WrappedReportData {
        WrappedReportData(
            year: year, totalWears: 0, mostWornWatch: nil, leastWornWatch: nil,
            totalMeasurements: 0, avgRateSecondsPerDay: nil,
            newWatchesAdded: 0, topTag: nil, highlightCount: 0,
            totalWearDays: 0, topBrand: nil, brandCount: 0,
            topWeekday: nil, busiestMonth: nil, longestStreak: 0,
            bestAccuracyWatch: nil, coscPassCount: 0, tagBreakdown: [],
            measurementQualityScore: nil, accuracyImprovement: nil
        )
    }
}
