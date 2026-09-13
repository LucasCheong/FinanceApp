import SwiftUI

// MARK: - 帳戶管理視圖
/// 現金戶口、投資帳戶、定期存款統一在這裡維護。
/// 現金帳戶餘額 = 起始餘額 + 記帳收支；投資帳戶連動組合市值；定期按利率計息。
struct AccountsView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddAccount = false
    @State private var editingAccount: Account?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    totalAssetsCard

                    if persistence.hasAccounts && persistence.unassignedTransactionCount > 0 {
                        unassignedBanner
                    }

                    if persistence.activeAccounts.isEmpty {
                        emptyState
                    } else {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            if !accounts(of: type).isEmpty {
                                section(title: type.rawValue, icon: type.systemIcon, accounts: accounts(of: type))
                            }
                        }
                    }

                    if !archivedAccounts.isEmpty {
                        archivedSection
                    }
                }
                .padding()
            }
            .navigationTitle("我的帳戶")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.financePrimary)
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AccountEditorView()
            }
            .sheet(item: $editingAccount) { account in
                AccountEditorView(account: account)
            }
        }
    }

    private func accounts(of type: AccountType) -> [Account] {
        persistence.activeAccounts.filter { $0.type == type }
    }

    private var archivedAccounts: [Account] {
        persistence.accounts.filter { $0.isArchived }
    }

    // MARK: - 總資產卡片
    private var totalAssetsCard: some View {
        VStack(spacing: 12) {
            Text("帳戶總資產")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(persistence.totalAccountAssets.moneyString(currency: persistence.baseCurrency))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.financePrimary)

            Text("基準幣種: \(persistence.baseCurrency.displayName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                AssetBreakdownItem(
                    title: "現金",
                    amount: persistence.totalCashAccountBalance,
                    currency: persistence.baseCurrency,
                    icon: AccountType.cash.systemIcon,
                    color: .financePrimary
                )
                AssetBreakdownItem(
                    title: "定期",
                    amount: persistence.totalFixedDepositValue,
                    currency: persistence.baseCurrency,
                    icon: AccountType.fixedDeposit.systemIcon,
                    color: .orange
                )
                if persistence.activeAccounts.contains(where: { $0.type == .investment }) {
                    AssetBreakdownItem(
                        title: "投資",
                        amount: persistence.portfolioMarketValue(in: persistence.baseCurrency),
                        currency: persistence.baseCurrency,
                        icon: AccountType.investment.systemIcon,
                        color: .green
                    )
                }
            }

            if persistence.totalFixedDepositAnnualInterest > 0 {
                HStack {
                    Label("定期年化利息", systemImage: "percent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(persistence.totalFixedDepositAnnualInterest.moneyString(currency: persistence.baseCurrency))
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 未歸屬交易提示
    /// 建立帳戶前記下的交易沒有帳戶欄位，這些金額仍計入總結餘但不屬於任何帳戶。
    private var unassignedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("有 \(persistence.unassignedTransactionCount) 筆記帳未指定帳戶")
                    .font(.subheadline.bold())
            }

            Text("這些金額仍計入總結餘（淨額 \(persistence.unassignedCashFlow.moneyString(currency: persistence.baseCurrency))），但不屬於任何帳戶。可一次性歸入指定帳戶。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !persistence.transactableAccounts.isEmpty {
                Menu {
                    ForEach(persistence.transactableAccounts) { account in
                        Button(account.displayName) {
                            persistence.assignUnassignedTransactions(to: account.id)
                        }
                    }
                } label: {
                    Label("全部歸入…", systemImage: "arrow.right.circle.fill")
                        .font(.caption.bold())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.12))
        .cornerRadius(12)
    }

    // MARK: - 帳戶分組
    private func section(title: String, icon: String, accounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Text("\(accounts.count) 個")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(accounts) { account in
                Button {
                    editingAccount = account
                } label: {
                    AccountRow(account: account)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        editingAccount = account
                    } label: {
                        Label("編輯", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        persistence.deleteAccount(account)
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - 已封存帳戶
    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("已封存", systemImage: "archivebox")
                    .font(.headline)
                Spacer()
                Text("不計入總資產")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(archivedAccounts) { account in
                Button {
                    editingAccount = account
                } label: {
                    HStack {
                        Image(systemName: account.type.systemIcon)
                            .foregroundStyle(.secondary)
                        Text(account.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(account.currency.code)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(Color.cardBackground)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 空狀態
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("尚未建立帳戶")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("點擊右上角 + 建立現金戶口、投資帳戶或定期存款")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Text("未建立帳戶時，記帳結餘沿用原本的收支淨額計算")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 資產分解項目
struct AssetBreakdownItem: View {
    let title: String
    let amount: Double
    let currency: Currency
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(amount.moneyString(currency: currency))
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - 帳戶行
struct AccountRow: View {
    @StateObject private var persistence = PersistenceService.shared
    let account: Account

    private var balance: Double {
        persistence.currentBalance(for: account)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.subheadline.bold())
                    if !account.institution.isEmpty {
                        Text(account.institution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(balance.moneyString(currency: account.currency))
                        .font(.headline)
                        .foregroundStyle(balance >= 0 ? Color.primary : Color.loss)
                    Text(account.currency.code)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if account.currency != persistence.baseCurrency {
                Text("≈ \(persistence.balanceInBaseCurrency(for: account).moneyString(currency: persistence.baseCurrency))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if account.type == .fixedDeposit {
                Divider()
                fixedDepositDetail
            }

            if account.type == .investment {
                Divider()
                Text("餘額連動組合分頁的持倉市值")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !account.note.isEmpty {
                Text(account.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.financePrimary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: 定期存款明細
    private var fixedDepositDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\((account.annualRate * 100).compactString())% 年利率", systemImage: "percent")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
                Text(account.compounding.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已累積利息")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(account.accruedInterest.moneyString(currency: account.currency))
                        .font(.caption.bold())
                        .foregroundStyle(.gain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("年化利息")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(account.annualInterest.moneyString(currency: account.currency))
                        .font(.caption.bold())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("到期本息")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(account.maturityValue.moneyString(currency: account.currency))
                        .font(.caption.bold())
                }
            }

            ProgressView(value: account.termProgress)
                .tint(account.isMatured ? .gain : .financePrimary)

            HStack {
                Text("起息 \(account.startDate.formatted(as: "yyyy/MM/dd"))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if account.isMatured {
                    Text("已到期")
                        .font(.caption2.bold())
                        .foregroundStyle(.gain)
                } else {
                    Text("到期 \(account.maturityDate.formatted(as: "yyyy/MM/dd"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - 帳戶編輯視圖
/// 新增與編輯共用。傳入 account 為編輯模式，不傳為新增模式。
struct AccountEditorView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    private let existing: Account?

    @State private var name: String
    @State private var institution: String
    @State private var type: AccountType
    @State private var currency: Currency
    @State private var note: String
    @State private var isArchived: Bool

    @State private var initialBalance: String
    @State private var principal: String
    /// 以百分比輸入（3.5 代表 3.5%），存入模型時除以 100
    @State private var ratePercent: String
    @State private var startDate: Date
    @State private var termMonths: String
    @State private var compounding: InterestCompounding

    @State private var showingDeleteAlert = false

    init(account: Account? = nil) {
        existing = account
        _name = State(initialValue: account?.name ?? "")
        _institution = State(initialValue: account?.institution ?? "")
        _type = State(initialValue: account?.type ?? .cash)
        _currency = State(initialValue: account?.currency ?? .hkd)
        _note = State(initialValue: account?.note ?? "")
        _isArchived = State(initialValue: account?.isArchived ?? false)
        _initialBalance = State(initialValue: Self.numberText(account?.initialBalance))
        _principal = State(initialValue: Self.numberText(account?.principal))
        _ratePercent = State(initialValue: Self.numberText(account.map { $0.annualRate * 100 }))
        _startDate = State(initialValue: account?.startDate ?? Date())
        _termMonths = State(initialValue: String(account?.termMonths ?? 12))
        _compounding = State(initialValue: account?.compounding ?? .simple)
    }

    /// 0 顯示為空字串，避免每次編輯都要先刪掉一個 0
    private static func numberText(_ value: Double?) -> String {
        guard let value, value != 0 else { return "" }
        return String(format: value == value.rounded() ? "%.0f" : "%.2f", value)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 依當前輸入組出的草稿，用來即時預覽定期利息
    private var draft: Account {
        var account = existing ?? Account(name: name)
        account.name = name.trimmingCharacters(in: .whitespaces)
        account.institution = institution.trimmingCharacters(in: .whitespaces)
        account.type = type
        account.currency = currency
        account.note = note
        account.isArchived = isArchived
        account.initialBalance = Double(initialBalance) ?? 0
        account.principal = Double(principal) ?? 0
        account.annualRate = (Double(ratePercent) ?? 0) / 100
        account.startDate = startDate
        account.termMonths = max(1, Int(termMonths) ?? 12)
        account.compounding = compounding
        return account
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("帳戶類型") {
                    Picker("類型", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.systemIcon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(type.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("基本資料") {
                    TextField("帳戶名稱（例如：澳門幣儲蓄）", text: $name)
                    TextField("開戶機構（例如：中國銀行）", text: $institution)
                    Picker("幣種", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { cur in
                            Text(cur.displayName).tag(cur)
                        }
                    }
                }

                switch type {
                case .cash:
                    cashSection
                case .investment:
                    investmentSection
                case .fixedDeposit:
                    fixedDepositSection
                    interestPreview
                }

                Section("備註") {
                    TextField("添加備註（可選）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Toggle("封存此帳戶", isOn: $isArchived)
                } footer: {
                    Text("封存後不計入總資產，也不會出現在記帳的帳戶選項中，但歷史記錄保留。")
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("刪除帳戶", systemImage: "trash")
                        }
                    } footer: {
                        Text("刪除後，已登記到此帳戶的記帳會變回「未指定帳戶」，交易本身不會被刪除。")
                    }
                }
            }
            .navigationTitle(existing == nil ? "新增帳戶" : "編輯帳戶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .bold()
                }
            }
            .alert("刪除帳戶？", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("刪除", role: .destructive) {
                    if let existing {
                        persistence.deleteAccount(existing)
                    }
                    dismiss()
                }
            } message: {
                Text("此帳戶的餘額與定期利息會從總資產移除。")
            }
        }
    }

    // MARK: - 現金帳戶
    private var cashSection: some View {
        Section {
            HStack {
                Text("起始餘額")
                Spacer()
                TextField("0", text: $initialBalance)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(currency.code)
                    .foregroundStyle(.secondary)
            }

            if let existing, existing.type == .cash {
                HStack {
                    Text("記帳淨額")
                    Spacer()
                    Text(persistence.netTransactionAmount(for: existing.id, in: currency)
                        .moneyString(currency: currency))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("目前餘額")
                    Spacer()
                    Text(persistence.currentBalance(for: draft).moneyString(currency: currency))
                        .bold()
                }
            }
        } footer: {
            Text("填入開始使用本 App 時的戶口餘額。之後每筆記帳指定此帳戶，餘額會自動加減。")
        }
    }

    // MARK: - 投資帳戶
    private var investmentSection: some View {
        Section {
            HStack {
                Text("目前市值")
                Spacer()
                Text(persistence.portfolioMarketValue(in: currency).moneyString(currency: currency))
                    .bold()
            }
        } footer: {
            Text("投資帳戶餘額由組合分頁的持倉自動計算（現價 × 股數，取不到報價時用成本價）。建立多個投資帳戶時，總資產只會計算一次組合市值，避免重複。")
        }
    }

    // MARK: - 定期存款
    private var fixedDepositSection: some View {
        Section("定期存款條款") {
            HStack {
                Text("存入本金")
                Spacer()
                TextField("0", text: $principal)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(currency.code)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("年利率")
                Spacer()
                TextField("3.5", text: $ratePercent)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text("%")
                    .foregroundStyle(.secondary)
            }

            DatePicker("起息日", selection: $startDate, displayedComponents: [.date])

            HStack {
                Text("存期")
                Spacer()
                TextField("12", text: $termMonths)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("個月")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach([3, 6, 12, 24, 36], id: \.self) { months in
                    Button("\(months)月") {
                        termMonths = String(months)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            Picker("計息方式", selection: $compounding) {
                ForEach(InterestCompounding.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
        }
    }

    // MARK: - 利息預覽
    private var interestPreview: some View {
        Section {
            LabeledRow(title: "到期日", value: draft.maturityDate.formatted(as: "yyyy/MM/dd"))
            LabeledRow(title: "到期總利息", value: draft.maturityInterest.moneyString(currency: currency), highlight: true)
            LabeledRow(title: "到期本息合計", value: draft.maturityValue.moneyString(currency: currency))
            LabeledRow(title: "年化利息", value: draft.annualInterest.moneyString(currency: currency))
            LabeledRow(title: "每月約", value: draft.monthlyInterest.moneyString(currency: currency))
            LabeledRow(title: "每日約", value: draft.dailyInterest.moneyString(currency: currency))
        } header: {
            Text("利息試算")
        } footer: {
            Text("年化利息會計入收息頁的年度收入。存期不足一年時仍以年化口徑呈現，方便與股息並列比較。")
        }
    }

    private func save() {
        var account = draft
        if existing == nil {
            account.createdAt = Date()
            persistence.addAccount(account)
        } else {
            persistence.updateAccount(account)
        }
        dismiss()
    }
}

// MARK: - 標籤數值行
struct LabeledRow: View {
    let title: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold(highlight)
                .foregroundStyle(highlight ? Color.financePrimary : Color.primary)
        }
        .font(.subheadline)
    }
}
