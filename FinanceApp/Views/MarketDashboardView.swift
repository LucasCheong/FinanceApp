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
    }

    var filteredStocks: [StockInfo] {
        switch marketFilter {
        case .all: return StockDatabase.allStocks
        case .us: return StockDatabase.allUS
        case .hk: return StockDatabase.allHK
        }
    }

    var displayQuotes: [StockQuote] {
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
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 市場篩選
                marketFilterPicker

                // 標籤切換
                tabPicker

                // 內容
                if stockService.isLoading {
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
                    Button {
                        Task { await refreshData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if stockService.quotes.isEmpty {
                    await refreshData()
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

    // MARK: - 股票列表
    private var quotesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(displayQuotes.enumerated()), id: \.element.id) { index, quote in
                    MarketQuoteRow(quote: quote, rank: index + 1, tab: selectedTab)
                }
            }
            .padding()
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
