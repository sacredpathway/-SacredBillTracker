import XCTest
import PDFKit
import StoreKit
import UIKit
@testable import SacredBillTracker

@MainActor
final class ReceiptJarTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var filesDirectory: URL!
    private var store: ReceiptJarStore!
    private var ownerA: SacredBillTrackerUserID!
    private var ownerB: SacredBillTrackerUserID!

    override func setUp() async throws {
        try await super.setUp()
        ownerA = UUID()
        ownerB = UUID()
        suiteName = "ReceiptJarTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        filesDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptJarTests-\(UUID().uuidString)", isDirectory: true)
        let cloudDefaults = CloudBackedDefaults(defaults: defaults)
        store = ReceiptJarStore(
            defaults: cloudDefaults,
            metadataKey: "sbt.receiptJar.tests.\(UUID().uuidString)",
            filesDirectory: filesDirectory,
            currentUserID: ownerA
        )
    }

    override func tearDown() async throws {
        store.deleteImportedData()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: filesDirectory)
        store = nil
        defaults = nil
        suiteName = nil
        filesDirectory = nil
        ownerA = nil
        ownerB = nil
        try await super.tearDown()
    }

    func testManualReceiptCanBeCreatedEditedAssociatedSearchedFilteredSortedAndDeleted() {
        let billID = UUID()
        var draft = ReceiptDraft()
        draft.merchant = "Sacred Market"
        draft.total = Decimal(string: "49.99")!
        draft.tax = Decimal(string: "4.10")
        draft.notes = "altar candles"
        draft.associatedBillID = billID

        store.save(draft)

        XCTAssertEqual(store.receipts.count, 1)
        var saved = store.receipts[0]
        XCTAssertEqual(saved.merchant, "Sacred Market")
        XCTAssertEqual(saved.ownerUserID, ownerA)
        XCTAssertEqual(saved.associatedBillID, billID)
        XCTAssertEqual(store.filteredReceipts(searchText: "candles", source: nil, associatedOnly: true, sort: .newest), [saved])

        var edit = ReceiptDraft(record: saved)
        edit.merchant = "Sacred Market Updated"
        edit.total = Decimal(string: "59.99")!
        store.save(edit)

        XCTAssertEqual(store.receipts.count, 1)
        saved = store.receipts[0]
        XCTAssertEqual(saved.merchant, "Sacred Market Updated")
        XCTAssertEqual(store.filteredReceipts(searchText: "", source: nil, associatedOnly: false, sort: .amountHigh).first?.total, Decimal(string: "59.99"))

        store.delete(saved)
        XCTAssertTrue(store.receipts.isEmpty)
    }

    func testDuplicateDetectionUsesMerchantDateAmountAndRecognizedText() {
        var first = ReceiptDraft()
        first.merchant = "Corner Store"
        first.total = Decimal(string: "12.34")!
        first.recognizedText = "Corner Store\nTotal $12.34"
        store.save(first)

        var duplicate = ReceiptDraft()
        duplicate.merchant = "Corner Store"
        duplicate.purchasedAt = first.purchasedAt
        duplicate.total = first.total
        duplicate.recognizedText = first.recognizedText

        XCTAssertEqual(store.duplicate(for: duplicate)?.merchant, "Corner Store")
    }

    func testReceiptTextParsingExtractsMerchantDateTotalAndTaxForReviewBeforeSave() {
        let parsed = ReceiptOCRService.parse(
            text: """
            Neighborhood Grocery
            09/21/2026
            Sales Tax $1.23
            Total $18.45
            """,
            fallbackDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(parsed.merchant, "Neighborhood Grocery")
        XCTAssertEqual(parsed.total, Decimal(string: "18.45"))
        XCTAssertEqual(parsed.tax, Decimal(string: "1.23"))
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: parsed.purchasedAt), 2026)
    }

    func testImageImportStoresOriginalAndProducesEditablePhotoDraft() async {
        let data = sampleImageData()
        let draft = await store.preparePhotoReceipt(data: data, filename: "receipt/photo:test.jpg")

        XCTAssertEqual(draft.source, .photoLibrary)
        XCTAssertEqual(draft.originalFilename, "receipt/photo:test.jpg")
        XCTAssertNotNil(draft.storedFilename)
        XCTAssertFalse(draft.storedFilename?.contains("/") ?? true)

        store.save(draft)
        XCTAssertNotNil(store.originalURL(for: store.receipts[0]))
    }

    func testPDFImportStoresOriginalAndExtractsText() async throws {
        let url = try samplePDFURL()
        let draft = await store.prepareFileReceipt(url: url)

        XCTAssertEqual(draft.source, .pdf)
        XCTAssertEqual(draft.originalFilename, url.lastPathComponent)
        XCTAssertEqual(draft.merchant, "PDF Shop")
        XCTAssertEqual(draft.total, Decimal(string: "22.10"))
        XCTAssertTrue(draft.recognizedText.contains("PDF Shop"))

        store.save(draft)
        XCTAssertNotNil(store.originalURL(for: store.receipts[0]))
    }

    func testImportedDataDeletionRemovesMetadataAndOriginalFiles() async {
        let draft = await store.preparePhotoReceipt(data: sampleImageData(), filename: "receipt.jpg")
        store.save(draft)
        let originalURL = store.originalURL(for: store.receipts[0])
        XCTAssertNotNil(originalURL)

        store.deleteImportedData()

        XCTAssertTrue(store.receipts.isEmpty)
        if let originalURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        }
    }

    func testReceiptJarPartitionsMetadataAndFilesByAuthenticatedAccount() async {
        var first = ReceiptDraft()
        first.merchant = "Account A Market"
        first.total = Decimal(string: "10.00")!
        store.save(first)
        let ownerAReceipt = store.receipts[0]

        store.setCurrentUser(ownerB)
        XCTAssertTrue(store.receipts.isEmpty)

        let second = await store.preparePhotoReceipt(data: sampleImageData(), filename: "owner-b.jpg")
        store.save(second)
        XCTAssertEqual(store.receipts.count, 1)
        XCTAssertEqual(store.receipts[0].ownerUserID, ownerB)
        XCTAssertNil(store.originalURL(for: ownerAReceipt))

        store.setCurrentUser(ownerA)
        XCTAssertEqual(store.receipts.map(\.merchant), ["Account A Market"])
    }

    func testSignedOutReceiptJarDoesNotLeakPreviousAccountData() {
        var draft = ReceiptDraft()
        draft.merchant = "Private Receipt"
        store.save(draft)

        store.setCurrentUser(nil)

        XCTAssertTrue(store.receipts.isEmpty)
        var signedOutDraft = ReceiptDraft()
        signedOutDraft.merchant = "Should Not Save"
        store.save(signedOutDraft)
        XCTAssertTrue(store.receipts.isEmpty)
        XCTAssertNotNil(store.lastError)
    }

    func testDeleteImportedDataOnlyRemovesCurrentAccountPartition() async {
        let first = await store.preparePhotoReceipt(data: sampleImageData(), filename: "owner-a.jpg")
        store.save(first)
        let ownerAURL = store.originalURL(for: store.receipts[0])

        store.setCurrentUser(ownerB)
        let second = await store.preparePhotoReceipt(data: sampleImageData(), filename: "owner-b.jpg")
        store.save(second)
        let ownerBURL = store.originalURL(for: store.receipts[0])

        store.deleteImportedData()

        XCTAssertTrue(store.receipts.isEmpty)
        if let ownerBURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: ownerBURL.path))
        }
        if let ownerAURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: ownerAURL.path))
        }

        store.setCurrentUser(ownerA)
        XCTAssertEqual(store.receipts.count, 1)
        XCTAssertNotNil(store.originalURL(for: store.receipts[0]))
    }

    func testLegacyUnownedReceiptMetadataIsQuarantinedUntilExplicitMigration() throws {
        let metadataKey = "sbt.receiptJar.legacy.\(UUID().uuidString)"
        let legacyRecord = ReceiptRecord(
            id: UUID(),
            ownerUserID: nil,
            merchant: "Legacy Shop",
            purchasedAt: Date(),
            total: Decimal(string: "3.99")!,
            tax: nil,
            source: .manual,
            originalFilename: nil,
            storedFilename: nil,
            recognizedText: "",
            notes: "",
            associatedBillID: nil,
            createdAt: Date(),
            updatedAt: Date(),
            fingerprint: "legacy"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode([legacyRecord]), forKey: metadataKey)

        let quarantined = ReceiptJarStore(
            defaults: CloudBackedDefaults(defaults: defaults),
            metadataKey: metadataKey,
            filesDirectory: filesDirectory,
            currentUserID: ownerA
        )

        XCTAssertTrue(quarantined.hasLegacyUnownedLocalMetadata)
        XCTAssertTrue(quarantined.receipts.isEmpty)
    }

    func testReceiptOCRRedactsPaymentCardsBeforePersistence() {
        let text = """
        Sacred Shop
        VISA 4111 1111 1111 1111
        CVV: 123
        Order 123456
        Total $42.00
        """
        let parsed = ReceiptOCRService.parse(text: text, fallbackDate: Date(timeIntervalSince1970: 0))
        var draft = ReceiptDraft()
        draft.merchant = parsed.merchant
        draft.recognizedText = parsed.recognizedText
        store.save(draft)

        let savedText = store.receipts[0].recognizedText
        XCTAssertFalse(savedText.contains("4111 1111 1111 1111"))
        XCTAssertFalse(savedText.contains("CVV: 123"))
        XCTAssertTrue(savedText.contains(ReceiptPrivacyRedactor.cardToken))
        XCTAssertTrue(savedText.contains(ReceiptPrivacyRedactor.securityCodeToken))
        XCTAssertTrue(savedText.contains("Order 123456"))
    }

    func testReceiptOCRPreservesMaskedLastFourAndNonCardReceiptNumbers() {
        let text = "VISA **** 1234\nReceipt 123456789012\nTotal $12.00"
        let redacted = ReceiptPrivacyRedactor.redactPaymentCardData(in: text)

        XCTAssertTrue(redacted.contains("VISA **** 1234"))
        XCTAssertTrue(redacted.contains("Receipt 123456789012"))
    }

    func testReceiptOCRRedactsTrackData() {
        let redacted = ReceiptPrivacyRedactor.redactPaymentCardData(
            in: "%B4111111111111111^CUSTOMER/TEST^26011234567890000000"
        )

        XCTAssertEqual(redacted, ReceiptPrivacyRedactor.trackDataToken)
    }

    func testReceiptJarProductIsConfiguredAsLocalNonConsumable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("SacredBillTracker/Configuration.storekit")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let products = try XCTUnwrap(json?["products"] as? [[String: Any]])
        let product = try XCTUnwrap(products.first { $0["productID"] as? String == ProductID.receiptJarLifetime })

        XCTAssertEqual(product["type"] as? String, "NonConsumable")
        XCTAssertEqual(product["displayPrice"] as? String, "49.99")
        XCTAssertEqual(product["familyShareable"] as? Bool, false)
    }

    func testReceiptJarReleaseGateRemovesProductWhenDisabled() {
        let disabledProducts = ReceiptJarReleaseGate.filterStoreKitProducts(ProductID.allKnown, enabled: false)

        XCTAssertFalse(disabledProducts.contains(ProductID.receiptJarLifetime))
        XCTAssertTrue(disabledProducts.contains(ProductID.essentialMonthly))
        XCTAssertTrue(disabledProducts.contains(ProductID.unlimitedMonthly))
        XCTAssertTrue(disabledProducts.contains(ProductID.autoTrackMonthly))
    }

    func testReceiptJarReleaseGateAllowsProductOnlyWhenEnabled() {
        let enabledProducts = ReceiptJarReleaseGate.filterStoreKitProducts(ProductID.allKnown, enabled: true)

        XCTAssertTrue(enabledProducts.contains(ProductID.receiptJarLifetime))
        XCTAssertTrue(ReceiptJarReleaseGate.allowsEntitlement(productID: ProductID.receiptJarLifetime, enabled: true))
        XCTAssertFalse(ReceiptJarReleaseGate.allowsEntitlement(productID: ProductID.receiptJarLifetime, enabled: false))
        XCTAssertTrue(ReceiptJarReleaseGate.allowsEntitlement(productID: ProductID.essentialMonthly, enabled: false))
    }

    func testReceiptJarEntitlementIsIndependentFromEssentialAndUnlimited() {
        let manager = SubscriptionManager()

        manager.applyVerifiedProductsForTesting([ProductID.essentialMonthly])
        XCTAssertFalse(manager.hasReceiptJar)
        XCTAssertEqual(manager.rawPlanTier, .essential)

        manager.applyVerifiedProductsForTesting([ProductID.unlimitedMonthly])
        XCTAssertFalse(manager.hasReceiptJar)
        XCTAssertEqual(manager.rawPlanTier, .unlimited)

        manager.applyVerifiedProductsForTesting([ProductID.receiptJarLifetime])
        XCTAssertTrue(manager.hasReceiptJar)
        XCTAssertEqual(manager.rawPlanTier, .free)
    }

    func testPostPurchaseSuccessRequiresMatchingFeatureAccess() {
        XCTAssertTrue(SBTPostPurchaseAccessPolicy.grantsPurchasedPlan(
            purchased: .essential,
            active: .essential
        ))
        XCTAssertTrue(SBTPostPurchaseAccessPolicy.grantsPurchasedPlan(
            purchased: .essential,
            active: .unlimited
        ))
        XCTAssertTrue(SBTPostPurchaseAccessPolicy.grantsPurchasedPlan(
            purchased: .unlimited,
            active: .unlimited
        ))
        XCTAssertFalse(SBTPostPurchaseAccessPolicy.grantsPurchasedPlan(
            purchased: .essential,
            active: .free
        ))
        XCTAssertFalse(SBTPostPurchaseAccessPolicy.grantsPurchasedPlan(
            purchased: .unlimited,
            active: .business
        ))
    }

    func testRecognizedPlanProductsMapToExpectedFeatureAccess() {
        let manager = SubscriptionManager()

        manager.applyVerifiedProductsForTesting([ProductID.essentialMonthly])
        XCTAssertEqual(manager.effectiveTier, .essential)
        XCTAssertTrue(manager.canUnlimitedBills)
        XCTAssertTrue(manager.canIncomeTracking)
        XCTAssertFalse(manager.canManagedProfiles)

        manager.applyVerifiedProductsForTesting([ProductID.unlimitedMonthly])
        XCTAssertEqual(manager.effectiveTier, .unlimited)
        XCTAssertTrue(manager.canManagedProfiles)
        XCTAssertTrue(manager.canForecasting)

        manager.applyVerifiedProductsForTesting([ProductID.proMonthly])
        XCTAssertEqual(manager.effectiveTier, .business)
        XCTAssertTrue(manager.canBusinessTracking)
        XCTAssertFalse(manager.canManagedProfiles)

        manager.applyVerifiedProductsForTesting([ProductID.autoTrackMonthly])
        XCTAssertEqual(manager.effectiveTier, .unlimited)
        XCTAssertTrue(manager.hasAutoTrack)
        XCTAssertTrue(manager.canManagedProfiles)
    }

    func testGmailFinderRemainsArchitectureOnlyWithReadOnlyScope() {
        XCTAssertEqual(GmailReceiptFinderPlan.exactScopes, ["https://www.googleapis.com/auth/gmail.readonly"])
        XCTAssertTrue(GmailReceiptFinderPlan.productionRequirements.contains { $0.localizedCaseInsensitiveContains("OAuth") })
        XCTAssertTrue(GmailReceiptFinderPlan.productionRequirements.contains { $0.localizedCaseInsensitiveContains("security assessment") })
    }

    private func sampleImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
            UIColor.black.setFill()
            "R".draw(at: CGPoint(x: 30, y: 25), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }

    private func samplePDFURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 240))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            let text = "PDF Shop\n09/21/2026\nTax $2.10\nTotal $22.10"
            text.draw(
                in: CGRect(x: 24, y: 24, width: 250, height: 160),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
        }
        return url
    }
}

final class UnifiedAccountArchitectureTests: XCTestCase {
    func testProviderSubjectMapsToInternalSacredAccountID() {
        let account = UUID()
        let link = SBTLinkedIdentity(
            accountID: account,
            provider: .apple,
            providerSubject: "001.apple.subject",
            verifiedEmail: "hide@privaterelay.appleid.com",
            isPrivateRelayEmail: true,
            linkedAt: Date()
        )

        let decision = SBTAccountLinkingPolicy.decision(
            signedInAccountID: nil,
            incomingProvider: .apple,
            incomingProviderSubject: "001.apple.subject",
            incomingVerifiedEmail: "different@example.com",
            existingLinks: [link]
        )

        XCTAssertEqual(decision, .alreadyLinked(account))
    }

    func testSameEmailAcrossProvidersRequiresExplicitReauthenticationNotSilentMerge() {
        let existing = SBTLinkedIdentity(
            accountID: UUID(),
            provider: .emailPassword,
            providerSubject: "email:user@example.com",
            verifiedEmail: "user@example.com",
            isPrivateRelayEmail: false,
            linkedAt: Date()
        )

        let decision = SBTAccountLinkingPolicy.decision(
            signedInAccountID: UUID(),
            incomingProvider: .google,
            incomingProviderSubject: "google-subject",
            incomingVerifiedEmail: "USER@example.com",
            existingLinks: [existing]
        )

        if case .requireExplicitReauthentication = decision {
            XCTAssertTrue(true)
        } else {
            XCTFail("Email-only identity matches must not silently merge accounts.")
        }
    }

    func testSignedInAccountCanLinkNewProviderAfterProof() {
        let account = UUID()

        let decision = SBTAccountLinkingPolicy.decision(
            signedInAccountID: account,
            incomingProvider: .google,
            incomingProviderSubject: "google-subject",
            incomingVerifiedEmail: "owner@example.com",
            existingLinks: []
        )

        XCTAssertEqual(decision, .linkToSignedInAccount(account))
    }

    func testCrossPlatformEntitlementsStayAccountScopedAndRevocationAware() {
        let account = UUID()
        let other = UUID()
        let now = Date()
        let entitlements = [
            SBTAccountEntitlement(
                accountID: account,
                provider: .appleAppStore,
                productID: ProductID.essentialMonthly,
                originalTransactionID: "1000001",
                latestTransactionID: "1000002",
                kind: .plan(.essential),
                status: "active",
                expiresAt: now.addingTimeInterval(3600),
                renewalState: "auto_renew_on",
                lastVerifiedAt: now,
                revokedAt: nil
            ),
            SBTAccountEntitlement(
                accountID: account,
                provider: .googlePlay,
                productID: ProductID.receiptJarLifetime,
                originalTransactionID: "GPA.1234-5678-9012-34567",
                latestTransactionID: "GPA.1234-5678-9012-34567",
                kind: .receiptJarLifetime,
                status: "active",
                expiresAt: nil,
                renewalState: nil,
                lastVerifiedAt: now,
                revokedAt: nil
            ),
            SBTAccountEntitlement(
                accountID: other,
                provider: .googlePlay,
                productID: ProductID.unlimitedMonthly,
                originalTransactionID: "GPA.other",
                latestTransactionID: "GPA.other",
                kind: .plan(.unlimited),
                status: "active",
                expiresAt: now.addingTimeInterval(3600),
                renewalState: nil,
                lastVerifiedAt: now,
                revokedAt: nil
            )
        ]

        XCTAssertEqual(
            SBTCrossPlatformEntitlementPolicy.planTier(for: account, entitlements: entitlements, now: now),
            .essential
        )
        XCTAssertTrue(
            SBTCrossPlatformEntitlementPolicy.hasReceiptJarLifetime(for: account, entitlements: entitlements, now: now)
        )
        XCTAssertEqual(
            SBTCrossPlatformEntitlementPolicy.planTier(for: other, entitlements: entitlements, now: now),
            .unlimited
        )
    }

    func testExpiredOrRevokedEntitlementsDoNotGrantAccess() {
        let account = UUID()
        let now = Date()
        let entitlements = [
            SBTAccountEntitlement(
                accountID: account,
                provider: .appleAppStore,
                productID: ProductID.businessMonthly,
                originalTransactionID: "100",
                latestTransactionID: "101",
                kind: .plan(.business),
                status: "active",
                expiresAt: now.addingTimeInterval(-1),
                renewalState: nil,
                lastVerifiedAt: now,
                revokedAt: nil
            ),
            SBTAccountEntitlement(
                accountID: account,
                provider: .googlePlay,
                productID: ProductID.receiptJarLifetime,
                originalTransactionID: "GPA.revoked",
                latestTransactionID: "GPA.revoked",
                kind: .receiptJarLifetime,
                status: "active",
                expiresAt: nil,
                renewalState: nil,
                lastVerifiedAt: now,
                revokedAt: now
            )
        ]

        XCTAssertEqual(
            SBTCrossPlatformEntitlementPolicy.planTier(for: account, entitlements: entitlements, now: now),
            .free
        )
        XCTAssertFalse(
            SBTCrossPlatformEntitlementPolicy.hasReceiptJarLifetime(for: account, entitlements: entitlements, now: now)
        )
    }

    func testAuthoritativeAppleLifecycleAndIdempotency() {
        let account = UUID()
        let now = Date()
        var reducer = SBTAuthoritativeEntitlementReducer()

        let essential = storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000001",
            latest: "1000002",
            productID: ProductID.essentialMonthly,
            kind: .plan(.essential),
            status: .active,
            eventID: "apple-initial",
            eventTime: now,
            expiresAt: now.addingTimeInterval(3600)
        )
        XCTAssertEqual(reducer.apply(essential), .applied)
        XCTAssertEqual(reducer.apply(essential), .duplicate)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .essential)

        let cancelledStillActive = storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000001",
            latest: "1000003",
            productID: ProductID.essentialMonthly,
            kind: .plan(.essential),
            status: .cancelledActive,
            eventID: "apple-cancelled",
            eventTime: now.addingTimeInterval(20),
            expiresAt: now.addingTimeInterval(3600)
        )
        XCTAssertEqual(reducer.apply(cancelledStillActive), .applied)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .essential)

        let expired = storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000001",
            latest: "1000004",
            productID: ProductID.essentialMonthly,
            kind: .plan(.essential),
            status: .expired,
            eventID: "apple-expired",
            eventTime: now.addingTimeInterval(4000),
            expiresAt: now.addingTimeInterval(-1)
        )
        XCTAssertEqual(reducer.apply(expired), .applied)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .free)
    }

    func testAppleRefundRevocationAndInvalidSignatureDenyAccess() {
        let account = UUID()
        let now = Date()
        var reducer = SBTAuthoritativeEntitlementReducer()

        let invalid = storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000005",
            latest: "1000006",
            productID: ProductID.unlimitedMonthly,
            kind: .plan(.unlimited),
            status: .active,
            eventID: "apple-invalid",
            eventTime: now,
            expiresAt: now.addingTimeInterval(3600),
            isSignatureVerified: false
        )
        XCTAssertEqual(reducer.apply(invalid), .failedVerification)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .free)

        let refunded = storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000007",
            latest: "1000008",
            productID: ProductID.unlimitedMonthly,
            kind: .plan(.unlimited),
            status: .refunded,
            eventID: "apple-refund",
            eventTime: now,
            expiresAt: now.addingTimeInterval(3600),
            revokedAt: now
        )
        XCTAssertEqual(reducer.apply(refunded), .applied)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .free)
    }

    func testGoogleLifecycleStatesAndOneTimeReceiptJarModel() {
        let account = UUID()
        let now = Date()
        var reducer = SBTAuthoritativeEntitlementReducer()

        XCTAssertEqual(reducer.apply(storeEvent(
            accountID: account,
            provider: .googlePlay,
            original: "GPA.essential",
            latest: "GPA.essential.renew1",
            productID: ProductID.essentialMonthly,
            kind: .plan(.essential),
            status: .grace,
            eventID: "google-grace",
            eventTime: now,
            expiresAt: now.addingTimeInterval(3600)
        )), .applied)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .essential)

        XCTAssertEqual(reducer.apply(storeEvent(
            accountID: account,
            provider: .googlePlay,
            original: "GPA.essential",
            latest: "GPA.essential.hold",
            productID: ProductID.essentialMonthly,
            kind: .plan(.essential),
            status: .accountHold,
            eventID: "google-hold",
            eventTime: now.addingTimeInterval(60),
            expiresAt: now.addingTimeInterval(3600)
        )), .applied)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .free)

        XCTAssertEqual(reducer.apply(storeEvent(
            accountID: account,
            provider: .googlePlay,
            original: "GPA.receiptjar",
            latest: "GPA.receiptjar",
            productID: ProductID.receiptJarLifetime,
            kind: .receiptJarLifetime,
            status: .active,
            eventID: "google-receiptjar",
            eventTime: now.addingTimeInterval(120),
            expiresAt: nil
        )), .applied)
        XCTAssertTrue(reducer.resolve(accountID: account, now: now).receiptJarLifetime)
    }

    func testOutOfOrderStoreEventCannotDowngradeNewerState() {
        let account = UUID()
        let now = Date()
        var reducer = SBTAuthoritativeEntitlementReducer()

        let expired = storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000010",
            latest: "1000012",
            productID: ProductID.unlimitedMonthly,
            kind: .plan(.unlimited),
            status: .expired,
            eventID: "newer-expired",
            eventTime: now.addingTimeInterval(100),
            expiresAt: now.addingTimeInterval(-1)
        )
        let olderActive = storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000010",
            latest: "1000011",
            productID: ProductID.unlimitedMonthly,
            kind: .plan(.unlimited),
            status: .active,
            eventID: "older-active",
            eventTime: now,
            expiresAt: now.addingTimeInterval(3600)
        )

        XCTAssertEqual(reducer.apply(expired), .applied)
        XCTAssertEqual(reducer.apply(olderActive), .ignoredOutOfOrder)
        XCTAssertEqual(reducer.resolve(accountID: account, now: now).planTier, .free)
    }

    func testPurchaseOwnershipConflictPreventsSecondAccountClaim() {
        let userA = UUID()
        let userB = UUID()
        let now = Date()
        var reducer = SBTAuthoritativeEntitlementReducer()
        let purchase = storeEvent(
            accountID: userA,
            provider: .googlePlay,
            original: "GPA.conflict",
            latest: "GPA.conflict",
            productID: ProductID.unlimitedMonthly,
            kind: .plan(.unlimited),
            status: .active,
            eventID: "google-user-a",
            eventTime: now,
            expiresAt: now.addingTimeInterval(3600)
        )
        XCTAssertEqual(reducer.apply(purchase), .applied)

        var attemptedClaim = purchase
        attemptedClaim.accountID = userB
        attemptedClaim.eventID = "google-user-b"
        attemptedClaim.eventTime = now.addingTimeInterval(1)

        XCTAssertEqual(reducer.apply(attemptedClaim), .ownershipConflict(existingOwner: userA))
        XCTAssertTrue(reducer.resolve(accountID: userA, now: now).hasConflict)
        XCTAssertEqual(reducer.resolve(accountID: userB, now: now).planTier, .free)
    }

    func testEntitlementPrecedenceUsesHighestActivePlanAndIndependentReceiptJar() {
        let account = UUID()
        let now = Date()
        var reducer = SBTAuthoritativeEntitlementReducer()

        XCTAssertEqual(reducer.apply(storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000020",
            latest: "1000021",
            productID: ProductID.essentialMonthly,
            kind: .plan(.essential),
            status: .active,
            eventID: "apple-essential",
            eventTime: now,
            expiresAt: now.addingTimeInterval(3600)
        )), .applied)
        XCTAssertEqual(reducer.apply(storeEvent(
            accountID: account,
            provider: .googlePlay,
            original: "GPA.unlimited",
            latest: "GPA.unlimited",
            productID: ProductID.unlimitedMonthly,
            kind: .plan(.unlimited),
            status: .active,
            eventID: "google-unlimited",
            eventTime: now.addingTimeInterval(1),
            expiresAt: now.addingTimeInterval(3600)
        )), .applied)
        XCTAssertEqual(reducer.apply(storeEvent(
            accountID: account,
            provider: .appleAppStore,
            original: "1000022",
            latest: "1000022",
            productID: ProductID.receiptJarLifetime,
            kind: .receiptJarLifetime,
            status: .active,
            eventID: "apple-receiptjar",
            eventTime: now.addingTimeInterval(2),
            expiresAt: nil
        )), .applied)

        let resolved = reducer.resolve(accountID: account, now: now)
        XCTAssertEqual(resolved.planTier, .unlimited)
        XCTAssertTrue(resolved.receiptJarLifetime)
        XCTAssertEqual(resolved.sourcePurchaseIDs.count, 3)
    }

    private func storeEvent(
        accountID: UUID,
        provider: SBTBillingProvider,
        original: String,
        latest: String,
        productID: String,
        kind: SBTAccountEntitlementKind,
        status: SBTStoreEntitlementStatus,
        eventID: String,
        eventTime: Date,
        expiresAt: Date?,
        revokedAt: Date? = nil,
        isSignatureVerified: Bool = true
    ) -> SBTVerifiedStoreEvent {
        SBTVerifiedStoreEvent(
            eventID: eventID,
            accountID: accountID,
            provider: provider,
            providerOriginalID: original,
            providerLatestID: latest,
            productID: productID,
            kind: kind,
            status: status,
            eventTime: eventTime,
            verifiedAt: eventTime,
            expiresAt: expiresAt,
            revokedAt: revokedAt,
            environment: "test",
            isSignatureVerified: isSignatureVerified
        )
    }
}
