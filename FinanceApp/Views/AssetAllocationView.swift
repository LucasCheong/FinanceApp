import SwiftUI
import Charts

// MARK: - 資產配置餅圖 + DCA 定期定額追蹤
struct AssetAllocationView: View {
    @StateObject private var persistence = PersistenceService.shared
    @StateObject private var stockService = StockService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentQuotes: [String: StockQuote] = [:]
    @State private var showingAddDCA = false
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("視圖", selection: $selectedTab) {
                    Text("資產配置").tag(0)
                    Text("定期定額").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    assetAllocationContent
                } else {
                    dcaTrackingContent
                }
            }
            .navigationTitle("資產分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                if selectedTab == 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAddDCA = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddDCA) {
                AddDCAPositionView()
            }
            .task {
                await refreshQuotes()
            }
        }
    }

    // MARK: - 資產配置內容
    private var assetAllocationContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 資產總覽
                totalWealthCard

                // 市場分佈餅圖
                marketPieChart

                // 各持倉明細
                holdingsBreakdown
            }
            .padding()
        }
    }

    private var totalWealthCard: some View {
        VStack(spacing: 8) {
            Text("資產總覽")
                .font(.headline)

            let stockValue = persistence.holdings.reduce(0) { total, holding in
                let price = currentQuotes[holding.symbol]?.currentPrice ?? holding.purchasePrice
                let value = Double(holding.shares) * price
                return total + ExchangeRateProvider.convert(value, from: Currency.from(market: holding.market), to: persistence.baseCurrency)
            }

            let cashValue = persistence.cashBalance

            Text((stockValue + cashValue).moneyString(currency: persistence.baseCurrency))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.financePrimary)

            HStack(spacing: 24) {
                VStack {
                    Text("現金")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cashValue.moneyString(currency: persistence.baseCurrency))
                        .font(.subheadline.bold())
                }
                VStack {
                    Text("股票")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(stockValue.moneyString(currency: persistence.baseCurrency))
                        .font(.subheadline.bold())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var marketPieChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("市場配置")
                .font(.headline)

            let stockByMarket = stockByMarketBreakdown

            if stockByMarket.isEmpty {
                Text("暫無持倉數據")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(stockByMarket) { item in
                    SectorMark(
                        angle: .value("金額", item.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("市場", item.label))
                }
                .frame(height: 250)

                // 圖例
                ForEach(stockByMarket) { item in
                    HStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 12, height: 12)
                        Text(item.label)
                            .font(.subheadline)
                        Spacer()
                        Text(item.value.moneyString(currency: persistence.baseCurrency))
                            .font(.subheadline.bold())
                        Text(String(format: "%.1f%%", item.percent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var holdingsBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("持倉明細")
                .font(.headline)

            ForEach(persistence.holdings) { holding in
                let quote = currentQuotes[holding.symbol]
                let price = quote?.currentPrice ?? holding.purchasePrice
                let value = Double(holding.shares) * price
                let currency = Currency.from(market: holding.market)
                let baseValue = ExchangeRateProvider.convert(value, from: currency, to: persistence.baseCurrency)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(holding.symbol)
                                .font(.subheadline.bold())
                            Text(holding.market.flag)
                        }
                        Text(holding.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(baseValue.moneyString(currency: persistence.baseCurrency))
                            .font(.subheadline.bold())
                        let totalStock = stockByMarketBreakdown.reduce(0) { $0 + $1.value }
                        Text(String(format: "%.1f%%", totalStock > 0 ? baseValue / totalStock * 100 : 0))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .cardStyle()
    }

    // MARK: - DCA 內容
    private var dcaTrackingContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if persistence.dcaPositions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("尚未建立定期定額計劃")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Button {
                            showingAddDCA = true
                        } label: {
                            Label("新增計劃", systemImage: "plus.circle.fill")
                        }
                    }
                    .padding(.vertical, 60)
                } else {
                    ForEach(persistence.dcaPositions) { position in
                        DCAPositionCard(position: position, currentPrice: currentQuotes[position.symbol]?.currentPrice)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 計算
    private struct MarketBreakdownItem: Identifiable {
        var id: String { label }
        let label: String
        let value: Double
        let percent: Double
        let color: Color
    }

    private var stockByMarketBreakdown: [MarketBreakdownItem] {
        var byMarket: [String: Double] = [:]

        for holding in persistence.holdings {
            let quote = currentQuotes[holding.symbol]
            let price = quote?.currentPrice ?? holding.purchasePrice
            let value = Double(holding.shares) * price
            let baseValue = ExchangeRateProvider.convert(value, from: Currency.from(market: holding.market), to: persistence.baseCurrency)
            byMarket[holding.market.rawValue, default: 0] += baseValue
        }

        let total = byMarket.values.reduce(0, +)
        let colors: [String: Color] = ["美股": .blue, "港股": .orange]

        return byMarket.map { (key, value) in
            MarketBreakdownItem(
                label: key,
                value: value,
                percent: total > 0 ? value / total * 100 : 0,
                color: colors[key] ?? .gray
            )
        }
        .sorted { $0.value > $1.value }
    }

    private func refreshQuotes() async {
        guard !persistence.holdings.isEmpty else { return }
        let stockInfos = persistence.holdings.map {
            StockInfo(symbol: $0.symbol, name: $0.name, market: $0.market, dividendYield: 0)
        }
        await stockService.fetchQuotes(for: stockInfos)
        await MainActor.run {
            for quote in stockService.quotes {
                currentQuotes[quote.symbol] = quote
            }
        }
    }
}

// MARK: - DCA 持倉卡片
struct DCAPositionCard: View {
    let position: DCAPosition
    let currentPrice: Double?

    var body: some View {
        VStack(spacing: 12) {
            // 標題
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(position.symbol)
                            .font(.headline.bold())
                        Text(position.market.flag)
                    }
                    Text(position.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(position.investmentCount) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("投入 \(position.investmentCount) 次")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 數據
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("總投入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(position.totalInvested.moneyString(currency: position.currency))
                        .font(.subheadline.bold())
                }
                VStack(alignment: .center) {
                    Text("平均成本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(position.avgCost.compactString())
                        .font(.subheadline.bold())
                }
                VStack(alignment: .trailing) {
                    Text("總股數")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f", position.totalShares))
                        .font(.subheadline.bold())
                }
            }

            if let price = currentPrice {
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text("當前價格")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(price.compactString())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("市值")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(position.currentValue(currentPrice: price).moneyString(currency: position.currency))
                            .font(.subheadline.bold())
                    }
                    VStack(alignment: .trailing) {
                        Text("回報率")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let pct = position.pnlPercent(currentPrice: price)
                        Text(String(format: "%+.2f%%", pct))
                            .font(.subheadline.bold())
                            .foregroundStyle(pct >= 0 ? .incomeColor : .expenseColor)
                    }
                }
            }

            // 記錄列表
            if !position.records.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("投入記錄")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(position.records.suffix(5)) { record in
                        HStack {
                            Text(record.date.shortDateString)
                                .font(.caption2)
                            Spacer()
                            Text(record.amount.moneyString(currency: position.currency))
                                .font(.caption2)
                            Text("@ \(record.pricePerShare.compactString())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if position.records.count > 5 {
                        Text("...共 \(position.records.count) 筆記錄")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - 新增 DCA 計劃
struct AddDCAPositionView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var name = ""
    @State private var market: StockHolding.StockMarket = .us
    @State private var amount = ""
    @State private var shares = ""
    @State private var pricePerShare = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("股票資訊") {
                    TextField("股票代碼", text: $symbol)
                        .textInputAutocapitalization(.characters)
                    TextField("股票名稱", text: $name)
                    Picker("市場", selection: $market) {
                        ForEach(StockHolding.StockMarket.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                }

                Section("首次投入") {
                    TextField("投入金額", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("買入股數", text: $shares)
                        .keyboardType(.decimalPad)
                    TextField("每股價格", text: $pricePerShare)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("新增定期定額")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("建立") { save() }
                        .disabled(symbol.isEmpty || name.isEmpty || Double(amount) == nil || Double(shares) == nil)
                        .bold()
                }
            }
        }
    }

    private func save() {
        guard let amt = Double(amount), let shrs = Double(shares), let price = Double(pricePerShare) else { return }

        let record = DCARecord(
            date: Date(),
            amount: amt,
            shares: shrs,
            pricePerShare: price
        )

        let position = DCAPosition(
            symbol: symbol.uppercased(),
            name: name,
            market: market,
            totalInvested: amt,
            totalShares: shrs,
            investmentCount: 1,
            currency: Currency.from(market: market),
            records: [record]
        )

        persistence.addDCAPosition(position)
        dismiss()
    }
}
