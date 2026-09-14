import Foundation

/// 本機問答：不連網、不用 API Key，答案全部由報告裡已經算好的數字組出來。
///
/// 只認得預先定義的題目。問到範圍外會回 nil，由呼叫方決定要提示什麼 —— 不會硬掰，
/// 因為這裡沒有語言模型，掰出來的東西沒有任何依據。
enum LocalAdvisorAnswers {

    struct Topic: Identifiable {
        let id: String
        /// 建議題目按鈕上顯示的文字
        let question: String
        /// 自由輸入時用來對應題目的關鍵詞，任一命中即算
        let keywords: [String]
        let build: (AdvisorReport) -> String
    }

    // MARK: - 對外接口

    /// 找不到對應題目時回 nil
    static func answer(for question: String, report: AdvisorReport) -> String? {
        matchedTopic(for: question)?.build(report)
    }

    /// 命中最多關鍵詞的題目優先，避免「每月支出」同時撞到備用金與開支結構兩題時選錯
    static func matchedTopic(for question: String) -> Topic? {
        let text = question.lowercased()
        var best: (topic: Topic, hits: Int)?
        for topic in topics {
            let hits = topic.keywords.filter { text.contains($0.lowercased()) }.count
            guard hits > 0 else { continue }
            if best == nil || hits > best!.hits {
                best = (topic, hits)
            }
        }
        return best?.topic
    }

    /// 沒命中任何題目時給的提示
    static let fallbackText = """
    這個問題我在本機答不了 —— 沒有連接語言模型時，我只能回答有明確計算依據的題目，硬掰的答案對你沒有幫助。

    你可以改問下面列出的建議題目，那些全部由你自己的數據算出來。若一定要問這題，用左上角選單的「複製問題與財務快照」，貼到電腦上的 AI 對話，再把回覆貼回來。
    """

    // MARK: - 格式化小工具

    private static func percent(_ value: Double) -> String {
        AdvisorEngine.percentText(value)
    }

    private static func money(_ value: Double, _ report: AdvisorReport) -> String {
        value.moneyString(currency: report.snapshot.baseCurrency)
    }

    private static func months(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - 題庫

    static let topics: [Topic] = [
        priorityTopic,
        emergencyFundTopic,
        surplusTopic,
        concentrationTopic,
        passiveIncomeTopic,
        allocationTopic,
        losingHoldingsTopic,
        expenseTopic,
        depositTopic,
        scoreTopic,
        exposureTopic,
        reviewCadenceTopic
    ]

    /// 建議題目列表（追問畫面的快捷按鈕）
    static var suggestedQuestions: [String] {
        topics.map(\.question)
    }

    // MARK: - 最該做的第一件事

    private static let priorityTopic = Topic(
        id: "priority",
        question: "我現在最該做的第一件事是什麼？",
        keywords: ["第一件", "最該", "優先", "先做", "從哪開始", "從何開始", "最重要"]
    ) { report in
        let critical = report.findings.filter { $0.severity == .critical }
        let warnings = report.findings.filter { $0.severity == .warning }

        if let first = critical.first {
            var text = "先處理這件：\(first.title)\n\n\(first.detail)\n\n做法：\(first.action)"
            if critical.count > 1 {
                text += "\n\n同樣列為需優先處理的還有 \(critical.count - 1) 項，但一次只推一件才推得動。這件完成再看報告的體檢清單。"
            }
            return text
        }
        if let first = warnings.first {
            return "沒有急事要救。下一步是：\(first.title)\n\n\(first.detail)\n\n做法：\(first.action)"
        }
        return "體檢沒有標出需要處理的項目，健康分 \(report.healthScore) 分（\(report.healthGrade)）。維持現在的節奏，按建議的頻率覆檢就好 —— 不用為了做事而做事。"
    }

    // MARK: - 緊急備用金

    private static let emergencyFundTopic = Topic(
        id: "emergency",
        question: "我的緊急備用金夠嗎？能撐多久？",
        keywords: ["備用金", "緊急", "撐多久", "撐幾個月", "失業", "應急", "儲備"]
    ) { report in
        let s = report.snapshot
        guard s.monthlyExpense > 0 else {
            return "這題現在算不出來 —— 還沒有足夠的支出記錄，分母是零。先在記帳頁連續記一兩個月，數字才有意義。"
        }

        let target = 6.0
        var text = "現金 \(money(s.cashBalance, report))，月均支出 \(money(s.monthlyExpense, report))，可支撐 \(months(s.emergencyMonths)) 個月。"

        if s.emergencyMonths >= target {
            text += "\n\n已達 6 個月的一般標準。"
            if s.emergencyMonths >= 12 {
                let idle = s.cashBalance - s.monthlyExpense * target
                text += "但超過 12 個月就過頭了 —— 約 \(money(idle, report)) 屬於閒置資金，被通脹慢慢磨掉。可以考慮撥一部分進定期或收息資產。"
            } else {
                text += "這一格不用再加，多出來的結餘該往投資或還債走。"
            }
        } else {
            let gap = s.monthlyExpense * target - s.cashBalance
            let surplus = s.monthlyIncome - s.monthlyExpense
            text += "\n\n距離 6 個月還差 \(money(gap, report))。"
            if surplus > 0 {
                let need = Int(ceil(gap / surplus))
                text += "按目前每月結餘 \(money(surplus, report)) 計，約 \(need) 個月補滿。這件事要排在加倉之前 —— 備用金不足時遇上突發支出，被迫在低位賣股的代價遠大於少賺的那點報酬。"
            } else {
                text += "但你目前沒有月結餘，先把收支轉正才談得上補備用金。"
            }
        }
        return text
    }

    // MARK: - 每月結餘怎麼分配

    private static let surplusTopic = Topic(
        id: "surplus",
        question: "每月結餘該怎麼分配？",
        keywords: ["結餘", "分配", "存多少", "儲蓄率", "盈餘", "每月該", "月供"]
    ) { report in
        let s = report.snapshot
        guard s.monthlyIncome > 0 || s.monthlyExpense > 0 else {
            return "還沒有收支記錄，沒辦法談分配。先記帳一兩個月。"
        }

        let surplus = s.monthlyIncome - s.monthlyExpense
        guard surplus > 0 else {
            return """
            目前每月是負結餘 \(money(abs(surplus), report))（收入 \(money(s.monthlyIncome, report))、支出 \(money(s.monthlyExpense, report))），儲蓄率 \(percent(s.savingsRate))。

            這個狀態下沒有東西可以分配。先從最大支出類別「\(s.topExpenseCategory.isEmpty ? "未分類" : s.topExpenseCategory)」下手，它佔了 \(percent(s.topExpenseRatio))。收支轉正之前，投資的討論都是次要的。
            """
        }

        var text = "每月結餘 \(money(surplus, report))，儲蓄率 \(percent(s.savingsRate))。\n\n"

        if s.emergencyMonths < 6 && s.monthlyExpense > 0 {
            text += "現階段建議全部先補備用金 —— 目前只夠 \(months(s.emergencyMonths)) 個月，未到 6 個月的標準。補滿之後再按下面的比例分流。\n\n"
        }

        let target = report.finalRiskLevel.targetAllocation
        text += """
        按你的風險等級「\(report.finalRiskLevel.title)」，目標配置是增長型 \(percent(target.growth))、收息型 \(percent(target.income))、防禦型 \(percent(target.defensive))。結餘照這個比例分：
        • 增長型 \(money(surplus * target.growth, report))
        • 收息型 \(money(surplus * target.income, report))
        • 防禦型 \(money(surplus * target.defensive, report))

        固定日子自動執行，不要看市況決定要不要投 —— 那是擇時，長期贏不了定額定期。
        """
        return text
    }

    // MARK: - 持倉集中度

    private static let concentrationTopic = Topic(
        id: "concentration",
        question: "我的持倉集中度有問題嗎？",
        keywords: ["集中", "分散", "持倉", "最大", "單一", "隻股", "重倉"]
    ) { report in
        let s = report.snapshot
        guard s.holdingsCount > 0 else {
            return "目前沒有持倉記錄，沒有集中度可談。"
        }
        guard !s.topHoldingName.isEmpty else {
            return "有 \(s.holdingsCount) 個持倉，但算不出佔比 —— 可能是市值取不到。到組合頁下拉刷新報價再看。"
        }

        var text = "共 \(s.holdingsCount) 個持倉，最大一筆是「\(s.topHoldingName)」，佔投資資產 \(percent(s.topHoldingRatio))。"

        if s.topHoldingRatio >= 0.30 {
            text += """


            這是明確的集中風險。單一標的超過三成，它的個別壞消息就足以決定你整年的報酬 —— 那不是投資判斷，是運氣。

            處理方式不是急著砍：先停止對它加倉，把新資金全部投到其他標的，讓它的佔比隨總額變大而自然稀釋。要主動減也分幾次做，別一次清掉。
            """
        } else if s.topHoldingRatio >= 0.20 {
            text += "\n\n偏高但還在可接受範圍。留意不要再對它加倉，讓新資金往別處走。"
        } else {
            text += "\n\n集中度沒有問題。"
        }

        if s.holdingsCount < 5 {
            text += "\n\n另外持倉數只有 \(s.holdingsCount) 個，本身就分散不足。不過持倉數不是越多越好 —— 5 到 15 個能兼顧分散與可管理性，超過就照顧不來。"
        }

        if !s.marketExposure.isEmpty {
            let list = s.marketExposure
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \(percent($0.value))" }
                .joined(separator: "、")
            text += "\n\n市場分布：\(list)。"
        }
        return text
    }

    // MARK: - 被動收入

    private static let passiveIncomeTopic = Topic(
        id: "passive",
        question: "被動收入還差多少才能覆蓋開支？",
        keywords: ["被動收入", "財務自由", "覆蓋", "退休", "股息", "派息", "現金流"]
    ) { report in
        let s = report.snapshot
        let annualExpense = s.monthlyExpense * 12
        guard annualExpense > 0 else {
            return "沒有支出記錄，算不出要覆蓋多少。先記帳一兩個月。"
        }

        var text = """
        年度被動收入 \(money(s.annualPassiveIncome, report))（股息 \(money(s.annualDividendIncome, report)) + 存款利息 \(money(s.depositInterest, report))），年支出 \(money(annualExpense, report))，覆蓋率 \(percent(s.dividendCoverage))。
        """

        if s.dividendCoverage >= 1 {
            text += "\n\n被動收入已經蓋過開支。這代表你不靠工作收入也能維持現在的生活水平 —— 接下來的重點從累積轉為保護：檢查收入來源夠不夠分散，別讓單一標的的減派息打穿整個現金流。"
            return text
        }

        let gap = annualExpense - s.annualPassiveIncome
        // 用你自己的實際息率推算，而不是拍一個假設數字
        let incomeBase = s.totalIncomeAssets + s.totalDepositPrincipal
        let effectiveYield = incomeBase > 0 ? s.annualPassiveIncome / incomeBase : 0

        text += "\n\n年缺口 \(money(gap, report))（每月 \(money(gap / 12, report))）。"

        if effectiveYield > 0.005 {
            let needed = gap / effectiveYield
            text += """


            你現在收息資產的實際息率是 \(percent(effectiveYield))。照這個息率，要補上缺口還需要約 \(money(needed, report)) 的收息資產。

            這個數字通常大得嚇人，那是正常的 —— 它也說明為什麼提高息率的效果遠不如降低開支：開支少 \(money(1000, report))，需要的本金就少 \(money(1000 / effectiveYield, report))。兩邊一起做才實際。
            """
        } else {
            text += "\n\n目前收息資產太少或還沒收到派息，算不出有意義的息率。先建立收息倉，這題下個月再看。"
        }
        return text
    }

    // MARK: - 資產配置與再平衡

    private static let allocationTopic = Topic(
        id: "allocation",
        question: "我的資產配置需要調整嗎？",
        keywords: ["配置", "比例", "再平衡", "平衡", "調整", "資產分布", "太多", "太少"]
    ) { report in
        let s = report.snapshot
        guard s.totalAssets > 0 else {
            return "還沒有資產數據。先在帳戶頁登記餘額、或在組合頁加入持倉。"
        }

        let target = report.finalRiskLevel.targetAllocation
        var text = """
        目前：增長型 \(percent(s.growthRatio))、收息型 \(percent(s.incomeRatio))、防禦型 \(percent(s.defensiveRatio))
        目標（\(report.finalRiskLevel.title)）：增長型 \(percent(target.growth))、收息型 \(percent(target.income))、防禦型 \(percent(target.defensive))
        """

        let needAction = report.rebalanceItems.filter(\.needsAction)
        if needAction.isEmpty {
            text += "\n\n三類都在目標的 10 個百分點以內，不用動。再平衡做得太頻繁只會多付手續費與稅。"
            return text
        }

        text += "\n\n偏離超過 10 個百分點、建議處理的："
        for item in needAction.sorted(by: { abs($0.deviation) > abs($1.deviation) }) {
            let verb = item.deltaAmount > 0 ? "增持" : "減持"
            text += "\n• \(item.bucket)：\(verb) \(money(abs(item.deltaAmount), report))（現時 \(percent(item.currentRatio))，目標 \(percent(item.targetRatio))）"
        }
        text += "\n\n優先用新資金往不足的那類投，而不是賣掉多出來的 —— 賣出會產生成本，加倉不會。"
        return text
    }

    // MARK: - 虧損持倉

    private static let losingHoldingsTopic = Topic(
        id: "losing",
        question: "虧損的持倉該怎麼處理？",
        keywords: ["虧損", "蝕", "止損", "跌", "賣掉", "浮虧", "回本"]
    ) { report in
        let s = report.snapshot
        guard s.holdingsCount > 0 else {
            return "目前沒有持倉記錄。"
        }

        var text = "整體未實現盈虧 \(money(s.unrealizedPnL, report))（\(percent(s.unrealizedPnLPercent))）。"

        if s.losingHoldings.isEmpty {
            text += "\n\n沒有虧損超過 20% 的持倉，暫時沒有需要特別檢視的標的。"
            return text
        }

        text += """


        虧損超過 20% 的：\(s.losingHoldings.joined(separator: "、"))

        判斷標準不是「跌了多少」，而是「當初買它的理由還在不在」：
        • 理由已經不成立（基本面變壞、當初看錯）→ 認賠出場，把資金放到更有把握的地方。虧損不會因為你抱著就變小。
        • 理由還成立，只是市場情緒 → 不動，或按原計劃繼續分批買。
        • 說不出當初的理由 → 這才是真正的問題。倉位建得沒有依據，賣或留都只是猜。

        要避開的是「等回本再賣」—— 成本價只對你有意義，市場不知道你買在哪裡，也不會為了你回去。
        """
        return text
    }

    // MARK: - 支出結構

    private static let expenseTopic = Topic(
        id: "expense",
        question: "我的開支哪裡最該砍？",
        keywords: ["開支", "支出", "省錢", "消費", "類別", "花費", "節省"]
    ) { report in
        let s = report.snapshot
        guard s.monthlyExpense > 0, !s.topExpenseCategory.isEmpty else {
            return "還沒有足夠的支出記錄可以分析。記帳頁連續記一兩個月，這題才答得準。"
        }

        var text = """
        月均支出 \(money(s.monthlyExpense, report))（統計 \(s.monthsOfData) 個月），最大類別是「\(s.topExpenseCategory)」，佔 \(percent(s.topExpenseRatio))，約 \(money(s.monthlyExpense * s.topExpenseRatio, report))。
        """

        if s.topExpenseRatio >= 0.40 {
            text += "\n\n單一類別佔四成以上，這裡是唯一值得花力氣的地方。省下 10% 就等於整體支出降 \(percent(s.topExpenseRatio * 0.1))，比砍五個小項目加起來都有效。"
        } else {
            text += "\n\n分布還算平均，沒有一個明顯的黑洞。這種情況下逐項砍的效果有限，把注意力放到提高收入或投資效率上，回報比省錢大。"
        }

        if s.monthsOfData < 3 {
            text += "\n\n提醒：只有 \(s.monthsOfData) 個月的數據，容易被一次性的大額支出帶偏。記滿三個月再下結論。"
        }
        return text
    }

    // MARK: - 定期存款與利息

    private static let depositTopic = Topic(
        id: "deposit",
        question: "定期到期後該續存還是轉投資？",
        keywords: ["定期", "利息", "存款", "息率", "續存", "到期", "利率"]
    ) { report in
        let s = report.snapshot
        guard s.totalDepositPrincipal > 0 else {
            return "目前沒有生息存款記錄。若你的現金戶口有利息，到帳戶頁把年利率填上，這題才算得出來。"
        }

        let depositRate = s.depositInterest / s.totalDepositPrincipal
        var text = """
        生息存款本金 \(money(s.totalDepositPrincipal, report))（儲蓄戶口 \(money(s.interestBearingCashValue, report)) + 定期 \(money(s.fixedDepositValue, report))），年利息 \(money(s.depositInterest, report))，實際息率 \(percent(depositRate))。
        """

        let incomeBase = s.totalIncomeAssets
        if incomeBase > 0 && s.annualDividendIncome > 0 {
            let dividendYield = s.annualDividendIncome / incomeBase
            text += "\n\n你收息資產的息率是 \(percent(dividendYield))。"
            if dividendYield > depositRate + 0.01 {
                text += "比存款高 \(percent(dividendYield - depositRate))，但那個差價是波動換來的 —— 收息股會跌價，定期不會。"
            } else {
                text += "跟存款差不多，甚至更低。這種情況下定期反而划算，因為它沒有價格風險。"
            }
        }

        text += """


        判斷方式：定期是你的防禦型資產。目前防禦型佔 \(percent(s.defensiveRatio))，目標是 \(percent(report.finalRiskLevel.targetAllocation.defensive))。
        """

        let defensiveTarget = report.finalRiskLevel.targetAllocation.defensive
        if s.defensiveRatio > defensiveTarget + 0.10 {
            text += "\n\n防禦型過重，到期的錢可以部分轉去增長或收息。"
        } else if s.defensiveRatio < defensiveTarget - 0.10 {
            text += "\n\n防禦型不足，建議續存。"
        } else {
            text += "\n\n比例合理，續存維持現狀就好。"
        }

        if s.emergencyMonths < 6 && s.monthlyExpense > 0 {
            text += "\n\n另外備用金只夠 \(months(s.emergencyMonths)) 個月，到期的錢優先補這一格 —— 而且要放在可以隨時動用的地方，不要再鎖進長年期定期。"
        }
        return text
    }

    // MARK: - 評分解釋

    private static let scoreTopic = Topic(
        id: "score",
        question: "我的財務健康分為什麼是這個數？",
        keywords: ["分數", "評分", "幾分", "健康分", "為什麼是", "扣分"]
    ) { report in
        var text = "健康分 \(report.healthScore)/100（\(report.healthGrade)）。細項：\n"
        for item in report.scoreBreakdown {
            text += "\n• \(item.name)：\(Int(item.score.rounded()))/\(Int(item.maxScore)) — \(item.comment)"
        }

        let weakest = report.scoreBreakdown
            .filter { $0.maxScore > 0 }
            .min { $0.ratio < $1.ratio }

        if let weakest, weakest.ratio < 0.6 {
            text += "\n\n拉低總分最多的是「\(weakest.name)」，只拿到 \(percent(weakest.ratio))。想提分先動這一項，其他都是零碎。"
        }
        text += "\n\n這個分數只用來看自己的變化趨勢，不要跟別人比 —— 每個人的收入結構與人生階段不同，同一個分數的意義不一樣。"
        return text
    }

    // MARK: - 市場與幣種曝險

    private static let exposureTopic = Topic(
        id: "exposure",
        question: "我的幣種與市場風險分散嗎？",
        keywords: ["幣種", "匯率", "美元", "港元", "外幣", "市場分布", "曝險"]
    ) { report in
        let s = report.snapshot
        guard !s.currencyExposure.isEmpty || !s.marketExposure.isEmpty else {
            return "目前沒有足夠的持倉資料算曝險。"
        }

        var text = ""
        if !s.currencyExposure.isEmpty {
            let list = s.currencyExposure
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \(percent($0.value))" }
                .joined(separator: "、")
            text += "幣種分布：\(list)\n"

            if let top = s.currencyExposure.max(by: { $0.value < $1.value }), top.value >= 0.80 {
                text += "\n\(top.key) 佔了 \(percent(top.value))，幾乎全押在一個幣上。若你的收入與開支也是這個幣種，那其實沒問題 —— 匯率風險來自「資產與負債的幣種不一致」，不是來自集中本身。反之若你未來要用別的幣花錢，這是需要處理的缺口。\n"
            }
        }

        if !s.marketExposure.isEmpty {
            let list = s.marketExposure
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \(percent($0.value))" }
                .joined(separator: "、")
            text += "\n市場分布：\(list)"
        }
        return text
    }

    // MARK: - 覆檢頻率

    private static let reviewCadenceTopic = Topic(
        id: "cadence",
        question: "多久應該檢視一次組合？",
        keywords: ["多久", "檢視", "頻率", "覆檢", "睇一次", "review"]
    ) { report in
        """
        建議節奏：
        • 每月：只記帳、對一次餘額。不看報價，不做決定。
        • 每季：看這份報告，確認三類資產的比例有沒有偏離超過 10 個百分點。
        • 每年，或人生有大變動時（換工作、結婚、生小孩、大額支出）：重做風險問卷。

        你目前的風險等級是「\(report.finalRiskLevel.title)」，可承受回撤 \(report.finalRiskLevel.toleratedDrawdown)。

        看得太密是實際的害處，不只是浪費時間 —— 每天看報價會把隨機波動誤讀成趨勢，然後在最不該動的時候動手。組合的表現主要由配置決定，不是由你檢視的次數決定。
        """
    }

    // MARK: - 複製給外部 AI 用的文字

    /// 產生可以貼到任何 AI 對話的完整內容：角色設定 + 財務快照 + 問題
    static func briefing(question: String, report: AdvisorReport) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        你是我的個人財務顧問。以下是我的財務分析報告，由 App 的本機規則引擎算出。請注意：

        1. 所有數字都已經算好，請直接引用，不要自行重算或推估。
        2. 不要推薦具體股票代號、基金或理財產品，只談資產類別、比例與執行方法。
        3. 用繁體中文回答，簡短直接，300 字以內。

        === 財務分析報告 ===
        \(LLMService.reportDigest(report))

        === 我的問題 ===
        \(trimmed.isEmpty ? "請就這份報告給我最重要的三個建議。" : trimmed)
        """
    }
}
