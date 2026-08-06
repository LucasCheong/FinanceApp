import SwiftUI
import UIKit
import LocalAuthentication
import UniformTypeIdentifiers

// MARK: - 設定視圖 - 全方位設定中心
struct SettingsView: View {
    @StateObject private var persistence = PersistenceService.shared

    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("colorScheme") private var colorScheme = "system"
    @AppStorage("priceAlertNotifications") private var priceAlertNotifications = true
    @AppStorage("rateUpdateIntervalHours") private var updateIntervalHours = 24.0
    @AppStorage("defaultTab") private var defaultTab = 0
    @AppStorage("decimalPlaces") private var decimalPlaces = 2
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("weeklyReminderEnabled") private var weeklyReminderEnabled = false
    @AppStorage("weeklyReminderWeekday") private var weeklyReminderWeekday = 1
    @AppStorage("weeklyReminderHour") private var weeklyReminderHour = 20
    @AppStorage("appIconName") private var appIconName = ""

    @State private var showingExportSuccess = false
    @State private var exportedURL: URL?
    @State private var showingChangeBaseAlert = false
    @State private var pendingBaseCurrency: Currency = .hkd
    @State private var showingImportPicker = false
    @State private var importMessage = ""
    @State private var showingImportResult = false
    @State private var isSyncing = false
    @State private var syncMessage = ""
    @State private var showingSyncResult = false

    private let weekdays = [(1, "星期日"), (2, "星期一"), (3, "星期二"), (4, "星期三"), (5, "星期四"), (6, "星期五"), (7, "星期六")]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 一般設定
                Section("一般") {
                    Picker(selection: pickerBinding) {
                        ForEach(Currency.allCases, id: \.self) { cur in
                            Text(cur.displayName).tag(cur)
                        }
                    } label: {
                        Label("介面幣種", systemImage: "dollarsign.circle")
                    }

                    Picker(selection: $defaultTab) {
                        Text("記帳").tag(0)
                        Text("發票").tag(1)
                        Text("市場").tag(2)
                        Text("組合").tag(3)
                        Text("收息").tag(4)
                    } label: {
                        Label("啟動分頁", systemImage: "house")
                    }

                    Picker(selection: $decimalPlaces) {
                        Text("2 位").tag(2)
                        Text("3 位").tag(3)
                        Text("4 位").tag(4)
                    } label: {
                        Label("金額小數位", systemImage: "number")
                    }

                    Toggle(isOn: $hapticsEnabled) {
                        Label("觸覺反饋", systemImage: "iphone.radiowaves.left.and.right")
                    }

                    Picker(selection: $updateIntervalHours) {
                        Text("每次啟動").tag(0.0)
                        Text("每 6 小時").tag(6.0)
                        Text("每 12 小時").tag(12.0)
                        Text("每 24 小時").tag(24.0)
                    } label: {
                        Label("匯率更新頻率", systemImage: "clock.arrow.circlepath")
                    }

                    if let updateTime = ExchangeRateProvider.lastUpdateTime {
                        HStack {
                            Label("上次更新", systemImage: "checkmark.circle")
                            Spacer()
                            Text(updateTime.dateTimeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - 外觀設定
                Section("外觀") {
                    Picker("主題", selection: $colorScheme) {
                        Text("跟隨系統").tag("system")
                        Text("淺色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Picker(selection: iconBinding) {
                        Text("朝陽橙").tag("")
                        Text("經典藍綠").tag("AppIcon")
                        Text("深邃藍").tag("AppIconDark")
                    } label: {
                        Label("App 圖標", systemImage: "app.badge")
                    }
                }

                // MARK: - 安全與通知
                Section("安全與通知") {
                    Toggle(isOn: $appLockEnabled) {
                        Label("Face ID / Touch ID 鎖", systemImage: "faceid")
                    }
                    Toggle(isOn: $priceAlertNotifications) {
                        Label("股價警報通知", systemImage: "bell.badge")
                    }
                    Toggle(isOn: weeklyReminderBinding) {
                        Label("每週記帳提醒", systemImage: "calendar.badge.clock")
                    }
                    if weeklyReminderEnabled {
                        Picker(selection: $weeklyReminderWeekday) {
                            ForEach(weekdays, id: \.0) { day in
                                Text(day.1).tag(day.0)
                            }
                        } label: {
                            Text("提醒日")
                        }
                        .onChange(of: weeklyReminderWeekday) { _ in rescheduleWeeklyReminder() }

                        Picker(selection: $weeklyReminderHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text("\(h):00").tag(h)
                            }
                        } label: {
                            Text("提醒時間")
                        }
                        .onChange(of: weeklyReminderHour) { _ in rescheduleWeeklyReminder() }
                    }
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
                        Label("匯出備份 (JSON)", systemImage: "doc.text")
                    }

                    Button {
                        showingImportPicker = true
                    } label: {
                        Label("導入備份 (JSON)", systemImage: "square.and.arrow.down")
                    }
                }

                // MARK: - iCloud 同步
                Section {
                    Button {
                        syncToICloud()
                    } label: {
                        if isSyncing {
                            HStack {
                                ProgressView()
                                Text("同步中…")
                            }
                        } else {
                            Label("備份到 iCloud", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    .disabled(isSyncing)

                    Button {
                        restoreFromICloud()
                    } label: {
                        Label("從 iCloud 還原", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(isSyncing)

                    if let syncTime = CloudSyncService.shared.lastSyncTime {
                        HStack {
                            Text("上次同步")
                            Spacer()
                            Text(syncTime.dateTimeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("iCloud 同步")
                } footer: {
                    Text("需登入 iCloud 帳戶。還原會覆蓋本機現有數據，請謹慎操作。")
                }

                // MARK: - 資訊
                Section("關於") {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text("1.3.0")
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
            .alert("匯出成功", isPresented: $showingExportSuccess) {
                Button("確定") { }
            } message: {
                Text("數據已匯出到檔案，可透過分享功能傳送。")
            }
            .alert("更改介面幣種", isPresented: $showingChangeBaseAlert) {
                Button("取消", role: .cancel) { }
                Button("確認更改") {
                    persistence.setBaseCurrency(pendingBaseCurrency)
                }
            } message: {
                Text("將以 \(pendingBaseCurrency.displayName) 作為全 App 的結算與顯示幣種，歷史數據不會被修改。")
            }
            .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert("導入結果", isPresented: $showingImportResult) {
                Button("確定") { }
            } message: {
                Text(importMessage)
            }
            .alert("iCloud 同步", isPresented: $showingSyncResult) {
                Button("確定") { }
            } message: {
                Text(syncMessage)
            }
        }
    }

    // MARK: - Bindings

    /// 基準幣種選擇 Binding：選擇時先彈出確認對話框
    private var pickerBinding: Binding<Currency> {
        Binding(
            get: { persistence.baseCurrency },
            set: { newValue in
                if newValue != persistence.baseCurrency {
                    pendingBaseCurrency = newValue
                    showingChangeBaseAlert = true
                }
            }
        )
    }

    /// App 圖標選擇 Binding：即時切換圖標
    private var iconBinding: Binding<String> {
        Binding(
            get: { appIconName },
            set: { newValue in
                let target: String? = newValue.isEmpty ? nil : newValue
                UIApplication.shared.setAlternateIconName(target) { error in
                    if let error = error {
                        print("切換圖標失敗: \(error.localizedDescription)")
                    } else {
                        appIconName = newValue
                    }
                }
            }
        )
    }

    /// 每週提醒開關 Binding
    private var weeklyReminderBinding: Binding<Bool> {
        Binding(
            get: { weeklyReminderEnabled },
            set: { enabled in
                weeklyReminderEnabled = enabled
                if enabled {
                    NotificationManager.shared.scheduleWeeklyReminder(
                        weekday: weeklyReminderWeekday, hour: weeklyReminderHour)
                } else {
                    NotificationManager.shared.cancelWeeklyReminder()
                }
            }
        )
    }

    private func rescheduleWeeklyReminder() {
        guard weeklyReminderEnabled else { return }
        NotificationManager.shared.scheduleWeeklyReminder(
            weekday: weeklyReminderWeekday, hour: weeklyReminderHour)
    }

    // MARK: - 數據導入
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let count = try persistence.importData(from: url)
                importMessage = "導入成功！共還原 \(count) 筆交易記錄。"
            } catch {
                importMessage = "導入失敗：\(error.localizedDescription)"
            }
        case .failure(let error):
            importMessage = "選擇檔案失敗：\(error.localizedDescription)"
        }
        showingImportResult = true
    }

    // MARK: - iCloud 同步
    private func syncToICloud() {
        isSyncing = true
        Task {
            do {
                let bytes = try await CloudSyncService.shared.uploadBackup()
                syncMessage = "備份成功！已上傳 \(bytes / 1024) KB 數據到 iCloud。"
            } catch {
                syncMessage = "備份失敗：\(error.localizedDescription)\n\n請確認已登入 iCloud，並在 Xcode 中啟用 iCloud Capability。"
            }
            isSyncing = false
            showingSyncResult = true
        }
    }

    private func restoreFromICloud() {
        isSyncing = true
        Task {
            do {
                let backupDate = try await CloudSyncService.shared.restoreBackup()
                syncMessage = "還原成功！已恢復 \(backupDate.dateTimeString) 的備份。"
            } catch {
                syncMessage = "還原失敗：\(error.localizedDescription)"
            }
            isSyncing = false
            showingSyncResult = true
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
            let combined = try persistence.createBackupData()
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
