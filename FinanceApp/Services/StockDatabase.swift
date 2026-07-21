import Foundation

/// 內置股票和ETF數據庫 - 包含美股和港股的熱門標的
struct StockDatabase {
    // MARK: - 美股熱門股票
    static let usStocks: [StockInfo] = [
        StockInfo(symbol: "AAPL", name: "Apple Inc.", market: .us, dividendYield: 0.0052),
        StockInfo(symbol: "MSFT", name: "Microsoft Corp.", market: .us, dividendYield: 0.0073),
        StockInfo(symbol: "GOOGL", name: "Alphabet Inc.", market: .us, dividendYield: 0.0),
        StockInfo(symbol: "AMZN", name: "Amazon.com Inc.", market: .us, dividendYield: 0.0),
        StockInfo(symbol: "NVDA", name: "NVIDIA Corp.", market: .us, dividendYield: 0.0003),
        StockInfo(symbol: "META", name: "Meta Platforms Inc.", market: .us, dividendYield: 0.0035),
        StockInfo(symbol: "TSLA", name: "Tesla Inc.", market: .us, dividendYield: 0.0),
        StockInfo(symbol: "BRK-B", name: "Berkshire Hathaway", market: .us, dividendYield: 0.0),
        StockInfo(symbol: "JPM", name: "JPMorgan Chase", market: .us, dividendYield: 0.0235),
        StockInfo(symbol: "V", name: "Visa Inc.", market: .us, dividendYield: 0.0075),
        StockInfo(symbol: "MA", name: "Mastercard Inc.", market: .us, dividendYield: 0.0055),
        StockInfo(symbol: "UNH", name: "UnitedHealth Group", market: .us, dividendYield: 0.0155),
        StockInfo(symbol: "HD", name: "Home Depot", market: .us, dividendYield: 0.0245),
        StockInfo(symbol: "JNJ", name: "Johnson & Johnson", market: .us, dividendYield: 0.0335),
        StockInfo(symbol: "PG", name: "Procter & Gamble", market: .us, dividendYield: 0.0245),
        StockInfo(symbol: "KO", name: "Coca-Cola Co.", market: .us, dividendYield: 0.0312),
        StockInfo(symbol: "PEP", name: "PepsiCo Inc.", market: .us, dividendYield: 0.0315),
        StockInfo(symbol: "XOM", name: "Exxon Mobil", market: .us, dividendYield: 0.0335),
        StockInfo(symbol: "CVX", name: "Chevron Corp.", market: .us, dividendYield: 0.0402),
        StockInfo(symbol: "ABBV", name: "AbbVie Inc.", market: .us, dividendYield: 0.0372),
    ]

    // MARK: - 美股高息ETF
    static let usETFs: [StockInfo] = [
        StockInfo(symbol: "SCHD", name: "Schwab US Dividend ETF", market: .us, dividendYield: 0.0355),
        StockInfo(symbol: "VYM", name: "Vanguard High Dividend ETF", market: .us, dividendYield: 0.0285),
        StockInfo(symbol: "HDV", name: "iShares Core High Dividend ETF", market: .us, dividendYield: 0.0315),
        StockInfo(symbol: "DVY", name: "iShares Select Dividend ETF", market: .us, dividendYield: 0.0325),
        StockInfo(symbol: "VIG", name: "Vanguard Dividend Appreciation ETF", market: .us, dividendYield: 0.0175),
        StockInfo(symbol: "JEPI", name: "JPM Equity Premium Income ETF", market: .us, dividendYield: 0.0725),
        StockInfo(symbol: "JEPQ", name: "JPM Nasdaq Equity Premium Income ETF", market: .us, dividendYield: 0.0655),
        StockInfo(symbol: "SCHG", name: "Schwab US Large-Cap Growth ETF", market: .us, dividendYield: 0.0045),
        StockInfo(symbol: "QQQ", name: "Invesco QQQ Trust", market: .us, dividendYield: 0.0055),
        StockInfo(symbol: "SPY", name: "SPDR S&P 500 ETF", market: .us, dividendYield: 0.0125),
        StockInfo(symbol: "VTI", name: "Vanguard Total Stock Market ETF", market: .us, dividendYield: 0.0145),
        StockInfo(symbol: "AGG", name: "iShares Core US Aggregate Bond ETF", market: .us, dividendYield: 0.0425),
        StockInfo(symbol: "BND", name: "Vanguard Total Bond Market ETF", market: .us, dividendYield: 0.0415),
        StockInfo(symbol: "PFF", name: "iShares Preferred Income Securities ETF", market: .us, dividendYield: 0.0565),
        StockInfo(symbol: "O", name: "Realty Income Corp", market: .us, dividendYield: 0.0555),
    ]

    // MARK: - 港股熱門股票
    static let hkStocks: [StockInfo] = [
        StockInfo(symbol: "0700.HK", name: "騰訊控股", market: .hk, dividendYield: 0.0085),
        StockInfo(symbol: "9988.HK", name: "阿里巴巴集團", market: .hk, dividendYield: 0.0),
        StockInfo(symbol: "0005.HK", name: "匯豐控股", market: .hk, dividendYield: 0.0725),
        StockInfo(symbol: "0388.HK", name: "香港交易所", market: .hk, dividendYield: 0.0285),
        StockInfo(symbol: "0939.HK", name: "建設銀行", market: .hk, dividendYield: 0.0835),
        StockInfo(symbol: "1398.HK", name: "工商銀行", market: .hk, dividendYield: 0.0855),
        StockInfo(symbol: "0941.HK", name: "中國移動", market: .hk, dividendYield: 0.0635),
        StockInfo(symbol: "0883.HK", name: "中海油", market: .hk, dividendYield: 0.0725),
        StockInfo(symbol: "0011.HK", name: "恒生銀行", market: .hk, dividendYield: 0.0565),
        StockInfo(symbol: "0002.HK", name: "中電控股", market: .hk, dividendYield: 0.0455),
        StockInfo(symbol: "0001.HK", name: "長和", market: .hk, dividendYield: 0.0425),
        StockInfo(symbol: "0016.HK", name: "新鴻基地產", market: .hk, dividendYield: 0.0555),
        StockInfo(symbol: "0003.HK", name: "香港中華煤氣", market: .hk, dividendYield: 0.0355),
        StockInfo(symbol: "0012.HK", name: "恒基地產", market: .hk, dividendYield: 0.0585),
        StockInfo(symbol: "1038.HK", name: "長江基建集團", market: .hk, dividendYield: 0.0525),
        StockInfo(symbol: "2318.HK", name: "中國平安", market: .hk, dividendYield: 0.0655),
        StockInfo(symbol: "2628.HK", name: "中國人壽", market: .hk, dividendYield: 0.0555),
        StockInfo(symbol: "0823.HK", name: "領展房產基金", market: .hk, dividendYield: 0.0685),
        StockInfo(symbol: "1810.HK", name: "小米集團", market: .hk, dividendYield: 0.0),
        StockInfo(symbol: "3690.HK", name: "美團", market: .hk, dividendYield: 0.0),
    ]

    // MARK: - 港股高息ETF
    static let hkETFs: [StockInfo] = [
        StockInfo(symbol: "2800.HK", name: "盈富基金 (Tracker Fund)", market: .hk, dividendYield: 0.0285),
        StockInfo(symbol: "2828.HK", name: "恒生中國企業指數ETF", market: .hk, dividendYield: 0.0355),
        StockInfo(symbol: "2833.HK", name: "恒生高股息率ETF", market: .hk, dividendYield: 0.0655),
        StockInfo(symbol: "3111.HK", name: "恒生高息股ETF", market: .hk, dividendYield: 0.0685),
        StockInfo(symbol: "02828.HK", name: "iShares A50 ETF", market: .hk, dividendYield: 0.0255),
        StockInfo(symbol: "03082.HK", name: "南方A50 ETF", market: .hk, dividendYield: 0.0225),
    ]

    // 所有標的
    static var allStocks: [StockInfo] {
        usStocks + usETFs + hkStocks + hkETFs
    }

    // 美股全部
    static var allUS: [StockInfo] {
        usStocks + usETFs
    }

    // 港股全部
    static var allHK: [StockInfo] {
        hkStocks + hkETFs
    }

    // 高息標的（收益率 > 4%）
    static var highYieldStocks: [StockInfo] {
        allStocks.filter { $0.dividendYield >= 0.04 }
    }
}

// MARK: - 股票信息結構
struct StockInfo: Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let market: StockHolding.StockMarket
    let dividendYield: Double

    var displayName: String {
        "\(name) (\(symbol))"
    }
}
