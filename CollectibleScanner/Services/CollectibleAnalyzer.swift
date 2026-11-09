import Foundation

final class CollectibleAnalyzer {
    private let categoryKeywords: [(CollectibleCategory, [String])] = [
        (.tradingCard, ["rookie card", "topps", "pokemon", "panini", "holo", "graded", "psa", "bgs", "card"]),
        (.comic, ["comic", "issue", "marvel", "dc comics", "variant cover"]),
        (.coin, ["coin", "mint mark", "silver dollar", "pcgs", "ngc"]),
        (.actionFigure, ["action figure", "funko", "hasbro", "mcfarlane", "figurine"]),
        (.toy, ["toy", "limited edition", "vintage toy"]),
        (.watch, ["watch", "swiss made", "automatic", "chronograph"]),
        (.sneaker, ["sneaker", "air jordan", "nike", "adidas", "size"]),
        (.vinyl, ["vinyl", "lp", "record", "33 rpm", "45 rpm"]),
        (.game, ["nintendo", "playstation", "xbox", "gameboy", "cartridge"]),
        (.stamp, ["stamp", "philatelic", "postage", "watermark"])
    ]

    private let brandAliases: [String: String] = [
        "pokemon": "Pokemon",
        "topps": "Topps",
        "panini": "Panini",
        "funko": "Funko",
        "hasbro": "Hasbro",
        "mattel": "Mattel",
        "lego": "LEGO",
        "marvel": "Marvel",
        "dc": "DC",
        "nintendo": "Nintendo",
        "sega": "Sega",
        "sony": "Sony",
        "adidas": "Adidas",
        "nike": "Nike",
        "omega": "Omega",
        "rolex": "Rolex"
    ]

    func analyze(_ payload: ScanPayload, supplementalInfo: String?) -> CollectibleProfile {
        let normalizedLines = payload.textLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let supplementalLines = parseSupplementalLines(from: supplementalInfo)
        let mergedLines = mergedLinesWithUniqueElements(primary: normalizedLines, secondary: supplementalLines)
        let blob = mergedLines.joined(separator: " ")
        let lowerBlob = blob.lowercased()

        let category = detectCategory(in: lowerBlob)
        let brand = detectBrand(in: lowerBlob)
        let year = detectYear(in: lowerBlob)
        let model = detectModel(in: mergedLines)
        let title = detectTitle(from: mergedLines, fallbackBrand: brand, category: category)
        let confidence = computeConfidence(
            category: category,
            brand: brand,
            year: year,
            model: model,
            barcode: payload.barcodes.first,
            textCount: mergedLines.count
        )

        return CollectibleProfile(
            title: title,
            probableCategory: category,
            brand: brand,
            year: year,
            modelNumber: model,
            barcode: payload.barcodes.first,
            detectedText: Array(mergedLines.prefix(6)),
            userProvidedInfo: supplementalInfo,
            confidence: confidence,
            // The on-device pipeline reads keywords off OCR text; it never matches a
            // catalogue. Saying so keeps the regime honest even offline.
            regime: payload.barcodes.first == nil ? .openEnded : .catalogMatched
        )
    }

    private func parseSupplementalLines(from supplementalInfo: String?) -> [String] {
        guard let supplementalInfo else {
            return []
        }

        return supplementalInfo
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func mergedLinesWithUniqueElements(primary: [String], secondary: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for line in primary + secondary {
            guard !line.isEmpty else { continue }
            let normalized = line.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            merged.append(line)
        }

        return merged
    }

    private func detectCategory(in lowerBlob: String) -> CollectibleCategory {
        for (category, words) in categoryKeywords {
            if words.contains(where: { lowerBlob.contains($0) }) {
                return category
            }
        }
        return .unknown
    }

    private func detectBrand(in lowerBlob: String) -> String? {
        for (alias, canonical) in brandAliases {
            if lowerBlob.contains(alias) {
                return canonical
            }
        }
        return nil
    }

    private func detectYear(in text: String) -> Int? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let pattern = #"\b(19\d{2}|20\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        let values = regex.matches(in: text, options: [], range: range).compactMap { match -> Int? in
            guard let yearRange = Range(match.range, in: text) else {
                return nil
            }
            let value = Int(text[yearRange])
            guard let value, value >= 1850, value <= currentYear else {
                return nil
            }
            return value
        }
        return values.sorted().last
    }

    private func detectModel(in lines: [String]) -> String? {
        let pattern = #"\b[A-Z0-9]{2,5}[- ][A-Z0-9]{2,8}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let modelRange = Range(match.range, in: line) {
                return String(line[modelRange])
            }
        }
        return nil
    }

    private func detectTitle(from lines: [String], fallbackBrand: String?, category: CollectibleCategory) -> String {
        if let headline = lines.first(where: { $0.count >= 4 }) {
            return headline
        }
        if let fallbackBrand {
            return "\(fallbackBrand) \(category.rawValue)"
        }
        return category == .unknown ? "Unknown Collectible" : category.rawValue
    }

    private func computeConfidence(
        category: CollectibleCategory,
        brand: String?,
        year: Int?,
        model: String?,
        barcode: String?,
        textCount: Int
    ) -> Double {
        var confidence = 0.2

        if category != .unknown { confidence += 0.25 }
        if brand != nil { confidence += 0.18 }
        if year != nil { confidence += 0.15 }
        if model != nil { confidence += 0.12 }
        if barcode != nil { confidence += 0.1 }
        confidence += min(0.15, Double(textCount) * 0.02)

        return min(0.96, confidence)
    }
}
