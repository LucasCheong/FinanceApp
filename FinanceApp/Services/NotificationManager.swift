import Foundation
import UserNotifications

/// 本地通知管理器 - 均線突破/跌破提醒
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - 請求通知權限
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("通知權限請求失敗: \(error.localizedDescription)")
            }
            if granted {
                print("通知權限已授予")
            } else {
                print("通知權限被拒絕")
            }
        }
    }

    // MARK: - 檢查信號並發送通知
    func checkAndNotifySignals(_ signals: [MovingAverageSignal]) {
        let actionableSignals = signals.filter { $0.isActionable }

        for signal in actionableSignals {
            switch signal.signalType {
            case .buyBreakout:
                sendBuySignalNotification(signal)
            case .sellBreakdown:
                sendSellSignalNotification(signal)
            default:
                break
            }
        }
    }

    // MARK: - 買入信號通知
    private func sendBuySignalNotification(_ signal: MovingAverageSignal) {
        let content = UNMutableNotificationContent()
        content.title = "📈 買入信號：\(signal.symbol)"
        content.body = "\(signal.name) 突破10日均線！\n當前價格：\(signal.currentPrice.compactString())\nMA10：\(signal.ma10.compactString())\n距離MA10：+\(String(format: "%.2f%%", signal.distanceToMA10))"
        content.sound = .default
        content.badge = 1

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "buy_signal_\(signal.symbol)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("發送買入通知失敗: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 賣出信號通知
    private func sendSellSignalNotification(_ signal: MovingAverageSignal) {
        let content = UNMutableNotificationContent()
        content.title = "📉 賣出信號：\(signal.symbol)"
        content.body = "\(signal.name) 跌破20日均線！\n當前價格：\(signal.currentPrice.compactString())\nMA20：\(signal.ma20.compactString())\n距離MA20：\(String(format: "%.2f%%", signal.distanceToMA20))"
        content.sound = .default
        content.badge = 1

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "sell_signal_\(signal.symbol)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("發送賣出通知失敗: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 信用卡還款提醒
    private static let creditCardReminderPrefix = "credit_card_payment_"
    private static let creditCardReminderIdsKey = "creditCardPaymentReminderIds"
    private static let creditCardReminderLimit = 60

    /// 重新建立所有已啟用的信用卡還款提醒。每張卡最多排程未來 12 個月，
    /// 並按系統 64 個待處理通知的上限預留空間給其他通知。
    func syncCreditCardPaymentReminders(for accounts: [Account]) {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        let previousIdentifiers = defaults.stringArray(forKey: Self.creditCardReminderIdsKey) ?? []
        center.removePendingNotificationRequests(withIdentifiers: previousIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: previousIdentifiers)

        let creditCards = accounts.filter {
            $0.type == .creditCard
                && !$0.isArchived
                && $0.paymentReminderEnabled == true
        }
        guard !creditCards.isEmpty else {
            defaults.removeObject(forKey: Self.creditCardReminderIdsKey)
            return
        }

        requestAuthorization()
        let remindersPerCard = max(1, min(12, Self.creditCardReminderLimit / creditCards.count))
        var scheduledIdentifiers: [String] = []

        for account in creditCards {
            let remainingCapacity = Self.creditCardReminderLimit - scheduledIdentifiers.count
            guard remainingCapacity > 0 else { break }
            let occurrenceCount = min(remindersPerCard, remainingCapacity)

            for occurrence in upcomingPaymentReminders(
                dueDay: account.effectivePaymentDueDay,
                daysBefore: account.effectivePaymentReminderDaysBefore,
                count: occurrenceCount
            ) {
                let content = UNMutableNotificationContent()
                content.title = "💳 信用卡還款提醒"
                content.body = "\(account.selectionDisplayName) 將於 \(occurrence.dueMonth) 月 \(occurrence.dueDay) 日到期，請確認待還結欠。"
                content.sound = .default

                let identifier = Self.creditCardReminderPrefix
                    + account.id.uuidString
                    + "_\(occurrence.dueYear)_\(occurrence.dueMonth)"
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: occurrence.reminderDate
                    ),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )
                center.add(request) { error in
                    if let error {
                        print("設定信用卡還款提醒失敗: \(error.localizedDescription)")
                    }
                }
                scheduledIdentifiers.append(identifier)
            }
        }

        defaults.set(scheduledIdentifiers, forKey: Self.creditCardReminderIdsKey)
    }

    /// 依每個月實際天數計算還款日；例如設定 31 日時，二月會改用該月最後一天。
    private func upcomingPaymentReminders(
        dueDay: Int,
        daysBefore: Int,
        count: Int
    ) -> [(reminderDate: Date, dueYear: Int, dueMonth: Int, dueDay: Int)] {
        let calendar = Calendar.current
        let now = Date()
        var startComponents = calendar.dateComponents([.year, .month], from: now)
        startComponents.day = 1
        startComponents.hour = 9
        startComponents.minute = 0
        guard let currentMonth = calendar.date(from: startComponents) else { return [] }

        var reminders: [(Date, Int, Int, Int)] = []
        var monthOffset = 0
        while reminders.count < count && monthOffset < count + 2 {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: currentMonth),
                  let dayRange = calendar.range(of: .day, in: .month, for: month)
            else {
                monthOffset += 1
                continue
            }

            let monthParts = calendar.dateComponents([.year, .month], from: month)
            let actualDueDay = min(max(1, dueDay), dayRange.count)
            var dueComponents = DateComponents()
            dueComponents.calendar = calendar
            dueComponents.timeZone = calendar.timeZone
            dueComponents.year = monthParts.year
            dueComponents.month = monthParts.month
            dueComponents.day = actualDueDay
            dueComponents.hour = 9
            dueComponents.minute = 0

            if let dueDate = calendar.date(from: dueComponents),
               let reminderDate = calendar.date(byAdding: .day, value: -max(0, daysBefore), to: dueDate),
               reminderDate > now,
               let year = monthParts.year,
               let monthNumber = monthParts.month {
                reminders.append((reminderDate, year, monthNumber, actualDueDay))
            }
            monthOffset += 1
        }
        return reminders
    }

    // MARK: - 清除所有通知
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UserDefaults.standard.removeObject(forKey: Self.creditCardReminderIdsKey)
    }

    // MARK: - 每週記帳提醒
    static let weeklyReminderId = "weekly_accounting_reminder"

    /// 設定每週記帳提醒（weekday: 1=星期日 … 7=星期六）
    func scheduleWeeklyReminder(weekday: Int, hour: Int, minute: Int = 0) {
        requestAuthorization()

        let content = UNMutableNotificationContent()
        content.title = "📝 記帳提醒"
        content.body = "本週還未記帳哦，花一分鐘記錄一下開支吧！"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.weeklyReminderId, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("設定每週提醒失敗: \(error.localizedDescription)")
            } else {
                print("每週提醒已設定：星期\(weekday) \(hour):\(String(format: "%02d", minute))")
            }
        }
    }

    /// 取消每週記帳提醒
    func cancelWeeklyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyReminderId])
    }
}
