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
            guard await requestAuthorizationIfNeeded() else {
                #if DEBUG
                print("⚠️ scheduleWindReminder: 권한 거부 — skip (\(watch.brand) \(watch.model))")
                #endif
                return
            }
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
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                #if DEBUG
                print("⚠️ scheduleWindReminder add failed: \(error)")
                #endif
            }
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
            guard await requestAuthorizationIfNeeded() else {
                #if DEBUG
                print("⚠️ scheduleBatteryReminder: 권한 거부 — skip (\(watch.brand) \(watch.model))")
                #endif
                return
            }
            let cal = Calendar.current
            // Round 1-2 (Jay 사용자 보고 후속): 이전 구현은 warn(=due-7d) vs (오늘+60s) max 후
            //   comps.hour=9 강제 → 오늘 09:00 (이미 지남) 으로 해석되어 trigger 거부되던 버그.
            //   수정: 9시 fire 시각을 같은 day-anchor 로 명시적으로 build 후 (이미 지났으면) 내일로 push.
            let warnDay = cal.date(byAdding: .day, value: -7, to: due) ?? due
            var fireComps = cal.dateComponents([.year, .month, .day], from: warnDay)
            fireComps.hour = 9
            fireComps.minute = 0
            var fire = cal.date(from: fireComps) ?? warnDay
            if fire <= Date() {
                // warn 일이 이미 지났거나 09:00 도 지남 → 내일 09:00.
                fire = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))?
                    .addingTimeInterval(9 * 3600) ?? Date().addingTimeInterval(60)
            }
            let trigComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)

            let content = UNMutableNotificationContent()
            content.title = String(format: NSLocalizedString("notif.battery.title", comment: ""),
                                   watch.nickname ?? "\(watch.brand) \(watch.model)")
            content.body = String(format: NSLocalizedString("notif.battery.body_prefix", comment: ""), NotificationService.shortDate(due))
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: trigComps, repeats: false)
            let request = UNNotificationRequest(identifier: batteryID(watch), content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(request)
                #if DEBUG
                print("ℹ️ scheduleBatteryReminder: \(watch.brand) at \(fire)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ scheduleBatteryReminder add failed: \(error)")
                #endif
            }
        }
    }

    static func cancelBatteryReminder(for watch: Watch) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [batteryID(watch)])
    }

    private static func shortDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    // MARK: - Random pick (랜덤 시계 뽑기)

    /// 다음 번 fire 시각에 등록된 시계 중 하나를 랜덤으로 뽑아 단발 알림 예약.
    /// 사용자가 해당 알림을 보거나 앱을 다시 열 때 reschedule 호출하여 다음 날 재예약.
    static func scheduleRandomPick(watches: [Watch], hour: Int, minute: Int, enabled: Bool) {
        cancelRandomPick()
        // Round 19 (사용자 보고: "오늘의 시계 뽑기 알람 안 옴"):
        //   이전 조건 `watches.count >= 2` → 시계 1개 사용자는 알람 silently dropped.
        //   1개라도 그 시계로 알림 의미 있음 (선택지가 1개일 뿐).
        guard enabled, !watches.isEmpty else { return }
        guard let pick = watches.randomElement() else { return }
        Task {
            guard await requestAuthorizationIfNeeded() else {
                #if DEBUG
                print("⚠️ scheduleRandomPick: 권한 거부 — 알림 등록 skip.")
                #endif
                return
            }
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
            do {
                try await UNUserNotificationCenter.current().add(request)
                #if DEBUG
                print("ℹ️ scheduleRandomPick: \(pick.brand) \(pick.model) at \(fire)")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ scheduleRandomPick add failed: \(error)")
                #endif
            }
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
            guard await requestAuthorizationIfNeeded() else {
                #if DEBUG
                print("⚠️ scheduleJournalReminder: 권한 거부 — skip")
                #endif
                return
            }
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("notif.journal.title", comment: "")
            content.body = NSLocalizedString("notif.journal.body", comment: "")
            content.sound = .default
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: journalReminderID, content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                #if DEBUG
                print("⚠️ scheduleJournalReminder add failed: \(error)")
                #endif
            }
        }
    }

    static func cancelJournalReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [journalReminderID])
    }

    // MARK: - Overhaul reminder (오버홀 정비 알림)

    private static func overhaulID(_ watch: Watch) -> String { "overhaul-\(watch.id.uuidString)" }

    /// 시계 1개에 대해 오버홀 알림 스케줄.
    /// 알림 시점 = lastOverhaulDate(또는 createdAt) + (years*365 - 180) 일 @ 09:00 local.
    /// 사용자 설정: 6개월 전 사전 안내 1회.
    /// quartz 제외 (battery service 가 다름).
    static func scheduleOverhaulReminder(for watch: Watch, lastOverhaulDate: Date, years: Int, enabled: Bool) {
        guard enabled, watch.movementType != .quartz else {
            cancelOverhaulReminder(for: watch)
            return
        }
        // 권장일 = lastOverhaulDate + years 년. 알림은 6개월 전.
        let cal = Calendar.current
        guard let dueDate = cal.date(byAdding: .year, value: years, to: lastOverhaulDate),
              let notifyDate = cal.date(byAdding: .month, value: -6, to: dueDate)
        else { return }
        // 과거 시점이면 알림 안 의미 — 이미 지난 권장일은 7일 후 1회 발송 (사용자가 등록 후 즉시 인지).
        let fireDate = notifyDate < Date() ? cal.date(byAdding: .day, value: 7, to: Date()) ?? Date() : notifyDate
        // 9시 정각으로 보정.
        var comps = cal.dateComponents([.year, .month, .day], from: fireDate)
        comps.hour = 9
        comps.minute = 0
        guard let finalFire = cal.date(from: comps), finalFire > Date() else {
            cancelOverhaulReminder(for: watch)
            return
        }
        Task {
            guard await requestAuthorizationIfNeeded() else { return }
            let content = UNMutableNotificationContent()
            let watchName = watch.nickname ?? "\(watch.brand) \(watch.model)"
            content.title = String(format: NSLocalizedString("notif.overhaul.title", comment: ""), watchName)
            content.body = String(format: NSLocalizedString("notif.overhaul.body", comment: ""), shortDate(dueDate))
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: finalFire),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: overhaulID(watch), content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelOverhaulReminder(for watch: Watch) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [overhaulID(watch)])
    }

    /// 모든 시계에 대해 오버홀 알림 일괄 (re-)schedule. App launch / Settings 변경 / ServiceLog 변경 시 호출.
    static func rescheduleAllOverhaulReminders(watches: [Watch], years: Int, enabled: Bool, in context: ModelContext) {
        for watch in watches {
            let lastDate = lastOverhaulDate(for: watch, in: context) ?? watch.createdAt
            scheduleOverhaulReminder(for: watch, lastOverhaulDate: lastDate, years: years, enabled: enabled)
        }
    }

    /// 시계의 마지막 fullOverhaul ServiceLog timestamp. 없으면 nil → caller 가 createdAt fallback.
    static func lastOverhaulDate(for watch: Watch, in context: ModelContext) -> Date? {
        let watchId = watch.id
        let overhaulRaw = ServiceType.fullOverhaul.rawValue
        let descriptor = FetchDescriptor<ServiceLog>(
            predicate: #Predicate { log in
                log.watch?.id == watchId && log.typeRaw == overhaulRaw
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first?.timestamp
    }
}

/// Round 19 (사용자 보고): foreground 일 때 알림 banner 가 표시 안 됨 — iOS 기본 동작.
///   UNUserNotificationCenterDelegate.willPresent 에서 `.banner + .sound` 반환해야 노출됨.
///   App init 시 한 번 등록.
final class TickLabNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TickLabNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
