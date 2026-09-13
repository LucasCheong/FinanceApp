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
    @State private var appLockError: String?
    @State private var showingAppLockError = false

    // AI 顧問
    @StateObject private var llm = LLMService.shared
    @State private var isTestingLLM = false
    @State private var llmTestMessage = ""
    @State private var showingLLMTestResult = false

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
                        Text("顧問").tag(5)
                        Text("設定").tag(6)
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

                // MARK: - AI 顧問
                Section {
                    Menu {
                        ForEach(LLMService.presets) { preset in
                            Button(preset.name) {
                                llm.baseURL = preset.baseURL
                                llm.model = preset.model
                            }
                        }
                    } label: {
                        HStack {
                            Label("快速填入服務商", systemImage: "wand.and.stars")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Base URL")
                            .frame(width: 84, alignment: .leading)
                        TextField(LLMService.defaultBaseURL, text: $llm.baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }

                    HStack {
                        Text("模型")
                            .frame(width: 84, alignment: .leading)
                        TextField(LLMService.defaultModel, text: $llm.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }

                    HStack {
                        Text("API Key")
                            .frame(width: 84, alignment: .leading)
                        SecureField("sk-…", text: $llm.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .font(.caption)
                    }

                    Button {
                        testLLMConnection()
                    } label: {
                        HStack {
                            Label("測試連線", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if isTestingLLM {
                                ProgressView()
                            } else if llm.isConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(isTestingLLM || !llm.isConfigured)
                } header: {
                    Text("AI 顧問")
                } footer: {
                    Text("顧問分頁的評分、體檢與再平衡建議全部由本機引擎計算，不需 API Key 即可使用。填入 Key 後，額外提供用顧問語氣寫成的文字說明與追問對話；此時你的收支、持倉與問卷明細會隨請求送至上方設定的服務商。兼容 OpenAI、DeepSeek、Kimi、智譜、Ollama 等任何 OpenAI 格式接口。API Key 存於本機 Keychain。")
                }

                // MARK: - 安全與通知
                Section("安全與通知") {
                    Toggle(isOn: appLockBinding) {
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
                    .disabled(isSyncing || !CloudSyncService.isEnabled)

                    Button {
                        restoreFromICloud()
                    } label: {
                        Label("從 iCloud 還原", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(isSyncing || !CloudSyncService.isEnabled)

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
                    if CloudSyncService.isEnabled {
                        Text("需登入 iCloud 帳戶。還原會覆蓋本機現有數據，請謹慎操作。")
                    } else {
                        Text("此功能需要付費的 Apple Developer 帳號。免費 Apple ID（Personal Team）無法簽署 iCloud capability，否則專案會無法編譯，因此已停用。請改用上方的「導出備份 (JSON)」保存數據。")
                    }
                }

                // MARK: - 資訊
                Section("關於") {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text("1.4.0")
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
            .alert("AI 連線測試", isPresented: $showingLLMTestResult) {
                Button("確定") { }
            } message: {
                Text(llmTestMessage)
            }
            .alert("無法啟用 App 鎖", isPresented: $showingAppLockError) {
                Button("確定") { }
            } message: {
                Text(appLockError ?? "")
            }
        }
    }

    // MARK: - Bindings

    /// App 鎖開關 Binding：啟用前先確認裝置真的驗得了，否則開了就再也進不了 App
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLockEnabled },
            set: { newValue in
                guard newValue else {
                    appLockEnabled = false
                    return
                }
                let context = LAContext()
                var error: NSError?
                // 用 deviceOwnerAuthentication 而非…WithBiometrics，核驗管道含裝置密碼
                if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                    appLockEnabled = true
                } else {
                    appLockEnabled = false
                    appLockError = "此裝置尚未設定面容、指紋或螢幕密碼，請先到「設定」設定完再回來開啟。\n\n\(error?.localizedDescription ?? "")"
                    showingAppLockError = true
                }
            }
        )
    }

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

    // MARK: - AI 連線測試
    private func testLLMConnection() {
        isTestingLLM = true
        Task {
            let result = await llm.testConnection()
            await MainActor.run {
                switch result {
                case .success(let reply):
                    llmTestMessage = "連線成功。模型回覆：\(reply)"
                case .failure(let error):
                    llmTestMessage = error.localizedDescription
                }
                isTestingLLM = false
                showingLLMTestResult = true
            }
        }
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
                syncMessage = "備份失敗：\(error.localizedDescription)"
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
/// 鎖屏以 overlay 疊在 ContentView 之上，而不是取代它，這樣回前台重新上鎖時不會把各分頁的狀態洗掉。
struct AppLockView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    /// 本次上鎖已自動彈過核驗，避免取消後回到前台又立即彈一次而陷入循環
    @State private var didPromptThisLock = false
    @State private var failureMessage: String?

    var body: some View {
        ContentView()
            .overlay {
                if appLockEnabled && !isUnlocked {
                    lockScreen
                }
            }
            .onAppear {
                autoPrompt()
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .background:
                    // 進背景就重新上鎖（面容核驗彈窗只會讓 phase 變 inactive，不會誤觸）
                    if appLockEnabled {
                        isUnlocked = false
                        didPromptThisLock = false
                        failureMessage = nil
                    }
                case .active:
                    autoPrompt()
                default:
                    break
                }
            }
    }

    // MARK: - 鎖屏
    private var lockScreen: some View {
        ZStack {
            // 不透光背景，確保底下的金額不會被看見
            Color(.systemBackground)

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.financePrimary)
                Text("財務管家已鎖定")
                    .font(.headline)

                if let failureMessage {
                    Text(failureMessage)
                        .font(.caption)
                        .foregroundStyle(.loss)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Text("核驗身分以繼續使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                .disabled(isAuthenticating)
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    // MARK: - 核驗

    /// 進入或回到前台時自動彈一次；被取消後不再自動重試，由使用者按「解鎖」
    private func autoPrompt() {
        guard appLockEnabled, !isUnlocked, !isAuthenticating, !didPromptThisLock else { return }
        didPromptThisLock = true
        authenticate()
    }

    private func authenticate() {
        guard !isAuthenticating else { return }

        let context = LAContext()
        context.localizedFallbackTitle = "使用裝置密碼"
        var error: NSError?

        // deviceOwnerAuthentication 含密碼備援：面容識別失效時還有路可走，不會被鎖在外面
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 裝置連密碼都沒設，繼續鎖著就是永久進不了，此時直接放行並關掉開關
            appLockEnabled = false
            isUnlocked = true
            return
        }

        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解鎖財務管家") { success, authError in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    isUnlocked = true
                    failureMessage = nil
                } else {
                    failureMessage = Self.describe(authError)
                }
            }
        }
    }

    /// 把 LAError 譯成使用者看得懂的話
    private static func describe(_ error: Error?) -> String {
        guard let code = (error as? LAError)?.code else {
            return "核驗未完成，請再試一次"
        }
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return "已取消核驗，請按「解鎖」重試"
        case .userFallback:
            return "請改用裝置密碼核驗"
        case .biometryLockout:
            return "面容識別已被鎖定，請按「解鎖」並輸入裝置密碼"
        case .biometryNotEnrolled, .biometryNotAvailable:
            return "此裝置無法使用面容識別，請改用裝置密碼"
        default:
            return "核驗失敗，請再試一次"
        }
    }
}
