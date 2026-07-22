import SwiftUI
import Charts

// MARK: - 預算管理 + 月度報告
struct BudgetView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate = Date()
    @State private var showingAddBudget = false
    @State private var showingReport = false

    var year: Int { Calendar.current.component(.year, from: selectedDate) }
    var month: Int { Calendar.current.component(.month, from: selectedDate) }

    var monthBudgets: [Budget] {
        persistence.budgetsForMonth(year: year, month: month)
    }

    var totalBudget: Double {
        monthBudgets.reduce(0) { $0 + $1.monthlyLimit }
    }

    var totalUsed: Double {
        monthBudgets.reduce(0) { $0 + $1.usedAmount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 月份選擇
                    monthSelector

                    // 總覽
                    budgetSummaryCard

                    // 各類別預算列表
                    budgetListCard

                    // 月度報告入口
                    monthlyReportButton
                }
                .padding()
            }
            .navigationTitle("預算管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddBudget = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddBudget) {
                AddBudgetView(year: year, month: month)
            }
            .sheet(isPresented: $showingReport) {
                MonthlyReportView(year: year, month: month)
            }
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
            }
            Spacer()
            Text("\(String(year))年 \(month)月")
                .font(.headline)
            Spacer()
            Button {
                selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
            }
        }
    }

    private var budgetSummaryCard: some View {
        VStack(spacing: 12) {
            Text("本月預算總覽")
                .font(.headline)

            let usagePercent = totalBudget > 0 ? (totalUsed / totalBudget * 100) : 0

            Text("\(totalUsed.moneyString(currency: persistence.baseCurrency)) / \(totalBudget.moneyString(currency: persistence.baseCurrency))")
                .font(.title2.bold())

            ProgressView(value: min(totalUsed, totalBudget), total: max(totalBudget, 1))
                .tint(usagePercent >= 100 ? .expenseColor : (usagePercent >= 80 ? .orange : .incomeColor))

            Text(String(format: "已使用 %.0f%%", usagePercent))
                .font(.caption)
                .foregroundStyle(usagePercent >= 100 ? .expenseColor : .secondary)

            if totalBudget - totalUsed < 0 {
                Text("超支 \((totalUsed - totalBudget).moneyString(currency: persistence.baseCurrency))")
                    .font(.caption.bold())
                    .foregroundStyle(.expenseColor)
            } else {
                Text("剩餘 \((totalBudget - totalUsed).moneyString(currency: persistence.baseCurrency))")
                    .font(.caption)
                    .foregroundStyle(.incomeColor)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var budgetListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("各類別預算")
                .font(.headline)

            if monthBudgets.isEmpty {
                Text("本月尚未設定預算")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(monthBudgets) { budget in
                    budgetRow(budget)
                }
            }
        }
        .cardStyle()
    }

    private func budgetRow(_ budget: Budget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: persistence.categoryIcon(for: budget.category, type: .expense))
                    .foregroundStyle(.financePrimary)
                Text(budget.category)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(budget.usedAmount.compactString()) / \(budget.monthlyLimit.compactString())")
                    .font(.caption)
                    .foregroundStyle(budget.isOverBudget ? .expenseColor : .secondary)
            }

            ProgressView(value: min(budget.usedAmount, budget.monthlyLimit), total: max(budget.monthlyLimit, 1))
                .tint(budget.isOverBudget ? .expenseColor : (budget.isNearLimit ? .orange : .incomeColor))

            HStack {
                Text(String(format: "%.0f%%", budget.usagePercent))
                    .font(.caption2)
                    .foregroundStyle(budget.isOverBudget ? .expenseColor : .secondary)
                Spacer()
                if budget.isOverBudget {
                    Text("超支 \(budget.remainingAmount.moneyString(currency: persistence.baseCurrency))")
                        .font(.caption2.bold())
                        .foregroundStyle(.expenseColor)
                } else {
                    Text("剩餘 \(budget.remainingAmount.moneyString(currency: persistence.baseCurrency))")
                        .font(.caption2)
                        .foregroundStyle(.incomeColor)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var monthlyReportButton: some View {
        Button {
            showingReport = true
        } label: {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("月度報告")
                        .font(.subheadline.bold())
                    Text("查看本月收支摘要")
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(10)
        }
    }
}

// MARK: - 新增預算視圖
struct AddBudgetView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    let year: Int
    let month: Int

    @State private var category = ExpenseCategory.food.rawValue
    @State private var limitAmount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("類別") {
                    Picker("選擇類別", selection: $category) {
                        ForEach(persistence.allCategoryNames(for: .expense), id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }

                Section("預算金額") {
                    TextField("月度上限", text: $limitAmount)
                        .keyboardType(.decimalPad)
                }

                Section("月份") {
                    Text("\(String(year))年 \(month)月")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新增預算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveBudget() }
                        .disabled(limitAmount.isEmpty || Double(limitAmount) == nil)
                        .bold()
                }
            }
        }
    }

    private func saveBudget() {
        guard let amount = Double(limitAmount), amount > 0 else { return }
        let budget = Budget(
            category: category,
            monthlyLimit: amount,
            currency: persistence.baseCurrency,
            year: year,
            month: month
        )
        persistence.addBudget(budget)
        dismiss()
    }
}

// MARK: - 月度報告視圖
struct MonthlyReportView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    let year: Int
    let month: Int

    var report: MonthlyReport {
        persistence.generateMonthlyReport(year: year, month: month)
    }

    var recentReports: [MonthlyReport] {
        persistence.recentMonthlyReports(count: 6)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 當月報告卡片
                    currentMonthCard

                    // 儲蓄率
                    savingsRateCard

                    // 收支趨勢圖
                    trendChartCard

                    // 最近6個月對比
                    recentMonthsCard
                }
                .padding()
            }
            .navigationTitle("\(String(year))年\(month)月報告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private var currentMonthCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("本月收支")
                    .font(.headline)
                Spacer()
                Text(report.budgetStatus)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(report.budgetStatus == "超支" ? Color.expenseColor : (report.budgetStatus == "達標" ? Color.incomeColor : Color.gray))
                    .cornerRadius(6)
            }

            HStack(spacing: 24) {
                VStack {
                    Text("收入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(report.totalIncome.moneyString(currency: persistence.baseCurrency))
                        .font(.title3.bold())
                        .foregroundStyle(.incomeColor)
                }
                VStack {
                    Text("支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(report.totalExpense.moneyString(currency: persistence.baseCurrency))
                        .font(.title3.bold())
                        .foregroundStyle(.expenseColor)
                }
                VStack {
                    Text("結餘")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(report.balance.moneyString(currency: persistence.baseCurrency))
                        .font(.title3.bold())
                        .foregroundStyle(report.balance >= 0 ? .incomeColor : .expenseColor)
                }
            }

            if let topCat = report.topExpenseCategory {
                Divider()
                HStack {
                    Image(systemName: persistence.categoryIcon(for: topCat, type: .expense))
                    Text("最大支出: \(topCat)")
                        .font(.caption)
                    Spacer()
                    Text(report.topExpenseAmount.moneyString(currency: persistence.baseCurrency))
                        .font(.caption.bold())
                }
            }

            Text("\(report.transactionCount) 筆交易")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var savingsRateCard: some View {
        VStack(spacing: 8) {
            Text("儲蓄率")
                .font(.headline)
            Text(String(format: "%.1f%%", report.savingsRate))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(report.savingsRate >= 20 ? .incomeColor : (report.savingsRate >= 0 ? .orange : .expenseColor))
            if report.savingsRate >= 20 {
                Text("儲蓄表現優秀！")
                    .font(.caption)
                    .foregroundStyle(.incomeColor)
            } else if report.savingsRate >= 0 {
                Text("繼續努力，目標 20%")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("本月入不敷出")
                    .font(.caption)
                    .foregroundStyle(.expenseColor)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var trendChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近 6 個月收支趨勢")
                .font(.headline)

            Chart(recentReports.reversed()) { rpt in
                BarMark(
                    x: .value("月份", "\(rpt.month)月"),
                    stacking: .center
                )
                .foregroundStyle(by: .value("類型", "收入"))
                .opacity(0)

                BarMark(
                    x: .value("月份", "\(rpt.month)月"),
                    y: .value("金額", rpt.totalExpense)
                )
                .foregroundStyle(by: .value("類型", "支出"))
                .position(by: .value("類型", "支出"))
            }
            .chartLegend(.hidden)
            .frame(height: 200)
        }
        .cardStyle()
    }

    private var recentMonthsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近 6 個月對比")
                .font(.headline)

            ForEach(recentReports) { rpt in
                HStack {
                    Text("\(rpt.monthName)")
                        .font(.subheadline)
                    Spacer()
                    Text(rpt.balance.moneyString(currency: persistence.baseCurrency))
                        .font(.subheadline.bold())
                        .foregroundStyle(rpt.balance >= 0 ? .incomeColor : .expenseColor)
                    Text(String(format: "%.0f%%", rpt.savingsRate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .cardStyle()
    }
}
