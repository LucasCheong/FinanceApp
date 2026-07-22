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

    // MARK: - 清除所有通知
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
