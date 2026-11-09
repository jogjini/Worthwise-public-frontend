import XCTest
@testable import CollectibleScanner

final class ValueEstimatorTests: XCTestCase {

    func testOfflineEstimateHasNoFabricatedComparables() {
        let profile = CollectibleProfile(
            title: "Test Card", probableCategory: .tradingCard,
            brand: "Pokemon", year: 1999, confidence: 0.8
        )
        let estimate = ValueEstimator().estimate(for: profile, condition: .good)
        XCTAssertTrue(estimate.comparables.isEmpty, "Offline estimates must not invent comparables")
        XCTAssertEqual(estimate.basis, .offlineEstimate)
    }

    func testOfflineConfidenceIsHonestlyLow() {
        let profile = CollectibleProfile(
            title: "Test", probableCategory: .coin, confidence: 0.95
        )
        let estimate = ValueEstimator().estimate(for: profile, condition: .mint)
        XCTAssertLessThanOrEqual(estimate.confidence, 0.35, "Heuristic confidence must stay low/honest")
    }

    func testBetterConditionRaisesValue() {
        let profile = CollectibleProfile(title: "Watch", probableCategory: .watch, confidence: 0.6)
        let poor = ValueEstimator().estimate(for: profile, condition: .poor)
        let mint = ValueEstimator().estimate(for: profile, condition: .mint)
        XCTAssertGreaterThan(mint.high, poor.high)
    }

    // MARK: - Price typing

    func testComparableDecodesPriceType() throws {
        let json = """
        {"source":"PriceCharting","price":250,"currency":"USD","note":"loose","priceType":"sold"}
        """.data(using: .utf8)!
        let comp = try JSONDecoder().decode(MarketComparable.self, from: json)
        XCTAssertEqual(comp.priceType, .sold)
        XCTAssertTrue(comp.priceType.isRealisedValue)
    }

    func testComparableWithoutPriceTypeDefaultsToAsking() throws {
        // Items saved before price typing existed, and responses from an older
        // server build, must still decode — and must not be flattered into
        // looking like sold data.
        let json = """
        {"source":"eBay US","price":50,"currency":"USD","note":"listing"}
        """.data(using: .utf8)!
        let comp = try JSONDecoder().decode(MarketComparable.self, from: json)
        XCTAssertEqual(comp.priceType, .asking)
        XCTAssertFalse(comp.priceType.isRealisedValue)
    }

    func testComparableSurvivesEncodeDecodeRoundTrip() throws {
        let original = MarketComparable(
            source: "Cardmarket", price: 286.2, currency: "USD",
            note: "trend price (265.00 EUR)", priceType: .guide
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(MarketComparable.self, from: data)
        XCTAssertEqual(restored.priceType, .guide)
        XCTAssertEqual(restored.source, "Cardmarket")
        XCTAssertEqual(restored.price, 286.2, accuracy: 0.001)
    }
}
