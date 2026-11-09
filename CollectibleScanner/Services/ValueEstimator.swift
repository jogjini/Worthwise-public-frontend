import Foundation

final class ValueEstimator {
    private let baseRanges: [CollectibleCategory: ClosedRange<Double>] = [
        .tradingCard: 20...280,
        .comic: 25...320,
        .coin: 35...400,
        .toy: 18...220,
        .actionFigure: 20...260,
        .watch: 120...1_800,
        .sneaker: 90...750,
        .vinyl: 25...240,
        .game: 30...420,
        .stamp: 15...180,
        .unknown: 15...120
    ]

    private let brandMultipliers: [String: Double] = [
        "pokemon": 1.45,
        "topps": 1.2,
        "panini": 1.2,
        "funko": 1.15,
        "lego": 1.2,
        "nintendo": 1.35,
        "nike": 1.2,
        "adidas": 1.15,
        "omega": 1.8,
        "rolex": 2.3
    ]

    func estimate(for profile: CollectibleProfile, condition: ConditionGrade) -> ValueEstimate {
        let base = baseRanges[profile.probableCategory] ?? (10...100)
        var low = base.lowerBound
        var high = base.upperBound

        low *= condition.multiplier
        high *= condition.multiplier

        if let brand = profile.brand?.lowercased(), let multiplier = brandMultipliers[brand] {
            low *= multiplier
            high *= multiplier
        }

        if let year = profile.year {
            let currentYear = Calendar.current.component(.year, from: Date())
            let age = max(0, currentYear - year)
            let ageMultiplier = min(2.0, 1.0 + (Double(age) / 90.0))
            low *= ageMultiplier
            high *= ageMultiplier
        }

        if profile.modelNumber != nil {
            low *= 1.1
            high *= 1.2
        }

        if profile.barcode != nil {
            low *= 1.05
            high *= 1.1
        }

        // Offline heuristic only — deliberately low, honest confidence (no market data).
        let estimatedConfidence = min(0.35, max(0.12, profile.confidence * 0.4))
        let query = buildQuery(from: profile)

        return ValueEstimate(
            low: rounded(low),
            high: rounded(high),
            confidence: estimatedConfidence,
            query: query,
            comparables: [],
            basis: .offlineEstimate
        )
    }

    private func buildQuery(from profile: CollectibleProfile) -> String {
        let parts: [String?] = [
            profile.brand,
            profile.title == "Unknown Collectible" ? nil : profile.title,
            profile.year.map(String.init),
            profile.modelNumber
        ]
        let primaryQuery = parts.compactMap { $0 }.joined(separator: " ")
        if !primaryQuery.isEmpty {
            return primaryQuery
        }

        guard let userProvidedInfo = profile.userProvidedInfo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userProvidedInfo.isEmpty else {
            return ""
        }

        if userProvidedInfo.count <= 70 {
            return userProvidedInfo
        }

        let truncated = userProvidedInfo.prefix(70).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncated)..."
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
