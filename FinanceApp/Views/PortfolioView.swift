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
    @State private var expandedHoldings: Set<UUID> = []
    @State private var sellingHolding: StockHolding?

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
            .sheet(item: $sellingHolding) { holding in
                SellHoldingView(holding: holding, quote: currentQuotes[holding.symbol])
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

            Text(totalWealth.amountString())
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.financePrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("基準幣種: \(persistence.baseCurrency.displayName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                VStack {
                    Text("今日變動")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(todayChange >= 0 ? "+" : "")\(todayChange.amountString())")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.changeColor(todayChange))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    Text("總盈虧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(totalPnL >= 0 ? "+" : "")\(totalPnL.amountString())")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.changeColor(totalPnL))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    Text("回報率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.2f%%", totalPnLPercent))
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.changeColor(totalPnL))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
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
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("持倉市值")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalStockValue.amountString())
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("投資成本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalCost.amountString())
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            if !persistence.stockSales.isEmpty {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已實現盈虧")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("累計 \(persistence.stockSales.count) 筆賣出")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text("\(persistence.realizedPnLTotal >= 0 ? "+" : "")\(persistence.realizedPnLTotal.amountString())")
                        .font(.headline)
                        .foregroundStyle(Color.changeColor(persistence.realizedPnLTotal))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - 持倉列表
    /// 卡片式列表，點擊可展開批次明細，長按可刪除
    private var holdingsList: some View {
        VStack(spacing: 8) {
            ForEach(persistence.holdings) { holding in
                VStack(spacing: 0) {
                    HoldingRow(
                        holding: holding,
                        quote: currentQuotes[holding.symbol],
                        isExpanded: expandedHoldings.contains(holding.id),
                        lotCount: holding.lots.count
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard holding.lots.count > 1 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedHoldings.contains(holding.id) {
                                expandedHoldings.remove(holding.id)
                            } else {
                                expandedHoldings.insert(holding.id)
                            }
                        }
                    }

                    HStack {
                        Button {
                            sellingHolding = holding
                        } label: {
                            Label("賣出", systemImage: "arrow.up.right.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .font(.caption.bold())
                        .foregroundStyle(.financePrimary)

                        Spacer()

                        if holding.lots.count > 1 {
                            Text(expandedHoldings.contains(holding.id)
                                 ? "收起批次"
                                 : "共 \(holding.lots.count) 個批次")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)

                    if expandedHoldings.contains(holding.id) {
                        Divider().padding(.horizontal)

                        ForEach(holding.lots) { lot in
                            LotRow(lot: lot, holding: holding, quote: currentQuotes[holding.symbol])
                                .contextMenu {
                                    if holding.lots.count > 1 {
                                        Button(role: .destructive) {
                                            persistence.deleteLot(lot, from: holding.id)
                                        } label: {
                                            Label("刪除此批次", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                }
                .background(Color.cardBackground)
                .cornerRadius(10)
                .contextMenu {
                    Button {
                        sellingHolding = holding
                    } label: {
                        Label("賣出", systemImage: "arrow.up.right.circle")
                    }
                    Button(role: .destructive) {
                        persistence.deleteHolding(holding)
                    } label: {
                        Label("刪除整個持倉", systemImage: "trash")
                    }
                }
            }

            Text("點擊持倉展開批次明細 · 長按可刪除")
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
    var isExpanded: Bool = false
    var lotCount: Int = 1

    private var currentPrice: Double {
        quote?.currentPrice ?? holding.purchasePrice
    }

    private var currentValue: Double {
        Double(holding.shares) * currentPrice
    }

    private var costValue: Double {
        holding.totalCost
    }

    private var pnl: Double {
        currentValue - costValue
    }

    private var pnlPercent: Double {
        costValue > 0 ? (pnl / costValue) * 100 : 0
    }

    private var currency: Currency {
        Currency.from(market: holding.market)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(holding.symbol)
                        .font(.subheadline.bold())
                    Text(holding.market.flag)
                        .font(.caption)
                    if lotCount > 1 {
                        Text("\(lotCount) 筆")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.financePrimary.opacity(0.15))
                            .cornerRadius(4)
                    }
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
                Text(currentValue.moneyString(currency: currency))
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("\(pnl >= 0 ? "+" : "")\(pnl.moneyString(currency: currency))  \(String(format: "%+.2f%%", pnlPercent))")
                    .font(.caption2)
                    .foregroundStyle(Color.changeColor(pnl))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if lotCount > 1 {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - 批次明細行
struct LotRow: View {
    let lot: StockHolding.Lot
    let holding: StockHolding
    let quote: StockQuote?

    private var currentPrice: Double {
        quote?.currentPrice ?? lot.purchasePrice
    }

    private var lotValue: Double {
        Double(lot.shares) * currentPrice
    }

    private var lotCost: Double {
        Double(lot.shares) * lot.purchasePrice
    }

    private var pnl: Double {
        lotValue - lotCost
    }

    private var pnlPercent: Double {
        lotCost > 0 ? (pnl / lotCost) * 100 : 0
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(lot.shares) 股 @ \(lot.purchasePrice.compactString())")
                    .font(.caption)
                Text(lot.purchaseDate.shortDateString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(lotValue.moneyString(currency: Currency.from(market: holding.market)))
                    .font(.caption)
                HStack(spacing: 2) {
                    Text(String(format: "%+.2f%%", pnlPercent))
                        .font(.caption2.bold())
                    Text("(\(pnl >= 0 ? "+" : "")\(pnl.moneyString(currency: Currency.from(market: holding.market))))")
                        .font(.caption2)
                }
                .foregroundStyle(Color.changeColor(pnl))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

// MARK: - 賣出持倉視圖
struct SellHoldingView: View {
    let holding: StockHolding
    let quote: StockQuote?

    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var sharesText = ""
    @State private var priceText = ""
    @State private var sellDate = Date()
    @State private var depositAccountId: UUID?

    private var currency: Currency { Currency.from(market: holding.market) }

    private var cashAccounts: [Account] {
        persistence.activeAccounts.filter { $0.type == .cash }
    }

    private var currentPrice: Double { quote?.currentPrice ?? holding.purchasePrice }

    private var shares: Int { Int(sharesText) ?? 0 }
    private var price: Double { Double(priceText) ?? 0 }

    private var isValid: Bool {
        shares > 0 && shares <= holding.shares && price > 0
    }

    /// 與 PersistenceService 相同的 FIFO 規則，只作即時預覽
    private var estimatedCostBasis: Double {
        var remaining = shares
        var cost = 0.0
        for lot in holding.lots.sorted(by: { $0.purchaseDate < $1.purchaseDate }) where remaining > 0 {
            let take = min(lot.shares, remaining)
            cost += Double(take) * lot.purchasePrice
            remaining -= take
        }
        return cost
    }

    private var proceeds: Double { Double(shares) * price }

    private var realizedPnL: Double { proceeds - estimatedCostBasis }

    var body: some View {
        NavigationStack {
            Form {
                Section("持倉") {
                    LabeledContent("股票", value: "\(holding.symbol) · \(holding.name)")
                    LabeledContent("持有股數", value: "\(holding.shares) 股")
                    LabeledContent("現價", value: currentPrice.moneyString(currency: currency))
                }

                Section("賣出資料") {
                    HStack {
                        Text("賣出股數")
                        Spacer()
                        TextField("0", text: $sharesText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(maxWidth: 100)
                        Button("全部") {
                            sharesText = "\(holding.shares)"
                        }
                        .font(.caption.bold())
                        .disabled(holding.shares == 0)
                    }

                    HStack {
                        Text("賣出價 (\(currency.symbol))")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 140)
                    }

                    DatePicker("賣出日期", selection: $sellDate, displayedComponents: .date)

                    if shares > holding.shares {
                        Text("超過持有股數（最多 \(holding.shares) 股）")
                            .font(.caption)
                            .foregroundStyle(.loss)
                    }
                }

                Section("存入帳戶") {
                    if cashAccounts.isEmpty {
                        Text("尚未建立現金帳戶，確認賣出時會自動建立「現金」帳戶（\(persistence.baseCurrency.code)）並存入所得。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("存入", selection: $depositAccountId) {
                            ForEach(cashAccounts) { account in
                                Text("\(account.name)（\(account.currency.code)）")
                                    .tag(Optional(account.id))
                            }
                        }
                        Text("賣出所得以 \(currency.code) 記入，並按帳戶幣種換算；記錄為轉帳，不計入收入。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section("結算") {
                    LabeledContent("賣出所得", value: proceeds.moneyString(currency: currency))
                    LabeledContent("已實現盈虧") {
                        Text("\(realizedPnL >= 0 ? "+" : "")\(realizedPnL.moneyString(currency: currency))")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.changeColor(realizedPnL))
                    }
                    LabeledContent("買入成本 (FIFO)", value: estimatedCostBasis.moneyString(currency: currency))
                    if isValid {
                        LabeledContent("賣出後剩餘", value: "\(holding.shares - shares) 股")
                    }
                }

                Section {
                    Text("賣出會按買入日期先進先出扣減批次，全部賣清後自動移除該持倉。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("賣出持倉")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("確認賣出") { confirmSell() }
                        .disabled(!isValid)
                        .bold()
                }
            }
            .onAppear {
                if priceText.isEmpty {
                    priceText = String(format: "%.2f", currentPrice)
                }
                if depositAccountId == nil {
                    depositAccountId = cashAccounts.first?.id
                }
            }
        }
    }

    private func confirmSell() {
        guard isValid else { return }
        persistence.sellShares(of: holding.id, shares: shares, price: price, date: sellDate,
                               depositAccountId: depositAccountId)
        dismiss()
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
    /// 上次自動填入的名稱，換股時要一併清掉，免得新代碼配舊股名存進資料
    @State private var autoFilledName: String?
    @State private var market: StockHolding.StockMarket = .us
    @State private var isCustom = false

    // 手動輸入代碼後的查價狀態
    @State private var isLookingUp = false
    @State private var lookupResult: StockQuote?
    @State private var lookupError: String?
    @FocusState private var isSymbolFocused: Bool

    /// 輸入代碼時即時比對股票資料庫，讓使用者直接揀選而不用記全碼
    private var symbolSuggestions: [StockInfo] {
        let raw = customSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !raw.isEmpty else { return [] }
        let bareQuery = raw.replacingOccurrences(of: ".HK", with: "")
        guard !bareQuery.isEmpty else { return [] }

        let matches = StockDatabase.allStocks.filter { stock in
            let symbol = stock.symbol.uppercased()
            let bare = symbol.replacingOccurrences(of: ".HK", with: "")
            return bare.hasPrefix(bareQuery)
                || bare.contains(bareQuery)
                || stock.name.contains(customSymbol.trimmingCharacters(in: .whitespaces))
        }

        return Array(matches
            .sorted { a, b in
                let aBare = a.symbol.uppercased().replacingOccurrences(of: ".HK", with: "")
                let bBare = b.symbol.uppercased().replacingOccurrences(of: ".HK", with: "")
                let aPrefix = aBare.hasPrefix(bareQuery)
                let bPrefix = bBare.hasPrefix(bareQuery)
                if aPrefix != bPrefix { return aPrefix }
                return aBare < bBare
            }
            .prefix(6))
    }

    /// 已查到報價時收起建議，避免與結果卡重複
    private var showSymbolSuggestions: Bool {
        !symbolSuggestions.isEmpty && lookupResult?.symbol.uppercased() != normalizedSymbol.uppercased()
    }

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
                            .focused($isSymbolFocused)
                            .onChange(of: customSymbol) { _ in
                                market = detectedMarket
                                // 代碼真的改了才丟掉上一次的查價結果
                                if lookupResult?.symbol != normalizedSymbol {
                                    lookupResult = nil
                                    lookupError = nil
                                }
                                if customName == autoFilledName {
                                    customName = ""
                                    autoFilledName = nil
                                }
                            }

                        // 輸入時即時列出相符股票，揀選後自動填代碼、名稱與市場
                        if showSymbolSuggestions {
                            VStack(spacing: 0) {
                                ForEach(symbolSuggestions) { stock in
                                    Button {
                                        selectSuggestion(stock)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(stock.symbol)
                                                .font(.subheadline.bold())
                                            Text(stock.market.flag)
                                                .font(.caption2)
                                            Text(stock.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                            Spacer()
                                            if stock.dividendYield > 0 {
                                                Text(stock.dividendYield.yieldPercent())
                                                    .font(.caption2)
                                                    .foregroundStyle(.financePrimary)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.vertical, 6)
                                    }
                                    .foregroundStyle(.primary)

                                    if stock.id != symbolSuggestions.last?.id {
                                        Divider()
                                    }
                                }
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
        if customName.isEmpty {
            customName = quote.name
            autoFilledName = quote.name
        }
        if purchasePrice.isEmpty { purchasePrice = String(format: "%.2f", quote.currentPrice) }
        // 寫入快取，新增完成後市值與總資產立即就是最新價
        StockService.shared.cacheHoldingQuotes([quote])
        Haptics.success()
    }

    /// 從建議列揀選股票：填好代碼、名稱與市場，並立即查價
    private func selectSuggestion(_ stock: StockInfo) {
        isSymbolFocused = false
        customSymbol = stock.symbol
        customName = stock.name
        autoFilledName = stock.name
        market = stock.market
        lookupResult = nil
        lookupError = nil
        Haptics.impact()
        Task { await lookupQuote() }
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
