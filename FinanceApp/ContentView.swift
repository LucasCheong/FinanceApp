import SwiftUI

// MARK: - 主視圖 - 底部標籤欄
struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showingBudget = false
    @State private var showingAlertCenter = false
    @State private var showingAssetAllocation = false
    @State private var showingSettings = false
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

        // 收息 + 設定
        DividendCalculatorView()
            .tabItem {
                Label("收息", systemImage: "percent")
            }
            .tag(4)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

// MARK: - 預覽
#Preview {
    ContentView()
        .environmentObject(PersistenceService.shared)
}
