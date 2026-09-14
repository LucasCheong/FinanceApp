import SwiftUI
import Charts

// MARK: - 投資組合視圖 - 持倉管理 + 每日財富結算
struct PortfolioView: View {
    @StateObject private var persistence = PersistenceService.shared
    @StateObject private var stockService = StockService.shared
    @State private var showingAddHolding = false
    @State private var isRefreshing = false
    @State private var currentQuotes: [String: StockQuote] = [:]
    @State private var showingAssetAllocation = false

    // 計算總股票市值（轉換為基準幣種）
    var totalStockValue: Double {
        persistence.holdings.reduce(0) { total, holding in
            let quote = currentQuotes[holding.symbol]
            let currentPrice = quote?.currentPrice ?? holding.purchasePrice
            let value = Double(holding.shares) * currentPrice
            let currency = Currency.from(market: holding.market)
            return total + ExchangeRateProvider.convert(value, from: currency, to: persistence.baseCurrency)
        }
    }

    // 總投資成本（轉換為基準幣種）
    var totalCost: Double {
        persistence.holdings.reduce(0) { total, holding in
            let cost = Double(holding.shares) * holding.purchasePrice
            let currency = Currency.from(market: holding.market)
            return total + ExchangeRateProvider.convert(cost, from: currency, to: persistence.baseCurrency)
        }
    }

    // 總盈虧（基準幣種）
    var totalPnL: Double {
        totalStockValue - totalCost
    }

    // 總盈虧百分比
    var totalPnLPercent: Double {
        totalCost > 0 ? (totalPnL / totalCost) * 100 : 0
    }

    // 總財富（基準幣種）
    var totalWealth: Double {
        persistence.cashBalance + totalStockValue
    }

    // 今日變化（轉換為基準幣種）
    var todayChange: Double {
        persistence.holdings.reduce(0) { total, holding in
            guard let quote = currentQuotes[holding.symbol] else { return total }
            let change = Double(holding.shares) * quote.change
            let currency = Currency.from(market: holding.market)
            return total + ExchangeRateProvider.convert(change, from: currency, to: persistence.baseCurrency)
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
                    HStack {
                        Button {
                            showingAssetAllocation = true
                        } label: {
                            Image(systemName: "chart.pie.fill")
                        }
                        Button {
                            showingAddHolding = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        Button {
                            Task { await refreshPrices() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddHolding) {
                AddHoldingView()
            }
            .sheet(isPresented: $showingAssetAllocation) {
                AssetAllocationView()
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

            Text(totalWealth.moneyString(currency: persistence.baseCurrency))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.financePrimary)

            Text("基準幣種: \(persistence.baseCurrency.displayName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 24) {
                VStack {
                    Text("今日變動")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(todayChange >= 0 ? "+" : "")\(todayChange.moneyString(currency: persistence.baseCurrency))")
                        .font(.headline)
                        .foregroundStyle(Color.changeColor(todayChange))
                }

                VStack {
                    Text("總盈虧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(totalPnL >= 0 ? "+" : "")\(totalPnL.moneyString(currency: persistence.baseCurrency))")
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
                Text(totalStockValue.moneyString(currency: persistence.baseCurrency))
                    .font(.title3.bold())
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("投資成本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalCost.moneyString(currency: persistence.baseCurrency))
                    .font(.title3.bold())
            }
        }
        .cardStyle()
    }

    // MARK: - 持倉列表
    /// 卡片式列表不在 List 內，.onDelete 不會生效，故用 contextMenu 提供刪除
    private var holdingsList: some View {
        VStack(spacing: 8) {
            ForEach(persistence.holdings) { holding in
                HoldingRow(holding: holding, quote: currentQuotes[holding.symbol])
                    .contextMenu {
                        Button(role: .destructive) {
                            persistence.deleteHolding(holding)
                        } label: {
                            Label("刪除持倉", systemImage: "trash")
                        }
                    }
            }

            Text("長按持倉可刪除")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
            StockInfo(
                symbol: holding.symbol,
                name: holding.name,
                market: holding.market,
                dividendYield: stockService.liveDividendYield(for: holding.symbol) ?? 0
            )
        }

        // 息率依實際派息記錄計算，6 小時內重用快取，不用每次下拉都重拉
        await stockService.refreshDividendYields(for: persistence.holdings.map { $0.symbol })
        await stockService.fetchQuotes(for: stockInfos)

        await MainActor.run {
            for quote in stockService.quotes {
                currentQuotes[quote.symbol] = quote
            }
            // 同步到持倉快取，帳戶頁的總資產才拿得到同一份市值
            stockService.cacheHoldingQuotes(stockService.quotes)
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
            dailyChange: dailyChange,
            baseCurrency: persistence.baseCurrency
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
                Text(currentValue.moneyString(currency: Currency.from(market: holding.market)))
                    .font(.subheadline.bold())
                HStack(spacing: 2) {
                    Image(systemName: pnl >= 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                    Text(String(format: "%+.2f%%", pnlPercent))
                        .font(.caption.bold())
                }
                .foregroundStyle(Color.changeColor(pnl))
                Text("\(pnl >= 0 ? "+" : "")\(pnl.moneyString(currency: Currency.from(market: holding.market)))")
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

    // 手動輸入代碼後的查價狀態
    @State private var isLookingUp = false
    @State private var lookupResult: StockQuote?
    @State private var lookupError: String?

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
                            .autocorrectionDisabled()
                            .onChange(of: customSymbol) { _ in
                                market = detectedMarket
                                // 代碼真的改了才丟掉上一次的查價結果
                                if lookupResult?.symbol != normalizedSymbol {
                                    lookupResult = nil
                                    lookupError = nil
                                }
                            }
                        TextField("股票名稱（查價後自動填入）", text: $customName)

                        // 市場由代碼自動識別，手選只會與實際查價的市場矛盾
                        HStack {
                            Text("市場")
                            Spacer()
                            Text(normalizedSymbol.isEmpty ? "—" : "\(detectedMarket.flag) \(detectedMarket.rawValue)")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await lookupQuote() }
                        } label: {
                            HStack(spacing: 8) {
                                if isLookingUp {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                                Text(isLookingUp ? "查詢中…" : "查詢最新股價")
                            }
                        }
                        .disabled(normalizedSymbol.isEmpty || isLookingUp)

                        if let quote = lookupResult {
                            quoteResultRow(quote)
                        }

                        if let lookupError {
                            Text(lookupError)
                                .font(.caption)
                                .foregroundStyle(.loss)
                        }
                    } else if let selected = selectedStock {
                        // 已選擇股票 - 顯示選中卡片 + 更改按鈕
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(selected.symbol)
                                        .font(.subheadline.bold())
                                    Text(selected.market.flag)
                                        .font(.caption)
                                }
                                Text(selected.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if selected.dividendYield > 0 {
                                    Text(selected.dividendYield.yieldPercent())
                                        .font(.caption2)
                                        .foregroundStyle(.financePrimary)
                                }
                            }
                            Spacer()
                            Button("更改") {
                                selectedStock = nil
                                searchText = ""
                            }
                            .font(.caption)
                            .foregroundStyle(.financePrimary)
                        }
                    } else {
                        // 搜尋模式
                        TextField("搜尋股票...", text: $searchText)

                        ForEach(searchResults.prefix(10)) { stock in
                            Button {
                                selectedStock = stock
                                market = stock.market
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
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                // 持倉信息 - 選擇股票或手動輸入後才顯示
                if isCustom || selectedStock != nil {
                    Section("持倉信息") {
                        TextField("股數", text: $shares)
                            .keyboardType(.numberPad)

                        TextField("買入價格", text: $purchasePrice)
                            .keyboardType(.decimalPad)

                        DatePicker("買入日期", selection: $purchaseDate, displayedComponents: .date)
                    }
                }

                if let sharesVal = Int(shares), let priceVal = Double(purchasePrice), sharesVal > 0 {
                    Section("投資總額") {
                        let currency = Currency.from(market: market)
                        Text((Double(sharesVal) * priceVal).moneyString(currency: currency))
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
            // 手動輸入必須先查到報價，否則代碼寫錯也不會有人發現
            return lookupResult != nil && Int(shares) ?? 0 > 0 && Double(purchasePrice) ?? 0 > 0
        } else {
            return selectedStock != nil && Int(shares) ?? 0 > 0 && Double(purchasePrice) ?? 0 > 0
        }
    }

    // MARK: - 手動輸入的代碼處理

    /// 把使用者輸入整理成 Yahoo Finance 認得的代碼：港股補足四位數字並加 .HK
    private var normalizedSymbol: String {
        let raw = customSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !raw.isEmpty else { return "" }

        if raw.hasSuffix(".HK") {
            return padCode(String(raw.dropLast(3))) + ".HK"
        }
        // 純數字一律視為港股代碼，美股不會是純數字
        if raw.allSatisfy(\.isNumber) {
            return padCode(raw) + ".HK"
        }
        return raw
    }

    private func padCode(_ digits: String) -> String {
        guard digits.allSatisfy(\.isNumber), digits.count < 4 else { return digits }
        return String(repeating: "0", count: 4 - digits.count) + digits
    }

    /// 市場由代碼看出來，不靠使用者自己選對
    private var detectedMarket: StockHolding.StockMarket {
        normalizedSymbol.hasSuffix(".HK") ? .hk : .us
    }

    /// 查價結果：確認代碼有效，並可一鍵把現價填成買入價
    private func quoteResultRow(_ quote: StockQuote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.gain)
                Text(quote.symbol)
                    .font(.subheadline.bold())
                Text(quote.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text(quote.currentPrice.moneyString(currency: Currency.from(market: detectedMarket)))
                    .font(.headline)
                Text(String(format: "%+.2f%%", quote.changePercent))
                    .font(.caption)
                    .foregroundStyle(quote.isPositive ? Color.gain : Color.loss)

                Spacer()

                Button("填入買入價") {
                    purchasePrice = String(format: "%.2f", quote.currentPrice)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    /// 手動輸入的代碼要靠 API 確認存不存在，順便把最新價與名稱帶回來
    @MainActor
    private func lookupQuote() async {
        let symbol = normalizedSymbol
        guard !symbol.isEmpty else { return }

        isLookingUp = true
        lookupError = nil
        lookupResult = nil

        let probe = StockInfo(symbol: symbol, name: symbol, market: detectedMarket, dividendYield: 0)
        let quote = await StockService.shared.fetchSingleQuote(for: probe)

        isLookingUp = false

        // fetchSingleQuote 失敗時會回一筆價格為 0 的後備報價，以此判定代碼是否有效
        guard let quote, quote.currentPrice > 0 else {
            lookupError = "查不到 \(symbol) 的報價。港股要寫成四位數字加 .HK（如 0700.HK），美股直接寫代號（如 AAPL）"
            Haptics.warning()
            return
        }

        customSymbol = symbol
        market = detectedMarket
        lookupResult = quote
        if customName.isEmpty { customName = quote.name }
        if purchasePrice.isEmpty { purchasePrice = String(format: "%.2f", quote.currentPrice) }
        // 寫入快取，新增完成後市值與總資產立即就是最新價
        StockService.shared.cacheHoldingQuotes([quote])
        Haptics.success()
    }

    private func saveHolding() {
        guard let sharesVal = Int(shares), sharesVal > 0,
              let priceVal = Double(purchasePrice), priceVal > 0 else { return }

        let symbol: String
        let name: String

        if isCustom {
            // 存正規化後的代碼，不然日後刷新報價會拉不到
            symbol = normalizedSymbol
            name = customName.isEmpty ? (lookupResult?.name ?? symbol) : customName
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
