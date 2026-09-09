import Foundation
import CloudKit

// MARK: - iCloud 同步服務（CloudKit 私有數據庫）
/// 將完整備份 JSON 上傳到 iCloud 私有數據庫，可在新設備還原。
final class CloudSyncService {
    static let shared = CloudSyncService()
    private init() {}

    /// iCloud 同步的總開關。
    ///
    /// 免費 Apple ID（Personal Team）無法簽署 iCloud capability，entitlements 裡包含 iCloud 會讓
    /// Xcode 建不出 provisioning profile，整個專案 build 不過。因此預設停用。
    ///
    /// 取得付費開發者帳號後恢復步驟：
    /// 1. FinanceApp.entitlements 加回 icloud-services 與 icloud-container-identifiers
    /// 2. 把這裡改成 true
    static let isEnabled = false

    private let recordType = "FinanceBackup"
    private let recordId = CKRecord.ID(recordName: "full_backup")

    private var container: CKContainer {
        CKContainer(identifier: "iCloud.com.lucascheong.financeapp")
    }

    private var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    /// iCloud 帳戶是否可用
    func checkAccountStatus() async -> Bool {
        guard Self.isEnabled else { return false }
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            print("iCloud 帳戶狀態檢查失敗: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 上傳備份

    /// 將現有數據上傳到 iCloud（返回上傳字節數）
    func uploadBackup() async throws -> Int {
        guard Self.isEnabled else { throw CloudSyncError.capabilityUnavailable }

        let data = try PersistenceService.shared.createBackupData()

        // CloudKit 用 CKAsset 存大數據：先寫到臨時檔案
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("icloud_backup_\(Date().timeIntervalSince1970).json")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 嘗試讀取現有記錄以保留元數據；沒有則新建
        let record: CKRecord
        if let existing = try? await privateDatabase.record(for: recordId) {
            record = existing
        } else {
            record = CKRecord(recordType: recordType, recordID: recordId)
        }
        record["data"] = CKAsset(fileURL: tempURL)
        record["updatedAt"] = Date() as CKRecordValue

        _ = try await privateDatabase.save(record)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "icloudLastSyncTime")
        return data.count
    }

    // MARK: - 下載還原

    /// 從 iCloud 下載備份並還原（覆蓋本地數據），返回備份日期
    @discardableResult
    func restoreBackup() async throws -> Date {
        guard Self.isEnabled else { throw CloudSyncError.capabilityUnavailable }

        let record = try await privateDatabase.record(for: recordId)

        guard let asset = record["data"] as? CKAsset, let fileURL = asset.fileURL else {
            throw CloudSyncError.noBackupFound
        }

        let count = try PersistenceService.shared.importData(from: fileURL)
        guard count >= 0 else { throw CloudSyncError.restoreFailed }

        let backupDate = (record["updatedAt"] as? Date) ?? Date()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "icloudLastSyncTime")
        return backupDate
    }

    /// 雲端是否有備份
    func hasCloudBackup() async -> Bool {
        guard Self.isEnabled else { return false }
        return (try? await privateDatabase.record(for: recordId)) != nil
    }

    /// 上次同步時間
    var lastSyncTime: Date? {
        let ts = UserDefaults.standard.double(forKey: "icloudLastSyncTime")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
}

enum CloudSyncError: LocalizedError {
    case noBackupFound
    case restoreFailed
    case capabilityUnavailable

    var errorDescription: String? {
        switch self {
        case .noBackupFound: return "iCloud 上未找到備份數據"
        case .restoreFailed: return "備份還原失敗"
        case .capabilityUnavailable:
            return "iCloud 同步需要付費的 Apple Developer 帳號。免費 Apple ID 無法簽署 iCloud capability，此功能已停用。請改用「導出備份 (JSON)」手動保存數據。"
        }
    }
}
