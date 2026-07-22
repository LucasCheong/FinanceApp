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

        // 每批最多 5 個，避免請求過多
        let batches = stride(from: 0, to: stocks.count, by: 5).map {
            Array(stocks[$0..<min($0 + 5, stocks.count)])
        }

        var results: [StockQuote] = []

        for batch in batches {
            let batchResults = await withTaskGroup(of: StockQuote?.self) { group -> [StockQuote] in
                for stock in batch {
                    group.addTask {
                        await self.fetchSingleQuote(for: stock)
                    }
                }
                var batchResults: [StockQuote] = []
                for await quote in group {
                    if let quote = quote {
                        batchResults.append(quote)
                    }
                }
                return batchResults
            }
            results.append(contentsOf: batchResults)
        }

        let finalResults = results
        await MainActor.run {
            self.quotes = finalResults
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

    // MARK: - 拉取歷史收盤價數據（用於均線計算）
    /// 返回最近 N 天的收盤價數組（按日期升序）
    func fetchHistoricalCloses(for symbol: String, days: Int = 30) async -> [Double] {
        // range=2mo 可獲取約 40 個交易日的數據
        let urlString = "\(baseURL)/\(symbol)?range=2mo&interval=1d"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            return parseHistoricalCloses(from: data, maxCount: days)
        } catch {
            print("獲取 \(symbol) 歷史數據失敗: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - 解析歷史收盤價
    private func parseHistoricalCloses(from data: Data, maxCount: Int) -> [Double] {
        struct ChartResponse: Decodable {
            struct Chart: Decodable {
                struct Result: Decodable {
                    struct Indicators: Decodable {
                        struct Quote: Decodable {
                            let close: [Double?]
                        }
                        let quote: [Quote]
                    }
                    let indicators: Indicators?
                }
                let result: [Result]?
            }
            let chart: Chart
        }

        do {
            let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
            guard let result = decoded.chart.result?.first,
                  let closes = result.indicators?.quote.first?.close else { return [] }
            // 過濾 nil 值，取最後 maxCount 個
            let validCloses = closes.compactMap { $0 }
            let startIndex = max(0, validCloses.count - maxCount)
            return Array(validCloses[startIndex...])
        } catch {
            print("解析歷史數據失敗: \(error)")
            return []
        }
    }

    // MARK: - 計算均線信號（批量）
    /// 對持倉中的股票批量計算均線信號
    func fetchMovingAverageSignals(for holdings: [StockHolding]) async -> [MovingAverageSignal] {
        var signals: [MovingAverageSignal] = []

        // 分批處理，每批 3 個
        let batches = stride(from: 0, to: holdings.count, by: 3).map {
            Array(holdings[$0..<min($0 + 3, holdings.count)])
        }

        for batch in batches {
            let batchSignals = await withTaskGroup(of: MovingAverageSignal?.self) { group -> [MovingAverageSignal] in
                for holding in batch {
                    group.addTask {
                        await self.calculateSignal(for: holding)
                    }
                }
                var results: [MovingAverageSignal] = []
                for await signal in group {
                    if let signal = signal {
                        results.append(signal)
                    }
                }
                return results
            }
            signals.append(contentsOf: batchSignals)
        }

        return signals
    }

    // MARK: - 計算單支股票的均線信號
    private func calculateSignal(for holding: StockHolding) async -> MovingAverageSignal? {
        let closes = await fetchHistoricalCloses(for: holding.symbol, days: 30)

        guard closes.count >= 20 else {
            // 數據不足，返回默認信號
            return MovingAverageSignal(
                symbol: holding.symbol,
                name: holding.name,
                market: holding.market,
                currentPrice: holding.purchasePrice,
                ma10: holding.purchasePrice,
                ma20: holding.purchasePrice,
                previousClose: holding.purchasePrice
            )
        }

        let currentPrice = closes.last ?? holding.purchasePrice
        let previousClose = closes.count >= 2 ? closes[closes.count - 2] : currentPrice

        // 計算 MA10（最近10天平均）
        let ma10Start = max(0, closes.count - 10)
        let ma10 = Array(closes[ma10Start...]).reduce(0, +) / Double(closes.count - ma10Start)

        // 計算 MA20（最近20天平均）
        let ma20Start = max(0, closes.count - 20)
        let ma20 = Array(closes[ma20Start...]).reduce(0, +) / Double(closes.count - ma20Start)

        return MovingAverageSignal(
            symbol: holding.symbol,
            name: holding.name,
            market: holding.market,
            currentPrice: currentPrice,
            ma10: ma10,
            ma20: ma20,
            previousClose: previousClose
        )
    }
}
