import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 記帳主視圖
struct AccountingView: View {
    @StateObject private var persistence = PersistenceService.shared
    @State private var showingAddTransaction = false
    @State private var showingAnalysis = false
    @State private var selectedFilter: TransactionFilter = .all
    @State private var searchText = ""
    @State private var showingAccounts = false
    @State private var showingBudget = false
    @State private var showingExchangeRate = false
    @State private var showingImport = false
    @State private var showingTransfer = false
    @State private var showingAddCategory = false
    @State private var showingDeleteAllExpenses = false
    @State private var showingDeleteAllExpensesDone = false
    @State private var deletedExpenseCount = 0

    enum TransactionFilter: String, CaseIterable {
        case all = "全部"
        case income = "收入"
        case expense = "支出"
        case transfer = "轉帳"
        case thisMonth = "本月"
    }

    var filteredTransactions: [Transaction] {
        var result: [Transaction]
        switch selectedFilter {
        case .all:
            result = persistence.transactions
        case .income:
            result = persistence.transactions.filter { $0.type == .income }
        case .expense:
            result = persistence.transactions.filter { $0.type == .expense }
        case .transfer:
            result = persistence.transactions.filter { $0.type == .transfer }
        case .thisMonth:
            result = persistence.transactions.filter { $0.date.isThisMonth }
        }

        // 關鍵字搜索：類別、備註、幣種、日期
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            result = result.filter { tx in
                tx.category.localizedCaseInsensitiveContains(keyword)
                || tx.note.localizedCaseInsensitiveContains(keyword)
                || tx.currency.code.localizedCaseInsensitiveContains(keyword)
                || tx.date.shortDateString.contains(keyword)
            }
        }
        return result
    }

    private var expenseCount: Int {
        persistence.transactions.filter { $0.type == .expense }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 財務概覽卡片
                    summaryCard

                    // 本月概覽
                    monthlyOverviewCard

                    // 支出分析入口按鈕
                    analysisButton

                    // 篩選器
                    filterPicker

                    // 搜索欄
                    searchField

                    // 交易列表
                    if filteredTransactions.isEmpty {
                        emptyState
                    } else {
                        transactionsList
                    }
                }
                .padding()
            }
            .navigationTitle("記帳")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Menu {
                            Button { showingAccounts = true } label: {
                                Label("我的帳戶", systemImage: "building.columns")
                            }
                            Button { showingBudget = true } label: {
                                Label("預算管理", systemImage: "creditcard.fill")
                            }
                            Button { showingExchangeRate = true } label: {
                                Label("匯率走勢", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            Button { showingImport = true } label: {
                                Label("導入支出 (CSV / XLSX)", systemImage: "square.and.arrow.down")
                            }
                            Button { showingAddCategory = true } label: {
                                Label("新增自定義類別", systemImage: "tag.circle")
                            }
                            if persistence.transactableAccounts.count >= 2 {
                                Divider()
                                Button { showingTransfer = true } label: {
                                    Label("帳戶轉帳", systemImage: "arrow.left.arrow.right.circle")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                showingDeleteAllExpenses = true
                            } label: {
                                Label("刪除所有支出", systemImage: "trash")
                            }
                            .disabled(expenseCount == 0)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundStyle(.financePrimary)
                        }
                        Button {
                            showingAnalysis = true
                        } label: {
                            Image(systemName: "chart.bar.fill")
                                .font(.title2)
                                .foregroundStyle(.financePrimary)
                        }
                        Button {
                            showingAddTransaction = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.financePrimary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView()
            }
            .sheet(isPresented: $showingAnalysis) {
                ExpenseAnalysisView()
            }
            .sheet(isPresented: $showingAccounts) {
                AccountsView()
            }
            .sheet(isPresented: $showingBudget) {
                BudgetView()
            }
            .sheet(isPresented: $showingExchangeRate) {
                ExchangeRateView()
            }
            .sheet(isPresented: $showingImport) {
                ExpenseImportView()
            }
            .sheet(isPresented: $showingTransfer) {
                TransferView()
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCustomCategoryView()
            }
            .confirmationDialog(
                "刪除所有支出？",
                isPresented: $showingDeleteAllExpenses,
                titleVisibility: .visible
            ) {
                Button("永久刪除 \(expenseCount) 筆支出", role: .destructive) {
                    deletedExpenseCount = persistence.deleteAllExpenses()
                    showingDeleteAllExpensesDone = deletedExpenseCount > 0
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此操作無法復原。所有手動、發票及 CSV / XLSX 匯入的支出記帳都會被刪除；收入、帳戶轉帳及發票原始記錄不受影響。")
            }
            .alert("刪除完成", isPresented: $showingDeleteAllExpensesDone) {
                Button("確定") { }
            } message: {
                Text("已刪除 \(deletedExpenseCount) 筆支出記錄。")
            }
        }
    }

    // MARK: - 財務概覽卡片
    private var summaryCard: some View {
        VStack(spacing: 12) {
            Text("現金結餘")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(persistence.cashBalance.moneyString(currency: persistence.baseCurrency))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(persistence.cashBalance >= 0 ? .gain : .loss)

            Text("基準幣種: \(persistence.baseCurrency.displayName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 32) {
                VStack(alignment: .leading) {
                    Label("總收入", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(persistence.totalIncome.moneyString(currency: persistence.baseCurrency))
                        .font(.headline)
                        .foregroundStyle(.incomeColor)
                }

                VStack(alignment: .leading) {
                    Label("總支出", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(persistence.totalExpense.moneyString(currency: persistence.baseCurrency))
                        .font(.headline)
                        .foregroundStyle(.expenseColor)
                }
            }

            // 建立帳戶後額外顯示定期、信用卡結欠與淨資產
            if persistence.hasAccounts {
                Divider()
                HStack {
                    Label("帳戶淨資產", systemImage: "building.columns")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(persistence.totalAccountAssets.moneyString(currency: persistence.baseCurrency))
                        .font(.caption.bold())
                }
                if persistence.totalFixedDepositValue > 0 {
                    HStack {
                        Label("其中定期", systemImage: AccountType.fixedDeposit.systemIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(persistence.totalFixedDepositValue.moneyString(currency: persistence.baseCurrency))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
                if persistence.totalCreditCardLiability != 0 {
                    HStack {
                        Label("信用卡結欠", systemImage: AccountType.creditCard.systemIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(persistence.totalCreditCardLiability.moneyString(currency: persistence.baseCurrency))
                            .font(.caption.bold())
                            .foregroundStyle(persistence.totalCreditCardLiability > 0 ? Color.loss : Color.gain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 本月概覽
    private var monthlyOverviewCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("本月收入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(persistence.monthlyIncome.moneyString(currency: persistence.baseCurrency))
                    .font(.title3.bold())
                    .foregroundStyle(.incomeColor)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("本月支出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(persistence.monthlyExpense.moneyString(currency: persistence.baseCurrency))
                    .font(.title3.bold())
                    .foregroundStyle(.expenseColor)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("本月結餘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(persistence.monthlyBalance.moneyString(currency: persistence.baseCurrency))
                    .font(.title3.bold())
                    .foregroundStyle(persistence.monthlyBalance >= 0 ? .gain : .loss)
            }
        }
        .cardStyle()
    }

    // MARK: - 支出分析入口按鈕
    private var analysisButton: some View {
        Button {
            showingAnalysis = true
        } label: {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("支出分析")
                        .font(.subheadline.bold())
                    Text("年度各類目支出對比")
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(10)
        }
    }

    // MARK: - 篩選器
    private var filterPicker: some View {
        Picker("篩選", selection: $selectedFilter) {
            ForEach(TransactionFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 搜索欄
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索類別、備註、幣種、日期…", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.cardBackground)
        .cornerRadius(10)
    }

    // MARK: - 交易列表
    /// 卡片式列表不在 List 內，.onDelete 不會生效，故用 contextMenu 提供刪除
    private var transactionsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredTransactions) { transaction in
                TransactionRow(transaction: transaction)
                    .contextMenu {
                        Button(role: .destructive) {
                            persistence.deleteTransaction(transaction)
                        } label: {
                            Label("刪除記帳", systemImage: "trash")
                        }
                    }
            }

            Text("長按記帳可刪除")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 空狀態
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暫無交易記錄")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("點擊右上角 + 添加交易")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 交易行視圖
struct TransactionRow: View {
    let transaction: Transaction

    private var categoryIcon: String {
        PersistenceService.shared.categoryIcon(for: transaction.category, type: transaction.type)
    }

    /// 此筆記帳計入哪個帳戶，未指定時不顯示
    private var accountName: String? {
        guard let accountId = transaction.accountId,
              let account = PersistenceService.shared.accounts.first(where: { $0.id == accountId })
        else { return nil }
        return account.name
    }

    /// 轉帳目標帳戶名稱
    private var targetAccountName: String? {
        guard let targetId = transaction.transferToAccountId,
              let account = PersistenceService.shared.accounts.first(where: { $0.id == targetId })
        else { return nil }
        return account.name
    }

    private var isTransfer: Bool { transaction.type == .transfer }

    var body: some View {
        HStack(spacing: 12) {
            // 類別圖標
            ZStack {
                Circle()
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .foregroundStyle(iconForegroundColor)
            }

            // 詳情
            VStack(alignment: .leading, spacing: 2) {
                if isTransfer {
                    Text(transaction.note.isEmpty ? "帳戶轉帳" : transaction.note)
                        .font(.subheadline.bold())
                    HStack(spacing: 4) {
                        if let from = accountName, let to = targetAccountName {
                            Text(from)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                            Text(to)
                        }
                        Text("·")
                        Text(transaction.date.shortDateString)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(transaction.note.isEmpty ? transaction.category : transaction.note)
                        .font(.subheadline.bold())
                    HStack {
                        Text(transaction.category)
                        Text("·")
                        Text(transaction.date.shortDateString)
                        if let accountName {
                            Text("·")
                            Label(accountName, systemImage: "building.columns")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if transaction.source == .invoice {
                        Label("發票導入", systemImage: "doc.viewfinder")
                            .font(.caption2)
                            .foregroundStyle(.financePrimary)
                    } else if transaction.isHistoricalExpense == true {
                        Label("歷史支出 · 不影響帳戶", systemImage: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // 金額
            Text(amountText)
                .font(.headline)
                .foregroundStyle(amountColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.cardBackground)
        .cornerRadius(10)
    }

    private var iconBackgroundColor: Color {
        switch transaction.type {
        case .income: return .incomeColor
        case .expense: return .expenseColor
        case .transfer: return .financePrimary
        }
    }

    private var iconForegroundColor: Color {
        switch transaction.type {
        case .income: return .incomeColor
        case .expense: return .expenseColor
        case .transfer: return .financePrimary
        }
    }

    private var amountText: String {
        switch transaction.type {
        case .income: return "+\(transaction.amount.moneyString(currency: transaction.currency))"
        case .expense: return "-\(transaction.amount.moneyString(currency: transaction.currency))"
        case .transfer: return transaction.amount.moneyString(currency: transaction.currency)
        }
    }

    private var amountColor: Color {
        switch transaction.type {
        case .income: return .incomeColor
        case .expense: return .expenseColor
        case .transfer: return .financePrimary
        }
    }
}

// MARK: - 添加交易視圖
struct AddTransactionView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var type: Transaction.TransactionType = .expense
    @State private var amount = ""
    @State private var category = ExpenseCategory.food.rawValue
    @State private var date = Date()
    @State private var note = ""
    @State private var currency: Currency = .hkd
    @State private var accountId: UUID?

    var currentCategories: [String] {
        persistence.allCategoryNames(for: type)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("交易類型") {
                    Picker("類型", selection: $type) {
                        ForEach(Transaction.TransactionType.bookkeepingCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.systemIcon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _ in
                        category = currentCategories.first ?? ""
                        if accountId == nil {
                            currency = persistence.defaultCurrency(for: type)
                        }
                    }
                }

                Section("金額") {
                    TextField("輸入金額", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.title3)
                }

                Section("幣種") {
                    Picker("幣種", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { cur in
                            Text(cur.displayName).tag(cur)
                        }
                    }
                }

                if !persistence.transactableAccounts.isEmpty {
                    Section {
                        Picker("帳戶", selection: $accountId) {
                            Text("未指定").tag(UUID?.none)
                            ForEach(persistence.transactableAccounts) { account in
                                Text(account.selectionDisplayName).tag(Optional(account.id))
                            }
                        }
                        .onChange(of: accountId) { newValue in
                            // 選定帳戶後以帳戶幣種為準；取消選擇後恢復交易類型的預設幣種
                            if let newValue,
                               let account = persistence.accounts.first(where: { $0.id == newValue }) {
                                currency = account.currency
                            } else {
                                currency = persistence.defaultCurrency(for: type)
                            }
                        }
                    } footer: {
                        Text("現金帳戶按收入增加、支出減少；信用卡則按支出增加結欠、收入或退款減少結欠。")
                    }
                }

                Section("類別") {
                    Picker("類別", selection: $category) {
                        ForEach(currentCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }

                Section("日期") {
                    DatePicker("日期", selection: $date, displayedComponents: [.date])
                }

                Section("備註") {
                    TextField("添加備註（可選）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("新增交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveTransaction() }
                        .disabled(amount.isEmpty || Double(amount) == nil)
                        .bold()
                }
            }
            .onAppear {
                // 只有一個可記帳帳戶時預設選上，多帳戶由使用者自行指定
                if accountId == nil, persistence.transactableAccounts.count == 1,
                   let account = persistence.transactableAccounts.first {
                    accountId = account.id
                    currency = account.currency
                } else if accountId == nil {
                    currency = persistence.defaultCurrency(for: type)
                }
            }
        }
    }

    private func saveTransaction() {
        guard let amountValue = Double(amount), amountValue > 0 else { return }

        let transaction = Transaction(
            date: date,
            amount: amountValue,
            type: type,
            category: category,
            note: note,
            source: .manual,
            currency: currency,
            accountId: accountId
        )

        persistence.addTransaction(transaction)
        dismiss()
    }
}

// MARK: - 帳戶轉帳視圖
/// 在現金帳戶與信用卡之間轉移資金。轉入信用卡代表還款，
/// 不影響總收入、總支出統計。
struct TransferView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var sourceAccountId: UUID?
    @State private var targetAccountId: UUID?
    @State private var amount = ""
    @State private var currency: Currency = .hkd
    @State private var date = Date()
    @State private var note = ""

    private var transferAccounts: [Account] {
        persistence.transactableAccounts
    }

    /// 可作為目標的帳戶（排除來源帳戶）
    private var targetAccounts: [Account] {
        transferAccounts.filter { $0.id != sourceAccountId }
    }

    private var canSave: Bool {
        guard let v = Double(amount), v > 0,
              let src = sourceAccountId,
              let tgt = targetAccountId,
              src != tgt
        else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("轉出帳戶", selection: $sourceAccountId) {
                        Text("請選擇").tag(UUID?.none)
                        ForEach(transferAccounts) { account in
                            HStack {
                                Text(account.selectionDisplayName)
                                Spacer()
                                Text(persistence.currentBalance(for: account)
                                    .moneyString(currency: account.currency))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(account.id))
                        }
                    }

                    Picker("轉入帳戶", selection: $targetAccountId) {
                        Text("請選擇").tag(UUID?.none)
                        ForEach(targetAccounts) { account in
                            HStack {
                                Text(account.selectionDisplayName)
                                Spacer()
                                Text(persistence.currentBalance(for: account)
                                    .moneyString(currency: account.currency))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(account.id))
                        }
                    }
                } header: {
                    Text("帳戶")
                } footer: {
                    Text("轉帳不影響收支統計；由現金帳戶轉入信用卡即記作還款並減少結欠。")
                }

                Section("金額") {
                    TextField("輸入轉帳金額", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.title3)
                }

                Section("幣種") {
                    Picker("幣種", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { cur in
                            Text(cur.displayName).tag(cur)
                        }
                    }
                }

                Section("日期") {
                    DatePicker("日期", selection: $date, displayedComponents: [.date])
                }

                Section("備註") {
                    TextField("添加備註（可選）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("帳戶轉帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("確認轉帳") { performTransfer() }
                        .disabled(!canSave)
                        .bold()
                }
            }
            .onChange(of: sourceAccountId) { newValue in
                // 自動對齊幣種為來源帳戶的幣種
                if let newValue,
                   let account = persistence.accounts.first(where: { $0.id == newValue }) {
                    currency = account.currency
                }
                // 目標帳戶與來源相同時清空
                if targetAccountId == newValue {
                    targetAccountId = nil
                }
            }
            .onAppear {
                // 預設選中前兩個帳戶
                if transferAccounts.count >= 2 {
                    sourceAccountId = transferAccounts[0].id
                    targetAccountId = transferAccounts[1].id
                    currency = transferAccounts[0].currency
                }
            }
        }
    }

    private func performTransfer() {
        guard let amountValue = Double(amount), amountValue > 0,
              let sourceId = sourceAccountId,
              let targetId = targetAccountId
        else { return }

        persistence.performTransfer(
            from: sourceId,
            to: targetId,
            amount: amountValue,
            currency: currency,
            date: date,
            note: note
        )
        dismiss()
    }
}

// MARK: - 支出 CSV / XLSX 匯入視圖
struct ExpenseImportView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    private static let xlsxType = UTType(filenameExtension: "xlsx") ?? .data

    @State private var showingFilePicker = false
    @State private var result: ExpenseImportParser.Result?
    @State private var fileName = ""
    @State private var accountId: UUID?
    @State private var isHistoricalExpense = false
    @State private var showingDeleteLastImport = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingCopyHint = false
    @State private var importedCount: Int?
    @State private var showingImportDone = false

    var body: some View {
        NavigationStack {
            Form {
                formatSection

                if !persistence.lastImportedTransactions.isEmpty {
                    lastImportSection
                }

                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label(fileName.isEmpty ? "選擇 CSV 或 XLSX 檔案" : "重新選擇檔案", systemImage: "folder")
                    }
                    if !fileName.isEmpty {
                        HStack {
                            Text("已選檔案")
                            Spacer()
                            Text(fileName).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.caption)
                    }
                }

                if let result {
                    resultSection(result)
                }
            }
            .navigationTitle("導入支出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("導入") { performImport() }
                        .disabled((result?.validCount ?? 0) == 0)
                        .bold()
                }
            }
            .fileImporter(isPresented: $showingFilePicker,
                          allowedContentTypes: [.commaSeparatedText, Self.xlsxType]) { outcome in
                handlePick(outcome)
            }
            .confirmationDialog(
                "刪除上一次導入數據？",
                isPresented: $showingDeleteLastImport,
                titleVisibility: .visible
            ) {
                Button("刪除 \(persistence.lastImportedTransactions.count) 筆記錄", role: .destructive) {
                    persistence.deleteLastImportBatch()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("只會刪除最近一次 CSV / XLSX 導入的整個批次，其他記帳不受影響。")
            }
            .alert("匯入完成", isPresented: $showingImportDone) {
                Button("完成") { dismiss() }
            } message: {
                Text("已匯入 \(importedCount ?? 0) 筆支出記錄。")
            }
            .alert("無法讀取檔案", isPresented: $showingError) {
                Button("確定") { }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("已複製範本", isPresented: $showingCopyHint) {
                Button("確定") { }
            } message: {
                Text("範本已複製到剪貼板。貼到 Excel / Numbers，按自己的資料填完，可直接儲存為 XLSX 或另存為 CSV 後匯入。")
            }
        }
    }

    // MARK: - 格式說明
    private var formatSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("欄位順序：日期、金額、幣種、類別、備註（備註可略）")
                Text("• 日期如 2026-07-01；幣種用代號 HKD / USD / CNY 等")
                Text("• 第一列可以是標題（中英皆可），也可以直接從資料開始")
                Text("• 支援原生 Excel XLSX，也支援 CSV（建議 CSV UTF-8）")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                UIPasteboard.general.string = ExpenseImportParser.templateCSV
                Haptics.success()
                showingCopyHint = true
            } label: {
                Label("複製 CSV 範本", systemImage: "doc.on.doc")
            }
        } header: {
            Text("檔案格式")
        } footer: {
            Text("XLSX 會讀取第一個含資料的工作表；舊式 .xls 不支援，請另存為 .xlsx 或 CSV。")
        }
    }

    // MARK: - 上次匯入
    private var lastImportSection: some View {
        let transactions = persistence.lastImportedTransactions
        let dates = transactions.map(\.date)
        let earliest = dates.min()?.shortDateString ?? "—"
        let latest = dates.max()?.shortDateString ?? "—"
        let range = earliest == latest ? earliest : "\(earliest) 至 \(latest)"
        let historicalCount = transactions.filter { $0.isHistoricalExpense == true }.count

        return Section {
            LabeledContent("記錄", value: "\(transactions.count) 筆")
            LabeledContent("支出日期", value: range)
            if historicalCount > 0 {
                LabeledContent("歷史支出", value: "\(historicalCount) 筆")
            }
            Button(role: .destructive) {
                showingDeleteLastImport = true
            } label: {
                Label("刪除上一次導入數據", systemImage: "arrow.uturn.backward.circle")
            }
        } header: {
            Text("上一次導入")
        } footer: {
            Text("刪除後無法復原，只會移除最近一次導入的批次。")
        }
    }

    // MARK: - 解析結果
    @ViewBuilder
    private func resultSection(_ result: ExpenseImportParser.Result) -> some View {
        if let headerError = result.headerError {
            Section {
                Label(headerError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            Section {
                Toggle("作為歷史支出", isOn: $isHistoricalExpense)
                    .onChange(of: isHistoricalExpense) { historical in
                        if historical { accountId = nil }
                    }

                if !isHistoricalExpense && !persistence.transactableAccounts.isEmpty {
                    Picker("歸屬帳戶", selection: $accountId) {
                        Text("不指定").tag(UUID?.none)
                        ForEach(persistence.transactableAccounts) { account in
                            Text(account.selectionDisplayName).tag(Optional(account.id))
                        }
                    }
                }
            } header: {
                Text("匯入方式")
            } footer: {
                if isHistoricalExpense {
                    Text("歷史支出會保留在支出統計及分析中，但不歸屬任何帳戶，也不會扣減現金或信用卡金額。")
                } else {
                    Text("選定帳戶後，每筆支出會扣減現金帳戶餘額或增加信用卡結欠；不指定則計入未歸屬現金結餘。")
                }
            }

            Section {
                HStack {
                    Label("可匯入", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Text("\(result.validCount) 筆").bold()
                }
                if result.invalidCount > 0 {
                    HStack {
                        Label("將略過", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
                        Spacer()
                        Text("\(result.invalidCount) 筆").bold()
                    }
                }
            } header: {
                Text("預覽")
            }

            Section("明細") {
                ForEach(result.rows) { row in
                    rowView(row)
                }
            }
        }
    }

    private func rowView(_ row: ExpenseImportParser.ParsedRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(row.isValid ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                if let tx = row.transaction {
                    Text("\(tx.category) · \(tx.amount.moneyString(currency: tx.currency))")
                        .font(.subheadline)
                    Text(tx.date.shortDateString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.summary)
                        .font(.subheadline)
                    Text("第 \(row.lineNumber) 列：\(row.errorReason ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - 行為
    private func handlePick(_ outcome: Result<URL, Error>) {
        switch outcome {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                fileName = url.lastPathComponent
                if url.pathExtension.lowercased() == "xlsx" {
                    result = try ExpenseImportParser.parseXLSX(
                        at: url,
                        defaultCurrency: persistence.defaultExpenseCurrency
                    )
                } else {
                    let data = try Data(contentsOf: url)
                    guard let text = ExpenseImportParser.decode(data) else {
                        errorMessage = "檔案編碼無法識別。請在 Excel 另存為「CSV UTF-8」後重試。"
                        showingError = true
                        return
                    }
                    result = ExpenseImportParser.parse(text, defaultCurrency: persistence.defaultExpenseCurrency)
                }
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func performImport() {
        guard let result, result.validCount > 0 else { return }
        importedCount = persistence.addImportedTransactions(
            result.validTransactions,
            accountId: accountId,
            asHistorical: isHistoricalExpense
        )
        showingImportDone = true
    }
}
