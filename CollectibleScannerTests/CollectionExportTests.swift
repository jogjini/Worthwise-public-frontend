import XCTest
@testable import CollectibleScanner

final class CollectionExportTests: XCTestCase {

    // MARK: Escaping

    func testCSVEscaping() {
        XCTAssertEqual(CollectionStore.csvEscape("plain"), "plain")
        XCTAssertEqual(CollectionStore.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(CollectionStore.csvEscape("she said \"hi\""), "\"she said \"\"hi\"\"\"")
        XCTAssertEqual(CollectionStore.csvEscape("line1\nline2"), "\"line1\nline2\"")
    }

    func testCSVEscapingWithSemicolonSeparator() {
        XCTAssertEqual(CollectionStore.csvEscape("plain", separator: ";"), "plain")
        XCTAssertEqual(CollectionStore.csvEscape("a;b", separator: ";"), "\"a;b\"")
        // A decimal comma is not the separator here, so amounts stay unquoted.
        XCTAssertEqual(CollectionStore.csvEscape("12,50", separator: ";"), "12,50")
        XCTAssertEqual(CollectionStore.csvEscape("say \"hi\"; bye", separator: ";"), "\"say \"\"hi\"\"; bye\"")
        XCTAssertEqual(CollectionStore.csvEscape("a\r\nb", separator: ";"), "\"a\r\nb\"")
    }

    // MARK: Locale

    func testSeparatorFollowsTheLocaleDecimalMark() {
        XCTAssertEqual(CollectionStore.csvSeparator(for: Locale(identifier: "en_US")), ",")
        XCTAssertEqual(CollectionStore.csvSeparator(for: Locale(identifier: "fr_BE")), ";")
        XCTAssertEqual(CollectionStore.csvSeparator(for: Locale(identifier: "de_DE")), ";")
    }

    func testNumbersUseTheLocaleDecimalMarkWithoutGrouping() {
        XCTAssertEqual(CollectionStore.csvNumber(1234.5, digits: 2, locale: Locale(identifier: "en_US")), "1234.50")
        XCTAssertEqual(CollectionStore.csvNumber(1234.5, digits: 2, locale: Locale(identifier: "fr_BE")), "1234,50")
        XCTAssertEqual(CollectionStore.csvNumber(2000, digits: 0, locale: Locale(identifier: "en_US")), "2000")
    }

    // MARK: Whole file

    func testUSFileHasHeaderColumnsAndUSDAmounts() {
        let item = makeItem(title: "Base Set Charizard, Unlimited", low: 310, high: 420, priceBasis: "sold", evidenceCount: 18, mid: 365)
        let folder = makeFolder("Cards", items: [item.id])
        let csv = CollectionStore.csv(items: [item], sets: [folder], locale: Locale(identifier: "en_US"), currencyCode: "USD")
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            lines[0],
            "Title,Category,Brand,Year,Set,Number,Condition,Folder,Estimate low (USD),Estimate high (USD),Best estimate (USD),Value level,Evidence,Sold median (USD),Sales,Prices checked,Notes"
        )
        let row = lines[1]
        XCTAssertTrue(row.hasPrefix("\"Base Set Charizard, Unlimited\",Trading Card,Pokémon,1999,Base Set,4/102,"), row)
        XCTAssertTrue(row.contains(",Cards,310.00,420.00,365.00,Strong,Sold prices,"), row)
    }

    func testBelgianFileUsesSemicolonsDecimalCommaAndTheDisplayCurrency() throws {
        let item = makeItem(title: "Five guineas; 1668", low: 100, high: 300, priceBasis: "guide", evidenceCount: 4, mid: 200)
        let csv = CollectionStore.csv(items: [item], sets: [], locale: Locale(identifier: "fr_BE"), currencyCode: "EUR")
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].contains("Estimate low (EUR);Estimate high (EUR);Best estimate (EUR)"), lines[0])
        XCTAssertTrue(lines[0].hasPrefix("Title;Category;"), lines[0])
        let row = lines[1]
        // The separator inside the title is quoted.
        XCTAssertTrue(row.hasPrefix("\"Five guineas; 1668\";"), row)
        let rate = try XCTUnwrap(DisplayCurrency.perUSD("EUR"))
        let expectedLow = CollectionStore.csvNumber(100 * rate, digits: 2, locale: Locale(identifier: "fr_BE"))
        XCTAssertTrue(expectedLow.contains(","), expectedLow)
        XCTAssertTrue(row.contains(";\(expectedLow);"), row)
    }

    func testRoughAndNoPriceItemsSayTheirLevel() {
        let rough = makeItem(title: "Old watch", low: 100, high: 2_000, priceBasis: "estimate", evidenceCount: nil, mid: nil)
        let csv = CollectionStore.csv(items: [rough], sets: [], locale: Locale(identifier: "en_US"), currencyCode: "USD")
        let row = csv.components(separatedBy: "\n")[1]
        XCTAssertTrue(row.contains(",Rough guide,"), row)
        // No best estimate below A/B.
        XCTAssertTrue(row.contains(",100.00,2000.00,,Rough guide,"), row)
    }

    func testNotSureConditionIsExportedAsNotSet() {
        var item = makeItem(title: "Coin", low: 10, high: 20, priceBasis: "sold", evidenceCount: 5, mid: 15)
        item.conditionSet = false
        let csv = CollectionStore.csv(items: [item], sets: [], locale: Locale(identifier: "en_US"), currencyCode: "USD")
        XCTAssertTrue(csv.contains(",Not set,"), csv)
    }

    func testFileNameCarriesTheDate() {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 14
        components.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        XCTAssertEqual(CollectionStore.csvFileName(for: date), "Worthwise collection 2026-10-14.csv")
    }

    // MARK: Totals and sort (04 §4.4)

    func testTotalsCountOnlyFairAndStrongItems() {
        let strong = makeItem(title: "A", low: 310, high: 420, priceBasis: "sold", evidenceCount: 18, mid: 365)
        let rough = makeItem(title: "C", low: 100, high: 2_000, priceBasis: "estimate", evidenceCount: nil, mid: nil)
        let totals = CollectionStore.totals(for: [strong, rough])
        XCTAssertEqual(strong.assessment.level, .strong)
        XCTAssertEqual(rough.assessment.level, .rough)
        XCTAssertEqual(totals.low, 310, accuracy: 0.001)
        XCTAssertEqual(totals.high, 420, accuracy: 0.001)
        XCTAssertEqual(totals.counted, 1)
        XCTAssertEqual(totals.uncounted, 1)
    }

    func testHighestValueKeepsRoughItemsBelowCountedOnes() {
        let small = makeItem(title: "Small", low: 10, high: 20, priceBasis: "sold", evidenceCount: 5, mid: 15)
        let big = makeItem(title: "Big", low: 310, high: 420, priceBasis: "sold", evidenceCount: 18, mid: 365)
        let roughButHigh = makeItem(title: "Rough", low: 1_000, high: 9_000, priceBasis: "estimate", evidenceCount: nil, mid: nil)
        let order = CollectionStore.sortByValue([roughButHigh, small, big]).map(\.title)
        XCTAssertEqual(order, ["Big", "Small", "Rough"])
    }

    // MARK: Fixtures

    private func makeItem(title: String, low: Double, high: Double, priceBasis: String?, evidenceCount: Int?, mid: Double?) -> SavedCollectible {
        let profile = CollectibleProfile(
            title: title,
            probableCategory: .tradingCard,
            brand: "Pokémon",
            year: 1999,
            modelNumber: "4/102",
            confidence: 0.95,
            attributes: [ItemAttribute(label: "Set", value: "Base Set")]
        )
        let estimate = ValueEstimate(
            low: low,
            high: high,
            confidence: 0.8,
            query: title,
            comparables: [],
            basis: priceBasis == "estimate" ? .aiEstimate : .marketListings,
            mid: mid,
            priceBasis: priceBasis,
            evidenceCount: evidenceCount
        )
        return SavedCollectible(profile: profile, estimate: estimate, condition: .good)
    }

    private func makeFolder(_ name: String, items: [UUID]) -> CollectibleSet {
        var folder = CollectibleSet(name: name)
        folder.itemIDs = items
        return folder
    }
}
