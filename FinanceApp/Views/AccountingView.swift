import SwiftUI

// MARK: - 記帳主視圖
struct AccountingView: View {
    @StateObject private var persistence = PersistenceService.shared
    @State private var showingAddTransaction = false
    @State private var selectedFilter: TransactionFilter = .all

    enum TransactionFilter: String, CaseIterable {
        case all = "全部"
        case income = "收入"
        case expense = "支出"
        case thisMonth = "本月"
    }

    var filteredTransactions: [Transaction] {
        switch selectedFilter {
        case .all:
            return persistence.transactions
        case .income:
            return persistence.transactions.filter { $0.type == .income }
        case .expense:
            return persistence.transactions.filter { $0.type == .expense }
        case .thisMonth:
            return persistence.transactions.filter { $0.date.isThisMonth }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 財務概覽卡片
                    summaryCard

                    // 本月概覽
                    monthlyOverviewCard

                    // 篩選器
                    filterPicker

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
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.financePrimary)
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionView()
            }
        }
    }

    // MARK: - 財務概覽卡片
    private var summaryCard: some View {
        VStack(spacing: 12) {
            Text("總資產結餘")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(persistence.cashBalance.currencyString())
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(persistence.cashBalance >= 0 ? .gain : .loss)

            HStack(spacing: 32) {
                VStack(alignment: .leading) {
                    Label("總收入", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(persistence.totalIncome.currencyString())
                        .font(.headline)
                        .foregroundStyle(.incomeColor)
                }

                VStack(alignment: .leading) {
                    Label("總支出", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(persistence.totalExpense.currencyString())
                        .font(.headline)
                        .foregroundStyle(.expenseColor)
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
                Text(persistence.transactions.monthlyIncome.currencyString())
                    .font(.title3.bold())
                    .foregroundStyle(.incomeColor)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("本月支出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(persistence.transactions.monthlyExpense.currencyString())
                    .font(.title3.bold())
                    .foregroundStyle(.expenseColor)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("本月結餘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(persistence.transactions.monthlyBalance.currencyString())
                    .font(.title3.bold())
                    .foregroundStyle(persistence.transactions.monthlyBalance >= 0 ? .gain : .loss)
            }
        }
        .cardStyle()
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

    // MARK: - 交易列表
    private var transactionsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredTransactions) { transaction in
                TransactionRow(transaction: transaction)
            }
            .onDelete { offsets in
                persistence.deleteTransaction(at: offsets)
            }
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
        if transaction.type == .income {
            return IncomeCategory(rawValue: transaction.category)?.icon ?? "banknote"
        } else {
            return ExpenseCategory(rawValue: transaction.category)?.icon ?? "creditcard"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 類別圖標
            ZStack {
                Circle()
                    .fill(transaction.type == .income ? Color.incomeColor.opacity(0.15) : Color.expenseColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .foregroundStyle(transaction.type == .income ? .incomeColor : .expenseColor)
            }

            // 詳情
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.note.isEmpty ? transaction.category : transaction.note)
                    .font(.subheadline.bold())
                HStack {
                    Text(transaction.category)
                    Text("·")
                    Text(transaction.date.shortDateString)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if transaction.source == .invoice {
                    Label("發票導入", systemImage: "doc.viewfinder")
                        .font(.caption2)
                        .foregroundStyle(.financePrimary)
                }
            }

            Spacer()

            // 金額
            Text("\(transaction.type == .income ? "+" : "-")\(transaction.amount.currencyString())")
                .font(.headline)
                .foregroundStyle(transaction.type == .income ? .incomeColor : .expenseColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.cardBackground)
        .cornerRadius(10)
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

    var currentCategories: [String] {
        type == .income
            ? IncomeCategory.allCases.map { $0.rawValue }
            : ExpenseCategory.allCases.map { $0.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("交易類型") {
                    Picker("類型", selection: $type) {
                        ForEach(Transaction.TransactionType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.systemIcon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, _ in
                        category = currentCategories.first ?? ""
                    }
                }

                Section("金額") {
                    TextField("輸入金額", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.title3)
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
            source: .manual
        )

        persistence.addTransaction(transaction)
        dismiss()
    }
}
