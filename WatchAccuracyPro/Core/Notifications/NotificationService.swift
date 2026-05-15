import Foundation
import SwiftData
import UserNotifications

/// 모든 로컬 알림 — 수동감기 리마인더 / Quartz 배터리 교체 / 랜덤 시계 뽑기 / 일기 리마인더 — 통합 관리.
/// 모든 호출은 main actor 가 아니어도 안전 (UNUserNotificationCenter 는 thread-safe).
enum NotificationService {

    // MARK: - Authorization

    /// 현재 권한 상태 — UI 측에서 빠른 동기 체크용.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 알림 권한 요청. 이미 결정된 경우 그 상태를 그대로 반환.
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    // MARK: - Identifiers

    private static func windID(_ watch: Watch) -> String { "wind-\(watch.id.uuidString)" }
    private static func batteryID(_ watch: Watch) -> String { "battery-\(watch.id.uuidString)" }
    private static let randomPickID = "random-pick"
    private static let journalReminderID = "journal-reminder"

    // MARK: - Manual winding (수동감기) — 매일 반복

    static func scheduleWindReminder(for watch: Watch) {
        guard watch.movementType == .manual, watch.windReminderEnabled else {
            cancelWindReminder(for: watch)
            return
        }
        Task {
            guard await requestAuthorizationIfNeeded() else { return }
            let content = UNMutableNotificationContent()
            // Round 109 (Hard Rule 3 + 아키텍처 C2): 알림 제목도 localize.
            content.title = String(format: NSLocalizedString("notif.wind.title", comment: ""),
                                   watch.nickname ?? "\(watch.brand) \(watch.model)")
            content.body = NSLocalizedString("notif.wind.body", comment: "")
            content.sound = .default

            var date = DateComponents()
            date.hour = watch.windReminderHour
            date.minute = watch.windReminderMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)

            let request = UNNotificationRequest(identifier: windID(watch), content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelWindReminder(for watch: Watch) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [windID(watch)])
    }

    // MARK: - Quartz battery — 1회성 (예상 방전일 1주 전 09:00)

    static func scheduleBatteryReminder(for watch: Watch) {
        guard watch.movementType == .quartz,
              watch.batteryReminderEnabled,
              let due = watch.batteryNextDue else {
            cancelBatteryReminder(for: watch)
            return
        }
        Task {
            guard await requestAuthorizationIfNeeded() else { return }
            let cal = Calendar.current
            // 1주 전 09:00 알림. 이미 지난 날짜라면 내일 09:00.
            let warn = cal.date(byAdding: .day, value: -7, to: due) ?? due
            let fire = max(warn, Date().addingTimeInterval(60))
            var comps = cal.dateComponents([.year, .month, .day], from: fire)
            comps.hour = 9
            comps.minute = 0

            let content = UNMutableNotificationContent()
            content.title = String(format: NSLocalizedString("notif.battery.title", comment: ""),
                                   watch.nickname ?? "\(watch.brand) \(watch.model)")
            content.body = String(format: NSLocalizedString("notif.battery.body_prefix", comment: ""), NotificationService.shortDate(due))
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: batteryID(watch), content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelBatteryReminder(for watch: Watch) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [batteryID(watch)])
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }

    // MARK: - Random pick (랜덤 시계 뽑기)

    /// 다음 번 fire 시각에 등록된 시계 중 하나를 랜덤으로 뽑아 단발 알림 예약.
    /// 사용자가 해당 알림을 보거나 앱을 다시 열 때 reschedule 호출하여 다음 날 재예약.
    static func scheduleRandomPick(watches: [Watch], hour: Int, minute: Int, enabled: Bool) {
        cancelRandomPick()
        guard enabled, watches.count >= 2 else { return }
        guard let pick = watches.randomElement() else { return }
        Task {
            guard await requestAuthorizationIfNeeded() else { return }
            let cal = Calendar.current
            let now = Date()
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = minute
            var fire = cal.date(from: comps) ?? now
            if fire <= now {
                fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire
            }
            let trigComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("notif.random.title", comment: "")
            content.body = String(format: NSLocalizedString("notif.random.body", comment: ""), pick.brand, pick.model)
            content.sound = .default
            content.userInfo = ["watchID": pick.id.uuidString]

            let trigger = UNCalendarNotificationTrigger(dateMatching: trigComps, repeats: false)
            let request = UNNotificationRequest(identifier: randomPickID, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelRandomPick() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [randomPickID])
    }

    // MARK: - Journal reminder (Round 96, 이형준 Critical #3)
    // 매일 저녁 사용자 지정 시각에 일기 작성 reminder.

    /// Round 96: 매일 hour:minute 시각 반복 알림. `enabled = false` 면 취소만.
    static func scheduleJournalReminder(enabled: Bool, hour: Int = 21, minute: Int = 0) {
        cancelJournalReminder()
        guard enabled else { return }
        Task {
            guard await requestAuthorizationIfNeeded() else { return }
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("notif.journal.title", comment: "")
            content.body = NSLocalizedString("notif.journal.body", comment: "")
            content.sound = .default
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: journalReminderID, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelJournalReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [journalReminderID])
    }
}
