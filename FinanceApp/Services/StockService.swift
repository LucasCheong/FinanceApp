import Foundation

/// 股票數據服務 - 通過 Yahoo Finance API 獲取美股和港股實時數據
final class StockService: ObservableObject {
    static let shared = StockService()

    @Published var quotes: [StockQuote] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - 批量獲取股票報價
    func fetchQuotes(for stocks: [StockInfo]) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        var results: [StockQuote] = []

        // 每批最多 5 個，避免請求過多
        let batches = stride(from: 0, to: stocks.count, by: 5).map {
            Array(stocks[$0..<min($0 + 5, stocks.count)])
        }

        for batch in batches {
            await withTaskGroup(of: StockQuote?.self) { group in
                for stock in batch {
                    group.addTask {
                        await self.fetchSingleQuote(for: stock)
                    }
                }
                for await quote in group {
                    if let quote = quote {
                        results.append(quote)
                    }
                }
            }
        }

        await MainActor.run {
            self.quotes = results
            self.isLoading = false
        }
    }

    // MARK: - 獲取單個股票報價
    func fetchSingleQuote(for stock: StockInfo) async -> StockQuote? {
        let urlString = "\(baseURL)/\(stock.symbol)?range=1d&interval=1d"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return createFallbackQuote(for: stock)
            }

            return parseQuote(from: data, stock: stock)
        } catch {
            print("獲取 \(stock.symbol) 報價失敗: \(error.localizedDescription)")
            return createFallbackQuote(for: stock)
        }
    }

    // MARK: - 解析 Yahoo Finance API 響應
    private func parseQuote(from data: Data, stock: StockInfo) -> StockQuote? {
        struct ChartResponse: Decodable {
            struct Chart: Decodable {
                struct Result: Decodable {
                    struct Meta: Decodable {
                        let symbol: String
                        let regularMarketPrice: Double
                        let chartPreviousClose: Double?
                        let previousClose: Double?
                        let currency: String?
                        let exchangeName: String?
                        let shortName: String?
                        let longName: String?
                    }
                    let meta: Meta
                }
                let result: [Result]?
                let error: ErrorResponse?
            }
            struct ErrorResponse: Decodable {
                let description: String?
            }
            let chart: Chart
        }

        do {
            let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
            guard let result = decoded.chart.result?.first else { return nil }
            let meta = result.meta

            let previousClose = meta.chartPreviousClose ?? meta.previousClose ?? meta.regularMarketPrice
            let change = meta.regularMarketPrice - previousClose
            let changePercent = previousClose > 0 ? (change / previousClose) * 100 : 0
            let name = meta.longName ?? meta.shortName ?? stock.name

            return StockQuote(
                symbol: stock.symbol,
                name: name,
                market: stock.market.rawValue,
                currentPrice: meta.regularMarketPrice,
                previousClose: previousClose,
                change: change,
                changePercent: changePercent,
                dividendYield: stock.dividendYield,
                currency: meta.currency ?? (stock.market == .us ? "USD" : "HKD"),
                exchange: meta.exchangeName ?? ""
            )
        } catch {
            print("解析 \(stock.symbol) 數據失敗: \(error)")
            return createFallbackQuote(for: stock)
        }
    }

    // MARK: - 創建後備報價（API 失敗時使用）
    private func createFallbackQuote(for stock: StockInfo) -> StockQuote {
        StockQuote(
            symbol: stock.symbol,
            name: stock.name,
            market: stock.market.rawValue,
            currentPrice: 0,
            previousClose: 0,
            change: 0,
            changePercent: 0,
            dividendYield: stock.dividendYield,
            currency: stock.market == .us ? "USD" : "HKD",
            exchange: ""
        )
    }

    // MARK: - 獲取最大漲幅
    func topGainers(count: Int = 10) -> [StockQuote] {
        quotes
            .filter { $0.currentPrice > 0 && $0.changePercent != 0 }
            .sorted { $0.changePercent > $1.changePercent }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - 獲取最大跌幅
    func topLosers(count: Int = 10) -> [StockQuote] {
        quotes
            .filter { $0.currentPrice > 0 && $0.changePercent != 0 }
            .sorted { $0.changePercent < $1.changePercent }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - 獲取最高收息率
    func topDividendYields(count: Int = 10) -> [StockQuote] {
        quotes
            .filter { $0.dividendYield > 0 }
            .sorted { $0.dividendYield > $1.dividendYield }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - 搜尋股票
    func searchStocks(query: String) -> [StockInfo] {
        let lowercaseQuery = query.lowercased()
        return StockDatabase.allStocks.filter {
            $0.symbol.lowercased().contains(lowercaseQuery) ||
            $0.name.lowercased().contains(lowercaseQuery)
        }
    }
}
