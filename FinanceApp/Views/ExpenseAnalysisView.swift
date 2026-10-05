import SwiftUI
import Charts

// MARK: - 支出分析圖表面板
struct ExpenseAnalysisView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPeriod: AnalysisPeriod = .month
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedQuarter: Int = ((Calendar.current.component(.month, from: Date()) - 1) / 3) + 1
    @State private var showingAddCategory = false

    var availableYears: [Int] {
        let years = persistence.availableYears
        let currentYear = Calendar.current.component(.year, from: Date())
        if years.contains(currentYear) {
            return years
        } else {
            return [currentYear] + years
        }
    }

    /// 當前時段的支出總覽
    var currentOverview: PeriodExpenseOverview {
        switch selectedPeriod {
        case .month:
            return persistence.monthlyExpenseOverview(year: selectedYear, month: selectedMonth)
        case .quarter:
            return persistence.quarterlyExpenseOverview(year: selectedYear, quarter: selectedQuarter)
        case .year:
            return persistence.yearlyPeriodOverview(for: selectedYear)
        }
    }

    /// 上一期標籤
    var previousPeriodLabel: String {
        switch selectedPeriod {
        case .month:
            let pm = selectedMonth == 1 ? 12 : selectedMonth - 1
            let py = selectedMonth == 1 ? selectedYear - 1 : selectedYear
            return "\(py)年\(pm)月"
        case .quarter:
            let pq = selectedQuarter == 1 ? 4 : selectedQuarter - 1
            let py = selectedQuarter == 1 ? selectedYear - 1 : selectedYear
            return "\(py)年Q\(pq)"
        case .year:
            return "\(selectedYear - 1)年"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 時段切換
                    periodPicker

                    // 年份選擇器
                    yearPicker

                    // 月份或季度選擇器
                    subPeriodPicker

                    // 總覽卡片
                    summaryCard

                    // 趨勢圖
                    trendChart

                    // 各類別支出柱狀圖
                    categoryBarChart

                    // 環比/同比增長分析
                    growthAnalysisCard

                    // 各類別明細列表
                    categoryDetailList

                    // 自定義類別管理
                    customCategorySection
                }
                .padding()
            }
            .navigationTitle("支出分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                AddCustomCategoryView()
            }
        }
    }

    // MARK: - 時段切換 (月/季/年)
    private var periodPicker: some View {
        Picker("分析維度", selection: $selectedPeriod) {
            ForEach(AnalysisPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 年份選擇器
    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        Text("\(String(year))")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedYear == year ? Color.financePrimary : Color.cardBackground)
                            .foregroundStyle(selectedYear == year ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
            }
        }
    }

    // MARK: - 月份或季度選擇器
    @ViewBuilder
    private var subPeriodPicker: some View {
        if selectedPeriod == .month {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        Button {
                            selectedMonth = month
                        } label: {
                            Text("\(month)月")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedMonth == month ? Color.financePrimary : Color.cardBackground)
                                .foregroundStyle(selectedMonth == month ? .white : .primary)
                                .cornerRadius(16)
                        }
                    }
                }
            }
        } else if selectedPeriod == .quarter {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(1...4, id: \.self) { q in
                        Button {
                            selectedQuarter = q
                        } label: {
                            Text("Q\(q)")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedQuarter == q ? Color.financePrimary : Color.cardBackground)
                                .foregroundStyle(selectedQuarter == q ? .white : .primary)
                                .cornerRadius(20)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 總覽卡片
    private var summaryCard: some View {
        let overview = currentOverview
        return VStack(spacing: 12) {
            Text(overview.periodLabel)
                .font(.headline)

            // 支出 / 收入
            HStack(spacing: 20) {
                VStack {
                    Text("總支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(overview.totalExpense.moneyString(currency: persistence.baseCurrency))
                        .font(.title2.bold())
                        .foregroundStyle(.expenseColor)
                }
                VStack {
                    Text("總收入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(overview.totalIncome.moneyString(currency: persistence.baseCurrency))
                        .font(.title2.bold())
                        .foregroundStyle(.incomeColor)
                }
            }

            // 日均支出 + 交易筆數
            HStack(spacing: 20) {
                VStack {
                    Text("日均支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(overview.dailyAverageExpense.moneyString(currency: persistence.baseCurrency))
                        .font(.subheadline.bold())
                }
                VStack {
                    Text("交易筆數")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(overview.transactionCount) 筆")
                        .font(.subheadline.bold())
                }
            }

            // 環比/同比變化
            if overview.previousPeriodExpense > 0 {
                Divider()
                HStack {
                    Image(systemName: overview.change >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(overview.change >= 0 ? .expenseColor : .incomeColor)
                    Text("vs \(previousPeriodLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(overview.change >= 0 ? "+" : "")\(overview.change.moneyString(currency: persistence.baseCurrency))")
                        .font(.subheadline.bold())
                        .foregroundStyle(overview.change >= 0 ? .expenseColor : .incomeColor)
                    Text("(\(String(format: "%+.1f%%", overview.changePercent)))")
                        .font(.caption)
                        .foregroundStyle(overview.change >= 0 ? .expenseColor : .incomeColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 趨勢圖
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch selectedPeriod {
            case .year, .month:
                Text("\(String(selectedYear)) 年月度趨勢")
                    .font(.headline)
                let trend = persistence.monthlyExpenseTrend(forYear: selectedYear)
                let hasData = trend.contains { $0.totalExpense > 0 }
                if hasData {
                    Chart(trend) { item in
                        LineMark(
                            x: .value("月", item.monthLabel),
                            y: .value("支出", item.totalExpense)
                        )
                        .foregroundStyle(Color.expenseColor)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("月", item.monthLabel),
                            y: .value("支出", item.totalExpense)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [Color.expenseColor.opacity(0.3), Color.expenseColor.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        if selectedPeriod == .month && item.month == selectedMonth {
                            PointMark(
                                x: .value("月", item.monthLabel),
                                y: .value("支出", item.totalExpense)
                            )
                            .foregroundStyle(Color.financePrimary)
                            .symbolSize(80)
                        }
                    }
                    .chartYAxisLabel(persistence.baseCurrency.symbol)
                    .frame(height: 200)
                } else {
                    emptyChartPlaceholder
                }

            case .quarter:
                Text("\(String(selectedYear)) 年季度對比")
                    .font(.headline)
                let quarters = persistence.quarterlyExpenseSummaries(forYear: selectedYear)
                let hasData = quarters.contains { $0.totalExpense > 0 }
                if hasData {
                    Chart(quarters) { item in
                        BarMark(
                            x: .value("季度", "Q\(item.month)"),
                            y: .value("支出", item.totalExpense)
                        )
                        .foregroundStyle(item.month == selectedQuarter ? Color.financePrimary : Color.financePrimary.opacity(0.4))
                        .annotation(position: .top) {
                            Text(item.totalExpense.compactString())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxisLabel(persistence.baseCurrency.symbol)
                    .frame(height: 200)
                } else {
                    emptyChartPlaceholder
                }
            }
        }
        .cardStyle()
    }

    private var emptyChartPlaceholder: some View {
        Text("暫無數據")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }

    // MARK: - 各類別支出柱狀圖
    private var categoryBarChart: some View {
        let overview = currentOverview
        return VStack(alignment: .leading, spacing: 8) {
            Text("各類別支出")
                .font(.headline)

            if overview.categories.isEmpty {
                Text("暫無支出記錄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(overview.categories) { stat in
                    BarMark(
                        x: .value("金額", stat.amount),
                        y: .value("類別", stat.category)
                    )
                    .foregroundStyle(by: .value("類別", stat.category))
                    .annotation(position: .trailing) {
                        HStack(spacing: 4) {
                            Text(stat.amount.compactString())
                            Text("(\(String(format: "%.0f%%", stat.percentage(of: overview.totalExpense))))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("金額 (\(persistence.baseCurrency.symbol))")
                .frame(height: CGFloat(max(overview.categories.count * 40, 200)))
                .chartLegend(.hidden)
            }
        }
        .cardStyle()
    }

    // MARK: - 環比/同比增長分析
    private var growthAnalysisCard: some View {
        let overview = currentOverview
        let compLabel: String = {
            switch selectedPeriod {
            case .month: return "環比分析"
            case .quarter: return "環比分析"
            case .year: return "同比分析"
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(compLabel)
                .font(.headline)

            Text("vs \(previousPeriodLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            let changes = overview.categories.filter { $0.previousPeriodAmount > 0 || $0.amount > 0 }
            if changes.isEmpty {
                Text("暫無對比數據")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(changes.filter { $0.change != 0 || $0.isNewCategory }) { stat in
                    HStack(spacing: 12) {
                        Image(systemName: stat.icon)
                            .frame(width: 28)
                            .foregroundStyle(.financePrimary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.category)
                                .font(.subheadline)
                            Text("\(stat.transactionCount) 筆交易")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if stat.isNewCategory {
                            Text("新增")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .cornerRadius(6)
                        } else {
                            VStack(alignment: .trailing) {
                                Text("\(stat.change >= 0 ? "+" : "")\(stat.change.moneyString(currency: persistence.baseCurrency))")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(stat.change >= 0 ? .expenseColor : .incomeColor)
                                Text(String(format: "%+.1f%%", stat.changePercent))
                                    .font(.caption2)
                                    .foregroundStyle(stat.change >= 0 ? .expenseColor : .incomeColor)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - 各類別明細列表
    private var categoryDetailList: some View {
        let overview = currentOverview
        return VStack(alignment: .leading, spacing: 8) {
            Text("類別明細")
                .font(.headline)

            if overview.categories.isEmpty {
                Text("暫無支出記錄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(overview.categories) { stat in
                    HStack(spacing: 12) {
                        Image(systemName: stat.icon)
                            .frame(width: 28)
                            .foregroundStyle(.financePrimary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.category)
                                .font(.subheadline)
                            Text("\(stat.transactionCount) 筆交易")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(stat.amount.moneyString(currency: persistence.baseCurrency))
                                .font(.subheadline.bold())
                            if stat.previousPeriodAmount > 0 {
                                Text("上期: \(stat.previousPeriodAmount.compactString())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(String(format: "%.1f%%", stat.percentage(of: overview.totalExpense)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        .cardStyle()
    }

    // MARK: - 自定義類別管理
    private var customCategorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("自定義類別")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddCategory = true
                } label: {
                    Label("新增", systemImage: "plus.circle.fill")
                        .font(.caption)
                }
            }

            if persistence.customCategories.isEmpty {
                Text("尚未新增自定義類別")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(persistence.customCategories) { cat in
                    HStack {
                        Image(systemName: cat.icon)
                            .frame(width: 28)
                            .foregroundStyle(.financePrimary)
                        Text(cat.name)
                            .font(.subheadline)
                        Spacer()
                        Text(cat.type.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive) {
                            persistence.deleteCustomCategory(cat)
                        } label: {
                            Label("刪除類別", systemImage: "trash")
                        }
                    }
                }

                Text("長按類別可刪除")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle()
    }
}

// MARK: - 新增自定義類別視圖
struct AddCustomCategoryView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var type: Transaction.TransactionType = .expense

    private let availableIcons: [String] = [
        "tag.fill", "fork.knife", "car.fill", "bag.fill", "gamecontroller.fill",
        "house.fill", "cross.case.fill", "graduationcap.fill", "chart.line.uptrend.xyaxis",
        "ellipsis.circle.fill", "airplane", "gift.fill", "creditcard.fill",
        "cup.and.saucer.fill", "book.fill", "bolt.fill", "wifi", "phone.fill",
        "cart.fill", "heart.fill", "ticket.fill", "wrench.fill", "paintbrush.fill"
    ]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var categoryAlreadyExists: Bool {
        persistence.allCategoryNames(for: type).contains {
            $0.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("類別名稱") {
                    TextField("輸入類別名稱", text: $name)
                    if !trimmedName.isEmpty && categoryAlreadyExists {
                        Label("此類型已有同名類別", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("類型") {
                    Picker("類型", selection: $type) {
                        ForEach(Transaction.TransactionType.bookkeepingCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("圖標") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(availableIcons, id: \.self) { iconName in
                            Image(systemName: iconName)
                                .font(.title2)
                                .foregroundStyle(icon == iconName ? .white : .primary)
                                .frame(width: 44, height: 44)
                                .background(icon == iconName ? Color.financePrimary : Color.gray.opacity(0.1))
                                .cornerRadius(10)
                                .onTapGesture {
                                    icon = iconName
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("新增類別")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveCategory() }
                        .disabled(trimmedName.isEmpty || categoryAlreadyExists)
                        .bold()
                }
            }
        }
    }

    private func saveCategory() {
        let category = CustomCategory(
            name: trimmedName,
            icon: icon,
            type: type,
            color: "financePrimary"
        )
        persistence.addCustomCategory(category)
        dismiss()
    }
}
