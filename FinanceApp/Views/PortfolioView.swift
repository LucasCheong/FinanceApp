import SwiftUI
import Charts

// MARK: - 投資組合視圖 - 持倉管理 + 每日財富結算
struct PortfolioView: View {
    @StateObject private var persistence = PersistenceService.shared
    @StateObject private var stockService = StockService.shared
    @State private var showingAddHolding = false
    @State private var isRefreshing = false
    @State private var currentQuotes: [String: StockQuote] = [:]

    // 計算總股票市值
    var totalStockValue: Double {
        persistence.holdings.reduce(0) { total, holding in
            let quote = currentQuotes[holding.symbol]
            let currentPrice = quote?.currentPrice ?? holding.purchasePrice
            return total + Double(holding.shares) * currentPrice
        }
    }

    // 總投資成本
    var totalCost: Double {
        persistence.holdings.reduce(0) { $0 + Double($1.shares) * $1.purchasePrice }
    }

    // 總盈虧
    var totalPnL: Double {
        totalStockValue - totalCost
    }

    // 總盈虧百分比
    var totalPnLPercent: Double {
        totalCost > 0 ? (totalPnL / totalCost) * 100 : 0
    }

    // 總財富
    var totalWealth: Double {
        persistence.cashBalance + totalStockValue
    }

    // 今日變化
    var todayChange: Double {
        persistence.holdings.reduce(0) { total, holding in
            guard let quote = currentQuotes[holding.symbol] else { return 0 }
            return total + Double(holding.shares) * quote.change
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 總財富卡片
                    totalWealthCard

                    // 財富走勢圖
                    if persistence.wealthSnapshots.count > 1 {
                        wealthChartCard
                    }

                    // 持倉概覽
                    portfolioSummaryCard

                    // 持倉列表
                    if persistence.holdings.isEmpty {
                        emptyHoldingsView
                    } else {
                        holdingsList
                    }

                    // 結算按鈕
                    if !persistence.holdings.isEmpty {
                        settleButton
                    }
                }
                .padding()
            }
            .navigationTitle("投資組合")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshPrices() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingAddHolding) {
                AddHoldingView()
            }
            .task {
                await refreshPrices()
            }
        }
    }

    // MARK: - 總財富卡片
    private var totalWealthCard: some View {
        VStack(spacing: 8) {
            Text("財富總額")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(totalWealth.currencyString())
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.financePrimary)

            HStack(spacing: 24) {
                VStack {
                    Text("今日變動")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(todayChange >= 0 ? "+" : "")\(todayChange.currencyString())")
                        .font(.headline)
                        .foregroundStyle(Color.changeColor(todayChange))
                }

                VStack {
                    Text("總盈虧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(totalPnL >= 0 ? "+" : "")\(totalPnL.currencyString())")
                        .font(.headline)
                        .foregroundStyle(Color.changeColor(totalPnL))
                }

                VStack {
                    Text("回報率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.2f%%", totalPnLPercent))
                        .font(.headline)
                        .foregroundStyle(Color.changeColor(totalPnL))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 財富走勢圖
    private var wealthChartCard: some View {
        VStack(alignment: .leading) {
            Text("財富走勢")
                .font(.headline)

            let snapshots = Array(persistence.wealthSnapshots.suffix(30))

            if snapshots.count > 1 {
                Chart(snapshots) { snapshot in
                    LineMark(
                        x: .value("日期", snapshot.date),
                        y: .value("財富", snapshot.totalWealth)
                    )
                    .foregroundStyle(.financePrimary)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("日期", snapshot.date),
                        y: .value("財富", snapshot.totalWealth)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [.financePrimary.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                .chartYScale(domain: .automatic)
            } else {
                Text("至少需要 2 筆結算記錄才能顯示走勢圖")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
            }
        }
        .cardStyle()
    }

    // MARK: - 持倉概覽
    private var portfolioSummaryCard: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("持倉市值")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalStockValue.currencyString())
                    .font(.title3.bold())
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("投資成本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalCost.currencyString())
                    .font(.title3.bold())
            }
        }
        .cardStyle()
    }

    // MARK: - 持倉列表
    private var holdingsList: some View {
        VStack(spacing: 8) {
            ForEach(persistence.holdings) { holding in
                HoldingRow(holding: holding, quote: currentQuotes[holding.symbol])
            }
            .onDelete { offsets in
                persistence.deleteHolding(at: offsets)
            }
        }
    }

    // MARK: - 空持倉
    private var emptyHoldingsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("尚未添加持倉")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                showingAddHolding = true
            } label: {
                Label("添加股票持倉", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.financePrimary)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 每日結算按鈕
    private var settleButton: some View {
        Button {
            settleDailyWealth()
        } label: {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                Text("結算今日財富")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.financePrimary)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
    }

    // MARK: - 刷新股價
    private func refreshPrices() async {
        guard !persistence.holdings.isEmpty else { return }

        await MainActor.run { isRefreshing = true }

        let stockInfos = persistence.holdings.map { holding in
            StockInfo(symbol: holding.symbol, name: holding.name, market: holding.market, dividendYield: 0)
        }

        await stockService.fetchQuotes(for: stockInfos)

        await MainActor.run {
            for quote in stockService.quotes {
                currentQuotes[quote.symbol] = quote
            }
            isRefreshing = false
        }
    }

    // MARK: - 每日財富結算
    private func settleDailyWealth() {
        let previousWealth = persistence.wealthSnapshots.last?.totalWealth ?? totalWealth
        let dailyChange = totalWealth - previousWealth

        let snapshot = WealthSnapshot(
            date: Date(),
            cashBalance: persistence.cashBalance,
            stockValue: totalStockValue,
            totalWealth: totalWealth,
            dailyChange: dailyChange
        )

        persistence.saveWealthSnapshot(snapshot)
    }
}

// MARK: - 持倉行視圖
struct HoldingRow: View {
    let holding: StockHolding
    let quote: StockQuote?

    private var currentPrice: Double {
        quote?.currentPrice ?? holding.purchasePrice
    }

    private var currentValue: Double {
        Double(holding.shares) * currentPrice
    }

    private var costValue: Double {
        Double(holding.shares) * holding.purchasePrice
    }

    private var pnl: Double {
        currentValue - costValue
    }

    private var pnlPercent: Double {
        costValue > 0 ? (pnl / costValue) * 100 : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(holding.symbol)
                        .font(.subheadline.bold())
                    Text(holding.market.flag)
                        .font(.caption)
                }
                Text(holding.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(holding.shares) 股 @ \(holding.purchasePrice.compactString())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(currentValue.currencyString(currency: holding.market == .us ? "USD" : "HKD"))
                    .font(.subheadline.bold())
                HStack(spacing: 2) {
                    Image(systemName: pnl >= 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                    Text(String(format: "%+.2f%%", pnlPercent))
                        .font(.caption.bold())
                }
                .foregroundStyle(Color.changeColor(pnl))
                Text("\(pnl >= 0 ? "+" : "")\(pnl.currencyString(currency: holding.market == .us ? "USD" : "HKD"))")
                    .font(.caption2)
                    .foregroundStyle(Color.changeColor(pnl))
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(10)
    }
}

// MARK: - 添加持倉視圖
struct AddHoldingView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedStock: StockInfo?
    @State private var shares = ""
    @State private var purchasePrice = ""
    @State private var purchaseDate = Date()
    @State private var customSymbol = ""
    @State private var customName = ""
    @State private var market: StockHolding.StockMarket = .us
    @State private var isCustom = false

    var searchResults: [StockInfo] {
        if searchText.isEmpty {
            return StockDatabase.allStocks
        }
        return StockService.shared.searchStocks(query: searchText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("選擇股票") {
                    Toggle("手動輸入股票代碼", isOn: $isCustom)

                    if isCustom {
                        TextField("股票代碼 (如 AAPL 或 0700.HK)", text: $customSymbol)
                            .textInputAutocapitalization(.characters)
                        TextField("股票名稱", text: $customName)
                        Picker("市場", selection: $market) {
                            ForEach(StockHolding.StockMarket.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                    } else {
                        TextField("搜尋股票...", text: $searchText)

                        if let selected = selectedStock {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(selected.displayName)
                                    .font(.subheadline)
                            }
                        }

                        ForEach(searchResults.prefix(10)) { stock in
                            Button {
                                selectedStock = stock
                                market = stock.market
                                if purchasePrice.isEmpty {
                                    // 預設不填，讓用戶輸入
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(stock.symbol)
                                            .font(.subheadline.bold())
                                        Text(stock.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if stock.dividendYield > 0 {
                                        Text(stock.dividendYield.yieldPercent())
                                            .font(.caption)
                                            .foregroundStyle(.financePrimary)
                                    }
                                    if selectedStock?.symbol == stock.symbol {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.financePrimary)
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

                    DatePicker("買入日期", selection: $purchaseDate, displayedComponents: .date)
                }

                if let sharesVal = Int(shares), let priceVal = Double(purchasePrice), sharesVal > 0 {
                    Section("投資總額") {
                        Text(Double(sharesVal) * priceVal.currencyString())
                            .font(.headline)
                            .foregroundStyle(.financePrimary)
                    }
                }
            }
            .navigationTitle("添加持倉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveHolding() }
                        .disabled(!canSave)
                        .bold()
                }
            }
        }
    }

    private var canSave: Bool {
        if isCustom {
            return !customSymbol.isEmpty && Int(shares) ?? 0 > 0 && Double(purchasePrice) ?? 0 > 0
        } else {
            return selectedStock != nil && Int(shares) ?? 0 > 0 && Double(purchasePrice) ?? 0 > 0
        }
    }

    private func saveHolding() {
        guard let sharesVal = Int(shares), sharesVal > 0,
              let priceVal = Double(purchasePrice), priceVal > 0 else { return }

        let symbol: String
        let name: String

        if isCustom {
            symbol = customSymbol.uppercased()
            name = customName.isEmpty ? customSymbol.uppercased() : customName
        } else if let stock = selectedStock {
            symbol = stock.symbol
            name = stock.name
        } else {
            return
        }

        let holding = StockHolding(
            symbol: symbol,
            name: name,
            market: market,
            shares: sharesVal,
            purchasePrice: priceVal,
            purchaseDate: purchaseDate
        )

        persistence.addHolding(holding)
        dismiss()
    }
}
