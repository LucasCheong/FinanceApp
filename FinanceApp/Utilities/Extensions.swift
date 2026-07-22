import SwiftUI
import Foundation

// MARK: - Double 格式化擴展
extension Double {
    /// 格式化為貨幣顯示（用 String 幣種代碼）
    func currencyString(currency: String = "HKD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: "zh_HK")
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// 格式化為貨幣顯示（用 Currency 枚舉）
    func currencyString(currency: Currency) -> String {
        currencyString(currency: currency.code)
    }

    /// 帶幣種符號的簡潔顯示（如 "HK$1,234.56"）
    func moneyString(currency: Currency) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let numberStr = formatter.string(from: NSNumber(value: self)) ?? "\(self)"
        return "\(currency.symbol)\(numberStr)"
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

// MARK: - 匯率轉換工具
enum ExchangeRateProvider {
    /// 預設匯率表（以 HKD 為基準，1 HKD = X 外幣）
    /// 實際使用時應從 API 獲取實時匯率
    static let defaultRates: [Currency: Double] = [
        .hkd: 1.0,
        .usd: 0.128,    // 1 HKD ≈ 0.128 USD
        .cny: 0.92,     // 1 HKD ≈ 0.92 CNY
        .twd: 4.12,     // 1 HKD ≈ 4.12 TWD
        .eur: 0.118,    // 1 HKD ≈ 0.118 EUR
        .gbp: 0.10,     // 1 HKD ≈ 0.10 GBP
        .jpy: 19.8,     // 1 HKD ≈ 19.8 JPY
        .sgd: 0.173,    // 1 HKD ≈ 0.173 SGD
        .aud: 0.196,    // 1 HKD ≈ 0.196 AUD
        .cad: 0.175     // 1 HKD ≈ 0.175 CAD
    ]

    /// 將金額從 from 幣種轉換為 to 幣種
    static func convert(_ amount: Double, from: Currency, to: Currency) -> Double {
        guard from != to else { return amount }
        let fromRate = defaultRates[from] ?? 1.0
        let toRate = defaultRates[to] ?? 1.0
        // 先轉為 HKD 再轉為目標幣種
        let inHKD = amount / fromRate
        return inHKD * toRate
    }
}

// MARK: - Double 跨幣種轉換擴展
extension Double {
    /// 轉換為目標幣種並格式化
    func convertedString(from sourceCurrency: Currency, to targetCurrency: Currency) -> String {
        let converted = ExchangeRateProvider.convert(self, from: sourceCurrency, to: targetCurrency)
        return converted.moneyString(currency: targetCurrency)
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

// MARK: - ShapeStyle 擴展（讓 .foregroundStyle(.financePrimary) 等點語法可用）
extension ShapeStyle where Self == Color {
    static var gain: Color { .green }
    static var loss: Color { .red }
    static var neutral: Color { .gray }
    static var financePrimary: Color { Color(red: 0.0, green: 0.5, blue: 0.8) }
    static var financeSecondary: Color { Color(red: 0.2, green: 0.6, blue: 0.9) }
    static var incomeColor: Color { .green }
    static var expenseColor: Color { .orange }
    static var cardBackground: Color { Color(.secondarySystemBackground) }
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

// MARK: - 財富計算輔助（原始幣種加總，不建議跨幣種使用）
extension Array where Element == Transaction {
    /// 按幣種分組的月度收入
    var monthlyIncomeByCurrency: [Currency: Double] {
        var result: [Currency: Double] = [:]
        for tx in self where tx.type == .income && tx.date.isThisMonth {
            result[tx.currency, default: 0] += tx.amount
        }
        return result
    }

    /// 按幣種分組的月度支出
    var monthlyExpenseByCurrency: [Currency: Double] {
        var result: [Currency: Double] = [:]
        for tx in self where tx.type == .expense && tx.date.isThisMonth {
            result[tx.currency, default: 0] += tx.amount
        }
        return result
    }
}
