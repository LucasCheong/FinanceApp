import Foundation
import SwiftUI

// MARK: - 顧問規則引擎
/// 全部計算在本地完成，不依賴任何外部服務。
/// 大模型（若已設定）僅用於把以下結論潤飾成自然語言，不參與數值計算。
enum AdvisorEngine {

    /// 股息率門檻：達此水平的股票持倉歸類為「收息型」而非「增長型」
    static let incomeYieldThreshold = 0.04

    // MARK: - 財務快照

    /// 從真實記帳與持倉數據計算財務快照
    /// - Parameters:
    ///   - persistence: 數據來源
    ///   - quotes: 最新報價（symbol -> quote），缺失時回退買入價
    ///   - months: 收支統計採樣月數
    static func buildSnapshot(
        persistence: PersistenceService,
        quotes: [String: StockQuote],
        months: Int = 6
    ) -> FinancialSnapshot {
        var snapshot = FinancialSnapshot()
        let base = persistence.baseCurrency
        snapshot.baseCurrency = base

        // --- 收支（近 months 個月）---
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        let recent = persistence.transactions.filter { $0.date >= cutoff }

        var incomeSum = 0.0
        var expenseSum = 0.0
        var expenseByCategory: [String: Double] = [:]

        for tx in recent {
            let amount = ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: base)
            if tx.type == .income {
                incomeSum += amount
            } else {
                expenseSum += amount
                expenseByCategory[tx.category, default: 0] += amount
            }
        }

        // 實際覆蓋的月數（避免只有 1 個月數據時把月均算高）
        let span = coveredMonths(transactions: recent, fallback: months)
        snapshot.monthsOfData = span
        snapshot.monthlyIncome = span > 0 ? incomeSum / Double(span) : 0
        snapshot.monthlyExpense = span > 0 ? expenseSum / Double(span) : 0
        snapshot.savingsRate = incomeSum > 0 ? (incomeSum - expenseSum) / incomeSum : 0

        if let top = expenseByCategory.max(by: { $0.value < $1.value }), expenseSum > 0 {
            snapshot.topExpenseCategory = top.key
            snapshot.topExpenseRatio = top.value / expenseSum
        }

        // --- 資產 ---
        snapshot.cashBalance = max(0, persistence.cashBalance)

        // 息率回退表：報價帶不回真實派息數據時才用
        var yieldBySymbol: [String: Double] = [:]
        for stock in StockDatabase.allStocks where stock.dividendYield > 0 {
            yieldBySymbol[stock.symbol] = stock.dividendYield
        }

        var stockValue = 0.0
        var stockCost = 0.0
        var growthStockValue = 0.0
        var incomeStockValue = 0.0
        var estimatedStockDividend = 0.0
        var incomeClassified: [String] = []
        var fallbackYield: [String] = []
        var valueBySymbol: [String: (name: String, value: Double)] = [:]
        var marketValue: [String: Double] = [:]
        var currencyValue: [String: Double] = [:]
        var losing: [String] = []

        for holding in persistence.holdings {
            let holdingCurrency = Currency.from(market: holding.market)
            let price = quotes[holding.symbol]?.currentPrice ?? holding.purchasePrice
            let rawValue = Double(holding.shares) * price
            let rawCost = Double(holding.shares) * holding.purchasePrice

            let value = ExchangeRateProvider.convert(rawValue, from: holdingCurrency, to: base)
            let cost = ExchangeRateProvider.convert(rawCost, from: holdingCurrency, to: base)

            stockValue += value
            stockCost += cost
            valueBySymbol[holding.symbol] = (holding.name, value)
            marketValue[holding.market.rawValue, default: 0] += value
            currencyValue[holdingCurrency.code, default: 0] += value

            // 依股息率分桶：高息股雖登記在股票分頁，仍應計入收息型資產。
            // 報價的 dividendYield 已由 StockService 套上近 12 個月實際派息算出的 TTM 息率；
            // 拉不到時才回退到預設值，並記下來在報告裡標明。
            let holdingYield: Double
            if let quoteYield = quotes[holding.symbol]?.dividendYield, quoteYield > 0 {
                holdingYield = quoteYield
            } else if let fallback = yieldBySymbol[holding.symbol], fallback > 0 {
                holdingYield = fallback
                fallbackYield.append(holding.name)
            } else {
                holdingYield = 0
            }

            if holdingYield >= incomeYieldThreshold {
                incomeStockValue += value
                estimatedStockDividend += value * holdingYield
                incomeClassified.append("\(holding.name)（\(percentText(holdingYield))）")
            } else {
                growthStockValue += value
            }

            // 單一持倉虧損超過 20% 時標記
            if rawCost > 0 {
                let pnlRatio = (rawValue - rawCost) / rawCost
                if pnlRatio <= -0.20 {
                    losing.append("\(holding.name)（\(String(format: "%.0f%%", pnlRatio * 100))）")
                }
            }
        }

        var dividendValue = 0.0
        var annualDividend = 0.0
        for position in persistence.dividendPositions {
            let value = ExchangeRateProvider.convert(position.totalInvestment, from: position.currency, to: base)
            let income = ExchangeRateProvider.convert(position.annualDividendIncome, from: position.currency, to: base)
            dividendValue += value
            annualDividend += income
            valueBySymbol[position.symbol] = (position.name, value)
            currencyValue[position.currency.code, default: 0] += value
        }

        snapshot.stockValue = stockValue
        snapshot.stockCost = stockCost
        snapshot.dividendValue = dividendValue
        snapshot.growthStockValue = growthStockValue
        snapshot.incomeStockValue = incomeStockValue
        snapshot.estimatedStockDividend = estimatedStockDividend
        snapshot.incomeClassifiedHoldings = incomeClassified
        snapshot.fallbackYieldHoldings = fallbackYield
        snapshot.annualDividendIncome = annualDividend + estimatedStockDividend
        snapshot.unrealizedPnL = stockValue - stockCost
        snapshot.unrealizedPnLPercent = stockCost > 0 ? (stockValue - stockCost) / stockCost : 0
        snapshot.losingHoldings = losing

        let total = snapshot.cashBalance + stockValue + dividendValue
        snapshot.totalAssets = total

        if total > 0 {
            snapshot.growthRatio = growthStockValue / total
            snapshot.incomeRatio = (dividendValue + incomeStockValue) / total
            snapshot.defensiveRatio = snapshot.cashBalance / total
        }

        // --- 風險指標 ---
        snapshot.emergencyMonths = snapshot.monthlyExpense > 0
            ? snapshot.cashBalance / snapshot.monthlyExpense
            : (snapshot.cashBalance > 0 ? 99 : 0)

        snapshot.holdingsCount = valueBySymbol.count

        let invested = stockValue + dividendValue
        if let top = valueBySymbol.max(by: { $0.value.value < $1.value.value }), invested > 0 {
            snapshot.topHoldingName = top.value.name
            snapshot.topHoldingRatio = top.value.value / invested
        }

        if invested > 0 {
            snapshot.marketExposure = marketValue.mapValues { $0 / max(stockValue, 0.01) }
            snapshot.currencyExposure = currencyValue.mapValues { $0 / invested }
        }

        let annualExpense = snapshot.monthlyExpense * 12
        snapshot.dividendCoverage = annualExpense > 0 ? snapshot.annualDividendIncome / annualExpense : 0

        return snapshot
    }

    /// 交易數據實際覆蓋的月份數
    private static func coveredMonths(transactions: [Transaction], fallback: Int) -> Int {
        guard let earliest = transactions.map({ $0.date }).min() else { return 0 }
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.month], from: earliest, to: Date())
        let span = (comps.month ?? 0) + 1
        return max(1, min(span, fallback))
    }

    // MARK: - 風險等級校準

    /// 用真實財務數據校準問卷結論
    /// 問卷反映「主觀意願」，數據反映「客觀承受力」，兩者取較保守的一方
    static func calibrate(profile: InvestorProfile, snapshot: FinancialSnapshot) -> (level: RiskLevel, note: String?) {
        let raw = profile.rawRiskLevel
        var delta = 0
        var reasons: [String] = []

        // 備用金不足是最硬的約束
        if snapshot.monthlyExpense > 0 {
            if snapshot.emergencyMonths < 3 {
                delta -= 2
                reasons.append("緊急備用金僅可支撐 \(String(format: "%.1f", snapshot.emergencyMonths)) 個月（建議至少 6 個月），抗風險能力不足")
            } else if snapshot.emergencyMonths < 6 {
                delta -= 1
                reasons.append("緊急備用金約 \(String(format: "%.1f", snapshot.emergencyMonths)) 個月，尚未達到 6 個月的安全水位")
            }
        }

        // 儲蓄率偏低意味著無法持續投入，也無法承受套牢
        if snapshot.monthlyIncome > 0 {
            if snapshot.savingsRate < 0 {
                delta -= 2
                reasons.append("近期收支為淨流出（儲蓄率 \(percentText(snapshot.savingsRate))），需先修復現金流")
            } else if snapshot.savingsRate < 0.10 {
                delta -= 1
                reasons.append("儲蓄率僅 \(percentText(snapshot.savingsRate))，可投入資金有限")
            }
        }

        var level = raw.adjusted(by: delta)

        // 行為與自述不符：實際持股比例遠超問卷等級的目標
        let targetGrowth = raw.targetAllocation.growth
        if snapshot.totalAssets > 0 && snapshot.growthRatio - targetGrowth > 0.25 {
            reasons.append("問卷結論為\(raw.title)，但實際增長型資產已佔 \(percentText(snapshot.growthRatio))，遠高於該等級建議的 \(percentText(targetGrowth))，實際風險敞口高於自述意願")
        }

        // 極端保守者不因數據上調
        if delta > 0 { level = raw }

        let note: String?
        if reasons.isEmpty {
            note = nil
        } else if level != raw {
            note = "問卷結論為\(raw.title)，但根據實際財務數據下調為\(level.title)：" + reasons.joined(separator: "；") + "。"
        } else {
            note = reasons.joined(separator: "；") + "。"
        }

        return (level, note)
    }

    // MARK: - 組合體檢

    static func buildFindings(snapshot: FinancialSnapshot, level: RiskLevel) -> [AdvisorFinding] {
        var findings: [AdvisorFinding] = []

        // 1. 緊急備用金
        if snapshot.monthlyExpense > 0 {
            let months = snapshot.emergencyMonths
            if months < 3 {
                findings.append(AdvisorFinding(
                    severity: .critical,
                    title: "緊急備用金不足",
                    detail: "現金結餘 \(money(snapshot.cashBalance, snapshot)) 僅能支撐 \(String(format: "%.1f", months)) 個月開支（月均支出 \(money(snapshot.monthlyExpense, snapshot))）。一旦收入中斷或遇突發支出，可能被迫在低點賣出資產。",
                    action: "在增加投資前，先把現金儲備補至 6 個月開支，即約 \(money(snapshot.monthlyExpense * 6, snapshot))。"
                ))
            } else if months < 6 {
                findings.append(AdvisorFinding(
                    severity: .warning,
                    title: "備用金尚未達安全水位",
                    detail: "現金可支撐 \(String(format: "%.1f", months)) 個月，距離建議的 6 個月還差約 \(money(max(0, snapshot.monthlyExpense * 6 - snapshot.cashBalance), snapshot))。",
                    action: "把未來數月的結餘優先補足備用金，再投入市場。"
                ))
            } else {
                findings.append(AdvisorFinding(
                    severity: .good,
                    title: "備用金充足",
                    detail: "現金可支撐 \(String(format: "%.1f", min(months, 99))) 個月開支，具備承受波動的緩衝。",
                    action: "維持現狀即可；若超過 12 個月開支，可考慮把多餘現金投入生息資產。"
                ))
            }
        }

        // 2. 儲蓄率
        if snapshot.monthlyIncome > 0 {
            let rate = snapshot.savingsRate
            if rate < 0 {
                findings.append(AdvisorFinding(
                    severity: .critical,
                    title: "收支為淨流出",
                    detail: "近 \(snapshot.monthsOfData) 個月月均收入 \(money(snapshot.monthlyIncome, snapshot))、月均支出 \(money(snapshot.monthlyExpense, snapshot))，儲蓄率 \(percentText(rate))。",
                    action: "投資無法彌補現金流缺口，優先從最大支出項「\(snapshot.topExpenseCategory)」著手削減。"
                ))
            } else if rate < 0.20 {
                findings.append(AdvisorFinding(
                    severity: .warning,
                    title: "儲蓄率偏低",
                    detail: "儲蓄率 \(percentText(rate))，月均可結餘 \(money(snapshot.monthlyIncome - snapshot.monthlyExpense, snapshot))。一般建議維持 20% 以上以加速累積本金。",
                    action: "設定每月自動轉出固定金額到投資帳戶，先儲後花。"
                ))
            } else {
                findings.append(AdvisorFinding(
                    severity: .good,
                    title: "儲蓄率健康",
                    detail: "儲蓄率 \(percentText(rate))，月均結餘 \(money(snapshot.monthlyIncome - snapshot.monthlyExpense, snapshot))，本金累積能力良好。",
                    action: "把結餘按目標配置比例定期投入，發揮複利效果。"
                ))
            }
        }

        // 3. 單一持倉集中度
        if snapshot.investedAssets > 0 && !snapshot.topHoldingName.isEmpty {
            let ratio = snapshot.topHoldingRatio
            if ratio > 0.40 {
                findings.append(AdvisorFinding(
                    severity: .critical,
                    title: "單一持倉過度集中",
                    detail: "「\(snapshot.topHoldingName)」佔投資資產 \(percentText(ratio))。單一標的的個別風險（財報、政策、行業衝擊）會主導整個組合表現。",
                    action: "逐步把單一持倉降至 20% 以下，減持部分可轉入其他市場或收息資產。"
                ))
            } else if ratio > 0.25 {
                findings.append(AdvisorFinding(
                    severity: .warning,
                    title: "最大持倉偏重",
                    detail: "「\(snapshot.topHoldingName)」佔投資資產 \(percentText(ratio))，高於建議的 25% 上限。",
                    action: "後續加倉時避開此標的，用新資金自然稀釋其比重。"
                ))
            }
        }

        // 4. 分散程度
        if snapshot.investedAssets > 0 {
            if snapshot.holdingsCount < 3 {
                findings.append(AdvisorFinding(
                    severity: .warning,
                    title: "持倉數量過少",
                    detail: "目前僅 \(snapshot.holdingsCount) 個標的，難以分散個別公司風險。",
                    action: "以 8 ~ 15 個標的或直接用寬基指數 ETF 建立核心倉位。"
                ))
            } else if snapshot.holdingsCount > 25 {
                findings.append(AdvisorFinding(
                    severity: .info,
                    title: "持倉過於分散",
                    detail: "共 \(snapshot.holdingsCount) 個標的，超出個人可跟蹤範圍，容易變成無效分散。",
                    action: "集中到最有信心的核心標的，其餘以 ETF 替代。"
                ))
            }
        }

        // 5. 市場集中
        if snapshot.stockValue > 0, let top = snapshot.marketExposure.max(by: { $0.value < $1.value }), top.value > 0.80 {
            findings.append(AdvisorFinding(
                severity: .info,
                title: "單一市場曝險偏高",
                detail: "\(top.key)佔股票資產 \(percentText(top.value))，組合表現高度綁定單一市場的政策與景氣週期。",
                action: "適度加入另一市場的資產，降低單一市場系統性風險。"
            ))
        }

        // 6. 幣種曝險
        if snapshot.investedAssets > 0 {
            let baseCode = snapshot.baseCurrency.code
            let foreign = snapshot.currencyExposure.filter { $0.key != baseCode }.values.reduce(0, +)
            if foreign > 0.60 {
                findings.append(AdvisorFinding(
                    severity: .info,
                    title: "外幣曝險較高",
                    detail: "非\(baseCode)資產佔 \(percentText(foreign))，匯率波動會直接影響以\(baseCode)計算的回報。",
                    action: "若未來支出以\(baseCode)為主，可保留部分\(baseCode)資產自然對沖。"
                ))
            }
        }

        // 7. 股息覆蓋率
        if snapshot.annualDividendIncome > 0 && snapshot.monthlyExpense > 0 {
            let coverage = snapshot.dividendCoverage
            if coverage >= 1.0 {
                findings.append(AdvisorFinding(
                    severity: .good,
                    title: "被動收入已覆蓋開支",
                    detail: "年股息 \(money(snapshot.annualDividendIncome, snapshot)) 已覆蓋年支出的 \(percentText(coverage))，具備財務獨立的基礎。",
                    action: "關注派息可持續性，避免為追高息而承擔過高本金風險。"
                ))
            } else {
                findings.append(AdvisorFinding(
                    severity: .info,
                    title: "被動收入覆蓋率 \(percentText(coverage))",
                    detail: "年股息 \(money(snapshot.annualDividendIncome, snapshot))，年支出 \(money(snapshot.monthlyExpense * 12, snapshot))。",
                    action: "若以財務自由為目標，按目前平均息率計算，還需增加約 \(money(neededCapital(snapshot), snapshot)) 的收息資產。"
                ))
            }
        }

        // 8. 支出結構
        if snapshot.topExpenseRatio > 0.40 && !snapshot.topExpenseCategory.isEmpty {
            findings.append(AdvisorFinding(
                severity: .info,
                title: "支出集中於「\(snapshot.topExpenseCategory)」",
                detail: "該類別佔總支出 \(percentText(snapshot.topExpenseRatio))。",
                action: "此處每削減 10%，即可多出 \(money(snapshot.monthlyExpense * snapshot.topExpenseRatio * 0.10, snapshot))／月的可投資金額。"
            ))
        }

        // 9. 帳面虧損持倉
        if !snapshot.losingHoldings.isEmpty {
            findings.append(AdvisorFinding(
                severity: .warning,
                title: "有持倉虧損超過 20%",
                detail: "包括 \(snapshot.losingHoldings.prefix(3).joined(separator: "、"))。",
                action: "重新檢視當初買入邏輯是否仍成立：邏輯已變則果斷處理，未變則不必因帳面波動離場。"
            ))
        }

        // 10. 現金拖累
        if snapshot.totalAssets > 0 && snapshot.defensiveRatio > 0.70 && snapshot.emergencyMonths > 12 {
            findings.append(AdvisorFinding(
                severity: .warning,
                title: "現金比重過高",
                detail: "現金佔總資產 \(percentText(snapshot.defensiveRatio))，且已遠超備用金需求。長期持有現金會被通脹侵蝕購買力。",
                action: "按\(level.title)的目標配置，分批把多餘現金投入生息資產。"
            ))
        }

        // 11. 高息股票被重新歸類的說明
        if !snapshot.incomeClassifiedHoldings.isEmpty {
            findings.append(AdvisorFinding(
                severity: .info,
                title: "\(snapshot.incomeClassifiedHoldings.count) 項股票持倉已計入收息型",
                detail: "息率達 \(percentText(incomeYieldThreshold)) 以上的持倉會歸入收息型而非增長型：\(snapshot.incomeClassifiedHoldings.prefix(5).joined(separator: "、"))。這些持倉估算每年可帶來股息 \(money(snapshot.estimatedStockDividend, snapshot))，已計入股息覆蓋率。",
                action: "息率依近 12 個月實際派息記錄除以現價計算，每次生成報告時重拉。"
            ))
        }

        // 12. 息率數據回退提醒
        if !snapshot.fallbackYieldHoldings.isEmpty {
            findings.append(AdvisorFinding(
                severity: .info,
                title: "\(snapshot.fallbackYieldHoldings.count) 項持倉的息率非實時數據",
                detail: "\(snapshot.fallbackYieldHoldings.prefix(5).joined(separator: "、"))拉不到近 12 個月的派息記錄，目前沿用預設息率，分桶結果可能不準。",
                action: "確認下一次能連網時重新生成報告；若持續拉不到，可能是該標的在資料源沒有派息記錄。"
            ))
        }

        return findings.sorted { $0.severity < $1.severity }
    }

    /// 達到股息覆蓋全部開支所需的額外收息本金
    private static func neededCapital(_ snapshot: FinancialSnapshot) -> Double {
        let annualExpense = snapshot.monthlyExpense * 12
        let gap = max(0, annualExpense - snapshot.annualDividendIncome)
        // 以目前收息型資產的實際平均息率估算，無數據時用 5%
        let incomeAssets = snapshot.totalIncomeAssets
        let yieldRate = incomeAssets > 0
            ? max(0.01, snapshot.annualDividendIncome / incomeAssets)
            : 0.05
        return gap / yieldRate
    }

    // MARK: - 再平衡建議

    static func buildRebalanceItems(snapshot: FinancialSnapshot, level: RiskLevel) -> [RebalanceItem] {
        guard snapshot.totalAssets > 0 else { return [] }
        let target = level.targetAllocation

        return [
            RebalanceItem(
                bucket: "增長型（股票）",
                currentRatio: snapshot.growthRatio,
                targetRatio: target.growth,
                deltaAmount: (target.growth - snapshot.growthRatio) * snapshot.totalAssets,
                color: .orange
            ),
            RebalanceItem(
                bucket: "收息型（含高息股）",
                currentRatio: snapshot.incomeRatio,
                targetRatio: target.income,
                deltaAmount: (target.income - snapshot.incomeRatio) * snapshot.totalAssets,
                color: .green
            ),
            RebalanceItem(
                bucket: "防禦型（現金）",
                currentRatio: snapshot.defensiveRatio,
                targetRatio: target.defensive,
                deltaAmount: (target.defensive - snapshot.defensiveRatio) * snapshot.totalAssets,
                color: .blue
            )
        ]
    }

    // MARK: - 財務健康評分

    static func buildScore(snapshot: FinancialSnapshot, level: RiskLevel) -> (total: Int, items: [ScoreItem]) {
        var items: [ScoreItem] = []

        // 1. 儲蓄率（25 分）
        let savingsScore: Double
        if snapshot.monthlyIncome <= 0 {
            savingsScore = 12.5
        } else if snapshot.savingsRate >= 0.30 {
            savingsScore = 25
        } else if snapshot.savingsRate <= 0 {
            savingsScore = 0
        } else {
            savingsScore = 25 * (snapshot.savingsRate / 0.30)
        }
        items.append(ScoreItem(
            name: "儲蓄能力",
            score: savingsScore,
            maxScore: 25,
            comment: snapshot.monthlyIncome > 0 ? "儲蓄率 \(percentText(snapshot.savingsRate))" : "記帳數據不足"
        ))

        // 2. 備用金（25 分）
        let emergencyScore: Double
        if snapshot.monthlyExpense <= 0 {
            emergencyScore = 12.5
        } else {
            emergencyScore = min(25, 25 * (snapshot.emergencyMonths / 6.0))
        }
        items.append(ScoreItem(
            name: "風險緩衝",
            score: emergencyScore,
            maxScore: 25,
            comment: snapshot.monthlyExpense > 0 ? "可支撐 \(String(format: "%.1f", min(snapshot.emergencyMonths, 99))) 個月" : "支出數據不足"
        ))

        // 3. 分散度（20 分）
        var diversifyScore: Double = 0
        if snapshot.investedAssets > 0 {
            let countScore = min(10, Double(snapshot.holdingsCount) / 8.0 * 10)
            let concentrationScore = snapshot.topHoldingRatio <= 0.20
                ? 10.0
                : max(0, 10 * (1 - (snapshot.topHoldingRatio - 0.20) / 0.40))
            diversifyScore = countScore + concentrationScore
        }
        items.append(ScoreItem(
            name: "分散程度",
            score: diversifyScore,
            maxScore: 20,
            comment: snapshot.investedAssets > 0
                ? "\(snapshot.holdingsCount) 個標的，最大佔 \(percentText(snapshot.topHoldingRatio))"
                : "尚無投資持倉"
        ))

        // 4. 配置匹配度（20 分）
        var allocationScore: Double = 0
        if snapshot.totalAssets > 0 {
            let target = level.targetAllocation
            let deviation = abs(snapshot.growthRatio - target.growth)
                + abs(snapshot.incomeRatio - target.income)
                + abs(snapshot.defensiveRatio - target.defensive)
            // 總偏離 0 得滿分，偏離 1.0（即完全錯配）得 0 分
            allocationScore = max(0, 20 * (1 - deviation))
        }
        items.append(ScoreItem(
            name: "配置匹配",
            score: allocationScore,
            maxScore: 20,
            comment: snapshot.totalAssets > 0 ? "對照\(level.title)目標配置" : "尚無資產數據"
        ))

        // 5. 被動收入（10 分）
        let coverageScore = min(10, snapshot.dividendCoverage * 10)
        items.append(ScoreItem(
            name: "被動收入",
            score: coverageScore,
            maxScore: 10,
            comment: "股息覆蓋開支 \(percentText(snapshot.dividendCoverage))"
        ))

        let total = Int(items.reduce(0) { $0 + $1.score }.rounded())
        return (max(0, min(100, total)), items)
    }

    // MARK: - 策略摘要（本地生成）

    static func buildStrategySummary(
        snapshot: FinancialSnapshot,
        profile: InvestorProfile,
        level: RiskLevel
    ) -> String {
        let target = level.targetAllocation
        var lines: [String] = []

        lines.append("【風險定位】你屬於\(level.title)投資者，\(level.subtitle)，可承受的參考回撤為 \(level.toleratedDrawdown)。")

        lines.append("【目標配置】增長型資產 \(percentText(target.growth))、收息型資產 \(percentText(target.income))、防禦型現金 \(percentText(target.defensive))。")

        if snapshot.totalAssets > 0 {
            lines.append("【目前實況】總資產 \(money(snapshot.totalAssets, snapshot))，其中增長型 \(percentText(snapshot.growthRatio))、收息型 \(percentText(snapshot.incomeRatio))、現金 \(percentText(snapshot.defensiveRatio))。")
        }

        // 執行要點
        let points = level.strategyKeywords.enumerated().map { "\($0.offset + 1). \($0.element)" }
        lines.append("【執行要點】\n" + points.joined(separator: "\n"))

        // 投入節奏
        let monthly = profile.monthlyInvestable > 0
            ? profile.monthlyInvestable
            : max(0, snapshot.monthlyIncome - snapshot.monthlyExpense)
        if monthly > 0 {
            let growthAmount = monthly * target.growth
            let incomeAmount = monthly * target.income
            let cashAmount = monthly * target.defensive
            lines.append("【每月投入建議】以每月 \(money(monthly, snapshot)) 計：增長型 \(money(growthAmount, snapshot))、收息型 \(money(incomeAmount, snapshot))、留存現金 \(money(cashAmount, snapshot))。採用定期定額可避免擇時風險。")
        }

        // 優先順序：備用金永遠優先
        if snapshot.emergencyMonths < 6 && snapshot.monthlyExpense > 0 {
            lines.append("【優先順序】目前備用金未達 6 個月開支，建議先把每月結餘全額補足備用金，達標後再按上述比例投入市場。")
        }

        if !profile.goalText.isEmpty {
            lines.append("【你的目標】\(profile.goalText)")
        }

        return lines.joined(separator: "\n\n")
    }

    // MARK: - 生成完整報告

    static func generateReport(
        persistence: PersistenceService,
        quotes: [String: StockQuote],
        profile: InvestorProfile
    ) -> AdvisorReport {
        let snapshot = buildSnapshot(persistence: persistence, quotes: quotes)
        let calibration = calibrate(profile: profile, snapshot: snapshot)
        let level = calibration.level
        let findings = buildFindings(snapshot: snapshot, level: level)
        let rebalance = buildRebalanceItems(snapshot: snapshot, level: level)
        let score = buildScore(snapshot: snapshot, level: level)
        let summary = buildStrategySummary(snapshot: snapshot, profile: profile, level: level)

        return AdvisorReport(
            snapshot: snapshot,
            profile: profile,
            finalRiskLevel: level,
            calibrationNote: calibration.note,
            healthScore: score.total,
            scoreBreakdown: score.items,
            findings: findings,
            rebalanceItems: rebalance,
            strategySummary: summary,
            narrative: nil
        )
    }

    // MARK: - 格式化工具

    static func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private static func money(_ value: Double, _ snapshot: FinancialSnapshot) -> String {
        value.moneyString(currency: snapshot.baseCurrency)
    }
}
