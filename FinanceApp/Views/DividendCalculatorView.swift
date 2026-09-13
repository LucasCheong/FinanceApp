import SwiftUI

// MARK: - 收息計算器視圖 - 計算每天/每月/每年的利息收入
struct DividendCalculatorView: View {
    @StateObject private var persistence = PersistenceService.shared
    @State private var showingAddPosition = false

    // 股息部分（以基準幣種結算）
    var dividendDailyIncome: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.dailyDividendIncome, from: pos.currency, to: persistence.baseCurrency)
        }
    }

    var dividendMonthlyIncome: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.monthlyDividendIncome, from: pos.currency, to: persistence.baseCurrency)
        }
    }

    var dividendAnnualIncome: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.annualDividendIncome, from: pos.currency, to: persistence.baseCurrency)
        }
    }

    var dividendInvestment: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.totalInvestment, from: pos.currency, to: persistence.baseCurrency)
        }
    }

    // 存款利息（儲蓄戶口 + 定期，年化口徑，已到期的定期不計）
    var depositAnnualInterest: Double { persistence.totalDepositAnnualInterest }
    var depositMonthlyInterest: Double { depositAnnualInterest / 12 }
    var depositDailyInterest: Double { depositAnnualInterest / 365 }

    /// 是否有任何存款利息來源
    var hasDepositInterest: Bool {
        !persistence.interestBearingCashAccounts.isEmpty || !persistence.activeFixedDeposits.isEmpty
    }

    // 總計 = 股息 + 存款利息
    var totalDailyIncome: Double { dividendDailyIncome + depositDailyInterest }
    var totalMonthlyIncome: Double { dividendMonthlyIncome + depositMonthlyInterest }
    var totalAnnualIncome: Double { dividendAnnualIncome + depositAnnualInterest }
    var totalInvestment: Double { dividendInvestment + persistence.totalInterestBearingPrincipal }

    var averageYield: Double {
        totalInvestment > 0 ? totalAnnualIncome / totalInvestment : 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 總收入概覽
                    totalIncomeCard

                    // 收入分解
                    incomeBreakdownCard

                    // 存款利息
                    if hasDepositInterest {
                        depositInterestCard
                    }

                    // 收息持倉列表
                    if persistence.dividendPositions.isEmpty {
                        if !hasDepositInterest {
                            emptyState
                        }
                    } else {
                        positionsList
                    }
                }
                .padding()
            }
            .navigationTitle("收息計算器")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddPosition = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.financePrimary)
                    }
                }
            }
            .sheet(isPresented: $showingAddPosition) {
                AddDividendPositionView()
            }
        }
    }

    // MARK: - 總收入卡片
    private var totalIncomeCard: some View {
        VStack(spacing: 12) {
            Text("年度被動收入")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(totalAnnualIncome.moneyString(currency: persistence.baseCurrency))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.financePrimary)

            if depositAnnualInterest > 0 {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.pie.fill")
                            .font(.caption2)
                            .foregroundStyle(.financePrimary)
                        Text("股息 \(dividendAnnualIncome.moneyString(currency: persistence.baseCurrency))")
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "percent")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("存款利息 \(depositAnnualInterest.moneyString(currency: persistence.baseCurrency))")
                            .font(.caption)
                    }
                }
            }

            HStack(spacing: 8) {
                Label("平均年息率", systemImage: "percent")
                    .font(.caption)
                Text(averageYield.yieldPercent())
                    .font(.caption.bold())
                    .foregroundStyle(.financePrimary)
            }

            HStack {
                Label("總投資額", systemImage: "dollarsign.circle")
                    .font(.caption)
                Text(totalInvestment.moneyString(currency: persistence.baseCurrency))
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 存款利息卡片
    /// 儲蓄戶口與定期的利息一律以年化口徑併入被動收入，方便與股息並列比較
    private var depositInterestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("存款利息", systemImage: "percent")
                    .font(.headline)
                Spacer()
                Text(depositAnnualInterest.moneyString(currency: persistence.baseCurrency) + " / 年")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }

            if !persistence.interestBearingCashAccounts.isEmpty {
                Label("儲蓄戶口", systemImage: AccountType.cash.systemIcon)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(persistence.interestBearingCashAccounts) { account in
                    cashInterestRow(account)
                }
            }

            if !persistence.activeFixedDeposits.isEmpty {
                if !persistence.interestBearingCashAccounts.isEmpty {
                    Divider()
                }
                Label("定期存款", systemImage: AccountType.fixedDeposit.systemIcon)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(persistence.activeFixedDeposits) { account in
                    fixedDepositRow(account)
                }
            }

            Text("在記帳分頁的「我的帳戶」中維護利率與存款條款")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    /// 儲蓄戶口一行：利率、計息餘額、年利息。餘額隨記帳浮動，沒有存期進度
    private func cashInterestRow(_ account: Account) -> some View {
        let balance = persistence.currentBalance(for: account)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(account.displayName)
                    .font(.subheadline)
                Spacer()
                Text((account.annualRate * 100).compactString() + "%")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("餘額 " + balance.moneyString(currency: account.currency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("年利息 " + account.savingsAnnualInterest(balance: balance).moneyString(currency: account.currency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// 定期一行：利率、本金、年利息、存期進度
    private func fixedDepositRow(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(account.displayName)
                    .font(.subheadline)
                Spacer()
                Text((account.annualRate * 100).compactString() + "%")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("本金 " + account.principal.moneyString(currency: account.currency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if account.isMatured {
                    Text("已到期，不再計息")
                        .font(.caption2)
                        .foregroundStyle(.gain)
                } else {
                    Text("年利息 " + account.annualInterest.moneyString(currency: account.currency))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: account.termProgress)
                .tint(account.isMatured ? .gain : .orange)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 收入分解卡片
    private var incomeBreakdownCard: some View {
        VStack(spacing: 12) {
            Text("收入分解")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                IncomeBreakdownItem(
                    title: "每日",
                    amount: totalDailyIncome,
                    currency: persistence.baseCurrency,
                    icon: "sun.max",
                    color: .orange
                )

                IncomeBreakdownItem(
                    title: "每月",
                    amount: totalMonthlyIncome,
                    currency: persistence.baseCurrency,
                    icon: "moon",
                    color: .blue
                )

                IncomeBreakdownItem(
                    title: "每年",
                    amount: totalAnnualIncome,
                    currency: persistence.baseCurrency,
                    icon: "calendar",
                    color: .green
                )
            }
        }
        .cardStyle()
    }

    // MARK: - 持倉列表
    private var positionsList: some View {
        VStack(spacing: 8) {
            ForEach(persistence.dividendPositions) { position in
                DividendPositionRow(position: position)
            }
            .onDelete { offsets in
                persistence.deleteDividendPosition(at: offsets)
            }
        }
    }

    // MARK: - 空狀態
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "percent")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("尚未添加收息股")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("點擊右上角 + 添加收息持倉")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 收入分解項目
struct IncomeBreakdownItem: View {
    let title: String
    let amount: Double
    let currency: Currency
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(amount.moneyString(currency: currency))
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - 收息持倉行
struct DividendPositionRow: View {
    let position: DividendPosition

    var body: some View {
        VStack(spacing: 8) {
            // 頂部：股票信息
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.symbol)
                        .font(.subheadline.bold())
                    Text(position.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(position.annualYield.yieldPercent())
                        .font(.headline)
                        .foregroundStyle(.financePrimary)
                    Text("年息率")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // 底部：收入明細
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(position.shares) 股 @ \(position.purchasePrice.compactString())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("投資: \(position.totalInvestment.moneyString(currency: position.currency))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 16) {
                    VStack(alignment: .center, spacing: 2) {
                        Text("日")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(position.dailyDividendIncome.moneyString(currency: position.currency))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .center, spacing: 2) {
                        Text("月")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(position.monthlyDividendIncome.moneyString(currency: position.currency))
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .center, spacing: 2) {
                        Text("年")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(position.annualDividendIncome.moneyString(currency: position.currency))
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
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
}

// MARK: - 添加收息持倉視圖
struct AddDividendPositionView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedStock: StockInfo?
    @State private var shares = ""
    @State private var annualYield = ""
    @State private var purchasePrice = ""
    @State private var frequency: Int = 4
    @State private var isCustom = false
    @State private var customSymbol = ""
    @State private var customName = ""
    @State private var currency: Currency = .hkd
    @State private var isFetchingYield = false
    @State private var yieldSourceNote = ""

    var searchResults: [StockInfo] {
        if searchText.isEmpty {
            return StockDatabase.highYieldStocks
        }
        return StockService.shared.searchStocks(query: searchText)
    }

    var canSave: Bool {
        let hasStock = isCustom ? !customSymbol.isEmpty : selectedStock != nil
        return hasStock && Int(shares) ?? 0 > 0 && Double(purchasePrice) ?? 0 > 0 && Double(annualYield) ?? 0 > 0
    }

    var previewIncome: (daily: Double, monthly: Double, annual: Double) {
        guard let sharesVal = Int(shares),
              let priceVal = Double(purchasePrice),
              let yieldVal = Double(annualYield) else {
            return (0, 0, 0)
        }
        let investment = Double(sharesVal) * priceVal
        let annual = investment * (yieldVal / 100)
        return (annual / 365, annual / 12, annual)
    }

    /// 拉取該股近 12 個月的實際派息記錄，覆寫預設息率
    private func refreshYield(for stock: StockInfo) async {
        await MainActor.run {
            isFetchingYield = true
            yieldSourceNote = ""
        }

        await StockService.shared.refreshDividendYields(for: [stock.symbol], maxAge: 0)
        let record = StockService.shared.dividendRecord(for: stock.symbol)

        await MainActor.run {
            if let record = record, record.payoutCount > 0 {
                annualYield = String(format: "%.2f", record.yield * 100)
                yieldSourceNote = "近 12 個月實際派息 \(record.payoutCount) 次，共 \(String(format: "%.3f", record.annualDividendPerShare)) / 股，按現價 \(String(format: "%.2f", record.priceAtCalculation)) 計算"
            } else if let record = record, record.hasNoDividend {
                yieldSourceNote = "近 12 個月查不到派息記錄，息率請自行填入"
            } else {
                yieldSourceNote = "取不到最新派息數據，目前顯示的是預設息率"
            }
            isFetchingYield = false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("選擇收息股") {
                    Toggle("手動輸入", isOn: $isCustom)

                    if isCustom {
                        TextField("股票代碼", text: $customSymbol)
                            .textInputAutocapitalization(.characters)
                        TextField("股票名稱", text: $customName)
                    } else {
                        TextField("搜尋高息股...", text: $searchText)

                        ForEach(searchResults.prefix(10)) { stock in
                            Button {
                                selectedStock = stock
                                annualYield = String(format: "%.2f", stock.dividendYield * 100)
                                Task { await refreshYield(for: stock) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(stock.symbol).font(.subheadline.bold())
                                        Text(stock.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text((StockService.shared.liveDividendYield(for: stock.symbol) ?? stock.dividendYield).yieldPercent())
                                        .font(.caption)
                                        .foregroundStyle(.financePrimary)
                                    if selectedStock?.symbol == stock.symbol {
                                        Image(systemName: "checkmark").foregroundStyle(.financePrimary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }

                    if isFetchingYield {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("正在拉取最新派息記錄...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !yieldSourceNote.isEmpty {
                        Text(yieldSourceNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("持倉信息") {
                    TextField("股數", text: $shares)
                        .keyboardType(.numberPad)
                    TextField("買入價格", text: $purchasePrice)
                        .keyboardType(.decimalPad)
                    TextField("年化收益率 (%)", text: $annualYield)
                        .keyboardType(.decimalPad)

                    Picker("派息頻率", selection: $frequency) {
                        Text("年度 (1次)").tag(1)
                        Text("半年度 (2次)").tag(2)
                        Text("季度 (4次)").tag(4)
                        Text("月度 (12次)").tag(12)
                    }

                    Picker("結算幣種", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { cur in
                            Text(cur.displayName).tag(cur)
                        }
                    }
                }

                // 預覽
                if canSave {
                    Section("預計收入") {
                        HStack {
                            Label("每日", systemImage: "sun.max")
                            Spacer()
                            Text(previewIncome.daily.moneyString(currency: currency))
                                .foregroundStyle(.orange)
                        }
                        HStack {
                            Label("每月", systemImage: "moon")
                            Spacer()
                            Text(previewIncome.monthly.moneyString(currency: currency))
                                .foregroundStyle(.blue)
                        }
                        HStack {
                            Label("每年", systemImage: "calendar")
                            Spacer()
                            Text(previewIncome.annual.moneyString(currency: currency))
                                .foregroundStyle(.green)
                                .bold()
                        }
                    }
                }
            }
            .navigationTitle("添加收息股")
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
        }
    }

    private func save() {
        guard let sharesVal = Int(shares), sharesVal > 0,
              let priceVal = Double(purchasePrice), priceVal > 0,
              let yieldVal = Double(annualYield), yieldVal > 0 else { return }

        let symbol: String
        let name: String

        if isCustom {
            symbol = customSymbol.uppercased()
            name = customName.isEmpty ? symbol : customName
        } else if let stock = selectedStock {
            symbol = stock.symbol
            name = stock.name
        } else {
            return
        }

        let position = DividendPosition(
            symbol: symbol,
            name: name,
            shares: sharesVal,
            annualYield: yieldVal / 100.0,  // 轉換為小數
            dividendFrequency: frequency,
            purchasePrice: priceVal,
            currency: currency
        )

        persistence.addDividendPosition(position)
        dismiss()
    }
}
