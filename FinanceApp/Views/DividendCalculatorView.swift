import SwiftUI

// MARK: - 收息計算器視圖 - 計算每天/每月/每年的利息收入
struct DividendCalculatorView: View {
    @StateObject private var persistence = PersistenceService.shared
    @State private var showingAddPosition = false

    // 總計（以基準幣種結算）
    var totalDailyIncome: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.dailyDividendIncome, from: pos.currency, to: persistence.baseCurrency)
        }
    }

    var totalMonthlyIncome: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.monthlyDividendIncome, from: pos.currency, to: persistence.baseCurrency)
        }
    }

    var totalAnnualIncome: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.annualDividendIncome, from: pos.currency, to: persistence.baseCurrency)
        }
    }

    var totalInvestment: Double {
        persistence.dividendPositions.reduce(0) { total, pos in
            total + ExchangeRateProvider.convert(pos.totalInvestment, from: pos.currency, to: persistence.baseCurrency)
        }
    }

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

                    // 收息持倉列表
                    if persistence.dividendPositions.isEmpty {
                        emptyState
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
            Text("年度股息收入")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(totalAnnualIncome.moneyString(currency: persistence.baseCurrency))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.financePrimary)

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
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(stock.symbol).font(.subheadline.bold())
                                        Text(stock.name).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(stock.dividendYield.yieldPercent())
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
