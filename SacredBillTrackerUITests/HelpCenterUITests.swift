//
//  HelpCenterUITests.swift
//  SacredBillTrackerUITests
//
//  UI verification for the DEBUG-only Learning Center launch route.
//

import XCTest

final class HelpCenterUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "SBT_UI_TEST_OPEN_HELP_CENTER"
        ]
        app.launch()
        dismissSystemAlertsIfNeeded()
        XCTAssertTrue(helpCenterList.waitForExistence(timeout: 20), "Learning Center did not open through the DEBUG-only UI test route.")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testCategoryBrowsingArticleContentAndBackNavigation() throws {
        XCTAssertTrue(app.staticTexts["Sacred Bill Tracker Learning Center"].exists)
        XCTAssertTrue(app.staticTexts["Feature directory"].exists)
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["learningCenterDirectory-faqs-and-troubleshooting"], maxSwipes: 8))
        scrollToTop()
        XCTAssertTrue(app.staticTexts["Getting Started"].exists)

        openArticle(id: "main-navigation", title: "Main app navigation")

        XCTAssertTrue(app.staticTexts["Where to find it"].exists)
        XCTAssertTrue(app.staticTexts["How to use it"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["helpArticleStep-main-navigation-1"].exists)
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["helpArticleStep-main-navigation-6"]))
        captureScreenshot(named: "help-center-main-navigation-article")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(helpCenterList.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["helpCenterArticleRow-main-navigation"], maxSwipes: 8))
    }

    func testSearchResultsAndEmptySearchResults() throws {
        let searchField = helpCenterSearchField()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        searchField.tap()
        searchField.typeText("Receipt")
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["helpCenterArticleRow-receipt-jar"], maxSwipes: 8))
        XCTAssertFalse(app.descendants(matching: .any)["helpCenterArticleRow-main-navigation"].exists)
        captureScreenshot(named: "help-center-search-receipt")

        scrollToTop()
        let visibleSearchField = helpCenterSearchField()
        clearSearchField(visibleSearchField)
        visibleSearchField.typeText("zzzz-no-topic")
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["helpCenterEmptyResults"], maxSwipes: 8))
        XCTAssertTrue(scrollToElement(app.staticTexts["No Help Topics"], maxSwipes: 2))
        captureScreenshot(named: "help-center-empty-search-results")
    }

    func testArticleRelatedNavigationLinkIsPresent() throws {
        searchFor("Receipt")
        openArticle(id: "receipt-jar", title: "Receipt Jar")

        XCTAssertTrue(scrollToElement(app.staticTexts["Limitations"]))
        XCTAssertTrue(scrollToElement(app.staticTexts["Take Me There"]))
        XCTAssertTrue(scrollToReceiptJarLink())
        captureScreenshot(named: "help-center-receipt-jar-article")
    }

    func testFAQSearchAndTroubleshootingArticle() throws {
        searchFor("restore")
        openArticle(id: "faq-upgrade-restore", title: "FAQ: upgrades, restores, and offer codes")

        XCTAssertTrue(app.staticTexts["Where to find it"].exists)
        XCTAssertTrue(app.staticTexts["Access"].exists)
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["helpArticleStep-faq-upgrade-restore-6"]))
        XCTAssertTrue(scrollToElement(app.staticTexts["Take Me There"]))
    }

    func testHelpCenterSupportsLargeDynamicTypeLaunch() throws {
        XCTAssertTrue(helpCenterList.exists)
        XCTAssertTrue(helpCenterSearchField().waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToElement(app.descendants(matching: .any)["helpCenterArticleRow-account-onboarding"], maxSwipes: 8))
        captureScreenshot(named: "help-center-large-dynamic-type")
    }

    private var helpCenterList: XCUIElement {
        app.descendants(matching: .any)["helpCenterList"]
    }

    private func openArticle(id: String, title: String) {
        let row = app.descendants(matching: .any)["helpCenterArticleRow-\(id)"]
        if !row.waitForExistence(timeout: 2) {
            XCTAssertTrue(scrollToElement(row, maxSwipes: 8), "Missing Help Center row for \(id).")
        }
        row.tap()

        let detail = app.descendants(matching: .any)["helpArticleDetail-\(id)"]
        XCTAssertTrue(detail.waitForExistence(timeout: 8), "Missing Help Center article detail for \(id).")
        XCTAssertTrue(app.staticTexts[title].exists)
    }

    private func helpCenterSearchField() -> XCUIElement {
        for _ in 0..<3 {
            let identifiedField = app.descendants(matching: .any)["helpCenterSearchField"]
            if identifiedField.exists {
                return identifiedField
            }

            let labeledField = app.textFields["Search features"]
            if labeledField.exists {
                return labeledField
            }

            helpCenterList.swipeUp()
        }

        return app.descendants(matching: .any)["helpCenterSearchField"]
    }

    private func searchFor(_ text: String) {
        scrollToTop()
        let searchField = helpCenterSearchField()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText(text)
    }

    private func scrollToTop(maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes {
            app.collectionViews.firstMatch.swipeDown()
        }
    }

    @discardableResult
    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 4) -> Bool {
        if element.exists {
            return true
        }

        for _ in 0..<maxSwipes {
            app.collectionViews.firstMatch.swipeUp()
            if element.exists {
                return true
            }
        }

        return element.exists
    }

    private func scrollToReceiptJarLink(maxSwipes: Int = 4) -> Bool {
        for _ in 0...maxSwipes {
            if app.buttons["Open Receipt Jar"].exists || app.staticTexts["Open Receipt Jar"].exists {
                return true
            }
            app.collectionViews.firstMatch.swipeUp()
        }

        return app.buttons["Open Receipt Jar"].exists || app.staticTexts["Open Receipt Jar"].exists
    }

    private func clearSearchField(_ searchField: XCUIElement) {
        guard let value = searchField.value as? String, !value.isEmpty else { return }
        searchField.tap()
        searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }

    private func dismissSystemAlertsIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denyButtons = [
            springboard.buttons["Don’t Allow"],
            springboard.buttons["Don't Allow"],
            springboard.buttons["Not Now"]
        ]

        for button in denyButtons where button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }
    }

    private func captureScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["SBT_UI_SCREENSHOT_DIR"],
              !directory.isEmpty else { return }

        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try screenshot.pngRepresentation.write(to: url, options: .atomic)
        } catch {
            XCTFail("Failed to write screenshot \(name): \(error)")
        }
    }
}
