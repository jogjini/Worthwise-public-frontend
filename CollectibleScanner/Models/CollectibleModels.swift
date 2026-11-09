import Foundation

enum CollectibleCategory: String, CaseIterable, Codable {
    case tradingCard = "Trading Card"
    case comic = "Comic"
    case coin = "Coin"
    case toy = "Toy"
    case actionFigure = "Action Figure"
    case watch = "Watch"
    case sneaker = "Sneaker"
    case vinyl = "Vinyl"
    case game = "Game"
    case stamp = "Stamp"
    case unknown = "Unknown"
}

enum ConditionGrade: String, CaseIterable, Identifiable {
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case veryGood = "Very Good"
    case mint = "Mint"

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .poor: return 0.45
        case .fair: return 0.65
        case .good: return 1.0
        case .veryGood: return 1.35
        case .mint: return 1.8
        }
    }

    /// Best first, as the condition menu lists them (04 §6.2).
    static let menuOrder: [ConditionGrade] = [.mint, .veryGood, .good, .fair, .poor]

    /// Sentence-case name, with card wording when the category is known
    /// (04 §6.6 Edit Details: Mint → "Gem mint", Very good → "Near mint"…).
    func label(for category: CollectibleCategory? = nil) -> String {
        if category == .tradingCard {
            switch self {
            case .mint: return "Gem mint"
            case .veryGood: return "Near mint"
            case .good: return "Lightly played"
            case .fair: return "Played"
            case .poor: return "Damaged"
            }
        }
        switch self {
        case .mint: return "Mint"
        case .veryGood: return "Very good"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    /// The menu item's subtitle (04 §6.2).
    var detail: String {
        switch self {
        case .mint: return "As new, no wear"
        case .veryGood: return "Light wear"
        case .good: return "Normal wear for its age"
        case .fair: return "Clear wear or small damage"
        case .poor: return "Heavy wear or damage"
        }
    }
}

struct ScanPayload {
    let textLines: [String]
    let barcodes: [String]
}

/// One display-ready attribute row, flattened server-side.
///
/// The server owns the field list and its order, so adding an attribute to a
/// category is a server-only change and old app builds keep working.
struct ItemAttribute: Identifiable, Codable, Hashable {
    var id: String { label }
    let label: String
    let value: String
}

/// Which identification problem this scan actually was.
///
/// `catalogMatched` — a real catalogue key was found (set + number, a barcode, a
/// named reference). A confident answer is justified.
/// `openEnded` — no printed key exists or none could be read. Identity is a bundle
/// of attributes and the decisive ones may not be in the photo at all.
enum IdentificationRegime: String, Codable {
    case catalogMatched
    case openEnded
}

struct CollectibleProfile: Identifiable, Codable {
    let id: UUID
    let title: String
    let probableCategory: CollectibleCategory
    let brand: String?
    let year: Int?
    let modelNumber: String?
    let barcode: String?
    let detectedText: [String]
    let userProvidedInfo: String?
    let confidence: Double
    /// Per-family attributes (coin legends, maker's marks…). For an open-ended
    /// item these are the real result, not decoration.
    let attributes: [ItemAttribute]
    let regime: IdentificationRegime
    /// Server verdict (04 §10 S3): the photo is not a collectible (a person, a
    /// landscape). `false` when absent, which is every server build today.
    let notCollectible: Bool
    /// Server suggestions when the match is unsure (04 §10 S6), at most 3.
    /// Empty when absent.
    let candidates: [MatchCandidate]

    init(
        id: UUID = UUID(),
        title: String,
        probableCategory: CollectibleCategory,
        brand: String? = nil,
        year: Int? = nil,
        modelNumber: String? = nil,
        barcode: String? = nil,
        detectedText: [String] = [],
        userProvidedInfo: String? = nil,
        confidence: Double,
        attributes: [ItemAttribute] = [],
        regime: IdentificationRegime = .catalogMatched,
        notCollectible: Bool = false,
        candidates: [MatchCandidate] = []
    ) {
        self.id = id
        self.title = title
        self.probableCategory = probableCategory
        self.brand = brand
        self.year = year
        self.modelNumber = modelNumber
        self.barcode = barcode
        self.detectedText = detectedText
        self.userProvidedInfo = userProvidedInfo
        self.confidence = confidence
        self.attributes = attributes
        self.regime = regime
        self.notCollectible = notCollectible
        self.candidates = candidates
    }

    enum CodingKeys: String, CodingKey {
        case id, title, brand, year, modelNumber, barcode,
             detectedText, userProvidedInfo, confidence,
             attributes, regime, notCollectible, candidates
        case probableCategory = "category"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        let rawTitle = (try? c.decode(String.self, forKey: .title)) ?? ""
        title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Item" : rawTitle
        probableCategory = (try? c.decode(CollectibleCategory.self, forKey: .probableCategory)) ?? .unknown
        brand = try? c.decode(String.self, forKey: .brand)
        year = try? c.decode(Int.self, forKey: .year)
        modelNumber = try? c.decode(String.self, forKey: .modelNumber)
        barcode = try? c.decode(String.self, forKey: .barcode)
        detectedText = (try? c.decode([String].self, forKey: .detectedText)) ?? []
        userProvidedInfo = try? c.decode(String.self, forKey: .userProvidedInfo)
        confidence = min(1.0, max(0.0, (try? c.decode(Double.self, forKey: .confidence)) ?? 0.0))
        attributes = (try? c.decode([ItemAttribute].self, forKey: .attributes)) ?? []
        // Absent from older server builds and from every locally-scanned item.
        // Defaulting to catalogMatched keeps existing behaviour unchanged.
        regime = (try? c.decode(IdentificationRegime.self, forKey: .regime)) ?? .catalogMatched
        // Both absent from every server build so far (04 §10 S3, S6): an old
        // response, or a saved item, decodes as "a collectible, no candidates".
        notCollectible = (try? c.decode(Bool.self, forKey: .notCollectible)) ?? false
        let decodedCandidates: [MatchCandidate] = (try? c.decode([MatchCandidate].self, forKey: .candidates)) ?? []
        candidates = Array(decodedCandidates.prefix(3))
    }
}

/// One "Is it one of these?" suggestion for an unsure match (04 §10 S6).
struct MatchCandidate: Codable, Hashable, Identifiable {
    var id: String { title + "|" + (detail ?? "") }
    let title: String
    /// 0…1, how likely the server thinks this candidate is.
    let confidence: Double
    /// A short line under the title, e.g. "Base Set · 1999".
    let detail: String?

    init(title: String, confidence: Double, detail: String? = nil) {
        self.title = title
        self.confidence = confidence
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        confidence = min(1.0, max(0.0, (try? c.decode(Double.self, forKey: .confidence)) ?? 0.0))
        detail = try? c.decode(String.self, forKey: .detail)
    }
}

/// What kind of evidence a comparable is. The difference is not cosmetic: a
/// completed sale is what an item fetched, an asking price is what someone hopes
/// to get, and the two routinely differ by 30% or more.
enum PriceType: String, Codable {
    case sold      // a completed sale — the strongest evidence
    case guide     // a catalogue / price-guide value
    case asking    // a live listing; an upper bound, not a market price

    /// Unlabelled prices are treated as listings, which is the conservative read.
    static let `default`: PriceType = .asking

    var badge: String {
        switch self {
        case .sold: return "SOLD"
        case .guide: return "GUIDE"
        case .asking: return "ASKING"
        }
    }

    /// True when this reflects what items actually change hands for.
    var isRealisedValue: Bool { self != .asking }
}

struct MarketComparable: Identifiable, Codable {
    let id: UUID
    let source: String
    let price: Double
    let currency: String
    let note: String
    let priceType: PriceType
    /// Deep link to the listing or product page this price came from, when the
    /// source API provides one. Validated and host-pinned server-side.
    let url: URL?
    /// The listing's photo (eBay), so the user can see what was compared.
    let imageURL: URL?

    init(
        id: UUID = UUID(),
        source: String,
        price: Double,
        currency: String = "USD",
        note: String,
        priceType: PriceType = .default,
        url: URL? = nil,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.price = price
        self.currency = currency
        self.note = note
        self.priceType = priceType
        self.url = url
        self.imageURL = imageURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        source = try c.decode(String.self, forKey: .source)
        price = try c.decode(Double.self, forKey: .price)
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        note = try c.decode(String.self, forKey: .note)
        // Absent in items saved before price typing existed, and in any response
        // from an older server build.
        priceType = (try? c.decode(PriceType.self, forKey: .priceType)) ?? .default
        // Optional everywhere: older saved items and older server builds have no
        // url, and a source may simply not expose one.
        if let raw = try? c.decode(String.self, forKey: .url), !raw.isEmpty {
            url = URL(string: raw)
        } else {
            url = nil
        }
        imageURL = (try? c.decode(String.self, forKey: .imageURL)).flatMap(URL.init(string:))
    }
}

/// How a value estimate was produced — so the UI can be honest about it.
enum ValuationBasis: String, Codable {
    case marketListings   // anchored to real current marketplace listings
    case aiEstimate       // AI value estimate, no listings found
    case offlineEstimate  // on-device heuristic fallback (rough, no market data)
    /// Open-ended item: attributes were read off the object, but no catalogue
    /// entry was matched, so any price is a band around similar things — never a
    /// valuation of *this* item.
    case attributesOnly
}

struct ValueEstimate: Codable {
    let low: Double
    let high: Double
    let confidence: Double
    let query: String
    let comparables: [MarketComparable]
    let basis: ValuationBasis
    /// `false` when the comparables are similar items rather than this exact one.
    let comparablesAreExact: Bool
    /// Free plan: how many listings the estimate used but the server withheld
    /// (a Pro feature), and where they came from. 0 / empty for Pro.
    let lockedComparableCount: Int
    let lockedSources: [String]
    /// The server's one-line account of how the range was reached, e.g.
    /// "From 3 sold prices and 6 listings". Nil from older servers.
    let priceSummary: String?
    /// Price history for the chart (Pro). Nil when there is none or it is locked.
    let history: PriceHistory?
    /// Free plan: a history exists but is a Pro feature.
    let historyLocked: Bool
    /// Source ids of what was priced; saved with the item so the server can
    /// re-price it daily (POST /api/prices). Opaque to the app.
    let priceKeys: JSONValue?
    /// Recent sold prices (last 90 days) for the "Sold prices" section. Display
    /// only: not part of the range. Nil when the server has none to offer.
    let sold: SoldSummary?

    // Price-engine fields (server `valueMid`, `priceBasis`, `evidenceCount`).
    // All optional: the server change set is not deployed yet, and items saved
    // before it have none of them. `ValueAssessment` falls back when nil.
    /// The engine's typical price in USD. Never shown as an estimate unless it
    /// sits inside the range (04 §4.3 "Best estimate").
    let mid: Double?
    /// Strongest evidence behind the range: "sold" | "guide" | "asking" | "estimate".
    /// Read it through `EvidenceKind(priceBasis:)`.
    let priceBasis: String?
    /// How many prices the range was built from (the same population as
    /// `priceSummary`). The one count every "prices" label reads (04 §4.6).
    let evidenceCount: Int?

    init(
        low: Double,
        high: Double,
        confidence: Double,
        query: String,
        comparables: [MarketComparable],
        basis: ValuationBasis = .aiEstimate,
        comparablesAreExact: Bool = true,
        lockedComparableCount: Int = 0,
        lockedSources: [String] = [],
        priceSummary: String? = nil,
        history: PriceHistory? = nil,
        historyLocked: Bool = false,
        priceKeys: JSONValue? = nil,
        sold: SoldSummary? = nil,
        mid: Double? = nil,
        priceBasis: String? = nil,
        evidenceCount: Int? = nil
    ) {
        self.low = low
        self.high = high
        self.confidence = confidence
        self.query = query
        self.comparables = comparables
        self.basis = basis
        self.comparablesAreExact = comparablesAreExact
        self.lockedComparableCount = lockedComparableCount
        self.lockedSources = lockedSources
        self.priceSummary = priceSummary
        self.history = history
        self.historyLocked = historyLocked
        self.priceKeys = priceKeys
        self.sold = sold
        self.mid = mid
        self.priceBasis = priceBasis
        self.evidenceCount = evidenceCount
    }

    enum CodingKeys: String, CodingKey {
        case low = "valueLow"
        case high = "valueHigh"
        case confidence = "valueConfidence"
        case query, comparables, basis
        case lockedComparableCount = "comparablesLocked"
        case lockedSources
        case priceSummary, history, historyLocked, priceKeys, sold
        case mid = "valueMid"
        case priceBasis, evidenceCount
    }

    /// Fields the SERVER sends that have no stored property of their own — they are
    /// inputs to `basis` / `comparablesAreExact` rather than values in their own
    /// right. Kept out of `CodingKeys` so `Encodable` synthesis still works.
    private enum ServerKeys: String, CodingKey {
        case regime, comparableMatch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawLow = (try? c.decode(Double.self, forKey: .low)) ?? 0.0
        let rawHigh = (try? c.decode(Double.self, forKey: .high)) ?? 0.0
        low = min(rawLow, rawHigh)
        high = max(rawLow, rawHigh)
        confidence = min(1.0, max(0.0, (try? c.decode(Double.self, forKey: .confidence)) ?? 0.0))
        query = (try? c.decode(String.self, forKey: .query)) ?? ""
        let comps = (try? c.decode([MarketComparable].self, forKey: .comparables)) ?? []
        comparables = comps
        let locked = max(0, (try? c.decode(Int.self, forKey: .lockedComparableCount)) ?? 0)
        lockedComparableCount = locked
        lockedSources = (try? c.decode([String].self, forKey: .lockedSources)) ?? []
        // All four are absent from older servers and from items saved before them.
        priceSummary = try? c.decode(String.self, forKey: .priceSummary)
        history = try? c.decode(PriceHistory.self, forKey: .history)
        historyLocked = (try? c.decode(Bool.self, forKey: .historyLocked)) ?? false
        priceKeys = try? c.decode(JSONValue.self, forKey: .priceKeys)
        sold = try? c.decode(SoldSummary.self, forKey: .sold)

        // Price-engine fields. Absent from older servers and older saved data.
        var decodedMid: Double? = nil
        if let rawMid = try? c.decode(Double.self, forKey: .mid), rawMid.isFinite, rawMid > 0 {
            decodedMid = rawMid
        }
        mid = decodedMid
        var decodedBasis: String? = nil
        if let rawBasis = try? c.decode(String.self, forKey: .priceBasis) {
            let trimmed = rawBasis.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            decodedBasis = trimmed.isEmpty ? nil : trimmed
        }
        priceBasis = decodedBasis
        var decodedCount: Int? = nil
        if let rawCount = try? c.decode(Int.self, forKey: .evidenceCount) {
            decodedCount = max(0, rawCount)
        }
        evidenceCount = decodedCount

        // Nested optionals get ugly fast here, so unwrap into plain locals first.
        var regime: IdentificationRegime = .catalogMatched
        var areExact = true
        if let server = try? decoder.container(keyedBy: ServerKeys.self) {
            if let decoded = try? server.decode(IdentificationRegime.self, forKey: .regime) {
                regime = decoded
            }
            if let match = try? server.decode(String.self, forKey: .comparableMatch) {
                areExact = match == "exact"
            }
        }
        comparablesAreExact = areExact

        // A saved item carries its own basis; trust it rather than re-deriving from
        // fields that were not persisted.
        if let stored = try? c.decode(ValuationBasis.self, forKey: .basis) {
            basis = stored
        } else if regime == .openEnded {
            // An open-ended item is never "market-checked", even when comparables
            // came back: those are prices for similar things, not for this object.
            // Claiming otherwise is the overconfidence this branch exists to remove.
            basis = .attributesOnly
        } else {
            // Locked listings still priced the estimate; they are just not shown.
            basis = (comps.isEmpty && locked == 0) ? .aiEstimate : .marketListings
        }
    }
}

// MARK: - Price history

/// One day's value in a price series. `t` is "YYYY-MM-DD".
struct PricePoint: Codable, Hashable, Sendable {
    let t: String
    let p: Double

    var date: Date? { PricePoint.dayFormatter.date(from: t) }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// A daily series from one source (a price guide, or our own daily re-pricing).
struct PriceSeries: Codable, Hashable, Identifiable, Sendable {
    var id: String { source }
    let source: String
    let kind: String
    let label: String
    let points: [PricePoint]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(String.self, forKey: .source)) ?? "Prices"
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "guide"
        label = (try? c.decode(String.self, forKey: .label)) ?? source
        points = ((try? c.decode([PricePoint].self, forKey: .points)) ?? []).filter { $0.p > 0 }
    }
}

/// One dated sale (an auction result, for example).
struct PriceSale: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(date)|\(price)|\(source ?? "")" }
    let date: String
    let price: Double
    let source: String?

    var day: Date? { PricePoint.dayFormatter.date(from: String(date.prefix(10))) }
}

/// What the result screen's chart draws: the `history` block of a scan, or of
/// POST /api/prices for a saved item.
struct PriceHistory: Codable, Hashable, Sendable {
    let series: [PriceSeries]
    let sales: [PriceSale]
    let since: String?

    init(series: [PriceSeries], sales: [PriceSale], since: String?) {
        self.series = series
        self.sales = sales
        self.since = since
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        series = (try? c.decode([PriceSeries].self, forKey: .series)) ?? []
        sales = (try? c.decode([PriceSale].self, forKey: .sales)) ?? []
        since = try? c.decode(String.self, forKey: .since)
    }

    /// Something worth drawing: a line needs two points, or at least one sale.
    var isDrawable: Bool { series.contains { $0.points.count >= 2 } || !sales.isEmpty }
}

// MARK: - Sold prices

/// One completed sale in the "Sold prices" section (eBay sold, TCGplayer sales).
struct SoldSale: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(date)|\(price)|\(source)|\(title)" }
    /// "YYYY-MM-DD"
    let date: String
    /// What the buyer paid, in USD. eBay prices include shipping.
    let price: Double
    let currency: String
    let title: String
    let url: URL?
    /// The sold listing's photo (eBay).
    let imageURL: URL?
    let source: String
    /// eBay shows the asking price for an accepted Best Offer, not the offer.
    let bestOffer: Bool
    let condition: String?

    var day: Date? { PricePoint.dayFormatter.date(from: String(date.prefix(10))) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        price = try c.decode(Double.self, forKey: .price)
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        if let raw = try? c.decode(String.self, forKey: .url), !raw.isEmpty {
            url = URL(string: raw)
        } else {
            url = nil
        }
        imageURL = (try? c.decode(String.self, forKey: .imageURL)).flatMap(URL.init(string:))
        source = (try? c.decode(String.self, forKey: .source)) ?? "eBay"
        bestOffer = (try? c.decode(Bool.self, forKey: .bestOffer)) ?? false
        condition = try? c.decode(String.self, forKey: .condition)
    }
}

/// The `sold` block of a scan: figures for everyone, the sales behind them
/// (list and chart) for Pro. Stored with saved items as it was at scan time.
struct SoldSummary: Codable, Hashable, Sendable {
    let count: Int
    let average: Double?
    let median: Double?
    let low: Double?
    let high: Double?
    let currency: String
    let windowDays: Int
    let sources: [String]
    let bestOfferCount: Int
    /// Best Offer sales are listed but left out of the figures.
    let bestOfferExcluded: Bool
    /// A card under $3: eBay sales left out (they sit at eBay's price floor).
    let ebayFloorExcluded: Bool
    /// "exact", or "similar" for an item matched on attributes only.
    let match: String
    /// Newest first. Empty on the free plan.
    let sales: [SoldSale]
    /// Free plan: how many sales are behind the figures.
    let salesLocked: Int
    /// The source is on but did not answer in time for this scan.
    let unavailable: Bool

    var isExact: Bool { match != "similar" }

    /// Built in code (tests, previews). The app itself decodes this block.
    init(
        count: Int,
        average: Double? = nil,
        median: Double? = nil,
        low: Double? = nil,
        high: Double? = nil,
        currency: String = "USD",
        windowDays: Int = 90,
        sources: [String] = [],
        bestOfferCount: Int = 0,
        bestOfferExcluded: Bool = false,
        ebayFloorExcluded: Bool = false,
        match: String = "exact",
        sales: [SoldSale] = [],
        salesLocked: Int = 0,
        unavailable: Bool = false
    ) {
        self.count = max(0, count)
        self.average = average
        self.median = median
        self.low = low
        self.high = high
        self.currency = currency
        self.windowDays = windowDays
        self.sources = sources
        self.bestOfferCount = bestOfferCount
        self.bestOfferExcluded = bestOfferExcluded
        self.ebayFloorExcluded = ebayFloorExcluded
        self.match = match
        self.sales = sales
        self.salesLocked = max(0, salesLocked)
        self.unavailable = unavailable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = max(0, (try? c.decode(Int.self, forKey: .count)) ?? 0)
        average = try? c.decode(Double.self, forKey: .average)
        median = try? c.decode(Double.self, forKey: .median)
        low = try? c.decode(Double.self, forKey: .low)
        high = try? c.decode(Double.self, forKey: .high)
        currency = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        windowDays = (try? c.decode(Int.self, forKey: .windowDays)) ?? 90
        sources = (try? c.decode([String].self, forKey: .sources)) ?? []
        bestOfferCount = (try? c.decode(Int.self, forKey: .bestOfferCount)) ?? 0
        bestOfferExcluded = (try? c.decode(Bool.self, forKey: .bestOfferExcluded)) ?? false
        ebayFloorExcluded = (try? c.decode(Bool.self, forKey: .ebayFloorExcluded)) ?? false
        match = (try? c.decode(String.self, forKey: .match)) ?? "exact"
        sales = ((try? c.decode([SoldSale].self, forKey: .sales)) ?? []).filter { $0.price > 0 }
        salesLocked = max(0, (try? c.decode(Int.self, forKey: .salesLocked)) ?? 0)
        unavailable = (try? c.decode(Bool.self, forKey: .unavailable)) ?? false
    }
}

// MARK: - Opaque JSON

/// A JSON value the app stores and sends back without interpreting it
/// (the server's `priceKeys`).
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    /// For JSONSerialization request bodies.
    var foundationValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let o): return o.mapValues(\.foundationValue)
        case .array(let a): return a.map(\.foundationValue)
        case .null: return NSNull()
        }
    }
}


// MARK: - Value assessment (redesign, 04 §4)
//
// One place decides how much a result can be trusted. The value card, tiles,
// totals, sort order, CSV, share card and review prompt all read the same
// `ValueAssessment`, so a level or a count can never disagree between screens.
// Every threshold lives in `ValueAssessment.T`.

/// How firm a value is: 04's D C B A, ordered weakest → strongest.
enum ValueLevel: Int, Comparable, CaseIterable {
    /// D: no number by default (not a collectible, too wide, on-device, nothing found).
    case noPrice = 0
    /// C: a rough guide (wide range, AI only, similar items, unsure match, weak engine).
    case rough = 1
    /// B: market evidence, with caveats.
    case fair = 2
    /// A: close match, tight range, sold or guide prices for this exact item.
    case strong = 3

    static func < (lhs: ValueLevel, rhs: ValueLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 04's letter, for logs and tests.
    var letter: String {
        switch self {
        case .strong: return "A"
        case .fair: return "B"
        case .rough: return "C"
        case .noPrice: return "D"
        }
    }

    /// CSV "Value level" column (04 §4.4).
    var csvLabel: String {
        switch self {
        case .strong: return "Strong"
        case .fair: return "Fair"
        case .rough: return "Rough guide"
        case .noPrice: return "No price"
        }
    }
}

/// How sure the identification is. One set of thresholds for the whole app
/// (`ValueAssessment.T.matchClose` / `matchPossible`).
enum MatchStrength: Int, Comparable, CaseIterable {
    case unsure = 0
    case possible = 1
    case close = 2

    init(confidence: Double) {
        if confidence >= ValueAssessment.T.matchClose {
            self = .close
        } else if confidence >= ValueAssessment.T.matchPossible {
            self = .possible
        } else {
            self = .unsure
        }
    }

    static func < (lhs: MatchStrength, rhs: MatchStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// "Close match" / "Possible match" / "Unsure match".
    var label: String {
        switch self {
        case .close: return "Close match"
        case .possible: return "Possible match"
        case .unsure: return "Unsure match"
        }
    }

    /// VoiceOver value: "Close" / "Possible" / "Unsure".
    var word: String {
        switch self {
        case .close: return "Close"
        case .possible: return "Possible"
        case .unsure: return "Unsure"
        }
    }

    /// Filled segments of the 3-segment meter.
    var filledSegments: Int {
        switch self {
        case .close: return 3
        case .possible: return 2
        case .unsure: return 1
        }
    }
}

/// The one evidence vocabulary (04 §4.6), strongest → weakest.
enum EvidenceKind: String, CaseIterable {
    case sold
    case guide
    case asking
    case aiEstimate

    /// The server's `priceBasis`: "sold" | "guide" | "asking" | "estimate".
    init?(priceBasis: String) {
        switch priceBasis.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sold": self = .sold
        case "guide": self = .guide
        case "asking": self = .asking
        case "estimate", "ai", "aiestimate", "ai_estimate": self = .aiEstimate
        default: return nil
        }
    }

    init(_ type: PriceType) {
        switch type {
        case .sold: self = .sold
        case .guide: self = .guide
        case .asking: self = .asking
        }
    }

    /// 3 = sold … 0 = AI estimate.
    var rank: Int {
        switch self {
        case .sold: return 3
        case .guide: return 2
        case .asking: return 1
        case .aiEstimate: return 0
        }
    }

    /// Sold or guide: what items actually fetch or are catalogued at.
    var isRealisedValue: Bool { self == .sold || self == .guide }

    /// The chip word (shown uppercase by the `.chip` role).
    var chip: String {
        switch self {
        case .sold: return "SOLD"
        case .guide: return "GUIDE"
        case .asking: return "ASKING"
        case .aiEstimate: return "AI ESTIMATE"
        }
    }

    /// What VoiceOver says for the chip. Never the letters.
    var spoken: String {
        switch self {
        case .sold: return "Sold prices"
        case .guide: return "Price guide"
        case .asking: return "Asking prices, not sales"
        case .aiEstimate: return "AI estimate, no market prices"
        }
    }

    /// SF Symbol for the chip.
    var glyph: String {
        switch self {
        case .sold: return "checkmark.seal.fill"
        case .guide: return "book.closed.fill"
        case .asking: return "storefront"
        case .aiEstimate: return "circle.dashed"
        }
    }

    /// Evidence line text when the server sent no `priceSummary`.
    var fallbackText: String {
        switch self {
        case .sold: return "Based on sold prices"
        case .guide: return "Based on price guides"
        case .asking: return "Based on asking prices only"
        case .aiEstimate: return "AI estimate · no market prices found"
        }
    }

    /// The strongest kind among some price types, nil when there are none.
    static func strongest(of types: [PriceType]) -> EvidenceKind? {
        var best: EvidenceKind? = nil
        for type in types {
            let kind = EvidenceKind(type)
            if best == nil || kind.rank > (best?.rank ?? -1) {
                best = kind
            }
        }
        return best
    }
}

/// Why a D result shows no number.
enum NoPriceReason: Equatable {
    /// `confirmed`: the server said so. Otherwise the client heuristic (04 §4.5).
    case notCollectible(confirmed: Bool)
    /// The range is more than 20× wide.
    case tooWide
    /// Priced on the iPhone only. `analysisOff`: photo analysis is turned off.
    case onDevice(analysisOff: Bool)
    /// Nothing priced it (high ≤ 0).
    case noValue

    /// D keeps a closed "Show the rough range" disclosure for these (04 §1).
    var showsRoughRange: Bool {
        switch self {
        case .tooWide: return true
        case .notCollectible(let confirmed): return !confirmed
        case .onDevice, .noValue: return false
        }
    }
}

/// A plain flag next to the number. Shown in this order, at most 2.
enum ValueCaveat: Equatable {
    case salesHigher(medianUSD: Double, count: Int)
    case salesLower(medianUSD: Double, count: Int)
    case wideRange
    case unsureMatch
    case similarItems
    case aiEstimate
}

/// A sentence about the value itself (not about the evidence).
enum ValueNote: Equatable {
    /// High end under `T.lowValueUSD`.
    case lowValue
    /// High end at or above `T.highValueUSD`.
    case highValue
    /// "…not an appraisal" inline (always in C; in A/B only with `.highValue`).
    case notAnAppraisal
}

/// The one number we stand behind inside the range. A midpoint never is one.
struct BestEstimate: Equatable {
    enum Source: Equatable {
        /// The median of ≥ `T.minSoldForBest` exact sales.
        case soldMedian(count: Int, windowDays: Int)
        /// The engine's `valueMid`.
        case engineMid
        /// The median of the visible sold/guide comparables.
        case compsMedian
    }

    let amountUSD: Double
    let source: Source
}

/// Everything `ValueAssessment` reads, from a fresh scan or a saved record.
struct ValueInputs {
    var title: String
    var category: CollectibleCategory
    /// Identification confidence, 0…1.
    var matchConfidence: Double
    /// Range in USD.
    var low: Double
    var high: Double
    /// The engine's value confidence (≤ 0.40 = prior fallback, no evidence).
    var valueConfidence: Double
    var basis: ValuationBasis
    var comparablesAreExact: Bool
    /// Visible comparables (Pro). Empty on Free.
    var comparables: [MarketComparable]
    /// Free plan: comparables the server withheld.
    var lockedCount: Int
    var priceSummary: String?
    /// Server `priceBasis` ("sold" | "guide" | "asking" | "estimate").
    var priceBasis: String?
    var evidenceCount: Int?
    /// Server `valueMid`, USD.
    var valueMid: Double?
    var sold: SoldSummary?
    /// Server verdict (04 §10 S3).
    var notCollectible: Bool
    /// The scan was on-device because photo analysis is off (`vm.lastScanWasLocalByChoice`).
    var analysisOff: Bool

    init(
        title: String = "",
        category: CollectibleCategory = .unknown,
        matchConfidence: Double,
        low: Double,
        high: Double,
        valueConfidence: Double,
        basis: ValuationBasis,
        comparablesAreExact: Bool = true,
        comparables: [MarketComparable] = [],
        lockedCount: Int = 0,
        priceSummary: String? = nil,
        priceBasis: String? = nil,
        evidenceCount: Int? = nil,
        valueMid: Double? = nil,
        sold: SoldSummary? = nil,
        notCollectible: Bool = false,
        analysisOff: Bool = false
    ) {
        self.title = title
        self.category = category
        self.matchConfidence = matchConfidence
        self.low = low
        self.high = high
        self.valueConfidence = valueConfidence
        self.basis = basis
        self.comparablesAreExact = comparablesAreExact
        self.comparables = comparables
        self.lockedCount = lockedCount
        self.priceSummary = priceSummary
        self.priceBasis = priceBasis
        self.evidenceCount = evidenceCount
        self.valueMid = valueMid
        self.sold = sold
        self.notCollectible = notCollectible
        self.analysisOff = analysisOff
    }

    /// A fresh scan. `analysisOff` = `vm.lastScanWasLocalByChoice`.
    init(profile: CollectibleProfile, estimate: ValueEstimate, analysisOff: Bool) {
        self.init(
            title: profile.title,
            category: profile.probableCategory,
            matchConfidence: profile.confidence,
            low: estimate.low,
            high: estimate.high,
            valueConfidence: estimate.confidence,
            basis: estimate.basis,
            comparablesAreExact: estimate.comparablesAreExact,
            comparables: estimate.comparables,
            lockedCount: estimate.lockedComparableCount,
            priceSummary: estimate.priceSummary,
            priceBasis: estimate.priceBasis,
            evidenceCount: estimate.evidenceCount,
            valueMid: estimate.mid,
            sold: estimate.sold,
            notCollectible: profile.notCollectible,
            analysisOff: analysisOff
        )
    }
}

/// The level, evidence, caveats and best estimate of one result (04 §4.3).
struct ValueAssessment {
    let level: ValueLevel
    let match: MatchStrength
    /// nil in D (the D body says why instead).
    let evidence: EvidenceKind?
    /// The one "prices behind this estimate" count. nil when 0 or in D.
    let evidenceCount: Int?
    /// `priceSummary` verbatim, else the kind's fallback. No suffixes:
    /// `EvidenceLine` adds them from `evidence` and `isExact`. nil in D.
    let evidenceText: String?
    /// Comparables are for this exact item (and it was catalogue-matched).
    let isExact: Bool
    /// A and B only.
    let best: BestEstimate?
    /// D only.
    let noPriceReason: NoPriceReason?
    /// All that apply, in display order. Show `displayCaveats` (max 2).
    let caveats: [ValueCaveat]
    let notes: [ValueNote]
    /// high / max(low, T.ratioFloorUSD).
    let ratio: Double
    /// The range, USD, ordered.
    let lowUSD: Double
    let highUSD: Double

    // MARK: Thresholds (tune on the eval set; 04 §4.2)

    enum T {
        static let matchClose: Double = 0.80
        static let matchPossible: Double = 0.55
        static let ratioStrong: Double = 2.5
        static let ratioFair: Double = 5.0
        static let ratioRough: Double = 20.0
        static let minEvidenceStrong: Int = 3
        static let minSoldForBest: Int = 3
        static let valueConfidenceFloor: Double = 0.40
        static let ratioFloorUSD: Double = 0.50
        static let lowValueUSD: Double = 10.0
        static let highValueUSD: Double = 1_000.0
        static let greatFindUSD: Double = 50.0
        static let maxDisplayedCaveats: Int = 2
    }

    // MARK: Derived

    /// A and B count in collection, folder and Home totals (04 §4.4).
    var countsInTotal: Bool { level >= .fair }

    /// "Highest value" sort key: best ?? midpoint, only when counted.
    var sortValueUSD: Double? {
        guard countsInTotal else { return nil }
        return best?.amountUSD ?? midpointUSD
    }

    var midpointUSD: Double { (lowUSD + highUSD) / 2 }

    /// The great-find hook (06 S2).
    var isGreatFind: Bool {
        guard level == .strong, match == .close else { return false }
        guard let kind = evidence, kind.isRealisedValue else { return false }
        let amount: Double = best?.amountUSD ?? midpointUSD
        return amount >= T.greatFindUSD
    }

    /// The caveats to show (first 2).
    var displayCaveats: [ValueCaveat] { Array(caveats.prefix(T.maxDisplayedCaveats)) }

    /// C on tiles and in their VoiceOver label (05 D8): "Wide range" /
    /// "Unsure match" / "Rough guide".
    var roughWord: String {
        if caveats.contains(.wideRange) { return "Wide range" }
        if caveats.contains(.unsureMatch) { return "Unsure match" }
        return "Rough guide"
    }

    /// The glyph that goes with `roughWord`.
    var roughGlyph: String {
        caveats.contains(.wideRange) ? "arrow.left.and.right" : "exclamationmark.triangle"
    }

    // MARK: Rules (04 §4.3: evaluate top to bottom, the first match wins)

    init(_ inputs: ValueInputs) {
        let low = max(0, min(inputs.low, inputs.high))
        let high = max(0, max(inputs.low, inputs.high))
        let ratio = high / max(low, T.ratioFloorUSD)
        let exact = inputs.comparablesAreExact && inputs.basis != .attributesOnly
        let match = MatchStrength(confidence: inputs.matchConfidence)
        let kind = ValueAssessment.evidenceKind(for: inputs)
        let count = ValueAssessment.evidenceCount(for: inputs)

        // S: usable exact sales with a median.
        let usableSold: SoldSummary? = ValueAssessment.usableSold(inputs.sold)
        var soldMedian: Double? = nil
        if let s = usableSold { soldMedian = s.median }
        var medianInside = false
        if let m = soldMedian { medianInside = m >= low && m <= high }
        let disagreement = soldMedian != nil && !medianInside

        // D
        var reason: NoPriceReason? = nil
        if inputs.notCollectible {
            reason = .notCollectible(confirmed: true)
        } else if ValueAssessment.looksNotCollectible(inputs) {
            reason = .notCollectible(confirmed: false)
        } else if inputs.basis == .offlineEstimate {
            reason = .onDevice(analysisOff: inputs.analysisOff)
        } else if high <= 0 {
            reason = .noValue
        } else if ratio > T.ratioRough {
            reason = .tooWide
        }

        // C / A / B
        let level: ValueLevel
        if reason != nil {
            level = .noPrice
        } else if ValueAssessment.isRough(ratio: ratio, kind: kind, exact: exact, match: match, valueConfidence: inputs.valueConfidence) {
            level = .rough
        } else if ValueAssessment.isStrong(ratio: ratio, kind: kind, exact: exact, match: match,
                                           count: count, hasUsableSold: usableSold != nil, disagreement: disagreement) {
            level = .strong
        } else {
            level = .fair
        }

        // Best estimate (A and B only)
        var best: BestEstimate? = nil
        if level >= .fair {
            if let s = usableSold, let m = s.median, medianInside {
                best = BestEstimate(amountUSD: m, source: .soldMedian(count: s.count, windowDays: s.windowDays))
            } else if let mid = inputs.valueMid, mid > 0, mid >= low, mid <= high {
                best = BestEstimate(amountUSD: mid, source: .engineMid)
            } else if let compsMedian = ValueAssessment.realisedCompsMedian(inputs.comparables),
                      compsMedian >= low, compsMedian <= high {
                best = BestEstimate(amountUSD: compsMedian, source: .compsMedian)
            }
        }

        // Caveats (A–C), in display order
        var caveats: [ValueCaveat] = []
        if level != .noPrice {
            if let s = usableSold, let m = s.median, !medianInside {
                if m > high {
                    caveats.append(.salesHigher(medianUSD: m, count: s.count))
                } else {
                    caveats.append(.salesLower(medianUSD: m, count: s.count))
                }
            }
            if level == .rough && ratio > T.ratioFair { caveats.append(.wideRange) }
            if match == .unsure { caveats.append(.unsureMatch) }
            if !exact { caveats.append(.similarItems) }
            if kind == .aiEstimate { caveats.append(.aiEstimate) }
        }

        // Notes
        var notes: [ValueNote] = []
        let isHighValue = high >= T.highValueUSD
        let isLowValue = high > 0 && high < T.lowValueUSD
        switch level {
        case .noPrice:
            if reason == .tooWide && isHighValue { notes.append(.highValue) }
        case .rough:
            notes.append(.notAnAppraisal)
            if isHighValue { notes.append(.highValue) }
            if isLowValue { notes.append(.lowValue) }
        case .fair, .strong:
            if isHighValue {
                notes.append(.highValue)
                notes.append(.notAnAppraisal)
            }
            if isLowValue { notes.append(.lowValue) }
        }

        // Evidence (A–C)
        var evidenceText: String? = nil
        if level != .noPrice {
            if let summary = inputs.priceSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                evidenceText = summary
            } else {
                evidenceText = kind.fallbackText
            }
        }

        self.level = level
        self.match = match
        self.evidence = level == .noPrice ? nil : kind
        self.evidenceCount = level == .noPrice ? nil : count
        self.evidenceText = evidenceText
        self.isExact = exact
        self.best = best
        self.noPriceReason = reason
        self.caveats = caveats
        self.notes = notes
        self.ratio = ratio
        self.lowUSD = low
        self.highUSD = high
    }

    // MARK: Rule helpers

    private static func isRough(ratio: Double, kind: EvidenceKind, exact: Bool,
                                match: MatchStrength, valueConfidence: Double) -> Bool {
        if ratio > T.ratioFair { return true }
        if kind == .aiEstimate { return true }
        if !exact { return true }
        if match == .unsure { return true }
        if valueConfidence <= T.valueConfidenceFloor { return true }
        return false
    }

    private static func isStrong(ratio: Double, kind: EvidenceKind, exact: Bool, match: MatchStrength,
                                 count: Int?, hasUsableSold: Bool, disagreement: Bool) -> Bool {
        guard match == .close else { return false }
        guard ratio <= T.ratioStrong else { return false }
        guard kind.isRealisedValue else { return false }
        guard exact else { return false }
        let enoughEvidence = (count ?? 0) >= T.minEvidenceStrong || hasUsableSold
        guard enoughEvidence else { return false }
        return !disagreement
    }

    /// `priceBasis` first, then (1) the best visible comparable type,
    /// (2) AI basis → AI, (3) market listings with no types → asking,
    /// (4) attributes-only → best comparable type, else AI.
    static func evidenceKind(for inputs: ValueInputs) -> EvidenceKind {
        if let raw = inputs.priceBasis, let kind = EvidenceKind(priceBasis: raw) {
            return kind
        }
        let strongest = EvidenceKind.strongest(of: inputs.comparables.map { $0.priceType })
        switch inputs.basis {
        case .aiEstimate:
            return strongest ?? .aiEstimate
        case .marketListings:
            return strongest ?? .asking
        case .attributesOnly:
            return strongest ?? .aiEstimate
        case .offlineEstimate:
            return .aiEstimate
        }
    }

    /// `evidenceCount`, else the visible comparables, else the withheld ones.
    /// nil when 0.
    static func evidenceCount(for inputs: ValueInputs) -> Int? {
        let raw: Int
        if let server = inputs.evidenceCount {
            raw = server
        } else if !inputs.comparables.isEmpty {
            raw = inputs.comparables.count
        } else {
            raw = inputs.lockedCount
        }
        return raw > 0 ? raw : nil
    }

    /// S: exact, available, ≥ `T.minSoldForBest` sales, with a median.
    static func usableSold(_ sold: SoldSummary?) -> SoldSummary? {
        guard let s = sold, !s.unavailable, s.isExact, s.count >= T.minSoldForBest else { return nil }
        guard let median = s.median, median > 0 else { return nil }
        return s
    }

    /// Median of the visible sold and guide comparables priced in USD.
    static func realisedCompsMedian(_ comparables: [MarketComparable]) -> Double? {
        var prices: [Double] = []
        for comp in comparables where comp.priceType != .asking && comp.price > 0 {
            if comp.currency.uppercased() == "USD" { prices.append(comp.price) }
        }
        guard !prices.isEmpty else { return nil }
        prices.sort()
        let mid = prices.count / 2
        if prices.count % 2 == 0 { return (prices[mid - 1] + prices[mid]) / 2 }
        return prices[mid]
    }

    /// 04 §4.5 soft heuristic: a person, a place or a screenshot, read from the
    /// title, only when nothing was catalogue-matched. Silent otherwise.
    static let notCollectibleTerms: [String] = [
        "photograph of", "landscape", "selfie", "portrait of", "screenshot",
        "people", "person", "scenery", "waterfall",
    ]
    /// Collected photographs (09 I8): "real photo postcard" is covered by "postcard".
    static let collectibleExceptions: [String] = [
        "vintage", "antique", "print", "postcard", "cabinet card", "carte",
        "tintype", "daguerreotype", "ambrotype", "photo album",
    ]

    static func looksNotCollectible(_ inputs: ValueInputs) -> Bool {
        guard !inputs.notCollectible, inputs.category == .unknown else { return false }
        guard inputs.basis == .attributesOnly || inputs.basis == .aiEstimate else { return false }
        let title = inputs.title.lowercased()
        let hit = notCollectibleTerms.contains { title.contains($0) }
        guard hit else { return false }
        let excepted = collectibleExceptions.contains { title.contains($0) }
        return !excepted
    }
}
