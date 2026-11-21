import Foundation
import Observation
import UserNotifications
import KLinguaCore

/// 每日提醒：用 iOS 本機通知（UserNotifications）排程，不經過網路。
///
/// 每次 App 進入背景、或使用者在設定頁更改提醒時，依目前學習狀態重新排「未來 7 天」的單次通知
/// （排程內容由 KLinguaCore 的 ReminderPlanner 決定）。只移除自己排的通知（ID 前綴 klingua.reminder.）。
@MainActor
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    enum Permission { case notDetermined, granted, denied }

    private(set) var permission: Permission = .notDetermined
    /// 最近一次排了幾則通知（設定頁顯示用）
    private(set) var scheduledCount = 0
    /// UI 測試時不碰系統通知
    var disabled = false

    func refreshPermission() async {
        guard !disabled else { return }
        permission = Self.map(await Self.authorizationStatus())
    }

    /// 第一次開啟提醒時才詢問通知權限
    func requestPermission() async -> Bool {
        guard !disabled else { return false }
        let granted = await Self.requestAuthorization()
        await refreshPermission()
        return granted
    }

    /// 依目前學習狀態重新排程。沒有通知權限時只清除舊的通知。
    func reschedule(using store: StudyStore, now: Date = Date()) async {
        guard !disabled else { return }
        let plan = store.reminderPlan(now: now)
        await refreshPermission()
        Self.remove(ids: await Self.pendingReminderIDs())
        guard permission == .granted else {
            scheduledCount = 0
            return
        }
        var added = 0
        for reminder in plan {
            let ok = await Self.add(id: reminder.id, title: reminder.title, body: reminder.body, fireDate: reminder.fireDate)
            if ok { added += 1 }
        }
        scheduledCount = added
    }

    // MARK: - UserNotifications（callback API 包成 nonisolated async，避免跨 actor 傳遞非 Sendable 物件）

    private static func map(_ status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized, .provisional, .ephemeral: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        @unknown default: .denied
        }
    }

    nonisolated private static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { c in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                c.resume(returning: settings.authorizationStatus)
            }
        }
    }

    nonisolated private static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { c in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                c.resume(returning: granted)
            }
        }
    }

    nonisolated private static func pendingReminderIDs() async -> [String] {
        await withCheckedContinuation { c in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                c.resume(returning: requests.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) })
            }
        }
    }

    nonisolated private static func remove(ids: [String]) {
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    nonisolated private static func add(id: String, title: String, body: String, fireDate: Date) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        return await withCheckedContinuation { c in
            UNUserNotificationCenter.current().add(request) { error in
                c.resume(returning: error == nil)
            }
        }
    }
}
