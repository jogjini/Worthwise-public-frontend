import XCTest
@testable import CollectibleScanner

final class CollectibleAnalyzerTests: XCTestCase {

    func testDetectsCategoryBrandAndYear() {
        let payload = ScanPayload(textLines: ["Charizard Holo", "Pokemon 1999", "PSA graded"], barcodes: [])
        let profile = CollectibleAnalyzer().analyze(payload, supplementalInfo: nil)
        XCTAssertEqual(profile.probableCategory, .tradingCard)
        XCTAssertEqual(profile.brand, "Pokemon")
        XCTAssertEqual(profile.year, 1999)
    }

    func testUnknownWhenNoSignals() {
        let payload = ScanPayload(textLines: ["zzz qqq"], barcodes: [])
        let profile = CollectibleAnalyzer().analyze(payload, supplementalInfo: nil)
        XCTAssertEqual(profile.probableCategory, .unknown)
    }
}

/// The server's `sold` block (Sold prices section) and saved items that keep it.
final class SoldSummaryDecodingTests: XCTestCase {

    private let response = """
    {"valueLow": 250, "valueHigh": 420, "valueConfidence": 0.8, "query": "Charizard",
     "comparables": [{"source": "eBay US", "price": 377, "note": "Charizard 4/102", "priceType": "asking"}],
     "sold": {"count": 3, "average": 290.5, "median": 285, "low": 260, "high": 330, "currency": "USD",
              "windowDays": 90, "sources": ["eBay", "TCGplayer"], "bestOfferCount": 1,
              "bestOfferExcluded": false, "ebayFloorExcluded": false, "match": "exact",
              "sales": [{"date": "2026-10-10", "price": 285, "currency": "USD", "title": "Charizard 4/102 Base Set",
                         "url": "https://www.ebay.com/itm/1", "source": "eBay", "bestOffer": true, "condition": null},
                        {"date": "2026-10-02", "price": 0, "title": "bad row", "source": "eBay"}],
              "salesLocked": 0}}
    """

    func testDecodesSoldBlock() throws {
        let estimate = try JSONDecoder().decode(ValueEstimate.self, from: Data(response.utf8))
        let sold = try XCTUnwrap(estimate.sold)
        XCTAssertEqual(sold.count, 3)
        XCTAssertEqual(sold.median, 285)
        XCTAssertEqual(sold.average, 290.5)
        XCTAssertTrue(sold.isExact)
        XCTAssertEqual(sold.sales.count, 1, "zero-price rows are dropped")
        XCTAssertEqual(sold.sales.first?.bestOffer, true)
        XCTAssertNotNil(sold.sales.first?.day)
        XCTAssertEqual(estimate.comparables.count, 1)
    }

    func testOlderServerHasNoSoldBlock() throws {
        let json = #"{"valueLow": 1, "valueHigh": 2, "valueConfidence": 0.5, "query": "x", "comparables": []}"#
        let estimate = try JSONDecoder().decode(ValueEstimate.self, from: Data(json.utf8))
        XCTAssertNil(estimate.sold)
    }

    func testFreePlanBlockHasFiguresButNoSales() throws {
        let json = #"{"valueLow": 1, "valueHigh": 2, "sold": {"count": 12, "median": 40, "average": 42, "sales": [], "salesLocked": 12, "match": "similar"}}"#
        let sold = try XCTUnwrap(try JSONDecoder().decode(ValueEstimate.self, from: Data(json.utf8)).sold)
        XCTAssertEqual(sold.salesLocked, 12)
        XCTAssertTrue(sold.sales.isEmpty)
        XCTAssertFalse(sold.isExact)
        XCTAssertEqual(sold.windowDays, 90)
    }

    func testUnavailableBlock() throws {
        let json = #"{"valueLow": 1, "valueHigh": 2, "sold": {"count": 0, "unavailable": true, "windowDays": 90, "sales": []}}"#
        let sold = try XCTUnwrap(try JSONDecoder().decode(ValueEstimate.self, from: Data(json.utf8)).sold)
        XCTAssertTrue(sold.unavailable)
        XCTAssertEqual(sold.count, 0)
    }

    func testSoldSurvivesASaveRoundTrip() throws {
        let sold = try XCTUnwrap(try JSONDecoder().decode(ValueEstimate.self, from: Data(response.utf8)).sold)
        let again = try JSONDecoder().decode(SoldSummary.self, from: JSONEncoder().encode(sold))
        XCTAssertEqual(again, sold)
    }
}

/// Settings → Currency: USD prices converted with the rates a scan brings.
final class DisplayCurrencyTests: XCTestCase {

    override func tearDown() {
        // Put the shipped rates back for other tests.
        DisplayCurrency.store(perUSD: DisplayCurrency.builtInPerUSD, date: DisplayCurrency.builtInDate)
        UserDefaults.standard.removeObject(forKey: DisplayCurrency.codeKey)
        super.tearDown()
    }

    func testConvertsWithStoredRates() {
        DisplayCurrency.store(perUSD: ["USD": 1, "EUR": 0.8, "GBP": 0.75], date: "2026-10-09")
        XCTAssertEqual(DisplayCurrency.fromUSD(100, to: "EUR").amount, 80, accuracy: 0.0001)
        XCTAssertEqual(DisplayCurrency.fromUSD(100, to: "EUR").code, "EUR")
        XCTAssertEqual(DisplayCurrency.ratesDate, "2026-10-09")
        // Missing from the stored block: the built-in rate is used.
        XCTAssertEqual(DisplayCurrency.fromUSD(100, to: "JPY").code, "JPY")
    }

    func testUSDAndUnknownStayUSD() {
        XCTAssertEqual(DisplayCurrency.fromUSD(42, to: "USD").amount, 42)
        XCTAssertEqual(DisplayCurrency.fromUSD(42, to: "XYZ").code, "USD")
    }

    func testBrokenRatesAreIgnored() {
        DisplayCurrency.store(perUSD: ["EUR": 0.8], date: "2026-10-09")
        DisplayCurrency.store(perUSD: ["GBP": 0.75], date: "2030-01-01") // no EUR: ignored
        XCTAssertEqual(DisplayCurrency.fromUSD(10, to: "EUR").amount, 8, accuracy: 0.0001)
        XCTAssertEqual(DisplayCurrency.ratesDate, "2026-10-09")
    }

    func testMoneyUsesTheChosenCurrency() {
        UserDefaults.standard.set("EUR", forKey: DisplayCurrency.codeKey)
        DisplayCurrency.store(perUSD: ["EUR": 0.5], date: "2026-10-09")
        let text = WW.money(100)
        XCTAssertTrue(text.contains("50"), text)
        XCTAssertTrue(text.contains("€"), text)
        // Amounts already in another currency are not converted again.
        XCTAssertTrue(WW.money(100, code: "GBP").contains("100"))
    }
}

/// 04 §4.3: value levels, calibrated on the 12 Oct simulator run.
final class ValueAssessmentTests: XCTestCase {

    private func inputs(
        low: Double,
        high: Double,
        match: Double = 0.9,
        valueConfidence: Double = 0.7,
        basis: ValuationBasis = .marketListings,
        priceBasis: String? = "sold",
        evidenceCount: Int? = 5,
        exact: Bool = true,
        sold: SoldSummary? = nil,
        title: String = "Base Set Charizard 4/102",
        category: CollectibleCategory = .tradingCard,
        comparables: [MarketComparable] = [],
        lockedCount: Int = 0,
        valueMid: Double? = nil,
        notCollectible: Bool = false,
        analysisOff: Bool = false
    ) -> ValueInputs {
        ValueInputs(
            title: title,
            category: category,
            matchConfidence: match,
            low: low,
            high: high,
            valueConfidence: valueConfidence,
            basis: basis,
            comparablesAreExact: exact,
            comparables: comparables,
            lockedCount: lockedCount,
            priceSummary: nil,
            priceBasis: priceBasis,
            evidenceCount: evidenceCount,
            valueMid: valueMid,
            sold: sold,
            notCollectible: notCollectible,
            analysisOff: analysisOff
        )
    }

    // MARK: Calibration rows (04 §4.3)

    func testPalpitoadIsFairBecauseSalesAreHigher() {
        let sold = SoldSummary(count: 12, median: 0.48)
        let va = ValueAssessment(inputs(low: 0.30, high: 0.39, match: 0.92, priceBasis: "guide", evidenceCount: 6, sold: sold))
        XCTAssertEqual(va.level, .fair)
        XCTAssertEqual(va.caveats.first, .salesHigher(medianUSD: 0.48, count: 12))
        XCTAssertNil(va.best, "a sold median outside the range is never the best estimate")
        XCTAssertTrue(va.notes.contains(.lowValue))
        XCTAssertTrue(va.countsInTotal)
    }

    func testJordan4IsStrongWithCloseMatchAndGuidePrices() {
        let va = ValueAssessment(inputs(low: 200, high: 340, match: 0.9, priceBasis: "guide", evidenceCount: 4, valueMid: 270))
        XCTAssertEqual(va.level, .strong)
        XCTAssertEqual(va.best, BestEstimate(amountUSD: 270, source: .engineMid))
        XCTAssertTrue(va.isGreatFind)
    }

    func testPS1ControllerIsFair() {
        let va = ValueAssessment(inputs(low: 20, high: 88, match: 0.85, priceBasis: "asking", evidenceCount: 9))
        XCTAssertEqual(va.level, .fair)
        XCTAssertEqual(va.evidence, .asking)
        XCTAssertEqual(va.evidenceCount, 9)
    }

    func testFiveGuineasIsRoughAtRatioExactlyTwenty() {
        let va = ValueAssessment(inputs(low: 1_000, high: 20_000, match: 0.7, basis: .aiEstimate,
                                        priceBasis: "estimate", evidenceCount: nil, category: .coin))
        XCTAssertEqual(va.ratio, 20, accuracy: 0.0001)
        XCTAssertEqual(va.level, .rough, "ratio 20 is not > 20, and an AI estimate is a rough guide")
        XCTAssertTrue(va.caveats.contains(.wideRange))
        XCTAssertTrue(va.caveats.contains(.aiEstimate))
        XCTAssertTrue(va.notes.contains(.notAnAppraisal))
        XCTAssertTrue(va.notes.contains(.highValue))
        XCTAssertFalse(va.countsInTotal)
        XCTAssertNil(va.sortValueUSD)
        XCTAssertEqual(va.roughWord, "Wide range")
    }

    func testRolexIsTooWide() {
        let va = ValueAssessment(inputs(low: 112, high: 25_054, match: 0.8, priceBasis: "asking", category: .watch))
        XCTAssertEqual(va.level, .noPrice)
        XCTAssertEqual(va.noPriceReason, .tooWide)
        XCTAssertTrue(va.notes.contains(.highValue))
        XCTAssertNil(va.evidence)
        XCTAssertNil(va.evidenceText)
        XCTAssertNil(va.best)
        XCTAssertTrue(va.caveats.isEmpty)
        XCTAssertFalse(va.countsInTotal)
    }

    func testLandscapeIsSoftNotCollectible() {
        let va = ValueAssessment(inputs(low: 20, high: 60, match: 0.6, basis: .aiEstimate, priceBasis: nil,
                                        title: "Photograph of a mountain landscape at sunset", category: .unknown))
        XCTAssertEqual(va.level, .noPrice)
        XCTAssertEqual(va.noPriceReason, .notCollectible(confirmed: false))
        XCTAssertEqual(va.noPriceReason?.showsRoughRange, true)
    }

    func testVintageLandscapePostcardIsNotFlagged() {
        let va = ValueAssessment(inputs(low: 5, high: 15, match: 0.6, basis: .aiEstimate, priceBasis: nil,
                                        title: "Vintage postcard of a landscape", category: .unknown))
        XCTAssertNotEqual(va.level, .noPrice)
    }

    /// 09 I8: collected historical photographs are not "a person".
    func testHistoricalPhotographsAreNotFlagged() {
        let titles: [String] = [
            "Tintype portrait of a soldier",
            "Daguerreotype portrait of a woman",
            "Ambrotype portrait of a child",
            "Photo album with portrait of a family",
        ]
        for title in titles {
            let va = ValueAssessment(inputs(low: 40, high: 120, match: 0.6, basis: .aiEstimate, priceBasis: nil,
                                            title: title, category: .unknown))
            XCTAssertNotEqual(va.level, .noPrice, title)
        }
    }

    func testServerVerdictIsConfirmedNotCollectible() {
        let va = ValueAssessment(inputs(low: 20, high: 30, notCollectible: true))
        XCTAssertEqual(va.noPriceReason, .notCollectible(confirmed: true))
        XCTAssertEqual(va.noPriceReason?.showsRoughRange, false)
    }

    // MARK: Edges

    func testLowZeroUsesTheRatioFloor() {
        let wide = ValueAssessment(inputs(low: 0, high: 15))
        XCTAssertEqual(wide.ratio, 30, accuracy: 0.0001)
        XCTAssertEqual(wide.noPriceReason, .tooWide)
        let cheap = ValueAssessment(inputs(low: 0, high: 2))
        XCTAssertEqual(cheap.ratio, 4, accuracy: 0.0001)
        XCTAssertNotEqual(cheap.level, .noPrice)
    }

    func testHighZeroIsNoValue() {
        let va = ValueAssessment(inputs(low: 0, high: 0))
        XCTAssertEqual(va.level, .noPrice)
        XCTAssertEqual(va.noPriceReason, .noValue)
    }

    func testRatioExactlyFiveIsFairAndJustAboveIsRough() {
        XCTAssertEqual(ValueAssessment(inputs(low: 10, high: 50, priceBasis: "asking")).level, .fair)
        XCTAssertEqual(ValueAssessment(inputs(low: 10, high: 50.01, priceBasis: "asking")).level, .rough)
    }

    func testRatioExactlyTwoAndAHalfIsStrong() {
        XCTAssertEqual(ValueAssessment(inputs(low: 100, high: 250)).level, .strong)
        XCTAssertEqual(ValueAssessment(inputs(low: 100, high: 250.01)).level, .fair)
    }

    func testSoldMedianBelowTheRangeIsSalesLower() {
        let sold = SoldSummary(count: 5, median: 80)
        let va = ValueAssessment(inputs(low: 100, high: 150, sold: sold))
        XCTAssertEqual(va.level, .fair)
        XCTAssertEqual(va.caveats.first, .salesLower(medianUSD: 80, count: 5))
    }

    func testSoldMedianInsideTheRangeIsTheBestEstimate() {
        let sold = SoldSummary(count: 18, median: 365, windowDays: 90)
        let va = ValueAssessment(inputs(low: 310, high: 420, evidenceCount: 22, sold: sold, valueMid: 340))
        XCTAssertEqual(va.level, .strong)
        XCTAssertEqual(va.best, BestEstimate(amountUSD: 365, source: .soldMedian(count: 18, windowDays: 90)))
        XCTAssertEqual(va.sortValueUSD, 365)
    }

    func testSimilarSalesAreNotUsable() {
        let similar = SoldSummary(count: 9, median: 120, match: "similar")
        XCTAssertNil(ValueAssessment.usableSold(similar))
        let tooFew = SoldSummary(count: 2, median: 120)
        XCTAssertNil(ValueAssessment.usableSold(tooFew))
        let unavailable = SoldSummary(count: 9, median: 120, unavailable: true)
        XCTAssertNil(ValueAssessment.usableSold(unavailable))
    }

    func testWeakEngineConfidenceIsRough() {
        XCTAssertEqual(ValueAssessment(inputs(low: 100, high: 150, valueConfidence: 0.40)).level, .rough)
    }

    func testUnsureMatchIsRough() {
        let va = ValueAssessment(inputs(low: 100, high: 150, match: 0.5))
        XCTAssertEqual(va.level, .rough)
        XCTAssertEqual(va.caveats, [.unsureMatch])
        XCTAssertEqual(va.roughWord, "Unsure match")
    }

    func testOpenEndedItemIsRoughWithSimilarItems() {
        let va = ValueAssessment(inputs(low: 100, high: 150, basis: .attributesOnly, priceBasis: "asking"))
        XCTAssertEqual(va.level, .rough)
        XCTAssertFalse(va.isExact)
        XCTAssertTrue(va.caveats.contains(.similarItems))
    }

    func testOnDeviceResults() {
        let off = ValueAssessment(inputs(low: 5, high: 50, basis: .offlineEstimate, priceBasis: nil, analysisOff: true))
        XCTAssertEqual(off.noPriceReason, .onDevice(analysisOff: true))
        let legacy = ValueAssessment(inputs(low: 5, high: 50, basis: .offlineEstimate, priceBasis: nil))
        XCTAssertEqual(legacy.noPriceReason, .onDevice(analysisOff: false))
    }

    func testGreatFindNeedsFifty() {
        XCTAssertFalse(ValueAssessment(inputs(low: 20, high: 40)).isGreatFind)
        XCTAssertTrue(ValueAssessment(inputs(low: 50, high: 100)).isGreatFind)
        XCTAssertEqual(ValueAssessment.T.greatFindUSD, 50)
    }

    // MARK: Match and evidence vocabulary

    func testMatchThresholds() {
        XCTAssertEqual(MatchStrength(confidence: 0.80), .close)
        XCTAssertEqual(MatchStrength(confidence: 0.7999), .possible)
        XCTAssertEqual(MatchStrength(confidence: 0.55), .possible)
        XCTAssertEqual(MatchStrength(confidence: 0.5499), .unsure)
        XCTAssertEqual(MatchStrength.close.filledSegments, 3)
        XCTAssertEqual(MatchStrength.unsure.label, "Unsure match")
    }

    func testEvidenceKindFromPriceBasisAndFallbacks() {
        XCTAssertEqual(EvidenceKind(priceBasis: "sold"), .sold)
        XCTAssertEqual(EvidenceKind(priceBasis: " Estimate "), .aiEstimate)
        XCTAssertNil(EvidenceKind(priceBasis: "mystery"))

        let comps = [
            MarketComparable(source: "eBay", price: 40, note: "", priceType: .asking),
            MarketComparable(source: "TCGplayer", price: 35, note: "", priceType: .guide),
        ]
        XCTAssertEqual(ValueAssessment.evidenceKind(for: inputs(low: 30, high: 45, priceBasis: nil, comparables: comps)), .guide)
        XCTAssertEqual(ValueAssessment.evidenceKind(for: inputs(low: 30, high: 45, basis: .aiEstimate, priceBasis: nil)), .aiEstimate)
        XCTAssertEqual(ValueAssessment.evidenceKind(for: inputs(low: 30, high: 45, priceBasis: nil)), .asking)
        XCTAssertEqual(ValueAssessment.evidenceKind(for: inputs(low: 30, high: 45, basis: .attributesOnly, priceBasis: nil)), .aiEstimate)
    }

    func testOneEvidenceCount() {
        let comps = [MarketComparable(source: "eBay", price: 40, note: "")]
        XCTAssertEqual(ValueAssessment.evidenceCount(for: inputs(low: 30, high: 45, evidenceCount: 13, comparables: comps, lockedCount: 12)), 13)
        XCTAssertEqual(ValueAssessment.evidenceCount(for: inputs(low: 30, high: 45, evidenceCount: nil, comparables: comps)), 1)
        XCTAssertEqual(ValueAssessment.evidenceCount(for: inputs(low: 30, high: 45, evidenceCount: nil, lockedCount: 12)), 12)
        XCTAssertNil(ValueAssessment.evidenceCount(for: inputs(low: 30, high: 45, evidenceCount: 0)))
    }

    func testNiceCeilingRoundsUp() {
        XCTAssertEqual(WW.niceCeiling(8.92), 10, accuracy: 0.0001)
        XCTAssertEqual(WW.niceCeiling(10), 10, accuracy: 0.0001)
        XCTAssertEqual(WW.niceCeiling(1582.5), 2000, accuracy: 0.0001)
        XCTAssertEqual(WW.niceCeiling(0.3), 0.5, accuracy: 0.0001)
        XCTAssertEqual(WW.niceCeiling(0), 0, accuracy: 0.0001)
    }
}

/// New server keys (04 coordinator note) and build-2 collection files.
final class RedesignDecodingTests: XCTestCase {

    func testDecodesPriceEngineFields() throws {
        let json = #"""
        {"title": "Charizard", "category": "Trading Card", "confidence": 0.9,
         "valueLow": 310, "valueHigh": 420, "valueConfidence": 0.8, "query": "Charizard", "comparables": [],
         "valueMid": 365, "priceBasis": "sold", "evidenceCount": 18,
         "priceSummary": "From 14 sold prices and 4 listings",
         "notCollectible": false, "candidates": [{"title": "Charizard 4/102", "confidence": 0.7, "detail": "Base Set"}]}
        """#
        let data = Data(json.utf8)
        let estimate = try JSONDecoder().decode(ValueEstimate.self, from: data)
        XCTAssertEqual(estimate.mid, 365)
        XCTAssertEqual(estimate.priceBasis, "sold")
        XCTAssertEqual(estimate.evidenceCount, 18)
        let profile = try JSONDecoder().decode(CollectibleProfile.self, from: data)
        XCTAssertFalse(profile.notCollectible)
        XCTAssertEqual(profile.candidates.first?.title, "Charizard 4/102")
    }

    func testOlderServerHasNoNewFields() throws {
        let json = #"{"title": "x", "confidence": 0.5, "valueLow": 1, "valueHigh": 2, "valueConfidence": 0.5, "query": "x", "comparables": []}"#
        let data = Data(json.utf8)
        let estimate = try JSONDecoder().decode(ValueEstimate.self, from: data)
        XCTAssertNil(estimate.mid)
        XCTAssertNil(estimate.priceBasis)
        XCTAssertNil(estimate.evidenceCount)
        let profile = try JSONDecoder().decode(CollectibleProfile.self, from: data)
        XCTAssertFalse(profile.notCollectible)
        XCTAssertTrue(profile.candidates.isEmpty)
    }

    /// A record as build 2 wrote it: none of the redesign fields.
    private let build2Record = #"""
    {"id": "6F1C2A8E-1D2B-4C3D-9E8F-0A1B2C3D4E5F", "savedAt": "2026-10-06T10:00:00Z", "condition": "Good",
     "title": "Palpitoad 23/101", "probableCategory": "Trading Card", "detectedText": [],
     "scanConfidence": 0.92, "estimateLow": 0.30, "estimateHigh": 0.39, "estimateConfidence": 0.7,
     "estimateQuery": "Palpitoad", "comparables": [], "basis": "marketListings",
     "comparablesAreExact": true, "priceSummary": "From 6 price guides", "inCollection": true}
    """#

    func testBuild2RecordStillDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(SavedCollectible.self, from: Data(build2Record.utf8))
        XCTAssertNil(item.conditionSet)
        XCTAssertTrue(item.isConditionSet)
        XCTAssertNil(item.priceBasis)
        XCTAssertNil(item.evidenceCount)
        XCTAssertNil(item.lockedComparableCount)
        // Free saved item with no comparables but a summary: asking (conservative), summary kept.
        let va = item.assessment
        XCTAssertEqual(va.evidence, .asking)
        XCTAssertEqual(va.evidenceText, "From 6 price guides")
        XCTAssertNil(va.evidenceCount)
        XCTAssertEqual(va.level, .fair)
    }

    func testLegacyRecordWithoutBasisIsAnAIEstimate() throws {
        let json = #"""
        {"id": "6F1C2A8E-1D2B-4C3D-9E8F-0A1B2C3D4E60", "savedAt": "2026-09-01T10:00:00Z", "condition": "Mint",
         "title": "Old watch", "probableCategory": "Watch", "detectedText": [], "scanConfidence": 0.85,
         "estimateLow": 100, "estimateHigh": 300, "estimateConfidence": 0.6, "estimateQuery": "watch", "comparables": []}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(SavedCollectible.self, from: Data(json.utf8))
        XCTAssertEqual(item.assessment.level, .rough)
        XCTAssertEqual(item.assessment.evidence, .aiEstimate)
    }

    func testNewFieldsSurviveASaveRoundTrip() throws {
        let profile = CollectibleProfile(title: "Charizard", probableCategory: .tradingCard, confidence: 0.9)
        let estimate = ValueEstimate(low: 310, high: 420, confidence: 0.8, query: "Charizard", comparables: [],
                                     basis: .marketListings, lockedComparableCount: 7,
                                     mid: 365, priceBasis: "sold", evidenceCount: 18)
        var item = SavedCollectible(profile: profile, estimate: estimate, condition: .good, conditionSet: false)
        item.condition = .veryGood
        item.userProvidedInfo = "Signed"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let again = try decoder.decode(SavedCollectible.self, from: encoder.encode(item))
        XCTAssertEqual(again.conditionSet, false)
        XCTAssertEqual(again.condition, .veryGood)
        XCTAssertEqual(again.userProvidedInfo, "Signed")
        XCTAssertEqual(again.priceBasis, "sold")
        XCTAssertEqual(again.evidenceCount, 18)
        XCTAssertEqual(again.valueMid, 365)
        XCTAssertEqual(again.lockedComparableCount, 7)
        XCTAssertEqual(again.notCollectible, false)
        XCTAssertEqual(again.assessment.evidence, .sold)
    }
}
