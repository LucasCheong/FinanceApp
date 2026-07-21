import Foundation

// MARK: - 記帳交易模型
struct Transaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var amount: Double
    var type: TransactionType
    var category: String
    var note: String
    var source: TransactionSource

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
