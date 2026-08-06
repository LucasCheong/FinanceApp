import SwiftUI

// MARK: - 主視圖 - 底部標籤欄
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

    var body: some View {
        Group {
            if colorScheme == "dark" {
                TabView(selection: $selectedTab) {
                    tabContent
                }
                .preferredColorScheme(.dark)
                .tint(.financePrimary)
            } else if colorScheme == "light" {
                TabView(selection: $selectedTab) {
                    tabContent
                }
                .preferredColorScheme(.light)
                .tint(.financePrimary)
            } else {
                TabView(selection: $selectedTab) {
                    tabContent
                }
                .tint(.financePrimary)
            }
        }
        .onAppear {
            PersistenceService.shared.processDueRecurringTransactions()
            // 啟動時拉取即時匯率（快取期可在設定頁調整，失敗時自動使用備用匯率）
            Task { await ExchangeRateProvider.fetchLiveRates() }
            // 刷新桌面小組件數據
            PersistenceService.shared.updateWidgetSnapshot()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        // 記帳
        AccountingView()
            .tabItem {
                Label("記帳", systemImage: "book.fill")
            }
            .tag(0)
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

        // 發票導入
        InvoiceImportView()
            .tabItem {
                Label("發票", systemImage: "doc.viewfinder.fill")
            }
            .tag(1)

        // 市場看板
        MarketDashboardView()
            .tabItem {
                Label("市場", systemImage: "chart.bar.fill")
            }
            .tag(2)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAlertCenter = true } label: {
                        Image(systemName: "bell.badge")
                    }
                }
            }
            .sheet(isPresented: $showingAlertCenter) { AlertCenterView() }

        // 投資組合
        PortfolioView()
            .tabItem {
                Label("組合", systemImage: "briefcase.fill")
            }
            .tag(3)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAssetAllocation = true } label: {
                        Image(systemName: "chart.pie.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAssetAllocation) { AssetAllocationView() }

        // 收息
        DividendCalculatorView()
            .tabItem {
                Label("收息", systemImage: "percent")
            }
            .tag(4)

        // 設定（獨立分頁，SettingsView 內含導航容器）
        SettingsView()
            .tabItem {
                Label("設定", systemImage: "gearshape.fill")
            }
            .tag(5)
    }
}

// MARK: - 預覽
#Preview {
    ContentView()
        .environmentObject(PersistenceService.shared)
}
