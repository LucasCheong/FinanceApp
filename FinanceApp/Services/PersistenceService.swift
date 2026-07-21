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

    // 發布的數據
    @Published var transactions: [Transaction] = []
    @Published var holdings: [StockHolding] = []
    @Published var invoices: [Invoice] = []
    @Published var dividendPositions: [DividendPosition] = []
    @Published var wealthSnapshots: [WealthSnapshot] = []

    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadAll()
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

    // MARK: - 計算屬性
    var totalIncome: Double {
        transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    var totalExpense: Double {
        transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    var cashBalance: Double {
        totalIncome - totalExpense
    }

    var totalDividendAnnualIncome: Double {
        dividendPositions.reduce(0) { $0 + $1.annualDividendIncome }
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
