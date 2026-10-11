import Foundation
import PhotosUI
import PDFKit
import QuickLook
import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

enum ReceiptSource: String, Codable, CaseIterable, Identifiable {
    case camera
    case photoLibrary
    case pdf
    case manual
    case gmail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .photoLibrary: return "Photos"
        case .pdf: return "PDF"
        case .manual: return "Manual"
        case .gmail: return "Gmail"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: return "camera.fill"
        case .photoLibrary: return "photo.fill"
        case .pdf: return "doc.richtext.fill"
        case .manual: return "square.and.pencil"
        case .gmail: return "envelope.badge.fill"
        }
    }
}

enum ReceiptSortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case merchant
    case amountHigh
    case amountLow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .merchant: return "Merchant"
        case .amountHigh: return "Amount high to low"
        case .amountLow: return "Amount low to high"
        }
    }
}

struct ReceiptRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var ownerUserID: SacredBillTrackerUserID?
    var merchant: String
    var purchasedAt: Date
    var total: Decimal
    var tax: Decimal?
    var source: ReceiptSource
    var originalFilename: String?
    var storedFilename: String?
    var recognizedText: String
    var notes: String
    var associatedBillID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var fingerprint: String
}

struct ReceiptDraft: Equatable, Identifiable {
    var id: UUID?
    var ownerUserID: SacredBillTrackerUserID?
    var merchant: String = ""
    var purchasedAt: Date = Date()
    var total: Decimal = 0
    var tax: Decimal?
    var source: ReceiptSource = .manual
    var originalFilename: String?
    var storedFilename: String?
    var recognizedText: String = ""
    var notes: String = ""
    var associatedBillID: UUID?

    var fingerprint: String {
        ReceiptFingerprint.make(
            merchant: merchant,
            purchasedAt: purchasedAt,
            total: total,
            text: recognizedText
        )
    }

    var canSave: Bool {
        !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {}

    init(record: ReceiptRecord) {
        id = record.id
        ownerUserID = record.ownerUserID
        merchant = record.merchant
        purchasedAt = record.purchasedAt
        total = record.total
        tax = record.tax
        source = record.source
        originalFilename = record.originalFilename
        storedFilename = record.storedFilename
        recognizedText = record.recognizedText
        notes = record.notes
        associatedBillID = record.associatedBillID
    }

    func record(ownerUserID: SacredBillTrackerUserID, createdAt: Date = Date()) -> ReceiptRecord {
        ReceiptRecord(
            id: id ?? UUID(),
            ownerUserID: ownerUserID,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            purchasedAt: purchasedAt,
            total: total,
            tax: tax,
            source: source,
            originalFilename: originalFilename,
            storedFilename: storedFilename,
            recognizedText: ReceiptPrivacyRedactor.redactPaymentCardData(in: recognizedText),
            notes: notes,
            associatedBillID: associatedBillID,
            createdAt: createdAt,
            updatedAt: Date(),
            fingerprint: fingerprint
        )
    }
}

enum ReceiptFingerprint {
    static func make(merchant: String, purchasedAt: Date, total: Decimal, text: String) -> String {
        let merchantKey = merchant
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let day = Calendar(identifier: .gregorian).startOfDay(for: purchasedAt).timeIntervalSince1970
        let amount = NSDecimalNumber(decimal: total).stringValue
        let textKey = text
            .lowercased()
            .prefix(180)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return [merchantKey, String(Int(day)), amount, textKey].joined(separator: "|")
    }
}

enum ReceiptPrivacyRedactor {
    static let cardToken = "[REDACTED PAYMENT CARD]"
    static let securityCodeToken = "[REDACTED CARD SECURITY CODE]"
    static let trackDataToken = "[REDACTED CARD TRACK DATA]"

    static func redactPaymentCardData(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var redacted = redactTrackData(in: text)
        redacted = redactSecurityCodes(in: redacted)
        redacted = redactPANs(in: redacted)
        return redacted
    }

    private static func redactTrackData(in text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?im)(?:^|\s)(?:%B|;)[0-9]{12,19}[\^=][^\r\n]*"#
        ) { _ in trackDataToken }
    }

    private static func redactSecurityCodes(in text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?im)\b(?:cvv|cvc|cid|security\s*code|card\s*code)\b\s*[:#-]?\s*\d{3,4}\b"#
        ) { _ in securityCodeToken }
    }

    private static func redactPANs(in text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?<![\d*])(?:\d[ -]?){13,19}(?![\d*])"#
        ) { value in
            let digits = value.filter(\.isNumber)
            guard (13...19).contains(digits.count), isLuhnValid(String(digits)) else {
                return value
            }
            let lastFour = digits.suffix(4)
            return "\(cardToken) **** \(lastFour)"
        }
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        replacement: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement(String(result[range])))
        }
        return result
    }

    private static func isLuhnValid(_ digits: String) -> Bool {
        var sum = 0
        var shouldDouble = false
        for char in digits.reversed() {
            guard var value = char.wholeNumberValue else { return false }
            if shouldDouble {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
            shouldDouble.toggle()
        }
        return sum > 0 && sum % 10 == 0
    }
}

struct ReceiptParsedValues: Equatable {
    var merchant: String
    var purchasedAt: Date
    var total: Decimal
    var tax: Decimal?
    var recognizedText: String
}

enum ReceiptOCRService {
    static func parse(image: UIImage) async -> ReceiptParsedValues {
        let text = await recognizedText(from: image)
        return parse(text: text, fallbackDate: Date())
    }

    static func parsePDF(url: URL) async -> ReceiptParsedValues {
        var text = ""
        if let document = PDFDocument(url: url) {
            for index in 0..<min(document.pageCount, 3) {
                text += (document.page(at: index)?.string ?? "") + "\n"
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let firstPage = document.page(at: 0) {
                text = await recognizedText(from: render(page: firstPage))
            }
        }
        return parse(text: text, fallbackDate: Date())
    }

    static func parse(text: String, fallbackDate: Date) -> ReceiptParsedValues {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let merchant = lines.first(where: { line in
            !line.localizedCaseInsensitiveContains("receipt") &&
            !line.localizedCaseInsensitiveContains("total") &&
            line.count > 2
        }) ?? "Receipt"
        return ReceiptParsedValues(
            merchant: merchant,
            purchasedAt: parseDate(from: lines) ?? fallbackDate,
            total: parseAmount(from: lines, labels: ["grand total", "amount paid", "total"]) ?? 0,
            tax: parseAmount(from: lines, labels: ["sales tax", "tax"]),
            recognizedText: text
        )
    }

    private static func recognizedText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                return request.results?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
            } catch {
                return ""
            }
        }.value
    }

    private static func render(page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            UIColor.white.set()
            context.fill(bounds)
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private static func parseAmount(from lines: [String], labels: [String]) -> Decimal? {
        let candidates = lines.filter { line in
            labels.contains { line.localizedCaseInsensitiveContains($0) }
        } + lines
        for line in candidates {
            if let amount = amounts(in: line).last { return amount }
        }
        return nil
    }

    private static func amounts(in line: String) -> [Decimal] {
        let pattern = #"(?<!\d)(?:\$)?\s*([0-9]{1,5}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+\.[0-9]{2})(?!\d)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex?.matches(in: line, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: line) else { return nil }
            return Decimal(string: line[valueRange].replacingOccurrences(of: ",", with: ""))
        } ?? []
    }

    private static func parseDate(from lines: [String]) -> Date? {
        let joined = lines.joined(separator: " ")
        let pattern = #"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..<joined.endIndex, in: joined)),
            let valueRange = Range(match.range(at: 1), in: joined)
        else { return nil }
        let value = String(joined[valueRange])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["M/d/yyyy", "MM/dd/yyyy", "M/d/yy", "MM/dd/yy", "M-d-yyyy", "MM-dd-yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

@MainActor
final class ReceiptJarStore: ObservableObject {
    @Published private(set) var receipts: [ReceiptRecord] = []
    @Published var lastError: String?

    private let metadataKey: String
    private let defaults: CloudBackedDefaults
    private let filesDirectoryOverride: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var currentUserID: SacredBillTrackerUserID?

    init(
        defaults: CloudBackedDefaults = .shared,
        metadataKey: String = "sbt.receiptJar.metadata.v1",
        filesDirectory: URL? = nil,
        currentUserID: SacredBillTrackerUserID? = nil
    ) {
        self.defaults = defaults
        self.metadataKey = metadataKey
        self.filesDirectoryOverride = filesDirectory
        self.currentUserID = currentUserID
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func setCurrentUser(_ userID: SacredBillTrackerUserID?) {
        guard currentUserID != userID else { return }
        currentUserID = userID
        lastError = nil
        load()
    }

    func load() {
        guard let owner = currentUserID else {
            receipts = []
            return
        }
        guard let data = defaults.data(forKey: scopedMetadataKey(owner: owner)) else {
            receipts = []
            return
        }
        do {
            receipts = try decoder.decode([ReceiptRecord].self, from: data)
                .filter { $0.ownerUserID == owner }
        } catch {
            lastError = "Receipt Jar could not read saved receipts."
            receipts = []
        }
    }

    func save(_ draft: ReceiptDraft) {
        guard let owner = currentUserID else {
            lastError = "Sign in before saving receipts so Receipt Jar can keep accounts separate."
            return
        }
        let existingCreatedAt = draft.id.flatMap { id in receipts.first(where: { $0.id == id })?.createdAt }
        var draft = draft
        draft.ownerUserID = owner
        let record = draft.record(ownerUserID: owner, createdAt: existingCreatedAt ?? Date())
        if let index = receipts.firstIndex(where: { $0.id == record.id }) {
            receipts[index] = record
        } else {
            receipts.insert(record, at: 0)
        }
        persist()
    }

    func delete(_ record: ReceiptRecord) {
        guard record.ownerUserID == currentUserID else { return }
        receipts.removeAll { $0.id == record.id }
        if let file = record.storedFilename {
            try? FileManager.default.removeItem(at: filesDirectory.appendingPathComponent(file))
        }
        persist()
    }

    func deleteImportedData() {
        guard currentUserID != nil else {
            receipts = []
            return
        }
        receipts.removeAll()
        try? FileManager.default.removeItem(at: filesDirectory)
        persist()
    }

    func duplicate(for draft: ReceiptDraft) -> ReceiptRecord? {
        receipts.first { receipt in
            receipt.ownerUserID == currentUserID &&
            receipt.id != draft.id && receipt.fingerprint == draft.fingerprint
        }
    }

    func filteredReceipts(
        searchText: String,
        source: ReceiptSource?,
        associatedOnly: Bool,
        sort: ReceiptSortOption
    ) -> [ReceiptRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var matches = receipts.filter { receipt in
            let matchesSearch = query.isEmpty ||
                receipt.merchant.lowercased().contains(query) ||
                receipt.notes.lowercased().contains(query) ||
                receipt.recognizedText.lowercased().contains(query)
            let matchesSource = source == nil || receipt.source == source
            let matchesAssociation = !associatedOnly || receipt.associatedBillID != nil
            return matchesSearch && matchesSource && matchesAssociation
        }
        matches.sort {
            switch sort {
            case .newest: return $0.purchasedAt > $1.purchasedAt
            case .oldest: return $0.purchasedAt < $1.purchasedAt
            case .merchant: return $0.merchant.localizedCaseInsensitiveCompare($1.merchant) == .orderedAscending
            case .amountHigh: return $0.total > $1.total
            case .amountLow: return $0.total < $1.total
            }
        }
        return matches
    }

    func preparePhotoReceipt(data: Data, filename: String = "receipt.jpg") async -> ReceiptDraft {
        guard currentUserID != nil else {
            lastError = "Sign in before importing receipts."
            return ReceiptDraft()
        }
        let storedName = store(data: data, preferredFilename: filename) ?? filename
        let image = UIImage(data: data) ?? UIImage()
        let parsed = await ReceiptOCRService.parse(image: image)
        return draft(from: parsed, source: .photoLibrary, originalFilename: filename, storedFilename: storedName)
    }

    func prepareCameraReceipt(image: UIImage) async -> ReceiptDraft {
        guard currentUserID != nil else {
            lastError = "Sign in before importing receipts."
            return ReceiptDraft()
        }
        let data = image.jpegData(compressionQuality: 0.88) ?? Data()
        let storedName = store(data: data, preferredFilename: "camera-receipt.jpg") ?? "camera-receipt.jpg"
        let parsed = await ReceiptOCRService.parse(image: image)
        return draft(from: parsed, source: .camera, originalFilename: "Camera receipt", storedFilename: storedName)
    }

    func prepareFileReceipt(url: URL) async -> ReceiptDraft {
        guard currentUserID != nil else {
            lastError = "Sign in before importing receipts."
            return ReceiptDraft()
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension.lowercased()
        let source: ReceiptSource = ext == "pdf" ? .pdf : .photoLibrary
        let storedName = copyFile(from: url)
        let parsed: ReceiptParsedValues
        if source == .pdf {
            parsed = await ReceiptOCRService.parsePDF(url: url)
        } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            parsed = await ReceiptOCRService.parse(image: image)
        } else {
            parsed = ReceiptOCRService.parse(text: "", fallbackDate: Date())
        }
        return draft(from: parsed, source: source, originalFilename: url.lastPathComponent, storedFilename: storedName)
    }

    func originalURL(for record: ReceiptRecord) -> URL? {
        guard record.ownerUserID == currentUserID else { return nil }
        guard let file = record.storedFilename else { return nil }
        let url = filesDirectory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func draft(
        from parsed: ReceiptParsedValues,
        source: ReceiptSource,
        originalFilename: String?,
        storedFilename: String?
    ) -> ReceiptDraft {
        var draft = ReceiptDraft()
        draft.ownerUserID = currentUserID
        draft.merchant = parsed.merchant
        draft.purchasedAt = parsed.purchasedAt
        draft.total = parsed.total
        draft.tax = parsed.tax
        draft.source = source
        draft.originalFilename = originalFilename
        draft.storedFilename = storedFilename
        draft.recognizedText = ReceiptPrivacyRedactor.redactPaymentCardData(in: parsed.recognizedText)
        return draft
    }

    private func persist() {
        guard let owner = currentUserID else { return }
        do {
            defaults.set(try encoder.encode(receipts), forKey: scopedMetadataKey(owner: owner))
        } catch {
            lastError = "Receipt Jar could not save receipts."
        }
    }

    private var filesDirectory: URL {
        let rootDirectory: URL
        if let filesDirectoryOverride {
            rootDirectory = filesDirectoryOverride
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            rootDirectory = root.appendingPathComponent("ReceiptJarFiles", isDirectory: true)
        }
        guard let owner = currentUserID else {
            return rootDirectory.appendingPathComponent("signed-out", isDirectory: true)
        }
        return rootDirectory.appendingPathComponent(owner.uuidString.lowercased(), isDirectory: true)
    }

    private func scopedMetadataKey(owner: SacredBillTrackerUserID) -> String {
        "\(metadataKey).\(owner.uuidString.lowercased())"
    }

    var hasLegacyUnownedLocalMetadata: Bool {
        defaults.data(forKey: metadataKey) != nil
    }

    var accountScopedStorageDescription: String {
        guard let owner = currentUserID else { return "Receipt Jar is locked until sign-in." }
        return "Receipt metadata key: \(scopedMetadataKey(owner: owner))"
    }

    private func ensureFilesDirectory() {
        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
    }

    private func store(data: Data, preferredFilename: String) -> String? {
        ensureFilesDirectory()
        let name = uniqueFilename(preferredFilename)
        let destination = filesDirectory.appendingPathComponent(name)
        do {
            try data.write(to: destination, options: .atomic)
            return name
        } catch {
            lastError = "Receipt Jar could not save the original receipt file."
            return nil
        }
    }

    private func copyFile(from url: URL) -> String? {
        ensureFilesDirectory()
        let name = uniqueFilename(url.lastPathComponent)
        let destination = filesDirectory.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return name
        } catch {
            lastError = "Receipt Jar could not import that file."
            return nil
        }
    }

    private func uniqueFilename(_ filename: String) -> String {
        let safeBase = filename.isEmpty ? "receipt" : filename
        let cleaned = safeBase
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
        return "\(UUID().uuidString)-\(cleaned)"
    }
}

struct GmailReceiptFinderPlan {
    static let exactScopes = [
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    static let productionRequirements = [
        "Configure a Google OAuth iOS client and reversed client ID.",
        "Complete Google's OAuth app verification for restricted Gmail scopes.",
        "Prepare a security assessment if Google classifies the production use as restricted-scope access.",
        "Update App Privacy answers for receipt email content used only for user-selected import.",
        "Provide in-app disconnect and delete-imported-receipts controls before enabling production auth."
    ]
}

struct ReceiptJarView: View {
    @EnvironmentObject private var subs: SubscriptionManager
    @EnvironmentObject private var billStore: BillStore
    @EnvironmentObject private var auth: AuthService
    @StateObject private var receiptStore = ReceiptJarStore()

    var body: some View {
        Group {
            if !ReceiptJarReleaseGate.isEnabled {
                ContentUnavailableView(
                    "Receipt Jar Unavailable",
                    systemImage: "shippingbox",
                    description: Text("Receipt Jar is not available in this release.")
                )
            } else if subs.hasReceiptJar {
                ReceiptJarUnlockedView(receiptStore: receiptStore)
                    .environmentObject(billStore)
            } else {
                ReceiptJarPurchaseView()
                    .environmentObject(subs)
            }
        }
        .navigationTitle("Receipt Jar")
        .task {
            receiptStore.setCurrentUser(auth.currentUserID)
            if ReceiptJarReleaseGate.isEnabled {
                await subs.prepareForPaywall()
            }
        }
        .onChange(of: auth.currentUserID) { _, userID in
            receiptStore.setCurrentUser(userID)
        }
    }
}

private struct ReceiptJarUnlockedView: View {
    @ObservedObject var receiptStore: ReceiptJarStore
    @EnvironmentObject private var billStore: BillStore
    @State private var searchText = ""
    @State private var selectedSource: ReceiptSource?
    @State private var associatedOnly = false
    @State private var sort: ReceiptSortOption = .newest
    @State private var showManual = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showEmailFinder = false
    @State private var photoItem: PhotosPickerItem?
    @State private var editingDraft: ReceiptDraft?
    @State private var isImporting = false
    @State private var confirmDeleteAll = false
    private static let privacyFooter = "Receipt metadata is saved with the app's small synced data store. Original files stay in this app's private container and are deleted when you remove receipt data."

    private var visibleReceipts: [ReceiptRecord] {
        receiptStore.filteredReceipts(
            searchText: searchText,
            source: selectedSource,
            associatedOnly: associatedOnly,
            sort: sort
        )
    }

    var body: some View {
        List {
            Section {
                ReceiptJarSummary(receipts: receiptStore.receipts)
                if receiptStore.hasLegacyUnownedLocalMetadata {
                    Label("Legacy local receipts are quarantined until an explicit account-owner migration is approved.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photos", systemImage: "photo")
                    }
                    Spacer()
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    Spacer()
                    Button { showFileImporter = true } label: {
                        Label("PDF/File", systemImage: "doc.badge.plus")
                    }
                }
                Button { showManual = true } label: {
                    Label("Add Manual Receipt", systemImage: "square.and.pencil")
                }
                Button { showEmailFinder = true } label: {
                    Label("Find Receipts in Email", systemImage: "envelope.badge")
                }
            } header: {
                Text("Add")
            }

            Section {
                Picker("Source", selection: Binding(
                    get: { selectedSource },
                    set: { selectedSource = $0 }
                )) {
                    Text("All").tag(Optional<ReceiptSource>.none)
                    ForEach(ReceiptSource.allCases) { source in
                        Text(source.title).tag(source as ReceiptSource?)
                    }
                }
                Picker("Sort", selection: $sort) {
                    ForEach(ReceiptSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Toggle("Only linked to bills", isOn: $associatedOnly)
            } header: {
                Text("Search and filter")
            }

            Section {
                if isImporting {
                    HStack {
                        ProgressView()
                        Text("Reading receipt")
                    }
                }
                if visibleReceipts.isEmpty {
                    ContentUnavailableView(
                        "No Receipts",
                        systemImage: "receipt",
                        description: Text("Add a photo, PDF, email receipt, or manual receipt.")
                    )
                } else {
                    ForEach(visibleReceipts) { receipt in
                        NavigationLink {
                            ReceiptDetailView(record: receipt, receiptStore: receiptStore)
                                .environmentObject(billStore)
                        } label: {
                            ReceiptRow(receipt: receipt, billName: billName(for: receipt.associatedBillID))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                receiptStore.delete(receipt)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Receipts")
            }

            Section {
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Label("Delete Imported Receipt Data", systemImage: "trash")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text(Self.privacyFooter)
            }
        }
        .searchable(text: $searchText, prompt: "Search merchant, notes, or receipt text")
        .sheet(item: $editingDraft) { draft in
            NavigationStack {
                ReceiptDraftReviewView(
                    title: draft.id == nil ? "Review Receipt" : "Edit Receipt",
                    draft: draft,
                    existingDuplicate: receiptStore.duplicate(for: draft)
                ) { updated in
                    receiptStore.save(updated)
                    editingDraft = nil
                }
                .environmentObject(billStore)
            }
        }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                ReceiptDraftReviewView(
                    title: "Manual Receipt",
                    draft: ReceiptDraft(),
                    existingDuplicate: nil
                ) { draft in
                    receiptStore.save(draft)
                    showManual = false
                }
                .environmentObject(billStore)
            }
        }
        .sheet(isPresented: $showCamera) {
            ReceiptCameraPicker { image in
                showCamera = false
                guard let image else { return }
                importCamera(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showEmailFinder) {
            NavigationStack {
                ReceiptEmailFinderView()
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            importFile(url)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
        .confirmationDialog(
            "Delete all imported receipt data?",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete Receipt Jar Data", role: .destructive) {
                receiptStore.deleteImportedData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved receipts and original imported files from this device.")
        }
        .alert(
            "Receipt Jar",
            isPresented: Binding(
                get: { receiptStore.lastError != nil },
                set: { if !$0 { receiptStore.lastError = nil } }
            ),
            presenting: receiptStore.lastError
        ) { _ in
            Button("OK", role: .cancel) { receiptStore.lastError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func billName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return billStore.allStoredBills.first(where: { $0.id == id })?.name
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        isImporting = true
        Task {
            defer {
                Task { @MainActor in
                    isImporting = false
                    photoItem = nil
                }
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let draft = await receiptStore.preparePhotoReceipt(data: data)
            await MainActor.run { editingDraft = draft }
        }
    }

    private func importCamera(_ image: UIImage) {
        isImporting = true
        Task {
            let draft = await receiptStore.prepareCameraReceipt(image: image)
            await MainActor.run {
                isImporting = false
                editingDraft = draft
            }
        }
    }

    private func importFile(_ url: URL) {
        isImporting = true
        Task {
            let draft = await receiptStore.prepareFileReceipt(url: url)
            await MainActor.run {
                isImporting = false
                editingDraft = draft
            }
        }
    }
}

private struct ReceiptJarSummary: View {
    let receipts: [ReceiptRecord]

    private var total: Decimal {
        receipts.reduce(Decimal(0)) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Receipt Jar", systemImage: "shippingbox.fill")
                .font(.headline)
                .foregroundStyle(Color.appAccentText)
            HStack {
                VStack(alignment: .leading) {
                    Text("\(receipts.count)")
                        .font(.title3.weight(.bold))
                    Text("Receipts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(total.currencyText)
                        .font(.title3.weight(.bold))
                    Text("Tracked total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ReceiptRow: View {
    let receipt: ReceiptRecord
    let billName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: receipt.source.systemImage)
                .foregroundStyle(Color.appAccentText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.merchant)
                    .font(.headline)
                    .lineLimit(1)
                Text(receipt.purchasedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let billName {
                    Text(billName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appHouseholdText)
                }
            }
            Spacer()
            Text(receipt.total.currencyText)
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct ReceiptDetailView: View {
    let record: ReceiptRecord
    @ObservedObject var receiptStore: ReceiptJarStore
    @EnvironmentObject private var billStore: BillStore
    @State private var editingDraft: ReceiptDraft?
    @State private var preview: ReceiptPreviewItem?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Merchant")
                    Spacer()
                    Text(record.merchant).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Date")
                    Spacer()
                    Text(record.purchasedAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total")
                    Spacer()
                    Text(record.total.currencyText).foregroundStyle(.secondary)
                }
                if let tax = record.tax {
                    HStack {
                        Text("Tax")
                        Spacer()
                        Text(tax.currencyText).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Source")
                    Spacer()
                    Text(record.source.title).foregroundStyle(.secondary)
                }
            }

            Section("Bill") {
                Text(billStore.allStoredBills.first(where: { $0.id == record.associatedBillID })?.name ?? "Not linked")
                    .foregroundStyle(record.associatedBillID == nil ? .secondary : .primary)
            }

            if let url = receiptStore.originalURL(for: record) {
                Section("Original") {
                    Button {
                        preview = ReceiptPreviewItem(url: url)
                    } label: {
                        Label("View Original Receipt", systemImage: "doc.viewfinder")
                    }
                    ShareLink(item: url) {
                        Label("Share Original", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if !record.notes.isEmpty {
                Section("Notes") {
                    Text(record.notes)
                }
            }

            if !record.recognizedText.isEmpty {
                Section("OCR Text") {
                    Text(record.recognizedText)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button {
                    editingDraft = ReceiptDraft(record: record)
                } label: {
                    Label("Edit Receipt", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    receiptStore.delete(record)
                } label: {
                    Label("Delete Receipt", systemImage: "trash")
                }
            }
        }
        .navigationTitle(record.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(item: $editingDraft) { draft in
            NavigationStack {
                ReceiptDraftReviewView(
                    title: "Edit Receipt",
                    draft: draft,
                    existingDuplicate: receiptStore.duplicate(for: draft)
                ) { updated in
                    receiptStore.save(updated)
                    editingDraft = nil
                }
                .environmentObject(billStore)
            }
        }
    }
}

private struct ReceiptDraftReviewView: View {
    let title: String
    @State var draft: ReceiptDraft
    let existingDuplicate: ReceiptRecord?
    let onSave: (ReceiptDraft) -> Void
    @EnvironmentObject private var billStore: BillStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let existingDuplicate {
                Section {
                    Label("Possible duplicate: \(existingDuplicate.merchant)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.appAmber)
                    Text(existingDuplicate.purchasedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Receipt") {
                TextField("Merchant", text: $draft.merchant)
                DatePicker("Date", selection: $draft.purchasedAt, displayedComponents: .date)
                DecimalField(title: "Total", value: $draft.total)
                DecimalOptionalField(title: "Tax", value: $draft.tax)
                Picker("Associated bill", selection: $draft.associatedBillID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(billStore.allStoredBills.filter { $0.deletedAt == nil }) { bill in
                        Text(bill.name).tag(Optional(bill.id))
                    }
                }
            }

            Section {
                TextEditor(text: $draft.recognizedText)
                    .frame(minHeight: 160)
                    .textInputAutocapitalization(.sentences)
            } header: {
                Text("Review OCR")
            } footer: {
                Text("Review and edit recognized text before saving. Nothing is imported silently.")
            }

            Section("Notes") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 90)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .disabled(!draft.canSave)
            }
        }
    }
}

private struct ReceiptJarPurchaseView: View {
    @EnvironmentObject private var subs: SubscriptionManager
    @State private var isPurchasing = false

    private var product: Product? { subs.receiptJarProduct }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "shippingbox.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.appAccentText)
                    Text("Receipt Jar")
                        .font(.title2.bold())
                    Text("Save receipt photos, PDFs, manual entries, OCR text, and bill links in one private receipt cabinet.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(product?.displayPrice ?? "$49.99")
                            .font(.title3.bold())
                        Text("one-time purchase")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Includes") {
                Label("Camera, Photos, PDF, and manual receipt entry", systemImage: "camera.metering.center.weighted")
                Label("OCR review before anything is saved", systemImage: "text.viewfinder")
                Label("Search, filter, sort, edit, delete, and original receipt viewing", systemImage: "line.3.horizontal.decrease.circle")
                Label("Associate receipts with existing bills", systemImage: "link")
                Label("Gmail receipt finder architecture prepared for approved OAuth", systemImage: "envelope.badge")
            }

            Section {
                Button {
                    purchase()
                } label: {
                    HStack {
                        Label("Unlock Receipt Jar", systemImage: "cart.badge.plus")
                        Spacer()
                        if isPurchasing { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(product == nil || isPurchasing)

                Button {
                    Task { await subs.restorePurchases() }
                } label: {
                    Label("Restore Receipt Jar Purchase", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("Receipt Jar is separate from Essential and Unlimited subscriptions. App Store Connect must contain a non-consumable product matching this app's product ID before release.")
            }

            if let error = subs.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(Color.appDangerText)
                }
            }
        }
    }

    private func purchase() {
        guard let product else { return }
        isPurchasing = true
        Task {
            _ = await subs.purchase(product)
            await MainActor.run { isPurchasing = false }
        }
    }
}

private struct ReceiptEmailFinderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Label("Gmail connection is not enabled yet", systemImage: "lock.shield")
                    .font(.headline)
                Text("Production OAuth must be configured and approved before Sacred Bill Tracker can connect to Gmail. The app will request read-only access, show likely receipt matches, and import only the receipts you select.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(GmailReceiptFinderPlan.exactScopes, id: \.self) { scope in
                    Text(scope)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text("Minimum Gmail scope")
            } footer: {
                Text("No password access, sending, deleting, archiving, moving, or unrelated mailbox actions are part of this design.")
            }

            Section("Planned workflow") {
                Label("Connect Gmail with explicit consent", systemImage: "person.badge.key")
                Label("Search likely receipt messages only", systemImage: "magnifyingglass")
                Label("Show merchant, date, amount, sender, and source preview", systemImage: "list.bullet.rectangle")
                Label("Select receipts, review extracted fields, then confirm import", systemImage: "checkmark.rectangle.stack")
                Label("Prevent duplicates using receipt fingerprints", systemImage: "checkmark.seal")
            }

            Section("Before production") {
                ForEach(GmailReceiptFinderPlan.productionRequirements, id: \.self) { requirement in
                    Label(requirement, systemImage: "checklist")
                }
            }

            Section {
                Button("Done") { dismiss() }
            }
        }
        .navigationTitle("Email Receipt Finder")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DecimalField: View {
    let title: String
    @Binding var value: Decimal
    @State private var text: String = ""

    var body: some View {
        TextField(title, text: Binding(
            get: {
                if text.isEmpty { text = value.plainText }
                return text
            },
            set: { newValue in
                text = newValue
                value = Decimal(string: newValue) ?? 0
            }
        ))
        .keyboardType(.decimalPad)
    }
}

private struct DecimalOptionalField: View {
    let title: String
    @Binding var value: Decimal?
    @State private var text: String = ""

    var body: some View {
        TextField(title, text: Binding(
            get: {
                if text.isEmpty, let value { text = value.plainText }
                return text
            },
            set: { newValue in
                text = newValue
                value = newValue.isEmpty ? nil : Decimal(string: newValue)
            }
        ))
        .keyboardType(.decimalPad)
    }
}

private struct ReceiptCameraPicker: UIViewControllerRepresentable {
    var onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onComplete(info[.originalImage] as? UIImage)
        }
    }
}

private struct ReceiptPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private extension Decimal {
    var plainText: String {
        NSDecimalNumber(decimal: self).stringValue
    }

    var currencyText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? plainText
    }
}
