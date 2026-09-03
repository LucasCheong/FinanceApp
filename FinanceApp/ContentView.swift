import SwiftUI

// MARK: - 主視圖 - 自定義底部標籤欄（支持 7 個標籤全部展示）
/// iPhone 原生 TabView 超過 5 個標籤會摺疊為「更多」，故使用自定義標籤欄
struct ContentView: View {
    // 啟動分頁可在設定頁調整（預設記帳）
    @State private var selectedTab: Int

    init() {
        _selectedTab = State(initialValue: UserDefaults.standard.integer(forKey: "defaultTab"))
    }

    @State private var showingBudget = false
    @State private var showingAlertCenter = false
    @State private var showingAssetAllocation = false
    @State private var showingExchangeRate = false

    @AppStorage("colorScheme") private var colorScheme = "system"

    /// 標籤定義：圖標與標題
    private let tabs: [(title: String, icon: String)] = [
        ("記帳", "book.fill"),
        ("發票", "doc.viewfinder.fill"),
        ("市場", "chart.bar.fill"),
        ("組合", "briefcase.fill"),
        ("收息", "percent"),
        ("顧問", "person.crop.circle.badge.checkmark"),
        ("設定", "gearshape.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            customTabBar
        }
        .preferredColorScheme(colorScheme == "dark" ? .dark : colorScheme == "light" ? .light : nil)
        .tint(.financePrimary)
        .onAppear {
            PersistenceService.shared.processDueRecurringTransactions()
            // 啟動時拉取即時匯率（快取期可在設定頁調整，失敗時自動使用備用匯率）
            Task { await ExchangeRateProvider.fetchLiveRates() }
            // 刷新桌面小組件數據
            PersistenceService.shared.updateWidgetSnapshot()
        }
    }

    // MARK: - 分頁內容
    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case 0:
            // 記帳
            AccountingView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showingBudget = true } label: {
                                Label("預算管理", systemImage: "creditcard.fill")
                            }
                            Button { showingExchangeRate = true } label: {
                                Label("匯率走勢", systemImage: "chart.line.uptrend.xyaxis")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingBudget) { BudgetView() }
                .sheet(isPresented: $showingExchangeRate) { ExchangeRateView() }

        case 1:
            // 發票導入
            InvoiceImportView()

        case 2:
            // 市場看板
            MarketDashboardView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAlertCenter = true } label: {
                            Image(systemName: "bell.badge")
                        }
                    }
                }
                .sheet(isPresented: $showingAlertCenter) { AlertCenterView() }

        case 3:
            // 投資組合
            PortfolioView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAssetAllocation = true } label: {
                            Image(systemName: "chart.pie.fill")
                        }
                    }
                }
                .sheet(isPresented: $showingAssetAllocation) { AssetAllocationView() }

        case 4:
            // 收息
            DividendCalculatorView()

        case 5:
            // 財務顧問
            AdvisorView()

        default:
            // 設定（SettingsView 内含導航容器）
            SettingsView()
        }
    }

    // MARK: - 自定義標籤欄
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    if selectedTab != index {
                        Haptics.impact()
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 19))
                        Text(tabs[index].title)
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(selectedTab == index ? Color.financePrimary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - 預覽
#Preview {
    ContentView()
        .environmentObject(PersistenceService.shared)
}
