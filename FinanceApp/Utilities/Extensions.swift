import SwiftUI
import Foundation

// MARK: - Double 格式化擴展
extension Double {
    /// 格式化為貨幣顯示
    func currencyString(currency: String = "HKD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: "zh_HK")
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// 格式化為百分比顯示
    func percentString() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self / 100)) ?? "\(self)%"
    }

    /// 格式化為簡潔數字
    func compactString() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// 格式化為收益率百分比（如 0.055 -> "5.50%"）
    func yieldPercent() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "\(self * 100)%"
    }
}

// MARK: - Date 格式化擴展
extension Date {
    func formatted(as format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "zh_Hant")
        return formatter.string(from: self)
    }

    var shortDateString: String {
        formatted(as: "yyyy-MM-dd")
    }

    var dateTimeString: String {
        formatted(as: "yyyy-MM-dd HH:mm")
    }

    var monthString: String {
        formatted(as: "yyyy年MM月")
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isThisMonth: Bool {
        let calendar = Calendar.current
        let now = Date()
        return calendar.component(.year, from: self) == calendar.component(.year, from: now) &&
               calendar.component(.month, from: self) == calendar.component(.month, from: now)
    }
}

// MARK: - Color 擴展
extension Color {
    static let gain = Color.green
    static let loss = Color.red
    static let neutral = Color.gray
    static let financePrimary = Color(red: 0.0, green: 0.5, blue: 0.8)
    static let financeSecondary = Color(red: 0.2, green: 0.6, blue: 0.9)
    static let cardBackground = Color(.secondarySystemBackground)
    static let incomeColor = Color.green
    static let expenseColor = Color.orange

    /// 根據漲跌返回顏色
    static func changeColor(_ value: Double) -> Color {
        if value > 0 { return .gain }
        if value < 0 { return .loss }
        return .neutral
    }
}

// MARK: - View 擴展
extension View {
    /// 卡片樣式修飾符
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    /// 根據條件隱藏視圖
    @ViewBuilder
    func isHidden(_ hidden: Bool) -> some View {
        if hidden {
            self.hidden()
        } else {
            self
        }
    }
}

// MARK: - 財富計算輔助
extension Array where Element == Transaction {
    var monthlyIncome: Double {
        filter { $0.type == .income && $0.date.isThisMonth }.reduce(0) { $0 + $1.amount }
    }

    var monthlyExpense: Double {
        filter { $0.type == .expense && $0.date.isThisMonth }.reduce(0) { $0 + $1.amount }
    }

    var monthlyBalance: Double {
        monthlyIncome - monthlyExpense
    }
}
