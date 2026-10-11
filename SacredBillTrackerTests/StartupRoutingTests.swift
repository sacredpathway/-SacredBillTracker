//
//  StartupRoutingTests.swift
//  SacredBillTrackerTests
//
//  Regression coverage for the cold-launch blank-screen/auth-restore window.
//

import XCTest
import SwiftUI
@testable import SacredBillTracker

@MainActor
final class StartupRoutingTests: XCTestCase {
    private let updateURL = URL(string: "https://apps.apple.com/app/id6762890363")!

    func test_returningUserLaunchesToMainAppAfterSessionRestores() {
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .allowed, hasResolvedSession: true, isSignedIn: true),
            .mainApp
        )
    }

    func test_genuineFirstLaunchRoutesToVisibleAuthGateAfterSessionResolution() {
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .allowed, hasResolvedSession: true, isSignedIn: false),
            .signedOut
        )
    }

    func test_unresolvedStartupShowsLoadingNotBlankOrSignedOut() {
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .allowed, hasResolvedSession: false, isSignedIn: false),
            .loading
        )
    }

    func test_restoredOnboardingCompleteStateKeepsMainAppRoute() {
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .optionalUpdate(latestBuild: 60), hasResolvedSession: true, isSignedIn: true),
            .mainApp
        )
    }

    func test_authenticationRestorationCompletionTransitionsToCorrectRoutes() {
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .allowed, hasResolvedSession: false, isSignedIn: false),
            .loading
        )
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .allowed, hasResolvedSession: true, isSignedIn: true),
            .mainApp
        )
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .allowed, hasResolvedSession: true, isSignedIn: false),
            .signedOut
        )
    }

    func test_initializationFailureResolvesToVisibleRecoverableAuthSurface() {
        XCTAssertEqual(
            RootStartupRouter.route(gateState: .allowed, hasResolvedSession: true, isSignedIn: false),
            .signedOut
        )
    }

    func test_entitlementRefreshDuringStartupDoesNotBlockMainAppRoute() {
        XCTAssertEqual(
            RootStartupRouter.route(
                gateState: .allowed,
                hasResolvedSession: true,
                isSignedIn: true,
                isEntitlementRefreshInFlight: true
            ),
            .mainApp
        )
    }

    func test_forceUpdateStillTakesPrecedence() {
        XCTAssertEqual(
            RootStartupRouter.route(
                gateState: .blocked(message: "Update required", appStoreURL: updateURL),
                hasResolvedSession: false,
                isSignedIn: false
            ),
            .forceUpdate(message: "Update required", appStoreURL: updateURL)
        )
    }
}

final class ThemeContrastTests: XCTestCase {
    func test_brandTextColorsMeetAAOnLightAndDarkSystemSurfaces() {
        let colorPairs: [(name: String, foreground: Color, background: Color)] = [
            ("gold text on app background", .appAccentText, .appBackground),
            ("gold text on card", .appAccentText, .appCardSurface),
            ("household text on app background", .appHouseholdText, .appBackground),
            ("household text on card", .appHouseholdText, .appCardSurface),
            ("business text on app background", .appBusinessText, .appBackground),
            ("business text on card", .appBusinessText, .appCardSurface),
            ("lime text on app background", .appLimeText, .appBackground),
            ("lime text on card", .appLimeText, .appCardSurface),
            ("danger text on app background", .appDangerText, .appBackground),
            ("danger text on card", .appDangerText, .appCardSurface)
        ]

        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for pair in colorPairs {
                let ratio = contrastRatio(pair.foreground, pair.background, traits: traits)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "\(pair.name) should meet WCAG AA in \(style == .dark ? "dark" : "light") mode; got \(ratio)"
                )
            }
        }
    }

    func test_onGoldTextMeetsAAOnSolidGoldFill() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let ratio = contrastRatio(.appOnGold, .appAccent, traits: traits)
            XCTAssertGreaterThanOrEqual(ratio, 4.5)
        }
    }

    private func contrastRatio(_ foreground: Color, _ background: Color, traits: UITraitCollection) -> CGFloat {
        let fg = UIColor(foreground).resolvedColor(with: traits).relativeLuminance
        let bg = UIColor(background).resolvedColor(with: traits).relativeLuminance
        let lighter = max(fg, bg)
        let darker = min(fg, bg)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

private extension UIColor {
    var relativeLuminance: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func convert(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * convert(red) + 0.7152 * convert(green) + 0.0722 * convert(blue)
    }
}
