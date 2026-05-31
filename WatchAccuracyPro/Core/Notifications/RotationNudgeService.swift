import EventKit
import Foundation
import UserNotifications

/// Sprint 7 (P2-14): 개인화 시계 로테이션 넛지.
///
/// 날씨(WeatherKit) 대신 요일/시간 기반 컨텍스트 + EventKit 오늘 일정 으로 추천.
/// WeatherKit entitlement 없이도 동작 — 방수 등급은 시계 스펙(caliber/movementType)으로 판단.
@MainActor
enum RotationNudgeService {
    private static let eventStore = EKEventStore()

    // MARK: - 로테이션 넛지 알림 예약

    /// 마지막 착용 후 N일 경과한 시계 있으면 다음날 아침 9시 알림 예약.
    static func scheduleIfNeeded(watches: [Watch], wearLogs: [WearLog], nudgeDays: Int = 7) {
        guard !watches.isEmpty else { return }
        Task {
            guard await NotificationService.requestAuthorizationIfNeeded() else { return }

            let today = Calendar.current.startOfDay(for: Date())
            let lastWornByWatch: [UUID: Date] = Dictionary(
                wearLogs.compactMap { log -> (UUID, Date)? in
                    guard let id = log.watch?.id else { return nil }
                    return (id, log.date)
                },
                uniquingKeysWith: { max($0, $1) }
            )

            // 오늘 착용 중인 시계 제외
            let wornToday = Set(wearLogs.filter {
                Calendar.current.startOfDay(for: $0.date) == today
            }.compactMap { $0.watch?.id })

            let longUnworn = watches.filter { w in
                guard !wornToday.contains(w.id) else { return false }
                let last = lastWornByWatch[w.id] ?? .distantPast
                let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
                return days >= nudgeDays
            }

            guard let pick = longUnworn.randomElement() else { return }
            await scheduleNudge(for: pick)
        }
    }

    private static func scheduleNudge(for watch: Watch) async {
        let id = "rotation-nudge-\(watch.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])

        // 내일 아침 9시
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) else { return }
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = 9; comps.minute = 0
        guard let fire = cal.date(from: comps), fire > Date() else { return }

        // EventKit에서 내일 일정 확인 → 포멀 이벤트 있으면 고급 시계 추천 문구
        let hasFormailEvent = await checkFormalEvent(on: tomorrow)
        let bodyKey = hasFormailEvent
            ? "notif.rotation.body_formal"
            : "notif.rotation.body_standard"

        let content = UNMutableNotificationContent()
        content.title = String(format: NSLocalizedString("notif.rotation.title", comment: ""),
                               watch.nickname ?? "\(watch.brand) \(watch.model)")
        content.body = String(localized: String.LocalizationValue(bodyKey))
        content.sound = .default
        content.userInfo = ["watchID": watch.id.uuidString]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - EventKit 포멀 일정 감지

    /// 내일 캘린더에 "미팅", "발표", "결혼", "행사" 등 포멀 키워드가 있으면 true.
    private static func checkFormalEvent(on date: Date) async -> Bool {
        // 권한 없으면 false (강제 요청 안 함 — 착용 기록 시 따로 요청)
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .writeOnly else { return false }

        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let formalKeywords = ["미팅", "발표", "회의", "결혼", "행사", "파티", "dinner", "meeting",
                              "presentation", "ceremony", "wedding", "interview", "conference"]
        return events.contains { event in
            let title = (event.title ?? "").lowercased()
            return formalKeywords.contains { title.contains($0) }
        }
    }

    // MARK: - EventKit 권한 요청

    static func requestCalendarAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return true }
        guard status == .notDetermined else { return false }
        return (try? await eventStore.requestFullAccessToEvents()) ?? false
    }
}
