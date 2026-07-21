import SwiftUI

// MARK: - 主視圖 - 底部標籤欄
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // 記帳
            AccountingView()
                .tabItem {
                    Label("記帳", systemImage: "book.fill")
                }
                .tag(0)

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

            // 投資組合
            PortfolioView()
                .tabItem {
                    Label("組合", systemImage: "briefcase.fill")
                }
                .tag(3)

            // 收息計算器
            DividendCalculatorView()
                .tabItem {
                    Label("收息", systemImage: "percent")
                }
                .tag(4)
        }
        .tint(.financePrimary)
    }
}

// MARK: - 預覽
#Preview {
    ContentView()
        .environmentObject(PersistenceService.shared)
}
