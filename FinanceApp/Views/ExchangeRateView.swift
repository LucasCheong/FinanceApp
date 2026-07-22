import SwiftUI
import Charts

// MARK: - 匯率走勢圖
struct ExchangeRateView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCurrency: Currency = .usd
    @State private var rateHistory: [RatePoint] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 幣種選擇器
                    currencySelector

                    // 當前匯率卡片
                    currentRateCard

                    // 匯率走勢圖
                    rateChartCard

                    // 匯率換算器
                    currencyConverterCard

                    // 所有幣種列表
                    allRatesList
                }
                .padding()
            }
            .navigationTitle("匯率走勢")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        generateRateHistory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                generateRateHistory()
            }
        }
    }

    private var currencySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Currency.allCases.filter { $0 != persistence.baseCurrency }, id: \.self) { cur in
                    Button {
                        selectedCurrency = cur
                        generateRateHistory()
                    } label: {
                        Text(cur.code)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedCurrency == cur ? Color.financePrimary : Color.cardBackground)
                            .foregroundStyle(selectedCurrency == cur ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
            }
        }
    }

    private var currentRateCard: some View {
        VStack(spacing: 12) {
            Text("當前匯率")
                .font(.headline)

            HStack(spacing: 16) {
                VStack {
                    Text("1 \(selectedCurrency.code)")
                        .font(.title2.bold())
                    Text(selectedCurrency.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.financePrimary)

                VStack {
                    let rate = ExchangeRateProvider.convert(1, from: selectedCurrency, to: persistence.baseCurrency)
                    Text(String(format: "%.4f", rate))
                        .font(.title2.bold())
                    Text(persistence.baseCurrency.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var rateChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(selectedCurrency.code) / \(persistence.baseCurrency.code) 走勢")
                .font(.headline)

            if rateHistory.isEmpty {
                Text("暫無歷史數據")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(rateHistory) { point in
                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("匯率", point.rate)
                    )
                    .foregroundStyle(.financePrimary)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("匯率", point.rate)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [.financePrimary.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 250)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }

                let firstRate = rateHistory.first?.rate ?? 0
                let lastRate = rateHistory.last?.rate ?? 0
                let change = lastRate - firstRate
                let changePercent = firstRate > 0 ? change / firstRate * 100 : 0

                HStack {
                    Text("30天變化:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.4f (%+.2f%%)", change, changePercent))
                        .font(.caption.bold())
                        .foregroundStyle(change >= 0 ? .incomeColor : .expenseColor)
                }
            }
        }
        .cardStyle()
    }

    private var currencyConverterCard: some View {
        CurrencyConverter(baseCurrency: persistence.baseCurrency, selectedCurrency: selectedCurrency)
    }

    private var allRatesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("所有幣種匯率 (基準: \(persistence.baseCurrency.code))")
                .font(.headline)

            ForEach(Currency.allCases.filter { $0 != persistence.baseCurrency }, id: \.self) { cur in
                HStack {
                    Text(cur.code)
                        .font(.subheadline.bold())
                    Text(cur.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    let rate = ExchangeRateProvider.convert(1, from: cur, to: persistence.baseCurrency)
                    Text(String(format: "%.4f", rate))
                        .font(.subheadline)
                    Text(persistence.baseCurrency.code)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .cardStyle()
    }

    // MARK: - 生成歷史匯率（模擬數據）
    private struct RatePoint: Identifiable {
        var id: Date { date }
        let date: Date
        let rate: Double
    }

    private func generateRateHistory() {
        let calendar = Calendar.current
        let currentRate = ExchangeRateProvider.convert(1, from: selectedCurrency, to: persistence.baseCurrency)
        var points: [RatePoint] = []

        for i in stride(from: 29, through: 0, by: -1) {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                // 模擬匯率波動 (±2%)
                let volatility = Double.random(in: -0.02...0.02)
                let trend = Double(i) * 0.0005
                let rate = currentRate * (1 + volatility - trend)
                points.append(RatePoint(date: date, rate: rate))
            }
        }

        rateHistory = points
    }
}

// MARK: - 匯率換算器
struct CurrencyConverter: View {
    let baseCurrency: Currency
    let selectedCurrency: Currency

    @State private var amount = ""
    @State private var direction = true // true: 外幣 -> 基準, false: 基準 -> 外幣

    var convertedAmount: Double {
        guard let amt = Double(amount), amt > 0 else { return 0 }
        if direction {
            return ExchangeRateProvider.convert(amt, from: selectedCurrency, to: baseCurrency)
        } else {
            return ExchangeRateProvider.convert(amt, from: baseCurrency, to: selectedCurrency)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("匯率換算器")
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("金額")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(direction ? selectedCurrency.code : baseCurrency.code, text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.title3)
                }

                Button {
                    direction.toggle()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title3)
                        .foregroundStyle(.financePrimary)
                }
                .padding(.top, 20)

                VStack(alignment: .trailing) {
                    Text("結果")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let toCurrency = direction ? baseCurrency : selectedCurrency
                    Text(convertedAmount.moneyString(currency: toCurrency))
                        .font(.title3.bold())
                        .foregroundStyle(.financePrimary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text("1 \(selectedCurrency.code) = \(String(format: "%.4f", ExchangeRateProvider.convert(1, from: selectedCurrency, to: baseCurrency))) \(baseCurrency.code)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}
