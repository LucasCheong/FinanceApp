import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers

// MARK: - 設定視圖 - App鎖 + 深色模式 + 數據匯出
struct SettingsView: View {
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("colorScheme") private var colorScheme = "system"

    @State private var showingExportSuccess = false
    @State private var exportedURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 安全設定
                Section("安全") {
                    Toggle(isOn: $appLockEnabled) {
                        Label("Face ID / Touch ID 鎖", systemImage: "faceid")
                    }
                    if appLockEnabled {
                        Text("啟動 App 時需要驗證身份")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - 外觀設定
                Section("外觀") {
                    Picker("主題", selection: $colorScheme) {
                        Text("跟隨系統").tag("system")
                        Text("淺色模式").tag("light")
                        Text("深色模式").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - 數據管理
                Section("數據管理") {
                    Button {
                        exportData()
                    } label: {
                        Label("匯出數據 (CSV)", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        exportJSON()
                    } label: {
                        Label("匯出數據 (JSON)", systemImage: "doc.text")
                    }
                }

                // MARK: - 資訊
                Section("關於") {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("基準幣種", systemImage: "dollarsign.circle")
                        Spacer()
                        Text(persistence.baseCurrency.displayName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("交易記錄", systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text("\(persistence.transactions.count) 筆")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("持倉數量", systemImage: "briefcase")
                        Spacer()
                        Text("\(persistence.holdings.count) 個")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("匯出成功", isPresented: $showingExportSuccess) {
                Button("確定") { }
            } message: {
                Text("數據已匯出到檔案，可透過分享功能傳送。")
            }
        }
    }

    // MARK: - CSV 匯出
    private func exportData() {
        var csv = "日期,類型,類別,金額,幣種,備註,來源\n"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for tx in persistence.transactions {
            let dateStr = formatter.string(from: tx.date)
            let note = tx.note.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(dateStr),\(tx.type.rawValue),\(tx.category),\(tx.amount),\(tx.currency.code),\"\(note)\",\(tx.source.rawValue)\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FinanceApp_Export_\(Date().timeIntervalSince1970).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportedURL = url
            showingExportSuccess = true
        } catch {
            print("CSV 匯出失敗: \(error)")
        }
    }

    // MARK: - JSON 匯出
    private func exportJSON() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            let data: [String: Any] = [
                "transactions": persistence.transactions,
                "holdings": persistence.holdings,
                "budgets": persistence.budgets,
                "customCategories": persistence.customCategories,
                "dividendPositions": persistence.dividendPositions,
                "recurringTransactions": persistence.recurringTransactions,
                "priceAlerts": persistence.priceAlerts,
                "dcaPositions": persistence.dcaPositions
            ]

            let combined = try JSONSerialization.data(withJSONObject: [
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "baseCurrency": persistence.baseCurrency.code,
                "data": data
            ], options: .prettyPrinted)

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FinanceApp_Backup_\(Date().timeIntervalSince1970).json")
            try combined.write(to: url, options: .atomic)
            exportedURL = url
            showingExportSuccess = true
        } catch {
            print("JSON 匯出失敗: \(error)")
        }
    }
}

// MARK: - App 鎖畫面
struct AppLockView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var isUnlocked = false

    var body: some View {
        Group {
            if !appLockEnabled || isUnlocked {
                ContentView()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.financePrimary)
                    Text("財務管家已鎖定")
                        .font(.headline)
                    Text("點擊解鎖以繼續使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        authenticate()
                    } label: {
                        Label("解鎖", systemImage: "faceid")
                            .font(.headline)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.financePrimary)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .onAppear {
            if appLockEnabled {
                authenticate()
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "解鎖財務管家") { success, _ in
                DispatchQueue.main.async {
                    isUnlocked = success
                }
            }
        } else {
            // 沒有生物識別，直接解鎖
            isUnlocked = true
        }
    }
}
