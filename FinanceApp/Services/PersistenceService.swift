import Foundation

/// 數據持久化服務 - 使用 JSON 文件存儲所有應用數據
final class PersistenceService: ObservableObject {
    static let shared = PersistenceService()

    // 數據存儲目錄
    private let documentsDirectory: URL

    // 文件名
    private let transactionsFile = "transactions.json"
    private let holdingsFile = "holdings.json"
    private let invoicesFile = "invoices.json"
    private let dividendsFile = "dividends.json"
    private let wealthSnapshotsFile = "wealth_snapshots.json"
    private let customCategoriesFile = "custom_categories.json"
    private let budgetsFile = "budgets.json"
    private let recurringFile = "recurring_transactions.json"
    private let priceAlertsFile = "price_alerts.json"
    private let dcaFile = "dca_positions.json"

    // 發布的數據
    @Published var transactions: [Transaction] = []
    @Published var holdings: [StockHolding] = []
    @Published var invoices: [Invoice] = []
    @Published var dividendPositions: [DividendPosition] = []
    @Published var wealthSnapshots: [WealthSnapshot] = []
    @Published var baseCurrency: Currency = .hkd   // 基準幣種（用於跨幣種結算）
    @Published var exchangeRates: [Currency: Double] = ExchangeRateProvider.defaultRates
    @Published var customCategories: [CustomCategory] = []
    @Published var budgets: [Budget] = []
    @Published var recurringTransactions: [RecurringTransaction] = []
    @Published var priceAlerts: [PriceAlert] = []
    @Published var dcaPositions: [DCAPosition] = []

    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadAll()
    }

    // MARK: - 預算管理
    func addBudget(_ budget: Budget) {
        budgets.removeAll { $0.category == budget.category && $0.year == budget.year && $0.month == budget.month }
        budgets.append(budget)
        saveBudgets()
    }

    func deleteBudget(at indexSet: IndexSet) {
        budgets.remove(atOffsets: indexSet)
        saveBudgets()
    }

    /// 取得指定年月的預算（含已用金額）
    func budgetsForMonth(year: Int, month: Int) -> [Budget] {
        let calendar = Calendar.current
        let monthTransactions = transactions.filter { tx in
            tx.type == .expense &&
            calendar.component(.year, from: tx.date) == year &&
            calendar.component(.month, from: tx.date) == month
        }

        return budgets.filter { $0.year == year && $0.month == month }.map { budget in
            var b = budget
            b.usedAmount = monthTransactions
                .filter { $0.category == budget.category }
                .reduce(0) { total, tx in
                    total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
                }
            return b
        }
    }

    // MARK: - 週期性交易
    func addRecurring(_ recurring: RecurringTransaction) {
        recurringTransactions.append(recurring)
        saveRecurring()
    }

    func deleteRecurring(at indexSet: IndexSet) {
        recurringTransactions.remove(atOffsets: indexSet)
        saveRecurring()
    }

    /// 執行到期的週期性交易
    func processDueRecurringTransactions() {
        let now = Date()
        let calendar = Calendar.current

        for i in recurringTransactions.indices where recurringTransactions[i].isEnabled {
            let rt = recurringTransactions[i]
            if let lastExec = rt.lastExecuted, calendar.isDate(lastExec, equalTo: now, toGranularity: .day) {
                continue
            }

            if rt.nextExecuteDate <= now {
                let tx = Transaction(
                    date: now,
                    amount: rt.amount,
                    type: rt.type,
                    category: rt.category,
                    note: "週期性: \(rt.title)",
                    source: .manual,
                    currency: rt.currency
                )
                transactions.insert(tx, at: 0)
                recurringTransactions[i].lastExecuted = now
            }
        }
        saveTransactions()
        saveRecurring()
    }

    // MARK: - 股價警報
    func addPriceAlert(_ alert: PriceAlert) {
        priceAlerts.append(alert)
        savePriceAlerts()
    }

    func deletePriceAlert(at indexSet: IndexSet) {
        priceAlerts.remove(atOffsets: indexSet)
        savePriceAlerts()
    }

    func updatePriceAlert(_ alert: PriceAlert) {
        if let index = priceAlerts.firstIndex(where: { $0.id == alert.id }) {
            priceAlerts[index] = alert
            savePriceAlerts()
        }
    }

    // MARK: - DCA 定期定額
    func addDCAPosition(_ position: DCAPosition) {
        dcaPositions.append(position)
        saveDCA()
    }

    func deleteDCAPosition(at indexSet: IndexSet) {
        dcaPositions.remove(atOffsets: indexSet)
        saveDCA()
    }

    func addDCARecord(to positionId: UUID, record: DCARecord) {
        guard let index = dcaPositions.firstIndex(where: { $0.id == positionId }) else { return }
        dcaPositions[index].records.append(record)
        dcaPositions[index].totalInvested += record.amount
        dcaPositions[index].totalShares += record.shares
        dcaPositions[index].investmentCount += 1
        saveDCA()
    }

    // MARK: - 月度報告
    func generateMonthlyReport(year: Int, month: Int) -> MonthlyReport {
        let calendar = Calendar.current
        let monthTxs = transactions.filter {
            calendar.component(.year, from: $0.date) == year &&
            calendar.component(.month, from: $0.date) == month
        }

        let income = monthTxs.filter { $0.type == .income }
            .reduce(0) { $0 + ExchangeRateProvider.convert($1.amount, from: $1.currency, to: baseCurrency) }
        let expense = monthTxs.filter { $0.type == .expense }
            .reduce(0) { $0 + ExchangeRateProvider.convert($1.amount, from: $1.currency, to: baseCurrency) }

        let expenseByCategory = Dictionary(grouping: monthTxs.filter { $0.type == .expense }, by: { $0.category })
            .mapValues { txs in
                txs.reduce(0) { $0 + ExchangeRateProvider.convert($1.amount, from: $1.currency, to: baseCurrency) }
            }
        let topCategory = expenseByCategory.max(by: { $0.value < $1.value })

        let monthBudgets = budgetsForMonth(year: year, month: month)
        let totalBudget = monthBudgets.reduce(0) { $0 + $1.monthlyLimit }
        let budgetStatus: String
        if totalBudget > 0 {
            budgetStatus = expense > totalBudget ? "超支" : "達標"
        } else {
            budgetStatus = "無預算"
        }

        let savingsRate = income > 0 ? ((income - expense) / income * 100) : 0

        return MonthlyReport(
            year: year,
            month: month,
            totalIncome: income,
            totalExpense: expense,
            balance: income - expense,
            topExpenseCategory: topCategory?.key,
            topExpenseAmount: topCategory?.value ?? 0,
            transactionCount: monthTxs.count,
            budgetStatus: budgetStatus,
            savingsRate: savingsRate
        )
    }

    /// 生成最近 N 個月的報告
    func recentMonthlyReports(count: Int = 6) -> [MonthlyReport] {
        let calendar = Calendar.current
        var reports: [MonthlyReport] = []
        let now = Date()

        for i in 0..<count {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                reports.append(generateMonthlyReport(year: year, month: month))
            }
        }
        return reports
    }

    // MARK: - 自定義類別管理
    func addCustomCategory(_ category: CustomCategory) {
        customCategories.append(category)
        saveCustomCategories()
    }

    func deleteCustomCategory(at indexSet: IndexSet) {
        customCategories.remove(atOffsets: indexSet)
        saveCustomCategories()
    }

    /// 獲取指定類型的所有類別名稱（預設 + 自定義）
    func allCategoryNames(for type: Transaction.TransactionType) -> [String] {
        let defaultCategories: [String]
        if type == .income {
            defaultCategories = IncomeCategory.allCases.map { $0.rawValue }
        } else {
            defaultCategories = ExpenseCategory.allCases.map { $0.rawValue }
        }
        let customNames = customCategories.filter { $0.type == type }.map { $0.name }
        return defaultCategories + customNames
    }

    /// 獲取類別圖標（包含自定義類別）
    func categoryIcon(for name: String, type: Transaction.TransactionType) -> String {
        if type == .income {
            if let cat = IncomeCategory(rawValue: name) { return cat.icon }
        } else {
            if let cat = ExpenseCategory(rawValue: name) { return cat.icon }
        }
        if let custom = customCategories.first(where: { $0.name == name }) {
            return custom.icon
        }
        return "ellipsis.circle.fill"
    }

    // MARK: - 年度支出統計
    /// 獲取所有交易年份（降序）
    var availableYears: [Int] {
        let calendar = Calendar.current
        let years = Set(transactions.compactMap { calendar.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    /// 計算指定年份的各類別支出統計
    func yearlyCategoryStats(for year: Int) -> [CategoryYearlyStats] {
        let calendar = Calendar.current
        let previousYear = year - 1

        // 當年交易
        let yearTransactions = transactions.filter {
            calendar.component(.year, from: $0.date) == year && $0.type == .expense
        }

        // 去年交易
        let prevYearTransactions = transactions.filter {
            calendar.component(.year, from: $0.date) == previousYear && $0.type == .expense
        }

        // 收集所有類別
        let allCategories = Set(yearTransactions.map { $0.category })
        let prevCategories = Set(prevYearTransactions.map { $0.category })
        let combinedCategories = allCategories.union(prevCategories)

        return combinedCategories.compactMap { category in
            let yearTxs = yearTransactions.filter { $0.category == category }
            let prevTxs = prevYearTransactions.filter { $0.category == category }

            let yearAmount = yearTxs.reduce(0) { total, tx in
                total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
            }
            let prevAmount = prevTxs.reduce(0) { total, tx in
                total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
            }

            // 只返回有數據的類別
            guard yearAmount > 0 || prevAmount > 0 else { return nil }

            return CategoryYearlyStats(
                category: category,
                icon: categoryIcon(for: category, type: .expense),
                year: year,
                amount: yearAmount,
                transactionCount: yearTxs.count,
                previousYearAmount: prevAmount
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    /// 計算指定年份的支出總覽
    func yearlyExpenseOverview(for year: Int) -> YearlyExpenseOverview {
        let calendar = Calendar.current
        let yearTransactions = transactions.filter {
            calendar.component(.year, from: $0.date) == year
        }
        let totalExpense = yearTransactions
            .filter { $0.type == .expense }
            .reduce(0) { total, tx in
                total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
            }
        let totalIncome = yearTransactions
            .filter { $0.type == .income }
            .reduce(0) { total, tx in
                total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
            }

        return YearlyExpenseOverview(
            year: year,
            totalExpense: totalExpense,
            totalIncome: totalIncome,
            categories: yearlyCategoryStats(for: year)
        )
    }

    // MARK: - 交易記錄
    func addTransaction(_ transaction: Transaction) {
        transactions.insert(transaction, at: 0)
        saveTransactions()
    }

    func deleteTransaction(at indexSet: IndexSet) {
        transactions.remove(atOffsets: indexSet)
        saveTransactions()
    }

    func updateTransaction(_ transaction: Transaction) {
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions[index] = transaction
            saveTransactions()
        }
    }

    // MARK: - 股票持倉
    func addHolding(_ holding: StockHolding) {
        holdings.append(holding)
        saveHoldings()
    }

    func deleteHolding(at indexSet: IndexSet) {
        holdings.remove(atOffsets: indexSet)
        saveHoldings()
    }

    // MARK: - 發票
    func addInvoice(_ invoice: Invoice) {
        invoices.insert(invoice, at: 0)
        saveInvoices()
    }

    func deleteInvoice(at indexSet: IndexSet) {
        invoices.remove(atOffsets: indexSet)
        saveInvoices()
    }

    func markInvoiceImported(_ invoice: Invoice) {
        if let index = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[index].importedAsTransaction = true
            saveInvoices()
        }
    }

    // MARK: - 收息股
    func addDividendPosition(_ position: DividendPosition) {
        dividendPositions.append(position)
        saveDividends()
    }

    func deleteDividendPosition(at indexSet: IndexSet) {
        dividendPositions.remove(atOffsets: indexSet)
        saveDividends()
    }

    // MARK: - 財富快照
    func saveWealthSnapshot(_ snapshot: WealthSnapshot) {
        // 移除今天的舊快照（如果有）
        let calendar = Calendar.current
        wealthSnapshots.removeAll { calendar.isDateInToday($0.date) }
        wealthSnapshots.append(snapshot)
        wealthSnapshots.sort { $0.date < $1.date }
        saveWealthSnapshots()
    }

    // MARK: - 計算屬性（以基準幣種結算）

    /// 總收入（轉換為基準幣種）
    var totalIncome: Double {
        transactions.filter { $0.type == .income }.reduce(0) { total, tx in
            total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
        }
    }

    /// 總支出（轉換為基準幣種）
    var totalExpense: Double {
        transactions.filter { $0.type == .expense }.reduce(0) { total, tx in
            total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
        }
    }

    /// 現金結餘（基準幣種）
    var cashBalance: Double {
        totalIncome - totalExpense
    }

    /// 本月收入（基準幣種）
    var monthlyIncome: Double {
        transactions.filter { $0.type == .income && $0.date.isThisMonth }
            .reduce(0) { total, tx in
                total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
            }
    }

    /// 本月支出（基準幣種）
    var monthlyExpense: Double {
        transactions.filter { $0.type == .expense && $0.date.isThisMonth }
            .reduce(0) { total, tx in
                total + ExchangeRateProvider.convert(tx.amount, from: tx.currency, to: baseCurrency)
            }
    }

    /// 本月結餘（基準幣種）
    var monthlyBalance: Double {
        monthlyIncome - monthlyExpense
    }

    /// 年度股息收入（轉換為基準幣種）
    var totalDividendAnnualIncome: Double {
        dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.annualDividendIncome, from: pos.currency, to: baseCurrency)
        }
    }

    /// 按幣種分組的股息收入
    var dividendIncomeByCurrency: [Currency: Double] {
        var result: [Currency: Double] = [:]
        for pos in dividendPositions {
            result[pos.currency, default: 0] += pos.annualDividendIncome
        }
        return result
    }

    /// 按幣種分組的交易結餘
    var cashBalanceByCurrency: [Currency: Double] {
        var incomeByCurrency: [Currency: Double] = [:]
        var expenseByCurrency: [Currency: Double] = [:]
        for tx in transactions {
            if tx.type == .income {
                incomeByCurrency[tx.currency, default: 0] += tx.amount
            } else {
                expenseByCurrency[tx.currency, default: 0] += tx.amount
            }
        }
        var result: [Currency: Double] = [:]
        for currency in incomeByCurrency.keys {
            result[currency] = (incomeByCurrency[currency] ?? 0) - (expenseByCurrency[currency] ?? 0)
        }
        for currency in expenseByCurrency.keys where result[currency] == nil {
            result[currency] = -(expenseByCurrency[currency] ?? 0)
        }
        return result
    }

    // MARK: - 存儲方法
    private func saveTransactions() {
        save(transactions, to: transactionsFile)
    }

    private func saveHoldings() {
        save(holdings, to: holdingsFile)
    }

    private func saveInvoices() {
        save(invoices, to: invoicesFile)
    }

    private func saveDividends() {
        save(dividendPositions, to: dividendsFile)
    }

    private func saveWealthSnapshots() {
        save(wealthSnapshots, to: wealthSnapshotsFile)
    }

    private func saveCustomCategories() {
        save(customCategories, to: customCategoriesFile)
    }

    private func saveBudgets() {
        save(budgets, to: budgetsFile)
    }

    private func saveRecurring() {
        save(recurringTransactions, to: recurringFile)
    }

    private func savePriceAlerts() {
        save(priceAlerts, to: priceAlertsFile)
    }

    private func saveDCA() {
        save(dcaPositions, to: dcaFile)
    }

    private func save<T: Encodable>(_ data: T, to filename: String) {
        let url = documentsDirectory.appendingPathComponent(filename)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(data)
            try data.write(to: url, options: .atomic)
        } catch {
            print("保存數據失敗: \(error.localizedDescription)")
        }
    }

    private func loadAll() {
        transactions = load(transactionsFile) ?? []
        holdings = load(holdingsFile) ?? []
        invoices = load(invoicesFile) ?? []
        dividendPositions = load(dividendsFile) ?? []
        wealthSnapshots = load(wealthSnapshotsFile) ?? []
        customCategories = load(customCategoriesFile) ?? []
        budgets = load(budgetsFile) ?? []
        recurringTransactions = load(recurringFile) ?? []
        priceAlerts = load(priceAlertsFile) ?? []
        dcaPositions = load(dcaFile) ?? []
    }

    private func load<T: Decodable>(_ filename: String) -> T? {
        let url = documentsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            print("載入數據失敗: \(error.localizedDescription)")
            return nil
        }
    }
}
