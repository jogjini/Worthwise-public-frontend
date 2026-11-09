import XCTest

/// App Store screenshots. Run through fastlane snapshot (`screenshots/generate.sh`),
/// which collects every `snapshot(...)` into `screenshots/raw/`.
///
/// The app runs in demo mode (`-UITestDemoData`, Debug only, see `DemoData.swift`):
/// a collection seeded from real scans, the Pro plan, and stored scan results
/// instead of server calls. The plan behind each frame is `screenshots/PLAN.md`.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// 01 and 02: the coin's result, top of the page, then its sold prices.
    func testCoinResult() {
        let app = launch(scanItem: "DemoCoin")
        getValue(app)
        snapshot("01_Value")

        // "Sold Prices" or "Sold Prices, Similar Items"
        scroll(app, bringing: app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sold Prices'")).firstMatch, toY: 100)
        snapshot("02_SoldPrices")
    }

    /// 03: the collection grid.
    func testCollection() {
        let app = launch()
        app.tabBars.buttons["Collection"].tap()
        // The redesign totals firm prices only, and every demo item is a rough
        // guide, so the frame shows the grid: Items/Folders switch at the top.
        let items = app.buttons["Items"]
        XCTAssertTrue(items.waitForExistence(timeout: 10))
        // Thumbnails are written to disk in the background on first launch.
        sleep(2)
        scroll(app, bringing: items, toY: 120)
        snapshot("03_Collection")
    }

    /// 04: correcting a match, on the jug (whose real match is Medium).
    func testCorrection() {
        let app = launch(scanItem: "DemoJug")
        getValue(app)
        app.buttons["Not the right item?"].tap()
        let field = app.textViews.firstMatch.waitForExistence(timeout: 5) ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // A fresh simulator shows the swipe-typing tip over the keyboard once.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 3) { tip.tap() }
        field.typeText("English pottery jug, 1830s")
        sleep(1)
        snapshot("04_Correct")
    }

    /// 05: what you can scan.
    func testCategories() {
        let app = launch()
        let header = app.staticTexts["Photo Guides"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        scroll(app, bringing: header, toY: 120)
        snapshot("05_Categories")
    }

    /// 06: the prices behind the estimate, on the saved Game Boy Advance
    /// (its item screen has no Save bar to scroll under the status bar).
    func testListings() {
        let app = launch()
        app.tabBars.buttons["Collection"].tap()
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Game Boy Advance'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        let header = app.staticTexts["Prices Behind This Estimate"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        sleep(1)
        scroll(app, bringing: header, toY: 112)
        snapshot("06_Listings")
    }

    /// Paywall, for App Store Connect's subscription review screenshot (not a
    /// marketing frame). Real launch, not demo mode: demo mode is Pro, and the
    /// paywall is what a free user sees. Prices come from RevenueCat.
    func testPaywall() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-has_seen_onboarding", "YES", "-ai_consent_granted", "YES", "-app_theme", "light"]
        app.launch()
        let pill = app.buttons.matching(NSPredicate(format: "label == 'Free plan' OR label CONTAINS 'free scan'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        pill.tap()
        let buy = app.buttons.matching(NSPredicate(format: "label == 'Start free trial' OR label == 'Continue'")).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 15))
        sleep(4) // prices load from RevenueCat
        snapshot("07_Paywall_Yearly") // selected by default
        for plan in ["Monthly", "Weekly"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", plan)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            sleep(1)
            snapshot("07_Paywall_\(plan)")
        }
    }

    // MARK: - Helpers

    private func launch(scanItem: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += [
            "-UITestDemoData",
            "-has_seen_onboarding", "YES",
            "-ai_consent_granted", "YES",
            "-app_theme", "light",
        ]
        if let scanItem {
            app.launchArguments += ["-UITestOpenScan", "-UITestScanItem", scanItem, "-UITestScanDelay", "1"]
        }
        app.launch()
        return app
    }

    /// From the review screen to the result.
    private func getValue(_ app: XCUIApplication) {
        let button = app.buttons["Get value"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["Save to collection"].waitForExistence(timeout: 20))
        sleep(1) // let the result's fade-in finish
    }

    /// Drags the page until `element`'s top edge sits at `targetY` points (or
    /// the page can't scroll further). Slow drags with a hold at the end, so the
    /// page stops where it's put. A drag loses a few points before the scroll
    /// starts, so each drag adds what the last one lost.
    private func scroll(_ app: XCUIApplication, bringing element: XCUIElement, toY targetY: CGFloat) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        var slack: CGFloat = 0
        var stuck = 0
        for _ in 0..<15 {
            let before = element.frame.minY
            let distance = before - targetY
            if abs(distance) < 4 { return }
            let request = max(min(distance + slack, 450), -450)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: request > 0 ? 650 : 200))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -request)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
            let moved = before - element.frame.minY
            if abs(moved) < 1 {
                stuck += 1
                if stuck >= 2 { return } // end of the page
                slack += distance > 0 ? 15 : -15
            } else {
                stuck = 0
                if (moved > 0) == (request > 0) { slack = request - moved }
            }
        }
        XCTFail("Couldn't scroll \(element) to y \(targetY); it's at \(element.frame.minY)")
    }
}
