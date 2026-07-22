import Foundation

// MARK: - 幣種枚舉
enum Currency: String, Codable, CaseIterable, Hashable {
    case hkd = "HKD"
    case usd = "USD"
    case cny = "CNY"
    case twd = "TWD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case sgd = "SGD"
    case aud = "AUD"
    case cad = "CAD"

    /// 顯示名稱（含符號）
    var displayName: String {
        switch self {
        case .hkd: return "🇭🇰 港元 (HKD)"
        case .usd: return "🇺🇸 美元 (USD)"
        case .cny: return "🇨🇳 人民幣 (CNY)"
        case .twd: return "🇹🇼 新台幣 (TWD)"
        case .eur: return "🇪🇺 歐元 (EUR)"
        case .gbp: return "🇬🇧 英鎊 (GBP)"
        case .jpy: return "🇯🇵 日圓 (JPY)"
        case .sgd: return "🇸🇬 新加坡元 (SGD)"
        case .aud: return "🇦🇺 澳元 (AUD)"
        case .cad: return "🇨🇦 加元 (CAD)"
        }
    }

    /// 簡短代號
    var code: String { rawValue }

    /// 貨幣符號
    var symbol: String {
        switch self {
        case .hkd: return "HK$"
        case .usd: return "US$"
        case .cny: return "¥"
        case .twd: return "NT$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        case .sgd: return "S$"
        case .aud: return "A$"
        case .cad: return "C$"
        }
    }

    /// 根據市場推導預設幣種
    static func from(market: StockHolding.StockMarket) -> Currency {
        switch market {
        case .us: return .usd
        case .hk: return .hkd
        }
    }

    /// 預設幣種
    static var `default`: Currency { .hkd }
}

// MARK: - 記帳交易模型
struct Transaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var amount: Double
    var type: TransactionType
    var category: String
    var note: String
    var source: TransactionSource
    var currency: Currency

    enum TransactionType: String, Codable, CaseIterable {
        case income = "收入"
        case expense = "支出"

        var systemIcon: String {
            switch self {
            case .income: return "arrow.down.circle.fill"
            case .expense: return "arrow.up.circle.fill"
            }
        }
    }

    enum TransactionSource: String, Codable {
        case manual = "手動輸入"
        case invoice = "發票導入"
    }
}

// MARK: - 股票持倉模型
struct StockHolding: Identifiable, Codable {
    var id: UUID = UUID()
    var symbol: String
    var name: String
    var market: StockMarket
    var shares: Int
    var purchasePrice: Double
    var purchaseDate: Date

    enum StockMarket: String, Codable, CaseIterable {
        case us = "美股"
        case hk = "港股"

        var suffix: String {
            switch self {
            case .us: return ""
            case .hk: return ".HK"
            }
        }

        var flag: String {
            switch self {
            case .us: return "🇺🇸"
            case .hk: return "🇭🇰"
            }
        }
    }
}

// MARK: - 股票報價模型
struct StockQuote: Identifiable, Codable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var market: String
    var currentPrice: Double
    var previousClose: Double
    var change: Double
    var changePercent: Double
    var dividendYield: Double
    var currency: String
    var exchange: String

    var isPositive: Bool { change >= 0 }
}

// MARK: - 發票模型
struct Invoice: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var merchant: String
    var amount: Double
    var currency: Currency
    var items: [String]
    var rawText: String
    var imageData: Data?
    var processed: Bool
    var importedAsTransaction: Bool
}

// MARK: - 收息股持倉模型
struct DividendPosition: Identifiable, Codable {
    var id: UUID = UUID()
    var symbol: String
    var name: String
    var shares: Int
    var annualYield: Double      // 年化收益率，例如 0.055 = 5.5%
    var dividendFrequency: Int   // 每年派息次數 (1=年度, 2=半年度, 4=季度, 12=月度)
    var purchasePrice: Double    // 每股買入價
    var currency: Currency        // 結算幣種

    // 計算總投資額
    var totalInvestment: Double {
        Double(shares) * purchasePrice
    }

    // 年度股息收入
    var annualDividendIncome: Double {
        totalInvestment * annualYield
    }

    // 月度股息收入
    var monthlyDividendIncome: Double {
        annualDividendIncome / 12.0
    }

    // 每日股息收入
    var dailyDividendIncome: Double {
        annualDividendIncome / 365.0
    }

    // 每股年度股息
    var annualDividendPerShare: Double {
        purchasePrice * annualYield
    }
}

// MARK: - 財富快照模型（用於每日結算）
struct WealthSnapshot: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var cashBalance: Double          // 現金餘額（記帳結餘）
    var stockValue: Double           // 股票市值
    var totalWealth: Double          // 總財富
    var dailyChange: Double          // 較前一日變化
    var baseCurrency: Currency       // 結算基準幣種
}

// MARK: - 記帳類別
enum ExpenseCategory: String, CaseIterable, Codable {
    case food = "餐飲"
    case transport = "交通"
    case shopping = "購物"
    case entertainment = "娛樂"
    case housing = "住房"
    case medical = "醫療"
    case education = "教育"
    case investment = "投資"
    case other = "其他"

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "gamecontroller.fill"
        case .housing: return "house.fill"
        case .medical: return "cross.case.fill"
        case .education: return "graduationcap.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum IncomeCategory: String, CaseIterable, Codable {
    case salary = "薪資"
    case dividend = "股息"
    case bonus = "獎金"
    case investment = "投資收益"
    case other = "其他"

    var icon: String {
        switch self {
        case .salary: return "banknote.fill"
        case .dividend: return "percent"
        case .bonus: return "gift.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - 自定義類別管理
struct CustomCategory: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var type: Transaction.TransactionType
    var color: String  // 顏色標識，用於圖表
}

// MARK: - 年度類別支出統計模型
struct CategoryYearlyStats: Identifiable {
    var id: String { "\(category)-\(year)" }
    let category: String
    let icon: String
    let year: Int
    let amount: Double
    let transactionCount: Int
    var previousYearAmount: Double  // 去年同類別金額

    /// 同比增長金額
    var yoyChange: Double {
        amount - previousYearAmount
    }

    /// 同比增長百分比
    var yoyPercent: Double {
        guard previousYearAmount > 0 else { return 0 }
        return (yoyChange / previousYearAmount) * 100
    }

    /// 是否為新增類別（去年沒有支出）
    var isNewCategory: Bool {
        previousYearAmount == 0 && amount > 0
    }
}

// MARK: - 年度支出總覽模型
struct YearlyExpenseOverview: Identifiable {
    var id: Int { year }
    let year: Int
    let totalExpense: Double
    let totalIncome: Double
    let categories: [CategoryYearlyStats]

    /// 前一年總支出
    var previousYearExpense: Double {
        categories.reduce(0) { $0 + $1.previousYearAmount }
    }

    /// 同比增長金額
    var yoyChange: Double {
        totalExpense - previousYearExpense
    }

    /// 同比增長百分比
    var yoyPercent: Double {
        guard previousYearExpense > 0 else { return 0 }
        return (yoyChange / previousYearExpense) * 100
    }
}

// MARK: - 均線技術信號模型
struct MovingAverageSignal: Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let market: StockHolding.StockMarket
    let currentPrice: Double
    let ma10: Double          // 10日均線
    let ma20: Double          // 20日均線
    let previousClose: Double // 前日收盤價

    // 信號類型
    enum SignalType: String {
        case buyBreakout    // 突破MA10，買入信號
        case sellBreakdown  // 跌破MA20，賣出信號
        case nearBuy        // 接近MA10（差距<2%）
        case nearSell       // 接近MA20（差距<2%）
        case hold           // 持有/無信號

        var displayName: String {
            switch self {
            case .buyBreakout: return "買入信號"
            case .sellBreakdown: return "賣出信號"
            case .nearBuy: return "關注買入"
            case .nearSell: return "關注賣出"
            case .hold: return "持有"
            }
        }

        var icon: String {
            switch self {
            case .buyBreakout: return "arrow.up.circle.fill"
            case .sellBreakdown: return "arrow.down.circle.fill"
            case .nearBuy: return "eye.fill"
            case .nearSell: return "eye.fill"
            case .hold: return "minus.circle"
            }
        }
    }

    // 判斷信號
    var signalType: SignalType {
        let ma10Diff = (currentPrice - ma10) / ma10 * 100
        let ma20Diff = (currentPrice - ma20) / ma20 * 100

        // 突破MA10：今日價格 > MA10 且前日收盤 <= MA10（剛突破）
        if currentPrice > ma10 && previousClose <= ma10 {
            return .buyBreakout
        }
        // 跌破MA20：今日價格 < MA20 且前日收盤 >= MA20（剛跌破）
        if currentPrice < ma20 && previousClose >= ma20 {
            return .sellBreakdown
        }
        // 接近MA10（差距在2%以內且在上方）
        if abs(ma10Diff) <= 2 && currentPrice >= ma10 {
            return .nearBuy
        }
        // 接近MA20（差距在2%以內且在下方）
        if abs(ma20Diff) <= 2 && currentPrice <= ma20 {
            return .nearSell
        }
        return .hold
    }

    // 是否為行動信號（需要提醒）
    var isActionable: Bool {
        signalType == .buyBreakout || signalType == .sellBreakdown
    }

    // 距離MA10的百分比
    var distanceToMA10: Double {
        guard ma10 > 0 else { return 0 }
        return (currentPrice - ma10) / ma10 * 100
    }

    // 距離MA20的百分比
    var distanceToMA20: Double {
        guard ma20 > 0 else { return 0 }
        return (currentPrice - ma20) / ma20 * 100
    }
}
