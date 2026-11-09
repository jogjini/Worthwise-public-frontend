import SwiftUI

// Home building blocks (WP1): the intro, the consent notice, the collection
// snapshot, the photo guides, "How Worthwise values", the empty recents card,
// the footer, and the How It Works sheet. (The file keeps its old name so the
// Xcode project needs no changes.)

// MARK: - How it works

/// "How It Works" (07 §4.3): reading a result, where the number comes from,
/// how sure we are, then photo technique, what a scan includes and why these
/// are estimates. Opened from Home, Settings and a result's "How we know".
struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WWSheetHeader(title: "How It Works", subtitle: "What it's worth, and how we know.", brand: true)
                        .padding(.top, WW.Space.xs)
                    HowItWorksAnatomy()
                        .padding(.top, WW.Space.xl)
                    HowItWorksLadder()
                        .padding(.top, WW.Space.sectionGap)
                    HowItWorksLevels()
                        .padding(.top, WW.Space.sectionGap)
                    ForEach(HowItWorksSheet.textSections) { section in
                        textSection(section)
                            .padding(.top, WW.Space.sectionGap)
                    }
                }
                .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                .padding(.bottom, WW.Space.xxxl)
            }
            .wwSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.wwBarTextProminent)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(WW.text)
    }

    private func textSection(_ section: InfoSection) -> some View {
        Text(section.body)
            .wwFont(.body)
            .foregroundStyle(WW.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wwSection(section.title)
    }

    struct InfoSection: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let textSections: [InfoSection] = [
        InfoSection(
            title: "Photograph the Item, Not the Room",
            body: "Fill the frame, lay the item flat, and use even light. A window beats a flash, which blows out foil and gloss. Hold the phone parallel to the item so the edges stay square."
        ),
        InfoSection(
            title: "Add the Back for a Better Match",
            body: "Trading cards: the back, so the set symbol and number are readable. Coins: the reverse. Pottery and glass: the base, where the maker's mark lives. Records: the label. Watches and sneakers: the caseback or size tag."
        ),
        InfoSection(
            title: "Type In What You Already Know",
            body: "Edition, serial number, where you bought it, any paperwork. A set name or certificate number turns a guess into a match faster than any photo."
        ),
        InfoSection(
            title: "What a Scan Includes",
            body: "Cloud analysis of your photos, a check against sold prices, price guides and marketplace listings, and the result you get back. Front and back of the same item count as one scan, and a scan that fails doesn't count. You get 3 free scans. Pro covers everyday use: up to 250 scans a month, or 60 a week on the weekly plan."
        ),
        InfoSection(
            title: "Estimates, Not Appraisals",
            body: "Every number here is automated and directional. Asking prices sit above what items actually sell for, so treat the top of a range as a ceiling. For anything that matters, check recent sold listings or get a professional opinion in person."
        ),
    ]
}

/// A numbered marker: 22 pt `text` circle with an `inverseText` numeral.
private struct AnatomyMarker: View {
    let number: Int
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        let side: CGFloat = min(size, 22 * WW.Size.graphicScaleCap)
        Text("\(number)")
            .font(.system(size: 12 * side / 22, weight: .semibold).monospacedDigit())
            .foregroundStyle(WW.inverseText)
            .frame(width: side, height: side)
            .background(WW.text, in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Reading a Result": the anatomy card, built from the real components with
/// example data (the 1921 Morgan dollar, 07 §1.2), then its legend.
private struct HowItWorksAnatomy: View {
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""

    static let exampleSales: [Double] = [38, 39.99, 41, 42, 43, 44, 45, 45, 46, 47, 48, 49, 51.5, 52]

    private struct LegendItem: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    private let legend: [LegendItem] = [
        LegendItem(id: 1, title: "How sure we are it's your item",
                   detail: "Close, possible or unsure. If it's wrong, tap Not the right item?"),
        LegendItem(id: 2, title: "What it usually sells for",
                   detail: "A range, never a single price. The tick is the best estimate, and each dot is one sale."),
        LegendItem(id: 3, title: "How we know",
                   detail: "The kind of prices we found, how many, and when we checked."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSectionHeader(title: "Reading a Result")
            card
            VStack(alignment: .leading, spacing: WW.Space.md) {
                ForEach(legend) { item in
                    legendRow(item)
                }
            }
            .padding(.top, WW.Space.xs)
        }
    }

    private var spokenExample: String {
        "Example result. Close match. Between \(WW.money(38)) and \(WW.money(52)), usually sells for \(WW.money(45)). Based on 14 sold prices in the last 90 days."
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            identity
            marked(1) {
                MatchIndicator(strength: .close)
            }
            marked(2) {
                valueBlock
            }
            marked(3) {
                evidenceBlock
            }
        }
        .wwCard(padding: WW.Space.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenExample)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Example · Coin · 1921")
                .wwFont(.meta)
                .foregroundStyle(WW.secondaryText)
            Text("Morgan silver dollar")
                .wwFont(.headline)
                .foregroundStyle(WW.text)
        }
        .padding(.leading, 28)
    }

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            ValueRangeText(lowUSD: 38, highUSD: 52, role: .valueRough)
            RangeBar(lowUSD: 38, highUSD: 52, bestUSD: 45, salesUSD: HowItWorksAnatomy.exampleSales)
            Text("Usually sells for \(WW.money(45))")
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var evidenceBlock: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            EvidenceLine(kind: .sold, text: "Based on 14 sold prices · last 90 days", isExact: true)
            Text("Prices checked 2 hours ago")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
        }
    }

    /// A row with its marker in the 28 pt gutter, aligned by first baseline.
    private func marked<Content: View>(_ number: Int, @ViewBuilder content: () -> Content) -> some View {
        let inner = content()
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            AnatomyMarker(number: number)
                .frame(width: 28, alignment: .leading)
            inner
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendRow(_ item: LegendItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AnatomyMarker(number: item.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Where the Number Comes From": the evidence ladder, strongest to weakest.
private struct HowItWorksLadder: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Rung: Identifiable {
        let kind: EvidenceKind
        let title: String
        let line: String
        var id: String { kind.rawValue }
    }

    private let rungs: [Rung] = [
        Rung(kind: .sold, title: "Sold prices", line: "What people actually paid. The strongest evidence."),
        Rung(kind: .guide, title: "Price guides", line: "Published prices for that exact item, like a card's market price."),
        Rung(kind: .asking, title: "Asking prices", line: "What sellers hope to get. Usually higher, so treat the top as a ceiling."),
        Rung(kind: .aiEstimate, title: "AI estimate", line: "No market prices found. A rough guide from the item's description."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSectionHeader(title: "Where the Number Comes From")
            VStack(alignment: .leading, spacing: WW.Space.md) {
                ladder
                WWHairline()
                similarNote
            }
            .wwCard()
        }
    }

    private var ladder: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            railLabel("Strongest", glyph: nil)
            ForEach(rungs) { rung in
                row(rung)
            }
            railLabel("Weakest", glyph: "arrow.down")
        }
        .padding(.leading, WW.Space.sm)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(WW.separator)
                .frame(width: 1)
                .accessibilityHidden(true)
        }
    }

    private func railLabel(_ text: String, glyph: String?) -> some View {
        HStack(spacing: 4) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .wwFont(.footnote)
        }
        .foregroundStyle(WW.tertiaryText)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func row(_ rung: Rung) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                EvidenceBadge(kind: rung.kind)
                rungText(rung)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .top, spacing: WW.Space.sm) {
                EvidenceBadge(kind: rung.kind)
                    .frame(width: 112, alignment: .leading)
                rungText(rung)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func rungText(_ rung: Rung) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rung.title)
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(rung.line)
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var similarNote: some View {
        (Text("Similar items").fontWeight(.semibold)
            + Text(": prices for look-alikes, not your exact piece. The range is wider on purpose."))
            .wwFont(.subhead)
            .foregroundStyle(WW.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "How Sure We Are": the level scale ("the surer we are, the bigger we say it").
private struct HowItWorksLevels: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.wwSurfaceLevel) private var surfaceLevel
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSectionHeader(title: "How Sure We Are")
            Text("Every result says how sure we are that it's your item: a close, possible or unsure match. Then the size of the value says how firm the price is.")
                .wwFont(.body)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
            levelRow(title: "A range you can use.",
                     detail: "Close match, enough evidence. Counted in your collection total.") {
                VStack(alignment: .leading, spacing: WW.Space.xxs) {
                    ValueRangeText(lowUSD: 38, highUSD: 52, role: .valueRough)
                    EvidenceBadge(kind: .sold)
                }
            }
            levelRow(title: "A rough guide.",
                     detail: "Wide range or thin evidence. Not counted in your total.") {
                VStack(alignment: .leading, spacing: WW.Space.xxs) {
                    CaveatFlag(glyph: "exclamationmark.triangle", text: "Rough guide", style: .inline)
                    ValueRangeText(lowUSD: 60, highUSD: 340, role: .price)
                }
            }
            levelRow(title: "No price.",
                     detail: "We'd rather say nothing than guess. Try a closer photo, or ask an expert.") {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 20, weight: .regular))
                        .accessibilityHidden(true)
                    Text("No price")
                        .wwFont(.headline)
                }
                .foregroundStyle(WW.secondaryText)
            }
        }
    }

    private func levelRow<Specimen: View>(title: String, detail: String, @ViewBuilder specimen: () -> Specimen) -> some View {
        let sample = specimen()
        let shape = RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: WW.Space.xs) {
                    sample
                    caption(title: title, detail: detail)
                }
            } else {
                HStack(alignment: .center, spacing: WW.Space.sm) {
                    sample
                        .fixedSize(horizontal: true, vertical: false)
                    caption(title: title, detail: detail)
                }
            }
        }
        .padding(WW.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceLevel == .elevated ? WW.elevated : WW.surface, in: shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(title: String, detail: String) -> some View {
        (Text(title).fontWeight(.semibold) + Text(" ") + Text(detail))
            .wwFont(.subhead)
            .foregroundStyle(WW.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Home intro

/// Under the brand bar: a greeting by time of day and "What's it worth?"
/// (05 §3.1). Greetings stay neutral (00: no weekend easter egg).
struct HomeIntro: View {
    init() {}

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
            Text("What's it worth?")
                .wwFont(.pageTitle)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Consent off

/// Home H4: photo analysis is off (05 §2.45). "Turn on" opens Settings.
struct ConsentOffNotice: View {
    let onTurnOn: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(onTurnOn: @escaping () -> Void) {
        self.onTurnOn = onTurnOn
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: WW.Space.xxs) {
                    message
                    turnOnButton
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    message
                    Spacer(minLength: WW.Space.xxs)
                    turnOnButton
                }
            }
        }
        .wwCard(padding: WW.Space.md, style: .caution)
    }

    private var message: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .wwFont(.subhead, weight: .semibold)
                .foregroundStyle(WW.caution)
                .accessibilityHidden(true)
            Text("Photo analysis is off, so items can't be identified.")
                .wwFont(.subhead)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var turnOnButton: some View {
        Button("Turn on", action: onTurnOn)
            .buttonStyle(WWTertiaryButtonStyle(tone: .accent, size: .small))
            .accessibilityLabel("Turn on photo analysis")
            .accessibilityHint("Opens Settings")
    }
}

// MARK: - Photo guides

/// One kind of item: how to photograph it, what to add, where its prices come
/// from, and one honest caveat (07 §5).
struct CategoryGuide: Identifiable, Hashable {
    /// The two photos the app actually takes (Review: front + back), 07 §5.1.
    struct Shots: Hashable {
        let first: String
        let second: String
        /// Glyph for the second frame.
        let detailGlyph: String
    }

    let id: String
    let icon: String
    let name: String
    let photos: [String]
    let details: String
    let prices: String
    let shots: Shots
    let goodToKnow: String

    /// The tile / plate glyph. Coins follow the display currency (05 §2.43).
    var glyph: String {
        id == "coins" ? WW.coinSymbol() : icon
    }

    /// The second shot-strip glyph (coins follow the currency too).
    var detailGlyph: String {
        id == "coins" ? WW.coinSymbol(filled: true) : shots.detailGlyph
    }

    /// "See what your ___ are worth", "Scan ___".
    var noun: String {
        switch id {
        case "cards": return "cards"
        case "coins": return "coins"
        case "comics": return "comics"
        case "vinyl": return "records"
        case "watches": return "watches"
        case "sneakers": return "sneakers"
        case "toys": return "toys"
        case "games": return "games"
        case "stamps": return "stamps"
        case "jewelry": return "jewelry"
        default: return "antiques"
        }
    }

    /// The user's kinds first, then the kinds their intent suggests (04 §5.1),
    /// then the rest in grid order.
    static func ordered(for interests: [String], intent: ScanIntent? = nil) -> [CategoryGuide] {
        let boost: [String] = intentOrder(intent)
        let mine: [CategoryGuide] = all.filter { interests.contains($0.id) }
        let boosted: [CategoryGuide] = boost.compactMap { id in
            interests.contains(id) ? nil : all.first(where: { $0.id == id })
        }
        let rest: [CategoryGuide] = all.filter { guide in
            !interests.contains(guide.id) && !boost.contains(guide.id)
        }
        return mine + boosted + rest
    }

    private static func intentOrder(_ intent: ScanIntent?) -> [String] {
        switch intent {
        case .some(.selling): return ["games", "toys", "sneakers", "cards", "vinyl"]
        case .some(.inherited): return ["antiques", "coins", "jewelry", "stamps", "watches"]
        default: return []
        }
    }

    static let all: [CategoryGuide] = [
        CategoryGuide(
            id: "cards", icon: "rectangle.stack", name: "Trading cards",
            photos: ["Front, flat and square to the camera", "The back if it's a sports card", "Crop to the card's edges"],
            details: "Edition (1st Edition, Shadowless), holo or reverse holo, and the grade if it's slabbed.",
            prices: "Price guides for the exact printing (TCGplayer, JustTCG, Scryfall, Cardmarket), plus eBay listings.",
            shots: Shots(first: "Front", second: "Back", detailGlyph: "rectangle.portrait.fill"),
            goodToKnow: "Graded? Photograph the slab label: the grade and certificate number decide the price."
        ),
        CategoryGuide(
            id: "coins", icon: "dollarsign.circle", name: "Coins",
            photos: ["Front and back, each filling the frame", "Raking light shows worn details", "Don't clean the coin first"],
            details: "Diameter in mm and weight in grams. Some designs were struck in several sizes worth very different amounts.",
            prices: "eBay listings for the same type.",
            shots: Shots(first: "Front", second: "Back", detailGlyph: "dollarsign.circle.fill"),
            goodToKnow: "Don't clean the coin first. Rare coins: get a professional opinion before you sell. Add size and weight in Details."
        ),
        CategoryGuide(
            id: "comics", icon: "book.closed", name: "Comics",
            photos: ["The full cover, straight on", "The slab label if it's graded", "The indicia (small print inside) for the year"],
            details: "Issue number, cover year, grade, and who signed it if it's signed.",
            prices: "eBay listings for the same issue, year, grade band and signature.",
            shots: Shots(first: "Cover", second: "Indicia or slab label", detailGlyph: "text.alignleft"),
            goodToKnow: "Signed? Say who signed it and whether it has a certificate."
        ),
        CategoryGuide(
            id: "vinyl", icon: "opticaldisc", name: "Vinyl",
            photos: ["The front sleeve", "The record label, where the catalog number is", "The barcode if there is one"],
            details: "Catalog number from the label or spine, and the pressing country if you know it.",
            prices: "Discogs price suggestions and listings for the release, plus eBay.",
            shots: Shots(first: "Sleeve", second: "Label", detailGlyph: "opticaldisc"),
            goodToKnow: "The catalog number on the label tells pressings apart, and they can sell for very different amounts."
        ),
        CategoryGuide(
            id: "watches", icon: "clock", name: "Watches",
            photos: ["The dial, straight on, no reflections", "The caseback with its reference number"],
            details: "Reference number, year, and whether you have the box and papers.",
            prices: "eBay listings for the same model and reference.",
            shots: Shots(first: "Dial", second: "Caseback", detailGlyph: "circle.circle"),
            goodToKnow: "We identify models, not authenticity. Box and papers often change the price."
        ),
        CategoryGuide(
            id: "sneakers", icon: "shoeprints.fill", name: "Sneakers",
            photos: ["Side profile of one shoe", "The size tag inside, with its style code"],
            details: "Size, colorway, and whether they're new or worn.",
            prices: "eBay listings for the same model and colorway.",
            shots: Shots(first: "Side", second: "Size tag", detailGlyph: "tag"),
            goodToKnow: "We identify models, not authenticity."
        ),
        CategoryGuide(
            id: "toys", icon: "teddybear", name: "Toys & figures",
            photos: ["The whole toy or the box front", "Any stamp, date or maker's mark underneath"],
            details: "Whether it's boxed, complete, and working.",
            prices: "eBay listings for the same toy.",
            shots: Shots(first: "Whole toy or box", second: "Marks underneath", detailGlyph: "magnifyingglass"),
            goodToKnow: "Boxed and complete usually sells for more. Say so in Details."
        ),
        CategoryGuide(
            id: "games", icon: "gamecontroller", name: "Games & consoles",
            photos: ["The cartridge, disc or console front", "The label on the back with the model number"],
            details: "Region (PAL, NTSC, Japan) and whether it's boxed and complete.",
            prices: "eBay listings for the same game or console.",
            shots: Shots(first: "Front", second: "Back label", detailGlyph: "barcode"),
            goodToKnow: "Region matters: PAL, NTSC and Japanese versions sell for different amounts."
        ),
        CategoryGuide(
            id: "antiques", icon: "cup.and.saucer", name: "Antiques & ceramics",
            photos: ["The whole piece, on a plain background", "The base or back, where marks are"],
            details: "Any marks, dimensions, and what you know about its history.",
            prices: "Similar pieces on eBay.",
            shots: Shots(first: "Whole piece", second: "Base and marks", detailGlyph: "magnifyingglass"),
            goodToKnow: "One-of-a-kind pieces get a wide range. Treat it as a starting point."
        ),
        CategoryGuide(
            id: "stamps", icon: "envelope", name: "Stamps",
            photos: ["The stamp straight on, all edges in", "The back, for hinge marks and watermarks"],
            details: "Country, year and face value. A catalog number if you have one.",
            prices: "eBay listings for the same stamp.",
            shots: Shots(first: "Straight on", second: "The back", detailGlyph: "envelope.fill"),
            goodToKnow: "Don't peel stamps off envelopes or album pages. Some are worth more left as they are."
        ),
        CategoryGuide(
            id: "jewelry", icon: "diamond", name: "Jewelry & silver",
            photos: ["The whole piece on a plain background", "The hallmark or maker's stamp, close up"],
            details: "Metal, weight in grams, any hallmarks, and stones if you know them.",
            prices: "Similar pieces on eBay.",
            shots: Shots(first: "Whole piece", second: "Hallmark", detailGlyph: "magnifyingglass"),
            goodToKnow: "We can't test metal or stones. For gold, gems and anything valuable, get it checked in person."
        ),
    ]
}

/// The 11 guide tiles: 3 columns, 2 at AX1–2, 1 (as rows) at AX3 (05 §2.43).
struct CategoryGrid: View {
    var interests: [String] = []
    var intent: ScanIntent? = nil
    let onSelect: (CategoryGuide) -> Void

    /// Redraws the Coins glyph when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(interests: [String] = [], intent: ScanIntent? = nil, onSelect: @escaping (CategoryGuide) -> Void) {
        self.interests = interests
        self.intent = intent
        self.onSelect = onSelect
    }

    private var columnCount: Int {
        if dynamicTypeSize >= .accessibility3 { return 1 }
        if dynamicTypeSize.isAccessibilitySize { return 2 }
        return 3
    }

    var body: some View {
        let guides: [CategoryGuide] = CategoryGuide.ordered(for: interests, intent: intent)
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columnCount)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(guides) { guide in
                Button {
                    onSelect(guide)
                } label: {
                    CategoryTile(guide: guide, isRow: columnCount == 1)
                }
                .buttonStyle(.wwPressable)
                .accessibilityLabel(guide.name)
                .accessibilityHint("Opens photo tips")
            }
        }
    }
}

private struct CategoryTile: View {
    let guide: CategoryGuide
    let isRow: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
        tileContent
            .frame(maxWidth: .infinity, minHeight: isRow ? WW.Size.rowTall : 88, alignment: isRow ? Alignment.leading : Alignment.center)
            .background(WW.surface, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
                }
            }
            .contentShape(shape)
    }

    @ViewBuilder
    private var tileContent: some View {
        if isRow {
            HStack(spacing: WW.Space.sm) {
                glyph
                name
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WW.Space.md)
            .padding(.vertical, WW.Space.sm)
        } else {
            VStack(spacing: WW.Space.xs) {
                glyph
                name
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
        }
    }

    /// Neutral, not Lapis: eleven accent glyphs would be the largest mass of
    /// Lapis on Home (05 §0.1, "one pigment, used sparingly").
    private var glyph: some View {
        Image(systemName: guide.glyph)
            .font(.system(size: 22, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(WW.text)
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }

    private var name: some View {
        Text(guide.name)
            .wwFont(.footnote, weight: .semibold)
            .foregroundStyle(WW.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What to photograph and add for one kind of item, where its prices come
/// from, and one honest caveat (07 §5.1). Pinned "Scan {noun}".
struct CategoryGuideSheet: View {
    let guide: CategoryGuide
    let onScan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""

    init(guide: CategoryGuide, onScan: @escaping () -> Void) {
        self.guide = guide
        self.onScan = onScan
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WWSheetHeader(
                        title: guide.name,
                        subtitle: "What we look for in \(guide.noun).",
                        brand: true,
                        systemImage: guide.glyph
                    )
                    .padding(.top, WW.Space.xs)
                    GuideShotStrip(guide: guide)
                        .padding(.top, WW.Space.xl)
                    photographSection
                        .padding(.top, WW.Space.sectionGap)
                    textSection("Add in Details", text: guide.details)
                        .padding(.top, WW.Space.sectionGap)
                    textSection("Where Prices Come From", text: guide.prices)
                        .padding(.top, WW.Space.sectionGap)
                    goodToKnowSection
                        .padding(.top, WW.Space.sectionGap)
                }
                .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                .padding(.bottom, WW.Space.xl)
            }
            .wwSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.wwBarTextProminent)
                        .fontWeight(.semibold)
                }
            }
            .wwBottomBar {
                Button {
                    // The host opens the camera once this sheet is gone.
                    onScan()
                    dismiss()
                } label: {
                    Label("Scan \(guide.noun)", systemImage: "camera")
                }
                .buttonStyle(.wwPrimary)
            }
        }
        .tint(WW.text)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var photographSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(guide.photos.enumerated()), id: \.offset) { index, line in
                GuideNumberedTip(number: index + 1, text: line)
            }
        }
        .wwCard()
        .wwSection("Photograph")
    }

    private func textSection(_ title: String, text: String) -> some View {
        Text(text)
            .wwFont(.body)
            .foregroundStyle(WW.text)
            .fixedSize(horizontal: false, vertical: true)
            .wwCard()
            .wwSection(title)
    }

    private var goodToKnowSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle")
                .wwFont(.body)
                .foregroundStyle(WW.accent)
                .accessibilityHidden(true)
            Text(guide.goodToKnow)
                .wwFont(.body)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .wwCard(style: .accentWash)
        .wwSection("Good to Know")
    }
}

private struct GuideNumberedTip: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WW.Space.sm) {
            AnatomyMarker(number: number)
            Text(text)
                .wwFont(.body)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The two photos the app takes for this kind of item (07 §5.1).
private struct GuideShotStrip: View {
    let guide: CategoryGuide

    var body: some View {
        HStack(alignment: .top, spacing: WW.Space.md) {
            shot(glyph: guide.glyph, label: guide.shots.first, recommended: false)
            shot(glyph: guide.detailGlyph, label: guide.shots.second, recommended: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo 1: \(guide.shots.first). Photo 2, recommended: \(guide.shots.second).")
    }

    private func shot(glyph: String, label: String, recommended: Bool) -> some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous)
                    .fill(WW.photoBackdrop)
                ViewfinderCorners(length: 16, radius: 6)
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .padding(10)
                Image(systemName: glyph)
                    .font(.system(size: 32, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white)
            }
            .frame(width: 88, height: 116)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                if recommended {
                    Text("Recommended")
                        .wwFont(.footnote)
                        .foregroundStyle(WW.secondaryText)
                }
            }
            .frame(width: 88, alignment: .leading)
        }
    }
}

// MARK: - Collection snapshot

/// Home H3: the counted total, item count (+ not counted) and the top three
/// thumbnails by value, linking to the Collection tab (05 §2.45).
struct CollectionSnapshotCard: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onOpen: () -> Void

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            content
        }
        .buttonStyle(.wwPressable)
        .accessibilityHint("Opens your collection")
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 14) {
            summary
            Spacer(minLength: WW.Space.xs)
            if !dynamicTypeSize.isAccessibilitySize {
                thumbs
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WW.tertiaryText)
                .accessibilityHidden(true)
        }
        .wwCard(padding: WW.Space.md)
        .contentShape(Rectangle())
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            Text("Your collection")
                .wwOverline()
            total
            Text(countLine)
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .wwAnimation(.crossfade, value: totalKey)
    }

    /// Counted items only (04 §4.4). Money crossfades, never rolls (06 M17).
    @ViewBuilder
    private var total: some View {
        if collectionStore.countedItems.isEmpty {
            Text("No total yet")
                .wwFont(.itemTitle)
                .foregroundStyle(WW.text)
                .transition(.opacity)
        } else {
            ValueRangeText(
                lowUSD: collectionStore.totalEstimatedLow,
                highUSD: collectionStore.totalEstimatedHigh,
                role: .priceLarge
            )
            .id(totalKey)
            .transition(.opacity)
        }
    }

    private var totalKey: String {
        "\(collectionStore.totalEstimatedLow)-\(collectionStore.totalEstimatedHigh)-\(displayCurrency)"
    }

    private var countLine: String {
        let count = collectionStore.items.count
        var line = count == 1 ? "1 item" : "\(count) items"
        let uncounted = collectionStore.uncountedCount
        if uncounted > 0 {
            line += " · \(uncounted) not counted"
        }
        return line
    }

    private var thumbIDs: [UUID] {
        Array(collectionStore.sortedByValue.prefix(3)).map(\.id)
    }

    /// Up to three overlapping thumbnails of the most valuable items; a new
    /// one settles in (06 M16).
    private var thumbs: some View {
        let ids: [UUID] = thumbIDs
        return HStack(spacing: -14) {
            ForEach(ids, id: \.self) { id in
                thumb(id)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .wwAnimation(.settle, value: ids)
        .accessibilityHidden(true)
    }

    private func thumb(_ id: UUID) -> some View {
        let shape = RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous)
        return Color.clear
            .frame(width: 44, height: 44)
            .overlay {
                if let image = collectionStore.thumbnail(for: id) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    PhotoPlaceholder()
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(WW.surface, lineWidth: 2)
            }
    }
}

// MARK: - How Worthwise values

/// The three steps behind every value, joined by a thread (07 §4.4), and the
/// way into How It Works.
struct HowItValuesCard: View {
    let onLearnMore: () -> Void
    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 34

    init(onLearnMore: @escaping () -> Void) {
        self.onLearnMore = onLearnMore
    }

    private struct Step: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let detail: String
    }

    private let steps: [Step] = [
        Step(id: 0, icon: "viewfinder", title: "Identify",
             detail: "We read names, numbers and marks, then match them against catalogs."),
        Step(id: 1, icon: "checkmark.seal", title: "Check the market",
             detail: "Sold prices first, then price guides, then asking prices, for that exact item."),
        Step(id: 2, icon: "arrow.left.and.right", title: "Give a range",
             detail: "With the evidence behind it, and a plain flag when the evidence is thin."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: WW.Space.md) {
                ForEach(steps) { step in
                    WWInfoRow(icon: step.icon, title: step.title, detail: step.detail, iconStyle: .neutral)
                        .background(alignment: .topLeading) {
                            thread(isLast: step.id == steps.count - 1)
                        }
                }
            }
            WWHairline()
                .padding(.top, WW.Space.md)
            Button(action: onLearnMore) {
                HStack(alignment: .center, spacing: WW.Space.xs) {
                    Text("Estimates, not appraisals: how to read a result")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WW.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(WWTertiaryButtonStyle(tone: .neutral, size: .small))
            .padding(.top, WW.Space.xxs)
        }
        .wwCard()
    }

    /// A 1 pt `separator` line from this step's circle down to the next one.
    @ViewBuilder
    private func thread(isLast: Bool) -> some View {
        if !isLast {
            let side: CGFloat = min(circleSize, WW.Size.infoIcon * WW.Size.graphicScaleCap)
            Rectangle()
                .fill(WW.separator)
                .frame(width: 1)
                .padding(.top, side)
                .padding(.bottom, -WW.Space.md)
                .offset(x: side / 2 - 0.5)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Empty recent scans

/// Home H1: what the Recent area says before the first scan (07 §3, with
/// 06 §4.5's truth fix: unsaved scans beyond 50 are pruned).
struct RecentEmptyCard: View {
    init() {}

    var body: some View {
        WWEmptyState(
            title: "Your scans appear here",
            message: "Save the ones you want to keep. We hold on to your last 50 unsaved scans.",
            style: .inline,
            illustration: AnyView(WWGhostTiles())
        )
    }
}

// MARK: - Footer

struct HomeFooter: View {
    init() {}

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 6) {
            WorthwiseMark(size: 22, tone: .ink)
                .opacity(0.35)
            Text(version.isEmpty ? "Worthwise" : "Worthwise \(version)")
                .wwFont(.footnote)
                .foregroundStyle(WW.tertiaryText)
            Text("Values are estimates for information only.")
                .wwFont(.footnote)
                .foregroundStyle(WW.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
