import SwiftUI

// MARK: - 警報中心 - 股價警報 + 週期性交易
struct AlertCenterView: View {
    @StateObject private var persistence = PersistenceService.shared
    @StateObject private var stockService = StockService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var showingAddAlert = false
    @State private var showingAddRecurring = false
    @State private var currentQuotes: [String: StockQuote] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("視圖", selection: $selectedTab) {
                    Text("股價警報").tag(0)
                    Text("週期性交易").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    priceAlertContent
                } else {
                    recurringContent
                }
            }
            .navigationTitle("警報中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedTab == 0 {
                            showingAddAlert = true
                        } else {
                            showingAddRecurring = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddAlert) {
                AddPriceAlertView()
            }
            .sheet(isPresented: $showingAddRecurring) {
                AddRecurringView()
            }
            .task {
                await checkAlerts()
            }
        }
    }

    // MARK: - 股價警報
    private var priceAlertContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if persistence.priceAlerts.isEmpty {
                    emptyState(icon: "bell.badge", text: "尚未設定股價警報", subtext: "設定目標價到價提醒")
                } else {
                    ForEach(persistence.priceAlerts) { alert in
                        PriceAlertRow(alert: alert, currentPrice: currentQuotes[alert.symbol]?.currentPrice)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 週期性交易
    private var recurringContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if persistence.recurringTransactions.isEmpty {
                    emptyState(icon: "arrow.clockwise.circle", text: "尚未設定週期性交易", subtext: "自動生成固定支出/收入")
                } else {
                    // 總覽
                    recurringSummary

                    ForEach(persistence.recurringTransactions) { rt in
                        RecurringRow(rt: rt)
                    }
                }
            }
            .padding()
        }
    }

    private var recurringSummary: some View {
        VStack(spacing: 8) {
            let monthlyExpense = persistence.recurringTransactions
                .filter { $0.isEnabled && $0.type == .expense && $0.frequency == .monthly }
                .reduce(0.0) { $0 + ExchangeRateProvider.convert($1.amount, from: $1.currency, to: persistence.baseCurrency) }

            Text("每月固定支出")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(monthlyExpense.moneyString(currency: persistence.baseCurrency))
                .font(.title2.bold())
                .foregroundStyle(.expenseColor)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func emptyState(icon: String, text: String, subtext: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(subtext)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 60)
    }

    private func checkAlerts() async {
        let alerts = persistence.priceAlerts.filter { $0.isEnabled }
        guard !alerts.isEmpty else { return }

        let symbols = Set(alerts.map { $0.symbol })
        let stockInfos = symbols.map { symbol in
            let alert = alerts.first { $0.symbol == symbol }!
            return StockInfo(symbol: symbol, name: alert.name, market: alert.market, dividendYield: 0)
        }

        await stockService.fetchQuotes(for: stockInfos)
        await MainActor.run {
            for quote in stockService.quotes {
                currentQuotes[quote.symbol] = quote
            }

            // 檢查觸發
            for alert in alerts {
                if let price = currentQuotes[alert.symbol]?.currentPrice, alert.shouldTrigger(currentPrice: price) {
                    sendAlertNotification(alert, price: price)
                    var updated = alert
                    updated.triggeredAt = Date()
                    updated.isEnabled = false
                    persistence.updatePriceAlert(updated)
                }
            }
        }
    }

    private func sendAlertNotification(_ alert: PriceAlert, price: Double) {
        let content = UNMutableNotificationContent()
        content.title = "🔔 股價警報：\(alert.symbol)"
        content.body = "\(alert.name) \(alert.condition.rawValue) \(alert.targetPrice.compactString())\n當前價格：\(price.compactString())"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "price_alert_\(alert.symbol)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - 股價警報行
struct PriceAlertRow: View {
    let alert: PriceAlert
    let currentPrice: Double?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(alert.isEnabled ? Color.financePrimary.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: alert.condition.icon)
                    .foregroundStyle(alert.isEnabled ? .financePrimary : .gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(alert.symbol)
                        .font(.subheadline.bold())
                    Text(alert.market.flag)
                }
                Text(alert.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(alert.condition.rawValue) \(alert.targetPrice.compactString())")
                    .font(.subheadline.bold())
                if let price = currentPrice {
                    Text("現價: \(price.compactString())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("載入中...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !alert.isEnabled {
                    if alert.triggeredAt != nil {
                        Text("已觸發")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    } else {
                        Text("已停用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(10)
    }
}

// MARK: - 週期性交易行
struct RecurringRow: View {
    let rt: RecurringTransaction

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rt.isEnabled ? Color.financePrimary.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: rt.frequency.icon)
                    .foregroundStyle(rt.isEnabled ? .financePrimary : .gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rt.title)
                    .font(.subheadline.bold())
                HStack {
                    Text(rt.frequency.rawValue)
                    Text("·")
                    Text("每月 \(rt.dayOfMonth) 號")
                    Text("·")
                    Text(rt.category)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(rt.type == .income ? "+" : "-")
                    + Text(rt.amount.moneyString(currency: rt.currency))
                .font(.subheadline.bold())
                .foregroundStyle(rt.type == .income ? .incomeColor : .expenseColor)

                if rt.isEnabled {
                    Text("下次: \(rt.nextExecuteDate.shortDateString)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("已停用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(10)
    }
}

// MARK: - 新增股價警報
struct AddPriceAlertView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var name = ""
    @State private var market: StockHolding.StockMarket = .us
    @State private var condition: PriceAlert.AlertCondition = .above
    @State private var targetPrice = ""

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

                Section("警報條件") {
                    Picker("條件", selection: $condition) {
                        ForEach(PriceAlert.AlertCondition.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("目標價格", text: $targetPrice)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("新增警報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("建立") { save() }
                        .disabled(symbol.isEmpty || targetPrice.isEmpty || Double(targetPrice) == nil)
                        .bold()
                }
            }
        }
    }

    private func save() {
        guard let price = Double(targetPrice), price > 0 else { return }
        let alert = PriceAlert(
            symbol: symbol.uppercased(),
            name: name,
            market: market,
            condition: condition,
            targetPrice: price
        )
        persistence.addPriceAlert(alert)
        dismiss()
    }
}

// MARK: - 新增週期性交易
struct AddRecurringView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amount = ""
    @State private var type: Transaction.TransactionType = .expense
    @State private var category = ExpenseCategory.food.rawValue
    @State private var currency: Currency = .hkd
    @State private var frequency: RecurringTransaction.Frequency = .monthly
    @State private var dayOfMonth = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("名稱", text: $title)
                    Picker("類型", selection: $type) {
                        ForEach(Transaction.TransactionType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _ in
                        category = persistence.allCategoryNames(for: type).first ?? ""
                    }
                }

                Section("金額") {
                    TextField("金額", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("幣種", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                }

                Section("類別") {
                    Picker("類別", selection: $category) {
                        ForEach(persistence.allCategoryNames(for: type), id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                }

                Section("週期") {
                    Picker("頻率", selection: $frequency) {
                        ForEach(RecurringTransaction.Frequency.allCases, id: \.self) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    if frequency != .weekly {
                        Stepper("每月第 \(dayOfMonth) 號", value: $dayOfMonth, in: 1...28)
                    }
                }
            }
            .navigationTitle("新增週期性交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("建立") { save() }
                        .disabled(title.isEmpty || Double(amount) == nil)
                        .bold()
                }
            }
        }
    }

    private func save() {
        guard let amt = Double(amount), amt > 0 else { return }
        let rt = RecurringTransaction(
            title: title,
            amount: amt,
            type: type,
            category: category,
            currency: currency,
            frequency: frequency,
            dayOfMonth: dayOfMonth,
            startDate: Date()
        )
        persistence.addRecurring(rt)
        dismiss()
    }
}
