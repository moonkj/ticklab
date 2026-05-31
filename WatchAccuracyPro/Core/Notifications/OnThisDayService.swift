import Foundation
import SwiftData
import UserNotifications

/// Sprint 13 (F3, Min+감성): "오늘, 그날" 추억 알림.
/// 구매일/첫 측정/첫 착용 기준 N주년이 오늘이면 회상 알림.
/// 데이터 없으면 발송 안 함 (빈 알림 방지).
@MainActor
enum OnThisDayService {
    private static let lastCheckKey = "ticklab.onThisDay.lastCheck"

    /// 앱 활성화 시 1일 1회 호출 — 오늘이 어떤 시계의 기념일인지 검사 후 즉시 알림.
    static func checkAndNotify(watches: [Watch], wearLogs: [WearLog]) {
        // 하루 1회 제한
        let today = Calendar.current.startOfDay(for: Date())
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let last, Calendar.current.isDate(last, inSameDayAs: today) { return }

        Task {
            guard await NotificationService.requestAuthorizationIfNeeded() else { return }
            guard let memory = findTodayMemory(watches: watches, wearLogs: wearLogs) else {
                UserDefaults.standard.set(today, forKey: lastCheckKey)
                return
            }
            await fire(memory)
            UserDefaults.standard.set(today, forKey: lastCheckKey)
        }
    }

    private struct Memory {
        let watch: Watch
        let years: Int
        let kind: String   // "purchase" | "first_wear"
    }

    private static func findTodayMemory(watches: [Watch], wearLogs: [WearLog]) -> Memory? {
        let cal = Calendar.current
        let now = Date()
        let (tMonth, tDay) = (cal.component(.month, from: now), cal.component(.day, from: now))

        // 구매일 N주년 (1년 이상)
        for w in watches {
            guard let pd = w.purchaseDate else { continue }
            let m = cal.component(.month, from: pd), d = cal.component(.day, from: pd)
            let years = cal.component(.year, from: now) - cal.component(.year, from: pd)
            if m == tMonth && d == tDay && years >= 1 {
                return Memory(watch: w, years: years, kind: "purchase")
            }
        }
        // 첫 착용 N주년
        let firstWearByWatch: [UUID: Date] = Dictionary(
            wearLogs.compactMap { log -> (UUID, Date)? in
                guard let id = log.watch?.id else { return nil }
                return (id, log.date)
            },
            uniquingKeysWith: { min($0, $1) }
        )
        for w in watches {
            guard let fw = firstWearByWatch[w.id] else { continue }
            let m = cal.component(.month, from: fw), d = cal.component(.day, from: fw)
            let years = cal.component(.year, from: now) - cal.component(.year, from: fw)
            if m == tMonth && d == tDay && years >= 1 {
                return Memory(watch: w, years: years, kind: "first_wear")
            }
        }
        return nil
    }

    private static func fire(_ memory: Memory) async {
        let content = UNMutableNotificationContent()
        let name = memory.watch.nickname ?? "\(memory.watch.brand) \(memory.watch.model)"
        content.title = String(localized: "notif.onthisday.title")
        let bodyKey = memory.kind == "purchase"
            ? "notif.onthisday.purchase"
            : "notif.onthisday.first_wear"
        content.body = String(format: NSLocalizedString(bodyKey, comment: ""), memory.years, name)
        content.sound = .default
        content.userInfo = ["watchID": memory.watch.id.uuidString]

        // 즉시 발송 (오늘 검사 시점)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "onthisday-\(memory.watch.id.uuidString)",
                                            content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
