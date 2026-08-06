import AppIntents
import Foundation

// MARK: - Siri / 捷徑 App Intents（iOS 16+）

/// 快速記帳指令：可透過 Siri 語音或「捷徑」App 调用
/// 例如：「嘿 Siri，用財務管家記一筆支出」
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "快速記帳"
    static var description = IntentDescription("用語音快速記一筆支出或收入")

    @Parameter(title: "金額", description: "金額數字")
    var amount: Double

    @Parameter(title: "類別", description: "支出類別，例如：餐飲、交通、購物", default: "餐飲")
    var category: String

    @Parameter(title: "備註", description: "可選備註")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("記一筆 \(\.$amount) 的 \(\.$category)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw NSError(domain: "FinanceApp.Intent", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "金額必須大於 0"])
        }

        let persistence = PersistenceService.shared
        let transaction = Transaction(
            date: Date(),
            amount: amount,
            type: .expense,
            category: category,
            note: note ?? "Siri 快捷記帳",
            source: .manual,
            currency: persistence.baseCurrency
        )
        persistence.addTransaction(transaction)
        persistence.updateWidgetSnapshot()

        let formatted = amount.moneyString(currency: persistence.baseCurrency)
        return .result(dialog: "已記錄：\(category) \(formatted)")
    }
}

/// 快速記收入指令
struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "快速記收入"
    static var description = IntentDescription("用語音快速記一筆收入")

    @Parameter(title: "金額")
    var amount: Double

    @Parameter(title: "類別", default: "薪資")
    var category: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw NSError(domain: "FinanceApp.Intent", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "金額必須大於 0"])
        }

        let persistence = PersistenceService.shared
        let transaction = Transaction(
            date: Date(),
            amount: amount,
            type: .income,
            category: category,
            note: "Siri 快捷記帳",
            source: .manual,
            currency: persistence.baseCurrency
        )
        persistence.addTransaction(transaction)
        persistence.updateWidgetSnapshot()

        let formatted = amount.moneyString(currency: persistence.baseCurrency)
        return .result(dialog: "已記錄收入：\(category) \(formatted)")
    }
}

// MARK: - Siri 短語註冊（安裝後即可用短語觸發）
struct FinanceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: ["用 \(.applicationName) 記帳", "\(.applicationName) 記一筆支出"]
        )
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: ["用 \(.applicationName) 記收入"]
        )
    }
}
