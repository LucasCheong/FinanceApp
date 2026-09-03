import Foundation
import Security

// MARK: - 大模型服務（OpenAI 兼容接口）
/// 只負責把本地規則引擎算好的結論潤飾成自然語言、以及回答追問。
/// 所有數字與判斷均來自 AdvisorEngine，模型不參與計算。
/// 未設定 API Key 時，上層會自動退回純本地結論。
final class LLMService: ObservableObject {
    static let shared = LLMService()

    // MARK: - 設定項

    private enum Keys {
        static let baseURL = "llmBaseURL"
        static let model = "llmModel"
        static let keychainAccount = "llmAPIKey"
    }

    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    /// 常見服務商預設值，供設定頁快速填入
    struct Preset: Identifiable {
        var id: String { name }
        let name: String
        let baseURL: String
        let model: String
    }

    static let presets: [Preset] = [
        Preset(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        Preset(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        Preset(name: "Moonshot Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k"),
        Preset(name: "智譜 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash"),
        Preset(name: "本地 Ollama", baseURL: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b")
    ]

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL) }
    }

    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    /// API Key 存 Keychain，不寫入 UserDefaults
    @Published var apiKey: String {
        didSet { Self.saveKeyToKeychain(apiKey) }
    }

    @Published var lastError: String?

    private init() {
        let defaults = UserDefaults.standard
        let savedURL = defaults.string(forKey: Keys.baseURL) ?? ""
        let savedModel = defaults.string(forKey: Keys.model) ?? ""
        baseURL = savedURL.isEmpty ? Self.defaultBaseURL : savedURL
        model = savedModel.isEmpty ? Self.defaultModel : savedModel
        apiKey = Self.loadKeyFromKeychain() ?? ""
    }

    /// 是否已具備調用條件
    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: normalizedBaseURL) != nil
    }

    private var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    // MARK: - Keychain

    private static let keychainService = "com.financeapp.FinanceApp.llm"

    private static func saveKeyToKeychain(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Keys.keychainAccount
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func loadKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Keys.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 對外接口

    /// 把報告潤飾為顧問口吻的敘述
    func polishReport(_ report: AdvisorReport) async throws -> String {
        let system = """
        你是一位謹慎、務實的個人財務顧問。你會收到一份由本地規則引擎計算好的財務分析結果。
        規則如下：
        1. 所有數字、比例、金額、風險等級都已由引擎算好，你必須完全照用，嚴禁自行計算、推算或修改任何數字。
        2. 不要推薦任何具體的股票代號、基金或產品名稱。只談資產類別與比例。
        3. 用繁體中文書寫，語氣像真人顧問對客戶說話，直接、坦誠，不要客套與免責套話。
        4. 結構：先用兩三句總結現況與最關鍵的問題，然後說明建議的策略方向，最後列出這個月可以立刻執行的 3 個動作。
        5. 全文控制在 400 字以內，不要使用 Markdown 標題符號。
        """
        let user = Self.reportDigest(report)
        return try await chat(system: system, messages: [(role: "user", content: user)])
    }

    /// 就報告內容進行追問
    func answer(
        question: String,
        report: AdvisorReport,
        history: [AdvisorMessage]
    ) async throws -> String {
        let system = """
        你是這位用戶的個人財務顧問。以下是他的完整財務分析報告，由本地規則引擎計算得出。
        規則如下：
        1. 只依據報告中的數據回答，不要自行編造或重新計算數字。若報告中沒有相關數據，直接說明數據不足，並告訴他需要補記哪些資料。
        2. 不推薦具體股票代號、基金或理財產品，只談資產類別、比例與執行方法。
        3. 用繁體中文，簡短直接，控制在 250 字以內。
        4. 若問題超出個人理財範圍，禮貌說明這不在你的職責內。

        === 財務分析報告 ===
        \(Self.reportDigest(report))
        """

        var messages: [(role: String, content: String)] = []
        // 只帶最近 8 輪，避免請求過長
        for message in history.suffix(8) {
            messages.append((role: message.role == .user ? "user" : "assistant", content: message.text))
        }
        messages.append((role: "user", content: question))
        return try await chat(system: system, messages: messages)
    }

    // MARK: - 報告摘要（送給模型的內容）

    /// 依用戶設定：上傳完整明細，讓模型的回答貼合真實情況
    static func reportDigest(_ report: AdvisorReport) -> String {
        let snapshot = report.snapshot
        let currency = snapshot.baseCurrency
        func money(_ value: Double) -> String { value.moneyString(currency: currency) }
        func percent(_ value: Double) -> String { AdvisorEngine.percentText(value) }

        var lines: [String] = []

        lines.append("[基準幣種] \(currency.code)")
        lines.append("[風險等級] \(report.finalRiskLevel.title)（\(report.finalRiskLevel.subtitle)），可承受回撤 \(report.finalRiskLevel.toleratedDrawdown)")
        if let note = report.calibrationNote {
            lines.append("[校準說明] \(note)")
        }
        lines.append("[財務健康評分] \(report.healthScore)/100（\(report.healthGrade)）")
        lines.append("[評分細項] " + report.scoreBreakdown
            .map { "\($0.name) \(Int($0.score.rounded()))/\(Int($0.maxScore))（\($0.comment)）" }
            .joined(separator: "、"))

        lines.append("""
        [收支] 統計月數 \(snapshot.monthsOfData)；月均收入 \(money(snapshot.monthlyIncome))；月均支出 \(money(snapshot.monthlyExpense))；儲蓄率 \(percent(snapshot.savingsRate))；最大支出類別 \(snapshot.topExpenseCategory.isEmpty ? "無記錄" : snapshot.topExpenseCategory)（佔 \(percent(snapshot.topExpenseRatio))）
        """)

        lines.append("""
        [資產] 總資產 \(money(snapshot.totalAssets))；現金 \(money(snapshot.cashBalance))（\(percent(snapshot.defensiveRatio))）；股票市值 \(money(snapshot.stockValue))（\(percent(snapshot.growthRatio))）；收息資產 \(money(snapshot.dividendValue))（\(percent(snapshot.incomeRatio))）
        """)

        lines.append("""
        [風險指標] 備用金可支撐 \(String(format: "%.1f", min(snapshot.emergencyMonths, 99))) 個月；持倉標的 \(snapshot.holdingsCount) 個；最大持倉「\(snapshot.topHoldingName.isEmpty ? "無" : snapshot.topHoldingName)」佔投資資產 \(percent(snapshot.topHoldingRatio))；未實現盈虧 \(money(snapshot.unrealizedPnL))（\(percent(snapshot.unrealizedPnLPercent))）；年股息收入 \(money(snapshot.annualDividendIncome))，覆蓋年開支 \(percent(snapshot.dividendCoverage))
        """)

        if !snapshot.marketExposure.isEmpty {
            lines.append("[市場分布] " + snapshot.marketExposure
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \(percent($0.value))" }
                .joined(separator: "、"))
        }
        if !snapshot.currencyExposure.isEmpty {
            lines.append("[幣種分布] " + snapshot.currencyExposure
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \(percent($0.value))" }
                .joined(separator: "、"))
        }
        if !snapshot.losingHoldings.isEmpty {
            lines.append("[虧損超 20% 持倉] " + snapshot.losingHoldings.joined(separator: "、"))
        }

        lines.append("[體檢發現]")
        for finding in report.findings {
            lines.append("- (\(finding.severity.label)) \(finding.title)：\(finding.detail) 建議：\(finding.action)")
        }

        lines.append("[再平衡]")
        for item in report.rebalanceItems {
            let direction = item.deltaAmount >= 0 ? "增持" : "減持"
            lines.append("- \(item.bucket)：目前 \(percent(item.currentRatio)) → 目標 \(percent(item.targetRatio))，建議\(direction) \(money(abs(item.deltaAmount)))")
        }

        lines.append("[問卷結論] 原始得分 \(report.profile.totalScore)/\(AdvisorQuestionBank.maxScore)，問卷等級 \(report.profile.rawRiskLevel.title)")
        for question in AdvisorQuestionBank.questions {
            guard let optionId = report.profile.answers[question.id],
                  let option = question.options.first(where: { $0.id == optionId }) else { continue }
            lines.append("- \(question.title) → \(option.label)")
        }
        if report.profile.monthlyInvestable > 0 {
            lines.append("[每月可投入] \(money(report.profile.monthlyInvestable))")
        }
        if !report.profile.goalText.isEmpty {
            lines.append("[自述目標] \(report.profile.goalText)")
        }

        lines.append("[引擎策略摘要]")
        lines.append(report.strategySummary)

        return lines.joined(separator: "\n")
    }

    // MARK: - 請求

    enum LLMError: LocalizedError {
        case notConfigured
        case invalidURL
        case http(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "尚未設定 AI 服務，請到「設定 → AI 顧問」填入 API Key。"
            case .invalidURL:
                return "API 位址格式不正確，請檢查 Base URL。"
            case .http(let code, let body):
                if code == 401 || code == 403 {
                    return "認證失敗（\(code)），請確認 API Key 是否正確且有效。"
                }
                let detail = body.isEmpty ? "" : "：\(body.prefix(200))"
                return "請求失敗（HTTP \(code)）\(detail)"
            case .emptyResponse:
                return "模型沒有返回內容，請稍後重試或更換模型。"
            }
        }
    }

    /// 測試連線可用性
    func testConnection() async -> Result<String, Error> {
        do {
            let reply = try await chat(
                system: "你是一個測試助手。",
                messages: [(role: "user", content: "只回覆四個字：連線正常")],
                maxTokens: 32
            )
            return .success(reply.isEmpty ? "連線正常" : reply)
        } catch {
            return .failure(error)
        }
    }

    private func chat(
        system: String,
        messages: [(role: String, content: String)],
        maxTokens: Int = 1200
    ) async throws -> String {
        guard isConfigured else { throw LLMError.notConfigured }
        guard let url = URL(string: normalizedBaseURL + "/chat/completions") else {
            throw LLMError.invalidURL
        }

        var payloadMessages: [[String: String]] = [["role": "system", "content": system]]
        payloadMessages.append(contentsOf: messages.map { ["role": $0.role, "content": $0.content] })

        let body: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": payloadMessages,
            "temperature": 0.4,
            "max_tokens": maxTokens,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
                         forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(http.statusCode, Self.extractErrorMessage(from: data) ?? text)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.emptyResponse
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyResponse }
        return trimmed
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return json["message"] as? String
    }
}
