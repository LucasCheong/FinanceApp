import SwiftUI

// MARK: - 市場看板視圖 - 顯示最大漲幅、跌幅和高息ETF
struct MarketDashboardView: View {
    @StateObject private var stockService = StockService.shared
    @State private var marketFilter: MarketFilter = .all
    @State private var selectedTab: MarketTab = .gainers

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
    }

    var filteredStocks: [StockInfo] {
        switch selectedTab {
        case .etfReturns:
            return StockDatabase.mainstreamUSETFs
        default:
            switch marketFilter {
            case .all: return StockDatabase.allStocks
            case .us: return StockDatabase.allUS
            case .hk: return StockDatabase.allHK
            }
        }
    }

    var displayQuotes: [StockQuote] {
        // ETF 年化回報標籤使用本地數據，不走網絡拉取
        if selectedTab == .etfReturns {
            return StockDatabase.mainstreamUSETFs
                .sorted { $0.annualizedReturn > $1.annualizedReturn }
                .map { stock in
                    StockQuote(
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
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 市場篩選（ETF年化回報標籤隱藏市場篩選）
                if selectedTab != .etfReturns {
                    marketFilterPicker
                }

                // 標籤切換
                tabPicker

                // 內容
                if selectedTab != .etfReturns && stockService.isLoading {
                    loadingView
                } else if displayQuotes.isEmpty {
                    emptyView
                } else {
                    quotesList
                }
            }
            .navigationTitle("市場看板")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedTab != .etfReturns {
                        Button {
                            Task { await refreshData() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                if selectedTab != .etfReturns && stockService.quotes.isEmpty {
                    await refreshData()
                }
            }
            .onChange(of: selectedTab) { newTab in
                if newTab != .etfReturns && stockService.quotes.isEmpty {
                    Task { await refreshData() }
                }
            }
        }
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
                    Label("美股主流 ETF 年化回報率排列", systemImage: "chart.bar.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.financePrimary)
                    Text("基於5年年化回報率，包含大盤、行業板塊、成長/價值、債券、商品等主流 ETF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                ForEach(Array(displayQuotes.enumerated()), id: \.element.id) { index, quote in
                    ETFReturnRow(quote: quote, rank: index + 1)
                }
            }
            .padding()
        }
    }

    // MARK: - 股票列表
    private var quotesList: some View {
        if selectedTab == .etfReturns {
            etfReturnsList
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
        guard selectedTab != .etfReturns else { return }
        await stockService.fetchQuotes(for: filteredStocks)
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
                }
                Text(quote.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
