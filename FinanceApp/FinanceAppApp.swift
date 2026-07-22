import SwiftUI

@main
struct FinanceAppApp: App {
    @StateObject private var persistence = PersistenceService.shared

    init() {
        // 請求通知權限
        NotificationManager.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(persistence)
        }
    }
}
