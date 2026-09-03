import Foundation
import SwiftUI

// MARK: - 風險等級
/// 由問卷得分推導，並經真實財務數據校準後得出
enum RiskLevel: Int, Codable, CaseIterable, Identifiable {
    case conservative = 0   // 保守
    case moderate = 1       // 穩健
    case balanced = 2       // 平衡
    case growth = 3         // 進取
    case aggressive = 4     // 積極

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .conservative: return "保守型"
        case .moderate: return "穩健型"
        case .balanced: return "平衡型"
        case .growth: return "進取型"
        case .aggressive: return "積極型"
        }
    }

    var subtitle: String {
        switch self {
        case .conservative: return "首重保本，難以承受本金虧損"
        case .moderate: return "追求穩定收息，可接受小幅波動"
        case .balanced: return "兼顧增值與防守，接受中度波動"
        case .growth: return "以資本增值為主，可承受較大波動"
        case .aggressive: return "追求高速增長，能承受大幅回撤"
        }
    }

    /// 可承受的參考最大回撤
    var toleratedDrawdown: String {
        switch self {
        case .conservative: return "5% 以內"
        case .moderate: return "5% ~ 10%"
        case .balanced: return "10% ~ 20%"
        case .growth: return "20% ~ 35%"
        case .aggressive: return "35% 以上"
        }
    }

    var color: Color {
        switch self {
        case .conservative: return .blue
        case .moderate: return .teal
        case .balanced: return .green
        case .growth: return .orange
        case .aggressive: return .red
        }
    }

    /// 目標資產配置
    var targetAllocation: AllocationTarget {
        switch self {
        case .conservative: return AllocationTarget(growth: 0.20, income: 0.25, defensive: 0.55)
        case .moderate:     return AllocationTarget(growth: 0.35, income: 0.30, defensive: 0.35)
        case .balanced:     return AllocationTarget(growth: 0.50, income: 0.25, defensive: 0.25)
        case .growth:       return AllocationTarget(growth: 0.65, income: 0.20, defensive: 0.15)
        case .aggressive:   return AllocationTarget(growth: 0.80, income: 0.10, defensive: 0.10)
        }
    }

    /// 策略關鍵詞（用於策略摘要）
    var strategyKeywords: [String] {
        switch self {
        case .conservative:
            return ["以高評級收息資產與現金為核心", "避免單一個股重倉", "優先建立充足備用金"]
        case .moderate:
            return ["收息資產打底提供現金流", "少量藍籌參與增長", "嚴格控制單一持倉上限"]
        case .balanced:
            return ["增長與收息並重", "跨市場分散降低單一市場風險", "定期定額攤平成本"]
        case .growth:
            return ["以增長型股票為主軸", "保留一定收息資產平衡波動", "設定停利停損紀律"]
        case .aggressive:
            return ["高比重增長型資產", "接受短期大幅波動換取長期回報", "必須維持獨立於投資的備用金"]
        }
    }

    static func from(score: Int) -> RiskLevel {
        switch score {
        case ..<8:   return .conservative
        case 8..<14: return .moderate
        case 14..<20: return .balanced
        case 20..<25: return .growth
        default:     return .aggressive
        }
    }

    /// 等級升降（校準用），自動夾在有效範圍內
    func adjusted(by delta: Int) -> RiskLevel {
        let target = max(0, min(RiskLevel.allCases.count - 1, rawValue + delta))
        return RiskLevel(rawValue: target) ?? self
    }
}

// MARK: - 目標配置
struct AllocationTarget: Codable {
    var growth: Double      // 增長型資產（股票）
    var income: Double      // 收息型資產
    var defensive: Double   // 防禦型（現金及等價物）
}

// MARK: - 問卷題目
struct AdvisorQuestion: Identifiable {
    let id: String
    let title: String
    let hint: String
    let options: [Option]

    struct Option: Identifiable {
        let id: Int
        let label: String
        let score: Int
    }
}

// MARK: - 問卷題庫
enum AdvisorQuestionBank {
    static let questions: [AdvisorQuestion] = [
        AdvisorQuestion(
            id: "age",
            title: "你目前的年齡層？",
            hint: "距離退休越遠，越有時間消化市場波動",
            options: [
                .init(id: 0, label: "30 歲以下", score: 4),
                .init(id: 1, label: "30 ~ 40 歲", score: 3),
                .init(id: 2, label: "40 ~ 50 歲", score: 2),
                .init(id: 3, label: "50 ~ 60 歲", score: 1),
                .init(id: 4, label: "60 歲以上", score: 0)
            ]
        ),
        AdvisorQuestion(
            id: "horizon",
            title: "這筆錢預計多久之內不會動用？",
            hint: "投資年期是決定可承受波動的關鍵",
            options: [
                .init(id: 0, label: "1 年以內", score: 0),
                .init(id: 1, label: "1 ~ 3 年", score: 1),
                .init(id: 2, label: "3 ~ 5 年", score: 2),
                .init(id: 3, label: "5 ~ 10 年", score: 3),
                .init(id: 4, label: "10 年以上", score: 4)
            ]
        ),
        AdvisorQuestion(
            id: "drawdown",
            title: "你最多能接受組合虧損多少而不失眠？",
            hint: "以總投資金額計算的帳面虧損幅度",
            options: [
                .init(id: 0, label: "幾乎不能虧（5% 以內）", score: 0),
                .init(id: 1, label: "5% ~ 10%", score: 1),
                .init(id: 2, label: "10% ~ 20%", score: 2),
                .init(id: 3, label: "20% ~ 35%", score: 3),
                .init(id: 4, label: "35% 以上都可接受", score: 4)
            ]
        ),
        AdvisorQuestion(
            id: "goal",
            title: "你的主要投資目標是？",
            hint: "目標決定資產配置的重心",
            options: [
                .init(id: 0, label: "保本，跑贏通脹就好", score: 0),
                .init(id: 1, label: "穩定收息，創造被動現金流", score: 1),
                .init(id: 2, label: "平衡增長，兼顧收息與增值", score: 2),
                .init(id: 3, label: "資本增值為主", score: 3),
                .init(id: 4, label: "追求高速增長", score: 4)
            ]
        ),
        AdvisorQuestion(
            id: "experience",
            title: "你的投資經驗有多久？",
            hint: "經驗影響面對波動時的決策品質",
            options: [
                .init(id: 0, label: "完全新手", score: 0),
                .init(id: 1, label: "1 ~ 3 年", score: 1),
                .init(id: 2, label: "3 ~ 5 年", score: 2),
                .init(id: 3, label: "5 ~ 10 年", score: 3),
                .init(id: 4, label: "10 年以上，經歷過完整牛熊", score: 4)
            ]
        ),
        AdvisorQuestion(
            id: "incomeStability",
            title: "你的收入穩定程度？",
            hint: "收入越穩定，越能承受投資波動",
            options: [
                .init(id: 0, label: "很不穩定（自由業／收入起伏大）", score: 0),
                .init(id: 1, label: "一般（有浮動獎金成分）", score: 2),
                .init(id: 2, label: "非常穩定（固定薪資／退休金）", score: 4)
            ]
        ),
        AdvisorQuestion(
            id: "reaction",
            title: "若組合在一個月內下跌 20%，你會？",
            hint: "這題反映真實的風險行為，權重最高",
            options: [
                .init(id: 0, label: "立刻全部賣出止損", score: 0),
                .init(id: 1, label: "賣掉一部分減輕壓力", score: 1),
                .init(id: 2, label: "什麼都不做，繼續持有", score: 3),
                .init(id: 3, label: "視為機會，加倉買入", score: 4)
            ]
        )
    ]

    static var maxScore: Int {
        questions.reduce(0) { $0 + ($1.options.map { $0.score }.max() ?? 0) }
    }

    static func question(id: String) -> AdvisorQuestion? {
        questions.first { $0.id == id }
    }
}

// MARK: - 投資者畫像（問卷結果）
struct InvestorProfile: Codable {
    /// 題目 id -> 選中的選項 id
    var answers: [String: Int] = [:]
    /// 每月可投入金額（基準幣種）
    var monthlyInvestable: Double = 0
    /// 自述的財務目標
    var goalText: String = ""
    var completedAt: Date?

    var isComplete: Bool {
        AdvisorQuestionBank.questions.allSatisfy { answers[$0.id] != nil }
    }

    var answeredCount: Int {
        AdvisorQuestionBank.questions.filter { answers[$0.id] != nil }.count
    }

    /// 問卷總得分
    var totalScore: Int {
        var sum = 0
        for question in AdvisorQuestionBank.questions {
            guard let optionId = answers[question.id],
                  let option = question.options.first(where: { $0.id == optionId }) else { continue }
            sum += option.score
        }
        return sum
    }

    /// 問卷原始風險等級（未經數據校準）
    var rawRiskLevel: RiskLevel { RiskLevel.from(score: totalScore) }
}

// MARK: - 財務快照（由真實數據計算）
struct FinancialSnapshot {
    var baseCurrency: Currency = .hkd

    // 收支
    var monthsOfData: Int = 0
    var monthlyIncome: Double = 0
    var monthlyExpense: Double = 0
    var savingsRate: Double = 0          // (收入-支出)/收入
    var topExpenseCategory: String = ""
    var topExpenseRatio: Double = 0

    // 資產
    var cashBalance: Double = 0
    var stockValue: Double = 0
    var stockCost: Double = 0
    var dividendValue: Double = 0
    var annualDividendIncome: Double = 0
    var totalAssets: Double = 0

    // 股票持倉依息率拆分（息率 ≥ 4% 歸為收息型）
    var growthStockValue: Double = 0
    var incomeStockValue: Double = 0
    /// 高息股票持倉的估算年股息（已計入 annualDividendIncome）
    var estimatedStockDividend: Double = 0
    /// 被重新歸類為收息型的股票名稱
    var incomeClassifiedHoldings: [String] = []

    /// 收息型資產總額（收息倉 + 高息股票持倉）
    var totalIncomeAssets: Double { dividendValue + incomeStockValue }

    // 比例
    var growthRatio: Double = 0
    var incomeRatio: Double = 0
    var defensiveRatio: Double = 0

    // 風險指標
    var emergencyMonths: Double = 0       // 備用金可支撐月數
    var holdingsCount: Int = 0
    var topHoldingName: String = ""
    var topHoldingRatio: Double = 0       // 佔投資資產比重
    var marketExposure: [String: Double] = [:]     // 美股／港股佔比
    var currencyExposure: [String: Double] = [:]   // 幣種佔比
    var dividendCoverage: Double = 0      // 年股息 / 年支出
    var unrealizedPnL: Double = 0
    var unrealizedPnLPercent: Double = 0
    var losingHoldings: [String] = []     // 虧損超過 20% 的持倉

    /// 投資資產總額（股票 + 收息）
    var investedAssets: Double { stockValue + dividendValue }

    var hasEnoughData: Bool { totalAssets > 0 || monthlyExpense > 0 }
}

// MARK: - 體檢發現
struct AdvisorFinding: Identifiable {
    let id = UUID()
    var severity: Severity
    var title: String
    var detail: String
    var action: String

    enum Severity: Int, Comparable {
        case critical = 0
        case warning = 1
        case info = 2
        case good = 3

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .critical: return "需優先處理"
            case .warning: return "建議調整"
            case .info: return "提醒"
            case .good: return "表現良好"
            }
        }

        var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            case .good: return "checkmark.seal.fill"
            }
        }

        var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            case .info: return .blue
            case .good: return .green
            }
        }
    }
}

// MARK: - 再平衡建議項
struct RebalanceItem: Identifiable {
    let id = UUID()
    var bucket: String          // 增長型／收息型／防禦型
    var currentRatio: Double
    var targetRatio: Double
    var deltaAmount: Double     // 正數=建議增持，負數=建議減持
    var color: Color

    var deviation: Double { currentRatio - targetRatio }
    var needsAction: Bool { abs(deviation) >= 0.10 }
}

// MARK: - 評分細項
struct ScoreItem: Identifiable {
    let id = UUID()
    var name: String
    var score: Double
    var maxScore: Double
    var comment: String

    var ratio: Double { maxScore > 0 ? score / maxScore : 0 }
}

// MARK: - 顧問報告
struct AdvisorReport {
    var generatedAt: Date = Date()
    var snapshot: FinancialSnapshot
    var profile: InvestorProfile
    var finalRiskLevel: RiskLevel
    /// 若數據校準改變了問卷結論，說明原因
    var calibrationNote: String?
    var healthScore: Int
    var scoreBreakdown: [ScoreItem]
    var findings: [AdvisorFinding]
    var rebalanceItems: [RebalanceItem]
    var strategySummary: String
    /// 大模型潤飾後的敘述（可選）
    var narrative: String?

    var healthGrade: String {
        switch healthScore {
        case 85...: return "優秀"
        case 70..<85: return "良好"
        case 55..<70: return "尚可"
        case 40..<55: return "偏弱"
        default: return "需改善"
        }
    }

    var healthColor: Color {
        switch healthScore {
        case 85...: return .green
        case 70..<85: return .teal
        case 55..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - 對話訊息（追問用）
struct AdvisorMessage: Identifiable {
    let id = UUID()
    var role: Role
    var text: String
    var date: Date = Date()

    enum Role {
        case user
        case advisor
    }
}
