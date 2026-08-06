import SwiftUI
import UIKit
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

    /// 帶幣種符號的簡潔顯示（如 "HK$1,234.56"，小數位數可在設定頁調整）
    func moneyString(currency: Currency) -> String {
        let decimals = UserDefaults.standard.object(forKey: "decimalPlaces") as? Int ?? 2
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
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
enum ExchangeRateProvider: @unchecked Sendable {
    /// 預設匯率表（以 HKD 為基準，1 HKD = X 外幣）- 作為離線/失敗時的備用值
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
        .cad: 0.175,    // 1 HKD ≈ 0.175 CAD
        .mop: 1.03      // 1 HKD ≈ 1.03 MOP（澳門幣與港元掛鈎）
    ]

    /// 即時匯率（啟動時從 open.er-api.com 免費 API 拉取）
    private static var liveRates: [Currency: Double]? = loadCachedRates()
    private static var isFetching = false

    /// 匯率快取有效期（可在設定頁調整，單位：小時；0 = 每次啟動都拉取，未設定時預設 24 小時）
    static var updateIntervalHours: Double {
        if let value = UserDefaults.standard.object(forKey: "rateUpdateIntervalHours") as? Double {
            return value
        }
        return 24   // 預設值
    }

    static var cacheMaxAge: TimeInterval {
        updateIntervalHours <= 0 ? 0 : updateIntervalHours * 3600
    }

    /// 目前生效的匯率表（即時 > 快取 > 預設）
    static var currentRates: [Currency: Double] {
        liveRates ?? defaultRates
    }

    /// 是否已載入即時匯率
    static var hasLiveRates: Bool { liveRates != nil }

    /// 即時匯率更新時間
    static var lastUpdateTime: Date? {
        let ts = UserDefaults.standard.double(forKey: "exchangeRatesTimestamp")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    /// 將金額從 from 幣種轉換為 to 幣種
    static func convert(_ amount: Double, from: Currency, to: Currency) -> Double {
        guard from != to else { return amount }
        let rates = currentRates
        let fromRate = rates[from] ?? 1.0
        let toRate = rates[to] ?? 1.0
        // 先轉為 HKD 再轉為目標幣種
        let inHKD = amount / fromRate
        return inHKD * toRate
    }

    /// 拉取即時匯率（免費 API：open.er-api.com，無需 API Key）
    /// 快取 24 小時，force=true 可強制重新拉取
    @MainActor
    static func fetchLiveRates(force: Bool = false) async {
        guard !isFetching else { return }

        // 快取檢查：在設定的更新頻率內不重複拉取
        if !force, cacheMaxAge > 0, let ts = lastUpdateTime,
           Date().timeIntervalSince(ts) < cacheMaxAge, hasLiveRates {
            return
        }

        isFetching = true
        defer { isFetching = false }

        guard let url = URL(string: "https://open.er-api.com/v6/latest/HKD") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? String, result == "success",
                  let ratesJson = json["rates"] as? [String: Double] else {
                print("匯率 API 返回格式異常")
                return
            }

            var newRates: [Currency: Double] = [:]
            for currency in Currency.allCases {
                if let rate = ratesJson[currency.code] {
                    newRates[currency] = rate
                }
            }

            if newRates[.hkd] != nil {
                liveRates = newRates
                cacheRates(newRates)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "exchangeRatesTimestamp")
                NotificationCenter.default.post(name: .exchangeRatesUpdated, object: nil)
                print("即時匯率已更新（\(newRates.count) 個幣種）")
            }
        } catch {
            print("匯率拉取失敗，使用備用匯率: \(error.localizedDescription)")
        }
    }

    // MARK: - 快取存取
    private static func cacheRates(_ rates: [Currency: Double]) {
        // UserDefaults 只支持屬性列表類型，鍵必須轉為 String
        var dict: [String: String] = [:]
        for (currency, rate) in rates {
            dict[currency.code] = String(rate)
        }
        UserDefaults.standard.set(dict, forKey: "exchangeRatesCache")
    }

    private static func loadCachedRates() -> [Currency: Double]? {
        // 更新頻率為「每次啟動」或快取過期則不使用快取
        let maxAge = cacheMaxAge
        if maxAge <= 0 { return nil }
        if let ts = UserDefaults.standard.object(forKey: "exchangeRatesTimestamp") as? Double,
           Date().timeIntervalSince1970 - ts > maxAge {
            return nil
        }
        guard let dict = UserDefaults.standard.dictionary(forKey: "exchangeRatesCache") as? [String: String] else {
            return nil
        }
        var rates: [Currency: Double] = [:]
        for (code, value) in dict {
            if let currency = Currency(rawValue: code), let rate = Double(value) {
                rates[currency] = rate
            }
        }
        return rates.isEmpty ? nil : rates
    }
}

// MARK: - 匯率更新通知
extension Notification.Name {
    static let exchangeRatesUpdated = Notification.Name("exchangeRatesUpdated")
}

// MARK: - Double 跨幣種轉換擴展
extension Double {
    /// 轉換為目標幣種並格式化
    func convertedString(from sourceCurrency: Currency, to targetCurrency: Currency) -> String {
        let converted = ExchangeRateProvider.convert(self, from: sourceCurrency, to: targetCurrency)
        return converted.moneyString(currency: targetCurrency)
    }
}

// MARK: - 觸覺反饋工具（可在設定頁開關）
enum Haptics {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    /// 成功反饋（記帳成功、解鎖成功等）
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 輕觸反饋（按鈕點擊、切換等）
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// 警告反饋（警報觸發、超預算等）
    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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

    var timeString: String {
        formatted(as: "HH:mm:ss")
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
