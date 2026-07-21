import SwiftUI
import PhotosUI
import UIKit

// MARK: - 發票批量導入視圖
struct InvoiceImportView: View {
    @StateObject private var persistence = PersistenceService.shared
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isProcessing = false
    @State private var processingProgress: Double = 0
    @State private var parsedInvoices: [ParsedInvoiceData] = []
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 選擇圖片區域
                    imageSelectionArea

                    // 已選圖片預覽
                    if !selectedImages.isEmpty {
                        imagePreviewGrid
                    }

                    // 處理按鈕
                    if !selectedImages.isEmpty && !isProcessing {
                        processButton
                    }

                    // 處理進度
                    if isProcessing {
                        processingProgressView
                    }

                    // 已導入的發票列表
                    if !persistence.invoices.isEmpty {
                        importedInvoicesSection
                    }
                }
                .padding()
            }
            .navigationTitle("發票導入")
            .sheet(isPresented: $showingResults) {
                InvoiceReviewView(parsedInvoices: $parsedInvoices)
            }
        }
    }

    // MARK: - 圖片選擇區域
    private var imageSelectionArea: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.financePrimary)

            Text("批量導入發票")
                .font(.title2.bold())

            Text("選擇多張發票照片，AI 將自動識別金額、日期和商家")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 20,
                matching: .images
            ) {
                Label("選擇發票照片", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.financePrimary)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
            .onChange(of: selectedItems) { _, _ in
                Task { await loadImages() }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - 圖片預覽網格
    private var imagePreviewGrid: some View {
        VStack(alignment: .leading) {
            Text("已選擇 \(selectedImages.count) 張發票")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 80)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                selectedImages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .background(Circle().fill(.white))
                            }
                            .padding(4)
                        }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - 處理按鈕
    private var processButton: some View {
        Button {
            Task { await processInvoices() }
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("開始識別 \(selectedImages.count) 張發票")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.financePrimary)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
    }

    // MARK: - 處理進度
    private var processingProgressView: some View {
        VStack(spacing: 12) {
            ProgressView(value: processingProgress, total: 1.0)
                .progressViewStyle(.linear)
            Text("正在識別發票... \(Int(processingProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    // MARK: - 已導入發票列表
    private var importedInvoicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已導入發票 (\(persistence.invoices.count))")
                .font(.headline)

            ForEach(persistence.invoices) { invoice in
                InvoiceRow(invoice: invoice)
            }
            .onDelete { offsets in
                persistence.deleteInvoice(at: offsets)
            }
        }
        .cardStyle()
    }

    // MARK: - 載入圖片
    private func loadImages() async {
        var images: [UIImage] = []
        for item in selectedItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await MainActor.run {
            selectedImages = images
        }
    }

    // MARK: - 處理發票 OCR
    private func processInvoices() async {
        await MainActor.run {
            isProcessing = true
            processingProgress = 0
            parsedInvoices = []
        }

        for (index, image) in selectedImages.enumerated() {
            do {
                let text = try await OCRService.shared.recognizeText(in: image)
                let parsed = OCRService.shared.parseInvoice(from: text)
                let imageData = image.jpegData(compressionQuality: 0.7)

                let parsedData = ParsedInvoiceData(
                    image: image,
                    imageData: imageData,
                    merchant: parsed.merchant,
                    amount: parsed.amount,
                    date: parsed.date,
                    items: parsed.items,
                    rawText: parsed.rawText
                )

                await MainActor.run {
                    parsedInvoices.append(parsedData)
                    processingProgress = Double(index + 1) / Double(selectedImages.count)
                }
            } catch {
                print("OCR 處理失敗: \(error)")
                await MainActor.run {
                    processingProgress = Double(index + 1) / Double(selectedImages.count)
                }
            }
        }

        await MainActor.run {
            isProcessing = false
            showingResults = true
        }
    }
}

// MARK: - 已導入發票行
struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.merchant)
                    .font(.subheadline.bold())
                HStack {
                    Text(invoice.date.shortDateString)
                    if invoice.importedAsTransaction {
                        Label("已記帳", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(invoice.amount.currencyString())
                .font(.headline)
                .foregroundStyle(.expenseColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 發票審核視圖
struct InvoiceReviewView: View {
    @Binding var parsedInvoices: [ParsedInvoiceData]
    @StateObject private var persistence = PersistenceService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(parsedInvoices.enumerated()), id: \.offset) { index, $invoice in
                    Section("發票 #\(index + 1) - \(invoice.merchant)") {
                        if let image = invoice.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                        }

                        TextField("商家名稱", text: $invoice.merchant)

                        HStack {
                            Text("金額")
                            Spacer()
                            TextField("0", value: $invoice.amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }

                        DatePicker("日期", selection: $invoice.date, displayedComponents: .date)

                        if !invoice.items.isEmpty {
                            DisclosureGroup("識別到的項目 (\(invoice.items.count))") {
                                ForEach(invoice.items, id: \.self) { item in
                                    Text(item)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        DisclosureGroup("原始文字") {
                            Text(invoice.rawText)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("審核發票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("導入記帳") { importAll() }
                        .bold()
                }
            }
        }
    }

    private func importAll() {
        for invoiceData in parsedInvoices {
            // 創建發票記錄
            let invoice = Invoice(
                date: invoiceData.date,
                merchant: invoiceData.merchant,
                amount: invoiceData.amount,
                items: invoiceData.items,
                rawText: invoiceData.rawText,
                imageData: invoiceData.imageData,
                processed: true,
                importedAsTransaction: true
            )
            persistence.addInvoice(invoice)

            // 同時創建交易記錄
            if invoiceData.amount > 0 {
                let transaction = Transaction(
                    date: invoiceData.date,
                    amount: invoiceData.amount,
                    type: .expense,
                    category: ExpenseCategory.other.rawValue,
                    note: "發票: \(invoiceData.merchant)",
                    source: .invoice
                )
                persistence.addTransaction(transaction)
            }
        }

        // 清理
        parsedInvoices = []
        dismiss()
    }
}

// MARK: - 解析後的發票數據（可編輯）
struct ParsedInvoiceData: Identifiable {
    let id = UUID()
    var image: UIImage?
    var imageData: Data?
    var merchant: String
    var amount: Double
    var date: Date
    var items: [String]
    var rawText: String
}
