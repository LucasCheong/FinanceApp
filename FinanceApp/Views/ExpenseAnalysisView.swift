import SwiftUI
import Charts

// MARK: - 支出分析圖表面板
struct ExpenseAnalysisView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
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

    var yearlyOverview: YearlyExpenseOverview {
        persistence.yearlyExpenseOverview(for: selectedYear)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 年份選擇器
                    yearPicker

                    // 年度總覽卡片
                    yearlySummaryCard

                    // 各類別支出柱狀圖
                    categoryBarChart

                    // 同比增長分析
                    yoyAnalysisCard

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

    // MARK: - 年度總覽卡片
    private var yearlySummaryCard: some View {
        VStack(spacing: 12) {
            Text("\(String(selectedYear)) 年度總覽")
                .font(.headline)

            HStack(spacing: 24) {
                VStack {
                    Text("年度支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(yearlyOverview.totalExpense.moneyString(currency: persistence.baseCurrency))
                        .font(.title2.bold())
                        .foregroundStyle(.expenseColor)
                }

                VStack {
                    Text("年度收入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(yearlyOverview.totalIncome.moneyString(currency: persistence.baseCurrency))
                        .font(.title2.bold())
                        .foregroundStyle(.incomeColor)
                }
            }

            // 同比變化
            if yearlyOverview.previousYearExpense > 0 {
                Divider()
                HStack {
                    Image(systemName: yearlyOverview.yoyChange >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(yearlyOverview.yoyChange >= 0 ? .expenseColor : .incomeColor)
                    Text("vs \(String(selectedYear - 1)) 年")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(yearlyOverview.yoyChange >= 0 ? "+" : "")\(yearlyOverview.yoyChange.moneyString(currency: persistence.baseCurrency))")
                        .font(.subheadline.bold())
                        .foregroundStyle(yearlyOverview.yoyChange >= 0 ? .expenseColor : .incomeColor)
                    Text("(\(String(format: "%+.1f%%", yearlyOverview.yoyPercent)))")
                        .font(.caption)
                        .foregroundStyle(yearlyOverview.yoyChange >= 0 ? .expenseColor : .incomeColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 各類別支出柱狀圖
    private var categoryBarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("各類別支出")
                .font(.headline)

            if yearlyOverview.categories.isEmpty {
                Text("本年度暫無支出記錄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(yearlyOverview.categories) { stat in
                    BarMark(
                        x: .value("金額", stat.amount),
                        y: .value("類別", stat.category)
                    )
                    .foregroundStyle(by: .value("類別", stat.category))
                    .annotation(position: .trailing) {
                        Text(stat.amount.compactString())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("金額 (\(persistence.baseCurrency.symbol))")
                .frame(height: CGFloat(max(yearlyOverview.categories.count * 40, 200)))
                .chartLegend(.hidden)
            }
        }
        .cardStyle()
    }

    // MARK: - 同比增長分析
    private var yoyAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("同比增長分析")
                .font(.headline)

            Text("與 \(String(selectedYear - 1)) 年對比")
                .font(.caption)
                .foregroundStyle(.secondary)

            let changes = yearlyOverview.categories.filter { $0.previousYearAmount > 0 || $0.amount > 0 }
            if changes.isEmpty {
                Text("暫無對比數據")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(changes.filter { $0.yoyChange != 0 || $0.isNewCategory }) { stat in
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
                                Text("\(stat.yoyChange >= 0 ? "+" : "")\(stat.yoyChange.moneyString(currency: persistence.baseCurrency))")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(stat.yoyChange >= 0 ? .expenseColor : .incomeColor)
                                Text(String(format: "%+.1f%%", stat.yoyPercent))
                                    .font(.caption2)
                                    .foregroundStyle(stat.yoyChange >= 0 ? .expenseColor : .incomeColor)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("類別明細")
                .font(.headline)

            if yearlyOverview.categories.isEmpty {
                Text("本年度暫無支出記錄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(yearlyOverview.categories) { stat in
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
                            if stat.previousYearAmount > 0 {
                                Text("去年: \(stat.previousYearAmount.compactString())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
                }
                .onDelete { offsets in
                    persistence.deleteCustomCategory(at: offsets)
                }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("類別名稱") {
                    TextField("輸入類別名稱", text: $name)
                }

                Section("類型") {
                    Picker("類型", selection: $type) {
                        ForEach(Transaction.TransactionType.allCases, id: \.self) { t in
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
                        .disabled(name.isEmpty)
                        .bold()
                }
            }
        }
    }

    private func saveCategory() {
        let category = CustomCategory(
            name: name,
            icon: icon,
            type: type,
            color: "financePrimary"
        )
        persistence.addCustomCategory(category)
        dismiss()
    }
}
