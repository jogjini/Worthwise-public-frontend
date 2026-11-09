import Foundation

extension ConditionGrade: Codable {}

struct SavedComparable: Codable, Identifiable {
    let id: UUID
    let source: String
    let price: Double
    let note: String
    // Added with the redesign. Optional so collections saved earlier still load.
    let priceType: PriceType?
    let url: URL?
    let currency: String?
    let imageURL: URL?

    init(source: String, price: Double, note: String, priceType: PriceType? = nil, url: URL? = nil, currency: String? = nil, imageURL: URL? = nil) {
        self.id = UUID()
        self.source = source
        self.price = price
        self.note = note
        self.priceType = priceType
        self.url = url
        self.currency = currency
        self.imageURL = imageURL
    }

    /// Back to the live model, so a saved item renders with the result screen.
    var asMarketComparable: MarketComparable {
        MarketComparable(
            source: source,
            price: price,
            currency: currency ?? "USD",
            note: note,
            priceType: priceType ?? .default,
            url: url,
            imageURL: imageURL
        )
    }
}

struct SavedCollectible: Codable, Identifiable {
    let id: UUID
    let savedAt: Date
    /// Editable (Edit Details). "Not sure" is stored as `.good` with
    /// `conditionSet == false`.
    var condition: ConditionGrade

    let title: String
    let probableCategory: CollectibleCategory
    let brand: String?
    let year: Int?
    let modelNumber: String?
    let barcode: String?
    let detectedText: [String]
    /// The user's notes (Review "Details", Edit Details "Your notes"). Editable.
    var userProvidedInfo: String?
    let scanConfidence: Double

    let estimateLow: Double
    let estimateHigh: Double
    let estimateConfidence: Double
    let estimateQuery: String
    let comparables: [SavedComparable]

    // Added with the redesign; nil on items saved before it.
    let basis: ValuationBasis?
    let attributes: [ItemAttribute]?
    let comparablesAreExact: Bool?
    let hasSecondImage: Bool?

    // Added with the price engine (Oct 2026); nil on items saved before it.
    /// How the range was reached, as the server put it.
    let priceSummary: String?
    /// Source ids for daily re-pricing (POST /api/prices). Opaque.
    let priceKeys: JSONValue?

    // Added with the Sold prices section (Oct 2026); nil on items saved before it.
    /// Sold prices as they were at scan time.
    let sold: SoldSummary?

    // Added with the redesign (13 Oct 2026); nil on items saved before it, so a
    // collection file written by build 2 still decodes. `ValueAssessment` falls
    // back when they are nil (see `ValueInputs(saved:)`).
    /// false = the user picked "Not sure" (stored grade is `.good`). nil = legacy: set.
    var conditionSet: Bool?
    /// Server `priceBasis` at scan time ("sold" | "guide" | "asking" | "estimate").
    let priceBasis: String?
    /// Server `evidenceCount` at scan time.
    let evidenceCount: Int?
    /// Server `valueMid` at scan time, USD.
    let valueMid: Double?
    /// Server not-a-collectible verdict at scan time.
    let notCollectible: Bool?
    /// Free plan: comparables withheld at scan time (for "You're on Pro now").
    let lockedComparableCount: Int?

    // Scan history. Every finished scan is stored; saving it to the collection
    // just sets `inCollection`. Both are nil on items saved before history
    // existed, which were all collection items.
    /// In the collection (vs. only in Recent scans). nil means true.
    var inCollection: Bool?
    /// Removed from Recent scans but kept in the collection. nil means false.
    var hiddenFromRecents: Bool?

    var isInCollection: Bool { inCollection ?? true }
    var isInRecents: Bool { !(hiddenFromRecents ?? false) }

    // NOTE: the item image is no longer stored inline here. It lives as a separate
    // file managed by CollectionStore (keyed by `id`), so this metadata stays small
    // and cheap to persist. Old files that embedded `imageData` are migrated on load.
    init(
        profile: CollectibleProfile,
        estimate: ValueEstimate,
        condition: ConditionGrade,
        hasSecondImage: Bool = false,
        inCollection: Bool = true,
        conditionSet: Bool = true
    ) {
        id = UUID()
        savedAt = Date()
        self.condition = condition
        self.conditionSet = conditionSet
        priceBasis = estimate.priceBasis
        evidenceCount = estimate.evidenceCount
        valueMid = estimate.mid
        notCollectible = profile.notCollectible
        lockedComparableCount = estimate.lockedComparableCount

        title = profile.title
        probableCategory = profile.probableCategory
        brand = profile.brand
        year = profile.year
        modelNumber = profile.modelNumber
        barcode = profile.barcode
        detectedText = profile.detectedText
        userProvidedInfo = profile.userProvidedInfo
        scanConfidence = profile.confidence

        estimateLow = estimate.low
        estimateHigh = estimate.high
        estimateConfidence = estimate.confidence
        estimateQuery = estimate.query
        comparables = estimate.comparables.map {
            SavedComparable(source: $0.source, price: $0.price, note: $0.note, priceType: $0.priceType, url: $0.url, currency: $0.currency, imageURL: $0.imageURL)
        }
        basis = estimate.basis
        attributes = profile.attributes
        comparablesAreExact = estimate.comparablesAreExact
        priceSummary = estimate.priceSummary
        priceKeys = estimate.priceKeys
        sold = estimate.sold
        self.hasSecondImage = hasSecondImage
        self.inCollection = inCollection
        hiddenFromRecents = false
    }

    var estimateMidpoint: Double {
        (estimateLow + estimateHigh) / 2
    }

    /// False only when the user chose "Not sure". Legacy items count as set.
    var isConditionSet: Bool { conditionSet ?? true }

    /// Level, evidence and caveats for this record (04 §4.2). Cheap: compute
    /// it where you need it rather than storing it.
    var assessment: ValueAssessment { ValueAssessment(ValueInputs(saved: self)) }
}

extension ValueInputs {
    /// A saved record. `analysisOff` is false: it isn't stored, so a legacy
    /// on-device record reads as "made without a connection".
    init(saved item: SavedCollectible) {
        let comps = item.comparables.map(\.asMarketComparable)
        // Same fallback as `ResultModel(saved:)` for records saved before `basis`.
        let basis = item.basis ?? (comps.isEmpty ? .aiEstimate : .marketListings)
        self.init(
            title: item.title,
            category: item.probableCategory,
            matchConfidence: item.scanConfidence,
            low: item.estimateLow,
            high: item.estimateHigh,
            valueConfidence: item.estimateConfidence,
            basis: basis,
            comparablesAreExact: item.comparablesAreExact ?? true,
            comparables: comps,
            lockedCount: item.lockedComparableCount ?? 0,
            priceSummary: item.priceSummary,
            priceBasis: item.priceBasis,
            evidenceCount: item.evidenceCount,
            valueMid: item.valueMid,
            sold: item.sold,
            notCollectible: item.notCollectible ?? false,
            analysisOff: false
        )
    }
}

struct CollectibleSet: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var name: String
    var itemIDs: [UUID]

    init(name: String) {
        id = UUID()
        createdAt = Date()
        self.name = name
        itemIDs = []
    }
}
