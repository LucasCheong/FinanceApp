import WidgetKit
import SwiftUI

// MARK: - 財務管家桌面小組件
/// 顯示今日支出、本月支出與持倉概覽，數據來自 App Group UserDefaults

/// App Group 標識（與主 App 的 PersistenceService 保持一致）
private let kAppGroupId = "group.com.financeapp.FinanceApp"

struct FinanceWidgetEntry: TimelineEntry {
    let date: Date
    let todayExpense: Double
    let monthExpense: Double
    let transactionCount: Int
    let holdingsCount: Int
    let currencyCode: String
}

struct FinanceWidgetProvider: TimelineProvider {
    private func makeEntry() -> FinanceWidgetEntry {
        let defaults = UserDefaults(suiteName: kAppGroupId)
        return FinanceWidgetEntry(
            date: Date(),
            todayExpense: defaults?.double(forKey: "widgetTodayExpense") ?? 0,
            monthExpense: defaults?.double(forKey: "widgetMonthExpense") ?? 0,
            transactionCount: defaults?.integer(forKey: "widgetTransactionCount") ?? 0,
            holdingsCount: defaults?.integer(forKey: "widgetHoldingsCount") ?? 0,
            currencyCode: defaults?.string(forKey: "widgetBaseCurrencyCode") ?? "HKD"
        )
    }

    func placeholder(in context: Context) -> FinanceWidgetEntry {
        FinanceWidgetEntry(date: Date(), todayExpense: 128.5, monthExpense: 3680,
                           transactionCount: 42, holdingsCount: 3, currencyCode: "HKD")
    }

    func getSnapshot(in context: Context, completion: @escaping (FinanceWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceWidgetEntry>) -> Void) {
        let entry = makeEntry()
        // 每 30 分鐘刷新一次
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 小組件視圖
struct FinanceWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FinanceWidgetProvider.Entry

    private var currency: Currency {
        Currency(rawValue: entry.currencyCode) ?? .hkd
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumView
            } else {
                smallView
            }
        }
        .padding()
        .containerBackgroundCompat()
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("財務管家", systemImage: "chart.pie.fill")
                .font(.caption.bold())
                .foregroundStyle(.blue)

            Spacer(minLength: 0)

            Text("今日支出")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.todayExpense.moneyString(currency: currency))
                .font(.title3.bold())
                .foregroundStyle(.orange)

            Text("本月累計")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.monthExpense.moneyString(currency: currency))
                .font(.headline.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("財務管家", systemImage: "chart.pie.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Spacer(minLength: 0)
                Text("今日支出")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.todayExpense.moneyString(currency: currency))
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("本月累計")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.monthExpense.moneyString(currency: currency))
                    .font(.title3.bold())
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Label("\(entry.transactionCount) 筆記帳", systemImage: "list.bullet")
                    Label("\(entry.holdingsCount) 個持倉", systemImage: "briefcase")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 容器背景相容處理（iOS 17 containerBackground / iOS 16 回退）
extension View {
    @ViewBuilder
    func containerBackgroundCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(.background, for: .widget)
        } else {
            self.background(Color(.systemBackground))
        }
    }
}

// MARK: - Widget 配置
struct FinanceWidget: Widget {
    let kind: String = "FinanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceWidgetProvider()) { entry in
            FinanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("財務管家")
        .description("查看今日支出、本月累計與持倉概覽")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FinanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        FinanceWidget()
    }
}
