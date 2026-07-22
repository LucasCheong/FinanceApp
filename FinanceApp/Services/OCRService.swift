import Foundation
@preconcurrency import Vision
import UIKit

/// OCR 服務 - 使用 Apple Vision 框架識別發票文字
final class OCRService {
    static let shared = OCRService()

    private init() {}

    // MARK: - 識別單張發票圖片
    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        return try await Self.performOCR(cgImage: cgImage)
    }

    // MARK: - 執行 OCR（nonisolated 避免 Sendable 警告）
    private nonisolated static func performOCR(cgImage: CGImage) async throws -> String {
        var resultText = ""
        var resultError: Error?

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                resultError = error
                return
            }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            resultText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        if let resultError = resultError {
            throw resultError
        }

        return resultText
    }

    // MARK: - 批量識別發票
    func recognizeTextBatch(in images: [UIImage]) async -> [(UIImage, String)] {
        var results: [(UIImage, String)] = []

        for image in images {
            do {
                let text = try await recognizeText(in: image)
                results.append((image, text))
            } catch {
                print("OCR 識別失敗: \(error.localizedDescription)")
                results.append((image, ""))
            }
        }

        return results
    }

    // MARK: - 從 OCR 文字中解析發票信息
    func parseInvoice(from text: String) -> ParsedInvoice {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        var merchant = ""
        var amount: Double = 0
        var date: Date?
        var items: [String] = []

        // 解析金額 - 尋找包含 $ 或數字的行
        let amountPattern = #"(?:HK\$|US\$|\$|NT\$|￥|¥)?\s*([0-9]+(?:[.,][0-9]{2}))"#
        let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: [])

        // 解析日期 - 多種格式
        let datePatterns = [
            #"\d{4}[/-]\d{1,2}[/-]\d{1,2}"#,
            #"\d{1,2}[/-]\d{1,2}[/-]\d{4}"#,
            #"\d{4}年\d{1,2}月\d{1,2}日"#
        ]

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // 嘗試解析金額
            if amountRegex != nil {
                let range = NSRange(location: 0, length: trimmedLine.utf16.count)
                if let match = amountRegex?.firstMatch(in: trimmedLine, options: [], range: range) {
                    let matchString = (trimmedLine as NSString).substring(with: match.range)
                    let numericString = matchString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
                    if let parsedAmount = Double(numericString), parsedAmount > amount {
                        amount = parsedAmount
                    }
                }
            }

            // 嘗試解析日期
            if date == nil {
                for pattern in datePatterns {
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let range = NSRange(location: 0, length: trimmedLine.utf16.count)
                        if let match = regex.firstMatch(in: trimmedLine, options: [], range: range) {
                            let dateString = (trimmedLine as NSString).substring(with: match.range)
                            date = parseDate(dateString)
                            break
                        }
                    }
                }
            }

            // 嘗試識別商家名稱（通常是前幾行非數字文字）
            if merchant.isEmpty {
                let hasNumber = trimmedLine.range(of: #"\d{3,}"#, options: .regularExpression) != nil
                let hasSpecialChars = trimmedLine.range(of: #"[\$#@]"#) != nil
                if !hasNumber && !hasSpecialChars && trimmedLine.count > 2 && trimmedLine.count < 30 {
                    merchant = trimmedLine
                }
            }

            // 收集可能的商品項目
            if trimmedLine.count > 3 && trimmedLine.count < 50 {
                let hasAmount = trimmedLine.range(of: #"\d+\.\d{2}"#, options: .regularExpression) != nil
                if hasAmount && !trimmedLine.contains("總計") && !trimmedLine.contains("合計") && !trimmedLine.contains("Total") {
                    items.append(trimmedLine)
                }
            }
        }

        // 如果沒有找到日期，使用今天
        if date == nil {
            date = Date()
        }

        return ParsedInvoice(
            merchant: merchant.isEmpty ? "未知商家" : merchant,
            amount: amount,
            date: date ?? Date(),
            items: items,
            rawText: text
        )
    }

    // MARK: - 日期解析
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()

        // 嘗試多種格式
        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "dd-MM-yyyy",
            "dd/MM/yyyy",
            "yyyy年MM月dd日",
            "yyyy年M月d日"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }
}

// MARK: - 解析後的發票數據
struct ParsedInvoice {
    var merchant: String
    var amount: Double
    var date: Date
    var items: [String]
    var rawText: String
}

// MARK: - OCR 錯誤
enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "無法處理圖片，請確保圖片格式正確"
        }
    }
}
