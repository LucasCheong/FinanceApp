import SwiftUI

// MARK: - 顧問狀態管理
final class AdvisorStore: ObservableObject {
    static let shared = AdvisorStore()

    @Published var profile: InvestorProfile {
        didSet { saveProfile() }
    }
    @Published var report: AdvisorReport?
    @Published var messages: [AdvisorMessage] = []
    @Published var isGenerating = false
    @Published var isPolishing = false
    @Published var isAnswering = false
    @Published var errorMessage: String?

    private let profileKey = "advisorInvestorProfile"

    private init() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(InvestorProfile.self, from: data) {
            profile = decoded
        } else {
            profile = InvestorProfile()
        }
    }

    private func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }

    /// 重做問卷
    func resetProfile() {
        profile = InvestorProfile()
        report = nil
        messages = []
    }

    /// 產生報告：本地引擎算結論，若已設定模型再潤飾
    func generateReport() async {
        guard profile.isComplete else { return }
        await MainActor.run {
            isGenerating = true
            errorMessage = nil
        }

        let quotes = await latestQuotes()
        let snapshotProfile = profile
        var newReport = AdvisorEngine.generateReport(
            persistence: PersistenceService.shared,
            quotes: quotes,
            profile: snapshotProfile
        )

        await MainActor.run {
            report = newReport
            messages = []
            isGenerating = false
        }

        guard LLMService.shared.isConfigured else { return }

        await MainActor.run { isPolishing = true }
        do {
            let narrative = try await LLMService.shared.polishReport(newReport)
            newReport.narrative = narrative
            await MainActor.run {
                report = newReport
                isPolishing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isPolishing = false
            }
        }
    }

    /// 僅重新潤飾（報告已存在時）
    func polishAgain() async {
        guard var current = report, LLMService.shared.isConfigured else { return }
        await MainActor.run {
            isPolishing = true
            errorMessage = nil
        }
        do {
            let narrative = try await LLMService.shared.polishReport(current)
            current.narrative = narrative
            await MainActor.run {
                report = current
                isPolishing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isPolishing = false
            }
        }
    }

    /// 追問
    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let current = report else { return }

        let history = messages
        await MainActor.run {
            messages.append(AdvisorMessage(role: .user, text: trimmed))
            isAnswering = true
            errorMessage = nil
        }

        if LLMService.shared.isConfigured {
            do {
                let reply = try await LLMService.shared.answer(
                    question: trimmed,
                    report: current,
                    history: history
                )
                await MainActor.run {
                    messages.append(AdvisorMessage(role: .advisor, text: reply))
                }
            } catch {
                let description = error.localizedDescription
                await MainActor.run {
                    errorMessage = description
                    messages.append(AdvisorMessage(role: .advisor, text: "抱歉，目前無法連線到 AI 服務：\(description)"))
                }
            }
        } else {
            await MainActor.run {
                messages.append(AdvisorMessage(
                    role: .advisor,
                    text: "追問功能需要連接 AI 服務。請到「設定 → AI 顧問」填入 API Key。\n\n在此之前，報告中的評分、體檢與再平衡建議全部由本機引擎計算，不需連網即可使用。"
                ))
            }
        }

        await MainActor.run { isAnswering = false }
    }

    /// 取得最新報價（沒有持倉時直接跳過網絡請求）
    private func latestQuotes() async -> [String: StockQuote] {
        let holdings = PersistenceService.shared.holdings
        guard !holdings.isEmpty else { return [:] }

        var yieldBySymbol: [String: Double] = [:]
        for stock in StockDatabase.allStocks where stock.dividendYield > 0 {
            yieldBySymbol[stock.symbol] = stock.dividendYield
        }

        // 先拉一次真實派息記錄（maxAge 0 = 不用快取），接著的報價就會帶上最新息率
        await StockService.shared.refreshDividendYields(for: holdings.map { $0.symbol }, maxAge: 0)

        let infos = holdings.map { holding in
            StockInfo(
                symbol: holding.symbol,
                name: holding.name,
                market: holding.market,
                dividendYield: StockService.shared.liveDividendYield(for: holding.symbol)
                    ?? yieldBySymbol[holding.symbol]
                    ?? 0
            )
        }
        await StockService.shared.fetchQuotes(for: infos)

        var dict: [String: StockQuote] = [:]
        for quote in StockService.shared.quotes {
            dict[quote.symbol] = quote
        }
        return dict
    }
}

// MARK: - 財務顧問主視圖
struct AdvisorView: View {
    @StateObject private var store = AdvisorStore.shared
    @State private var showingQuestionnaire = false
    @State private var showingChat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let report = store.report {
                        reportContent(report)
                    } else if store.profile.isComplete {
                        readyToGenerateCard
                    } else {
                        introCard
                    }
                    disclaimer
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("財務顧問")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingQuestionnaire = true
                        } label: {
                            Label(store.profile.isComplete ? "重做風險問卷" : "填寫風險問卷",
                                  systemImage: "list.bullet.clipboard")
                        }
                        if store.profile.isComplete {
                            Button {
                                Haptics.impact()
                                Task { await store.generateReport() }
                            } label: {
                                Label("重新分析", systemImage: "arrow.clockwise")
                            }
                        }
                        if store.report != nil && LLMService.shared.isConfigured {
                            Button {
                                Task { await store.polishAgain() }
                            } label: {
                                Label("重新生成顧問說明", systemImage: "sparkles")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingQuestionnaire) {
                AdvisorQuestionnaireView(store: store)
            }
            .sheet(isPresented: $showingChat) {
                AdvisorChatView(store: store)
            }
        }
    }

    // MARK: - 引導卡

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title)
                    .foregroundStyle(Color.financePrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("你的專屬財務顧問")
                        .font(.headline)
                    Text("結合風險問卷與你的真實記帳、持倉數據")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                bullet("list.bullet.clipboard", "7 題問卷判斷你的風險偏好")
                bullet("chart.pie.fill", "對照你的資產配置給出目標比例")
                bullet("stethoscope", "體檢集中度、備用金、儲蓄率等風險")
                bullet("arrow.left.arrow.right", "算出每一類資產該加多少、減多少")
            }

            Button {
                Haptics.impact()
                showingQuestionnaire = true
            } label: {
                Text("開始，用 2 分鐘填問卷")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.financePrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.financePrimary)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private var readyToGenerateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("問卷已完成")
                .font(.headline)
            Text("問卷結論為\(store.profile.rawRiskLevel.title)。接下來會讀取你的記帳與持倉數據，校準出真正適合你的策略。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Haptics.impact()
                Task { await store.generateReport() }
            } label: {
                HStack {
                    if store.isGenerating {
                        ProgressView().tint(.white)
                    }
                    Text(store.isGenerating ? "分析中…" : "生成我的投資策略")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.financePrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(store.isGenerating)
        }
        .cardStyle()
    }

    // MARK: - 報告內容

    @ViewBuilder
    private func reportContent(_ report: AdvisorReport) -> some View {
        scoreCard(report)
        riskLevelCard(report)
        if let narrative = report.narrative {
            narrativeCard(narrative)
        } else if LLMService.shared.isConfigured && store.isPolishing {
            polishingCard
        }
        allocationCard(report)
        rebalanceCard(report)
        findingsCard(report)
        strategyCard(report)
        askButton
        if let error = store.errorMessage {
            errorCard(error)
        }
        Text("分析基於近 \(report.snapshot.monthsOfData) 個月記帳數據，生成於 \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func scoreCard(_ report: AdvisorReport) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(report.healthScore)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(report.healthColor)
                Text("/ 100")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(report.healthGrade)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(report.healthColor.opacity(0.15))
                    .foregroundStyle(report.healthColor)
                    .clipShape(Capsule())
            }

            Text("財務健康評分")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(spacing: 10) {
                ForEach(report.scoreBreakdown) { item in
                    VStack(spacing: 4) {
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(item.score.rounded())) / \(Int(item.maxScore))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: item.ratio)
                            .tint(item.ratio >= 0.7 ? .green : (item.ratio >= 0.4 ? .orange : .red))
                        Text(item.comment)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func riskLevelCard(_ report: AdvisorReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("風險定位", systemImage: "speedometer")
                    .font(.headline)
                Spacer()
                Text(report.finalRiskLevel.title)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(report.finalRiskLevel.color.opacity(0.15))
                    .foregroundStyle(report.finalRiskLevel.color)
                    .clipShape(Capsule())
            }

            Text(report.finalRiskLevel.subtitle)
                .font(.subheadline)

            HStack(spacing: 6) {
                Image(systemName: "arrow.down.right.circle")
                    .foregroundStyle(.secondary)
                Text("可承受參考回撤 \(report.finalRiskLevel.toleratedDrawdown)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = report.calibrationNote {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private func narrativeCard(_ narrative: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("顧問說明", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if store.isPolishing {
                    ProgressView().controlSize(.small)
                }
            }
            Text(narrative)
                .font(.subheadline)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    private var polishingCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("AI 顧問正在整理說明…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .cardStyle()
    }

    private func allocationCard(_ report: AdvisorReport) -> some View {
        let target = report.finalRiskLevel.targetAllocation
        let snapshot = report.snapshot
        return VStack(alignment: .leading, spacing: 12) {
            Label("目標配置對比", systemImage: "chart.pie.fill")
                .font(.headline)

            allocationRow("增長型（低息股票）", current: snapshot.growthRatio, target: target.growth, color: .orange)
            allocationRow("收息型（含高息股）", current: snapshot.incomeRatio, target: target.income, color: .green)
            allocationRow("防禦型（現金）", current: snapshot.defensiveRatio, target: target.defensive, color: .blue)

            if snapshot.totalAssets > 0 {
                Text("息率達 \(AdvisorEngine.percentText(AdvisorEngine.incomeYieldThreshold)) 以上的股票持倉會歸入收息型，息率依近 12 個月實際派息記錄計算。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if snapshot.totalAssets <= 0 {
                Text("目前尚無資產數據，以上僅為目標比例。開始記帳並登記持倉後，這裡會顯示實際偏離。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func allocationRow(_ name: String, current: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline)
                Spacer()
                Text("\(AdvisorEngine.percentText(current)) → \(AdvisorEngine.percentText(target))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(max(current, 0), 1))
                    // 目標刻度線
                    Rectangle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 2, height: 14)
                        .offset(x: geo.size.width * min(max(target, 0), 1) - 1)
                }
            }
            .frame(height: 10)
        }
    }

    private func rebalanceCard(_ report: AdvisorReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("再平衡建議", systemImage: "arrow.left.arrow.right")
                .font(.headline)

            if report.snapshot.totalAssets <= 0 {
                Text("尚無資產數據，無法計算調整金額。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.rebalanceItems) { item in
                    HStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.bucket)
                            .font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.deltaAmount >= 0 ? "建議增持" : "建議減持")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(abs(item.deltaAmount).moneyString(currency: report.snapshot.baseCurrency))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(item.needsAction ? (item.deltaAmount >= 0 ? .green : .red) : .secondary)
                        }
                    }
                    if item.id != report.rebalanceItems.last?.id {
                        Divider()
                    }
                }

                Text("偏離目標 10% 以上才建議動手。頻繁調整會增加交易成本，建議每季或每半年檢視一次。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func findingsCard(_ report: AdvisorReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("組合體檢（\(report.findings.count) 項）", systemImage: "stethoscope")
                .font(.headline)

            if report.findings.isEmpty {
                Text("數據不足，無法進行體檢。請先記錄收支或登記持倉。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.findings) { finding in
                    AdvisorFindingRow(finding: finding)
                }
            }
        }
        .cardStyle()
    }

    private func strategyCard(_ report: AdvisorReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("策略摘要", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(report.strategySummary)
                .font(.subheadline)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    private var askButton: some View {
        Button {
            Haptics.impact()
            showingChat = true
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text("向顧問追問")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.financePrimary.opacity(0.12))
            .foregroundStyle(Color.financePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .cardStyle()
    }

    private var disclaimer: some View {
        Text("本頁分析由本機規則引擎依你的記帳與持倉數據計算，AI 僅負責把結論整理成文字。內容僅供個人財務規劃參考，不構成任何投資建議或要約，亦不涉及具體證券推薦。投資涉及風險，決策請自行判斷或諮詢持牌顧問。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

// MARK: - 體檢項目行
private struct AdvisorFindingRow: View {
    let finding: AdvisorFinding
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: finding.severity.icon)
                        .foregroundStyle(finding.severity.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(finding.severity.label)
                            .font(.caption2)
                            .foregroundStyle(finding.severity.color)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(Color.financePrimary)
                    Text(finding.action)
                        .font(.caption)
                        .foregroundStyle(Color.financePrimary)
                }
            }

            Divider()
        }
    }
}

// MARK: - 風險問卷
struct AdvisorQuestionnaireView: View {
    @ObservedObject var store: AdvisorStore
    @Environment(\.dismiss) private var dismiss

    @State private var answers: [String: Int] = [:]
    @State private var monthlyInvestable: String = ""
    @State private var goalText: String = ""

    private var isComplete: Bool {
        AdvisorQuestionBank.questions.allSatisfy { answers[$0.id] != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("以下 7 題用來判斷你的風險承受力。系統之後會用你的真實記帳與持倉數據再校準一次，所以請照實際想法作答。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(AdvisorQuestionBank.questions.enumerated()), id: \.element.id) { index, question in
                    Section {
                        ForEach(question.options) { option in
                            Button {
                                Haptics.impact()
                                answers[question.id] = option.id
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if answers[question.id] == option.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.financePrimary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("\(index + 1). \(question.title)")
                    } footer: {
                        Text(question.hint)
                    }
                }

                Section {
                    HStack {
                        Text("每月可投入")
                        Spacer()
                        TextField("選填", text: $monthlyInvestable)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                        Text(PersistenceService.shared.baseCurrency.code)
                            .foregroundStyle(.secondary)
                    }
                    TextField("你的財務目標（選填，例如：5 年內每月被動收入 8000）", text: $goalText, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("補充資料")
                } footer: {
                    Text("留空時，系統會用你記帳數據中的月均結餘來估算可投入金額。")
                }
            }
            .navigationTitle("風險問卷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { submit() }
                        .disabled(!isComplete)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("已完成 \(answers.count) / \(AdvisorQuestionBank.questions.count) 題")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                answers = store.profile.answers
                goalText = store.profile.goalText
                if store.profile.monthlyInvestable > 0 {
                    monthlyInvestable = String(format: "%.0f", store.profile.monthlyInvestable)
                }
            }
        }
    }

    private func submit() {
        var profile = InvestorProfile()
        profile.answers = answers
        profile.monthlyInvestable = Double(monthlyInvestable) ?? 0
        profile.goalText = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.completedAt = Date()
        store.profile = profile
        dismiss()
        Task { await store.generateReport() }
    }
}

// MARK: - 追問對話
struct AdvisorChatView: View {
    @ObservedObject var store: AdvisorStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    private let suggestions = [
        "我現在最該做的第一件事是什麼？",
        "我的持倉集中度會有什麼後果？",
        "每月結餘該怎麼分配？",
        "多久應該檢視一次組合？"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if store.messages.isEmpty {
                                emptyState
                            }
                            ForEach(store.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                            if store.isAnswering {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("顧問思考中…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: store.messages.count) { _ in
                        guard let lastId = store.messages.last?.id else { return }
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    TextField("輸入你的問題…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(
                                input.trimmingCharacters(in: .whitespaces).isEmpty || store.isAnswering
                                    ? Color.secondary
                                    : Color.financePrimary
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || store.isAnswering)
                }
                .padding()
            }
            .navigationTitle("追問顧問")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LLMService.shared.isConfigured
                 ? "顧問已讀取你的完整報告，可以直接問。"
                 : "尚未設定 AI 服務，追問功能無法回答。請到「設定 → AI 顧問」填入 API Key。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(suggestions, id: \.self) { text in
                Button {
                    input = text
                } label: {
                    HStack {
                        Text(text)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func messageBubble(_ message: AdvisorMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(message.role == .user ? Color.financePrimary : Color(.secondarySystemBackground))
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if message.role == .advisor { Spacer(minLength: 40) }
        }
    }

    private func send() {
        let question = input
        input = ""
        Haptics.impact()
        Task { await store.ask(question) }
    }
}
