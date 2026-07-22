import SwiftUI

// MARK: - 市場看板視圖 - 顯示最大漲幅、跌幅和高息ETF
struct MarketDashboardView: View {
    @StateObject private var stockService = StockService.shared
    @StateObject private var persistence = PersistenceService.shared
    @State private var marketFilter: MarketFilter = .all
    @State private var selectedTab: MarketTab = .gainers
    @State private var etfLiveQuotes: [String: StockQuote] = [:]   // ETF 實時報價快取
    @State private var lastRefreshTime: Date?                      // 最後刷新時間
    @State private var maSignals: [MovingAverageSignal] = []       // 均線信號

    enum MarketFilter: String, CaseIterable {
        case all = "全部"
        case us = "美股"
        case hk = "港股"
    }

    enum MarketTab: String, CaseIterable {
        case gainers = "最大漲幅"
        case losers = "最大跌幅"
        case highYield = "最高收息"
        case etfReturns = "ETF年化回報"
        case signals = "技術信號"
    }

    var filteredStocks: [StockInfo] {
        switch selectedTab {
        case .etfReturns:
            return StockDatabase.mainstreamUSETFs
        case .signals:
            return []  // 技術信號使用持倉數據
        default:
            switch marketFilter {
            case .all: return StockDatabase.allStocks
            case .us: return StockDatabase.allUS
            case .hk: return StockDatabase.allHK
            }
        }
    }

    var displayQuotes: [StockQuote] {
        // ETF 年化回報標籤：合併本地年化數據 + 實時價格
        if selectedTab == .etfReturns {
            return StockDatabase.mainstreamUSETFs
                .sorted { $0.annualizedReturn > $1.annualizedReturn }
                .map { stock in
                    // 如果有實時報價就用，否則用本地數據
                    if let live = etfLiveQuotes[stock.symbol] {
                        return StockQuote(
                            symbol: live.symbol,
                            name: live.name,
                            market: stock.market.rawValue,
                            currentPrice: live.currentPrice,
                            previousClose: live.previousClose,
                            change: live.change,
                            changePercent: live.changePercent,
                            dividendYield: stock.dividendYield,
                            currency: live.currency,
                            exchange: live.exchange
                        )
                    }
                    return StockQuote(
                        symbol: stock.symbol,
                        name: stock.name,
                        market: stock.market.rawValue,
                        currentPrice: 0,
                        previousClose: 0,
                        change: 0,
                        changePercent: 0,
                        dividendYield: stock.dividendYield,
                        currency: "USD",
                        exchange: "ETF"
                    )
                }
        }

        let filtered = stockService.quotes.filter { quote in
            switch marketFilter {
            case .all: return true
            case .us: return quote.market == StockHolding.StockMarket.us.rawValue
            case .hk: return quote.market == StockHolding.StockMarket.hk.rawValue
            }
        }

        switch selectedTab {
        case .gainers:
            return filtered
                .filter { $0.currentPrice > 0 }
                .sorted { $0.changePercent > $1.changePercent }
        case .losers:
            return filtered
                .filter { $0.currentPrice > 0 }
                .sorted { $0.changePercent < $1.changePercent }
        case .highYield:
            return filtered
                .filter { $0.dividendYield > 0 }
                .sorted { $0.dividendYield > $1.dividendYield }
        case .etfReturns:
            return []  // 已在上面處理
        case .signals:
            return []  // 技術信號使用獨立列表，不使用 displayQuotes
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 市場篩選（ETF年化回報/技術信號標籤隱藏市場篩選）
                if selectedTab != .etfReturns && selectedTab != .signals {
                    marketFilterPicker
                }

                // 標籤切換
                tabPicker

                // 最後更新時間
                if let lastRefreshTime {
                    lastRefreshBar
                }

                // 內容
                if stockService.isLoading {
                    loadingView
                } else if selectedTab == .signals {
                    if maSignals.isEmpty {
                        if persistence.holdings.isEmpty {
                            signalsEmptyView
                        } else {
                            signalsEmptyView
                        }
                    } else {
                        signalsList
                    }
                } else if displayQuotes.isEmpty {
                    emptyView
                } else {
                    quotesList
                }
            }
            .navigationTitle("市場看板")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshData() }
                    } label: {
                        Image(systemName: stockService.isLoading ? "arrow.clockwise.circle" : "arrow.clockwise")
                            .rotationEffect(.degrees(stockService.isLoading ? 360 : 0))
                            .animation(stockService.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: stockService.isLoading)
                    }
                    .disabled(stockService.isLoading)
                }
            }
            .task {
                await refreshData()
            }
            .onChange(of: selectedTab) { _ in
                Task { await refreshData() }
            }
        }
    }

    // MARK: - 最後更新時間條
    private var lastRefreshBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
            Text("最後更新：\(lastRefreshTime!.timeString)")
                .font(.caption2)
            Spacer()
            if stockService.isLoading {
                Text("更新中...")
                    .font(.caption2)
                    .foregroundStyle(.financePrimary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - 市場篩選器
    private var marketFilterPicker: some View {
        Picker("市場", selection: $marketFilter) {
            ForEach(MarketFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding()
        .onChange(of: marketFilter) { _ in
            Task { await refreshData() }
        }
    }

    // MARK: - 標籤切換
    private var tabPicker: some View {
        Picker("類型", selection: $selectedTab) {
            ForEach(MarketTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - ETF 年化回報列表
    private var etfReturnsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // 說明卡片
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("美股主流 ETF 年化回報率排列", systemImage: "chart.bar.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.financePrimary)
                        Spacer()
                        // 實時數據指示器
                        if !etfLiveQuotes.isEmpty {
                            Label("含實時報價", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            Label("離線數據", systemImage: "wifi.slash")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("基於5年年化回報率排列，點擊右上角刷新可獲取實時價格")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                ForEach(Array(displayQuotes.enumerated()), id: \.element.id) { index, quote in
                    ETFReturnRow(quote: quote, rank: index + 1, hasLivePrice: etfLiveQuotes[quote.symbol] != nil)
                }
            }
            .padding()
        }
    }

    // MARK: - 股票列表
    private var quotesList: some View {
        if selectedTab == .etfReturns {
            etfReturnsList
        } else if selectedTab == .signals {
            signalsList
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(displayQuotes.enumerated()), id: \.element.id) { index, quote in
                        MarketQuoteRow(quote: quote, rank: index + 1, tab: selectedTab)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - 技術信號列表
    private var signalsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // 說明卡片
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("自選股均線信號", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline.bold())
                            .foregroundStyle(.financePrimary)
                        Spacer()
                        // 行動信號數量
                        let actionCount = maSignals.filter { $0.isActionable }.count
                        if actionCount > 0 {
                            Text("\(actionCount) 個提醒")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.15))
                                .foregroundStyle(.red)
                                .cornerRadius(6)
                        }
                    }
                    Text("突破10日均線 → 買入信號 | 跌破20日均線 → 賣出信號")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // 行動信號優先顯示
                let sortedSignals = maSignals.sorted { $0.signalType.rawValue < $1.signalType.rawValue }
                ForEach(sortedSignals) { signal in
                    SignalRow(signal: signal)
                }
            }
            .padding()
        }
    }

    // MARK: - 技術信號空狀態
    private var signalsEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暫無自選股")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("請先到「投資組合」添加股票持倉\n系統將自動監測均線突破/跌破信號")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 載入中
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在獲取市場數據...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 空狀態
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暫無數據")
                .font(.headline)
            Text("點擊右上角刷新按鈕獲取最新數據")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 刷新數據
    private func refreshData() async {
        if selectedTab == .etfReturns {
            // ETF 標籤：拉取實時報價
            await MainActor.run { stockService.isLoading = true }
            let etfStocks = StockDatabase.mainstreamUSETFs
            var liveQuotes: [String: StockQuote] = [:]

            // 分批拉取，每批 5 個
            let batches = stride(from: 0, to: etfStocks.count, by: 5).map {
                Array(etfStocks[$0..<min($0 + 5, etfStocks.count)])
            }

            for batch in batches {
                let batchResults = await withTaskGroup(of: StockQuote?.self) { group -> [StockQuote] in
                    for stock in batch {
                        group.addTask {
                            await stockService.fetchSingleQuote(for: stock)
                        }
                    }
                    var results: [StockQuote] = []
                    for await quote in group {
                        if let quote = quote, quote.currentPrice > 0 {
                            results.append(quote)
                        }
                    }
                    return results
                }
                for quote in batchResults {
                    liveQuotes[quote.symbol] = quote
                }
            }

            await MainActor.run {
                self.etfLiveQuotes = liveQuotes
                self.stockService.isLoading = false
                self.lastRefreshTime = Date()
            }
        } else if selectedTab == .signals {
            // 技術信號標籤：拉取持倉的歷史數據計算均線
            guard !persistence.holdings.isEmpty else {
                await MainActor.run {
                    self.lastRefreshTime = Date()
                }
                return
            }

            await MainActor.run { stockService.isLoading = true }
            let signals = await stockService.fetchMovingAverageSignals(for: persistence.holdings)
            await MainActor.run {
                self.maSignals = signals
                self.stockService.isLoading = false
                self.lastRefreshTime = Date()

                // 發送本地通知（買入/賣出信號）
                NotificationManager.shared.checkAndNotifySignals(signals)
            }
        } else {
            // 其他標籤：常規拉取
            await stockService.fetchQuotes(for: filteredStocks)
            await MainActor.run {
                self.lastRefreshTime = Date()
            }
        }
    }
}

// MARK: - 市場報價行
struct MarketQuoteRow: View {
    let quote: StockQuote
    let rank: Int
    let tab: MarketDashboardView.MarketTab

    var body: some View {
        HStack(spacing: 12) {
            // 排名
            Text("#\(rank)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 30)

            // 股票信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(quote.symbol)
                        .font(.subheadline.bold())
                    Text(quote.market == StockHolding.StockMarket.us.rawValue ? "🇺🇸" : "🇭🇰")
                        .font(.caption)
                }
                Text(quote.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 右側數據
            VStack(alignment: .trailing, spacing: 2) {
                switch tab {
                case .gainers, .losers:
                    Text(quote.currentPrice.compactString())
                        .font(.subheadline.bold())
                    HStack(spacing: 2) {
                        Image(systemName: quote.isPositive ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                        Text(String(format: "%.2f%%", abs(quote.changePercent)))
                            .font(.caption.bold())
                    }
                    .foregroundStyle(Color.changeColor(quote.changePercent))

                case .highYield:
                    Text(quote.dividendYield.yieldPercent())
                        .font(.title3.bold())
                        .foregroundStyle(.financePrimary)
                    Text("年息率")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                case .etfReturns:
                    EmptyView()
                case .signals:
                    EmptyView()
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    tab == .highYield ? Color.financePrimary.opacity(0.2) :
                    Color.changeColor(quote.changePercent).opacity(0.15),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - ETF 年化回報行視圖
struct ETFReturnRow: View {
    let quote: StockQuote
    let rank: Int
    let hasLivePrice: Bool   // 是否有實時價格

    // 從 StockDatabase 查找對應的 annualizedReturn
    private var annualizedReturn: Double {
        StockDatabase.mainstreamUSETFs.first { $0.symbol == quote.symbol }?.annualizedReturn ?? 0
    }

    // 根據回報率決定顏色和圖標
    private var returnColor: Color {
        if annualizedReturn >= 0.15 { return .green }
        else if annualizedReturn >= 0.10 { return .financePrimary }
        else if annualizedReturn >= 0.05 { return .blue }
        else if annualizedReturn >= 0.0 { return .orange }
        else { return .red }
    }

    private var returnIcon: String {
        if annualizedReturn >= 0.15 { return "flame.fill" }
        else if annualizedReturn >= 0.10 { return "arrow.up.right" }
        else if annualizedReturn >= 0.05 { return "arrow.up" }
        else if annualizedReturn >= 0.0 { return "minus" }
        else { return "arrow.down" }
    }

    // 表現等級標籤
    private var performanceLabel: String {
        if annualizedReturn >= 0.15 { return "優秀" }
        else if annualizedReturn >= 0.10 { return "良好" }
        else if annualizedReturn >= 0.05 { return "一般" }
        else if annualizedReturn >= 0.0 { return "偏低" }
        else { return "虧損" }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 排名
            VStack(spacing: 2) {
                Text("#\(rank)")
                    .font(.subheadline.bold())
                    .foregroundStyle(returnColor)
                if rank <= 3 {
                    Image(systemName: "medal.fill")
                        .font(.caption2)
                        .foregroundStyle(rank == 1 ? .yellow : rank == 2 ? .gray : .orange)
                }
            }
            .frame(width: 36)

            // ETF 信息
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(quote.symbol)
                        .font(.subheadline.bold())
                    Text("🇺🇸")
                        .font(.caption)
                    Text(performanceLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(returnColor.opacity(0.15))
                        .foregroundStyle(returnColor)
                        .cornerRadius(4)
                    // 實時價格指示燈
                    if hasLivePrice {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(quote.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // 實時價格行
                if hasLivePrice {
                    HStack(spacing: 6) {
                        Text(quote.currentPrice.moneyString(currency: .usd))
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        HStack(spacing: 2) {
                            Image(systemName: quote.isPositive ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                            Text(String(format: "%.2f%%", abs(quote.changePercent)))
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(Color.changeColor(quote.changePercent))
                    }
                }
            }

            Spacer()

            // 右側年化回報
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: returnIcon)
                        .font(.caption)
                    Text(String(format: "%.2f%%", annualizedReturn * 100))
                        .font(.title3.bold())
                }
                .foregroundStyle(returnColor)

                HStack(spacing: 8) {
                    if quote.dividendYield > 0 {
                        Label(String(format: "息 %.2f%%", quote.dividendYield * 100), systemImage: "percent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(returnColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - 均線信號行視圖
struct SignalRow: View {
    let signal: MovingAverageSignal

    private var signalColor: Color {
        switch signal.signalType {
        case .buyBreakout: return .green
        case .sellBreakdown: return .red
        case .nearBuy: return .blue
        case .nearSell: return .orange
        case .hold: return .gray
        }
    }

    private var signalBgColor: Color {
        switch signal.signalType {
        case .buyBreakout: return Color.green.opacity(0.12)
        case .sellBreakdown: return Color.red.opacity(0.12)
        default: return Color.clear
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 信號圖標
            ZStack {
                Circle()
                    .fill(signalColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: signal.signalType.icon)
                    .font(.title3)
                    .foregroundStyle(signalColor)
            }

            // 股票信息
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(signal.symbol)
                        .font(.subheadline.bold())
                    Text(signal.market.flag)
                        .font(.caption)
                    // 信號標籤
                    Text(signal.signalType.displayName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(signalColor.opacity(0.15))
                        .foregroundStyle(signalColor)
                        .cornerRadius(4)
                }
                Text(signal.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // 均線數據
                HStack(spacing: 12) {
                    Label(String(format: "MA10: %@", signal.ma10.compactString()), systemImage: "10.circle")
                    Label(String(format: "MA20: %@", signal.ma20.compactString()), systemImage: "20.circle")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // 右側價格和距離
            VStack(alignment: .trailing, spacing: 3) {
                Text(signal.currentPrice.moneyString(currency: Currency.from(market: signal.market)))
                    .font(.subheadline.bold())

                // 距離MA10
                Text(String(format: "%@%.2f%%", signal.distanceToMA10 >= 0 ? "↑" : "↓", abs(signal.distanceToMA10)))
                    .font(.caption2.bold())
                    .foregroundStyle(signal.distanceToMA10 >= 0 ? .green : .red)

                // 距離MA20
                Text(String(format: "%@%.2f%%", signal.distanceToMA20 >= 0 ? "↑" : "↓", abs(signal.distanceToMA20)))
                    .font(.caption2)
                    .foregroundStyle(signal.distanceToMA20 >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(signalBgColor.opacity(0.5))
        .background(Color.cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(signalColor.opacity(signal.isActionable ? 0.4 : 0.15), lineWidth: signal.isActionable ? 1.5 : 1)
        )
    }
}
