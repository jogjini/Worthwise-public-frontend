import SwiftUI
import Charts
import Accessibility

// The result (WP2, 04 §6.4, 05 §3.5, 06 §2.4): one `ResultView` for fresh
// and stored results, the value card per level (A/B/C/D), the options menu,
// the action bar, the Pro cards, the improve card, the correction and
// Edit Details sheets, the sold-prices and price-history charts, and the
// share card. Money never animates (06 L3).

// MARK: - Model

/// Everything the result screen shows, built either from a fresh scan or from a
/// saved collection item, so both render exactly the same way.
struct ResultModel {
    /// Why a result came from the on-device pipeline. "The network was down"
    /// and "you turned photo analysis off" need different explanations.
    enum OnDeviceReason {
        case networkFallback
        case analysisDisabled
    }

    let title: String
    /// "Trading Card · 2011 · Pokémon" (drawn uppercase by the `.meta` role).
    let meta: String
    /// "Trading Card, 2011, Pokémon" for VoiceOver.
    let metaSpoken: String
    let category: CollectibleCategory
    let photos: [UIImage]
    let low: Double
    let high: Double
    let matchConfidence: Double
    let basis: ValuationBasis
    let comparables: [MarketComparable]
    let comparablesAreExact: Bool
    /// Free plan: comparables the server withheld (fresh and, since the
    /// redesign, saved records).
    let lockedCount: Int
    let lockedSources: [String]
    let details: [ItemAttribute]
    /// nil = "Not sure" (not set).
    let condition: ConditionGrade?
    let notes: String?
    let onDeviceReason: OnDeviceReason
    /// When the prices were looked up: now for a fresh scan, the scan date for
    /// a saved one. Collector apps show this so an old value isn't read as today's.
    let checkedAt: Date
    /// How the range was reached, from the server ("From 3 sold prices…").
    let priceSummary: String?
    /// The price chart's data (Pro). Nil when there is none or it is locked.
    let history: PriceHistory?
    /// Free plan: a history exists but is a Pro feature.
    let historyLocked: Bool
    /// A saved item whose history the server is still building.
    let historyPending: Bool
    /// Recent sold prices for the "Sold Prices" section. Nil hides the section.
    let sold: SoldSummary?
    /// Server candidates when the match is unsure (04 §10 S6). Fresh only.
    let candidates: [MatchCandidate]
    /// A back / base photo was taken.
    let hasBackPhoto: Bool
    /// Level, evidence, caveats and best estimate (04 §4). Computed once.
    let assessment: ValueAssessment

    /// A fresh scan. `condition: nil` means "Not sure".
    init(
        profile: CollectibleProfile,
        estimate: ValueEstimate,
        condition: ConditionGrade?,
        photos: [UIImage],
        onDeviceReason: OnDeviceReason
    ) {
        title = profile.title
        meta = ResultModel.metaLine(category: profile.probableCategory, year: profile.year, brand: profile.brand)
        metaSpoken = ResultModel.metaLine(category: profile.probableCategory, year: profile.year, brand: profile.brand, separator: ", ")
        category = profile.probableCategory
        self.photos = photos
        low = estimate.low
        high = estimate.high
        matchConfidence = profile.confidence
        basis = estimate.basis
        comparables = estimate.comparables
        comparablesAreExact = estimate.comparablesAreExact
        lockedCount = estimate.lockedComparableCount
        lockedSources = estimate.lockedSources
        details = ResultModel.detailRows(
            attributes: profile.attributes,
            category: profile.probableCategory,
            brand: profile.brand,
            year: profile.year,
            model: profile.modelNumber,
            barcode: profile.barcode
        )
        self.condition = condition
        notes = profile.userProvidedInfo
        self.onDeviceReason = onDeviceReason
        checkedAt = Date()
        priceSummary = estimate.priceSummary
        history = estimate.history
        historyLocked = estimate.historyLocked
        historyPending = false
        sold = estimate.sold
        candidates = profile.candidates
        hasBackPhoto = photos.count > 1
        let inputs = ValueInputs(profile: profile, estimate: estimate, analysisOff: onDeviceReason == .analysisDisabled)
        assessment = ValueAssessment(inputs)
    }

    /// A stored scan. `history` comes from the collection's daily re-pricing (POST /api/prices).
    init(saved item: SavedCollectible, photos: [UIImage], history: PriceHistory? = nil, historyLocked: Bool = false) {
        checkedAt = item.savedAt
        priceSummary = item.priceSummary
        self.history = history
        self.historyLocked = historyLocked && history == nil && item.priceKeys != nil
        historyPending = history == nil && !historyLocked && item.priceKeys != nil && item.isInCollection
        sold = item.sold
        title = item.title
        meta = ResultModel.metaLine(category: item.probableCategory, year: item.year, brand: item.brand)
        metaSpoken = ResultModel.metaLine(category: item.probableCategory, year: item.year, brand: item.brand, separator: ", ")
        category = item.probableCategory
        self.photos = photos
        low = item.estimateLow
        high = item.estimateHigh
        matchConfidence = item.scanConfidence
        let comps = item.comparables.map(\.asMarketComparable)
        basis = item.basis ?? (comps.isEmpty ? .aiEstimate : .marketListings)
        comparables = comps
        comparablesAreExact = item.comparablesAreExact ?? true
        lockedCount = item.lockedComparableCount ?? 0
        lockedSources = []
        details = ResultModel.detailRows(
            attributes: item.attributes ?? [],
            category: item.probableCategory,
            brand: item.brand,
            year: item.year,
            model: item.modelNumber,
            barcode: item.barcode
        )
        condition = item.isConditionSet ? item.condition : nil
        notes = item.userProvidedInfo
        onDeviceReason = .networkFallback
        candidates = []
        hasBackPhoto = (item.hasSecondImage ?? false) || photos.count > 1
        assessment = item.assessment
    }

    static func metaLine(category: CollectibleCategory, year: Int?, brand: String?, separator: String = " · ") -> String {
        var parts: [String] = []
        if category != .unknown { parts.append(category.rawValue) }
        if let year { parts.append(String(year)) }
        if let brand, !brand.isEmpty { parts.append(brand) }
        return parts.joined(separator: separator)
    }

    static func detailRows(
        attributes: [ItemAttribute],
        category: CollectibleCategory,
        brand: String?,
        year: Int?,
        model: String?,
        barcode: String?
    ) -> [ItemAttribute] {
        // Labels that are blank on purpose (continuation rows) are dropped.
        let cleaned = attributes.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.isEmpty }
        if !cleaned.isEmpty { return cleaned }
        var rows: [ItemAttribute] = []
        if category != .unknown { rows.append(ItemAttribute(label: "Category", value: category.rawValue)) }
        if let brand, !brand.isEmpty { rows.append(ItemAttribute(label: "Brand", value: brand)) }
        if let year { rows.append(ItemAttribute(label: "Year", value: String(year))) }
        if let model, !model.isEmpty { rows.append(ItemAttribute(label: "Number", value: model)) }
        if let barcode, !barcode.isEmpty { rows.append(ItemAttribute(label: "Barcode", value: barcode)) }
        return rows
    }

    /// Identifier rows (Number, Barcode, Cert, Catalogue, Ref.) are set in SF Mono (05 §2.34).
    static func isIdentifier(_ label: String) -> Bool {
        let key = label.lowercased().trimmingCharacters(in: .whitespaces)
        let exact: Set<String> = ["number", "barcode", "cert", "cert.", "catalogue", "catalog", "ref", "ref.",
                                  "reference", "upc", "ean", "isbn", "sku", "serial", "model"]
        if exact.contains(key) { return true }
        return key.hasSuffix(" number") || key.hasSuffix(" no.") || key.hasPrefix("cert") || key.hasPrefix("catalog")
    }

    // MARK: Derived

    var hasPhotos: Bool { !photos.isEmpty }

    /// "Prices checked just now" (+ " · prices may have changed" at 30 days or more, 07 §4.1).
    var checkedLine: String {
        let age: TimeInterval = -checkedAt.timeIntervalSinceNow
        let base: String
        if age < 120 {
            base = "Prices checked just now"
        } else {
            base = "Prices checked \(checkedAt.formatted(.relative(presentation: .named)))"
        }
        return age >= 30 * 86_400 ? base + " · prices may have changed" : base
    }

    /// Sale prices (USD) for the `RangeBar` dots, newest first. Pro only: a
    /// Free result with example sales (04 §10 S13) still has `salesLocked > 0`,
    /// and we never draw a sale we can't show (07 §4.2).
    var dotSalesUSD: [Double] {
        guard let sold, !sold.unavailable, sold.salesLocked == 0, !sold.sales.isEmpty else { return [] }
        let usd: [SoldSale] = sold.sales.filter { $0.currency.uppercased() == "USD" }
        let sorted: [SoldSale] = usd.sorted { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
        return sorted.map(\.price)
    }

    /// The plain-text line shared next to the card image (00 addition 10).
    var shareText: String {
        let va = assessment
        var parts: [String] = []
        let range = WW.range(va.lowUSD, va.highUSD)
        parts.append("\(title): \(range)\(va.level == .rough ? " (rough guide)" : "")")
        parts.append(va.match.label)
        if let evidence = va.evidenceText {
            let trimmed = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed)
        }
        parts.append("Prices checked \(checkedAt.formatted(date: .abbreviated, time: .omitted))")
        parts.append("Estimate, not an appraisal")
        return parts.joined(separator: ". ") + ". Worthwise"
    }
}

// MARK: - Result view

/// The result for a fresh scan or a stored record (04 §6.4–6.5). Hosts pass
/// navigation only (`ResultContext`); this view performs record mutations
/// itself through `CollectionStore`, draws its toolbar (options menu, and
/// Done for a fresh scan), the action bar, and plays the reveal (06 §2.4).
struct ResultView: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @AppStorage("ww.firstSaveShown") private var firstSaveShown = false
    @AppStorage("ww.firstCountedShown") private var firstCountedShown = false
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var creditManager: CreditManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: ResultModel
    let context: ResultContext
    /// Transition init only (04 §11.2): the old host's inline actions.
    private let legacyActions: AnyView?
    /// Transition init only: the old host's own correction flow.
    private let legacyCorrect: (() -> Void)?

    @State private var activeSheet: ResultSheet?
    @State private var toast: WWToastModel?
    /// Saved from this screen (keeps the "Saved" state in the bar of a stored record).
    @State private var savedHere = false
    /// "Replace saved item" done.
    @State private var replacedHere = false
    /// 06 M15 [P05]: after Save, "Scan next" takes the Lapis fill.
    @State private var emphasisOnScanNext = false

    // Reveal (06 §2.4)
    @State private var didStartReveal = false
    @State private var cardVisible = false
    @State private var spanProgress: Double = 0
    @State private var evidenceSettled = false
    @State private var stampTrigger = 0
    @State private var greatFindVisible = false
    @State private var swingAngle: Double = 0
    @AccessibilityFocusState private var identityFocused: Bool

    init(model: ResultModel, context: ResultContext) {
        self.model = model
        self.context = context
        self.legacyActions = nil
        self.legacyCorrect = nil
    }

    /// Transition init (04 §11.2): forwards to the new view with a stored
    /// context; `actions` render inline under the value card instead of the
    /// action bar. Remove once no host calls it.
    @available(*, deprecated, message: "Use ResultView(model:context:).")
    init<Actions: View>(
        model: ResultModel,
        onUnlockListings: (() -> Void)? = nil,
        onCorrect: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.model = model
        self.context = ResultContext(origin: .stored, onUnlock: onUnlockListings)
        self.legacyActions = AnyView(actions())
        self.legacyCorrect = onCorrect
    }

    // MARK: Derived state

    private var va: ValueAssessment { model.assessment }
    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isPro: Bool { creditManager.isPro }

    private var record: SavedCollectible? {
        guard let id = context.recordID else { return nil }
        return collectionStore.record(id: id)
    }

    private var isSaved: Bool { record?.isInCollection ?? false }

    private var currentFolder: CollectibleSet? {
        guard let id = context.recordID else { return nil }
        return collectionStore.setContaining(itemID: id)
    }

    /// Condition and notes as stored now (Edit Details changes the record,
    /// not the fresh model).
    private var shownCondition: ConditionGrade? {
        guard let record else { return model.condition }
        return record.isConditionSet ? record.condition : nil
    }

    private var shownNotes: String? {
        if let record { return record.userProvidedInfo }
        return model.notes
    }

    /// A rescan is possible: fresh results go back to Review; stored ones need a photo.
    private var canRescan: Bool {
        context.onRescan != nil && (context.isFresh || model.hasPhotos)
    }

    private var isOnDeviceD: Bool {
        guard va.level == .noPrice, let reason = va.noPriceReason else { return false }
        return reason.wwIsOnDevice
    }

    private var isNotCollectibleD: Bool {
        guard va.level == .noPrice, let reason = va.noPriceReason else { return false }
        return reason.wwIsNotCollectible
    }

    /// "Not the right item?" (hidden for D on-device, and in not-a-collectible
    /// D, where the card offers "It is a collectible").
    private var canCorrect: Bool {
        if legacyCorrect != nil { return true }
        return canRescan && !isOnDeviceD && !isNotCollectibleD
    }

    private var savedTitle: String {
        if let folder = currentFolder { return "Saved to \(folder.name)" }
        return "Saved"
    }

    // MARK: Body

    var body: some View {
        scrollContent
            .background(WW.background)
            .wwToast($toast)
            .wwBottomBar(pinned: barIsPinned) {
                actionBar(stacked: false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(sheet)
            }
            .task { await runReveal() }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headBlocks
                valueBlocks
                evidenceBlocks
                footer
            }
            .padding(.horizontal, WW.margin(for: dynamicTypeSize))
            .padding(.bottom, WW.Space.xxl)
        }
    }

    /// Photo, identity, match, "Not the right item?".
    private var headBlocks: some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultPhotoHeader(photos: model.photos, title: model.title)
                .padding(.top, WW.Space.xs)
            ResultIdentity(
                meta: model.meta,
                metaSpoken: model.metaSpoken,
                title: model.title,
                chipText: identityChipText
            )
            .accessibilityFocused($identityFocused)
            .padding(.top, WW.Space.md)
            matchBlock
        }
    }

    private var identityChipText: String? {
        guard isSaved else { return nil }
        if let folder = currentFolder { return "In your collection · \(folder.name)" }
        return "In your collection"
    }

    /// Match word, then "Not the right item?" on the same line when both fit
    /// (RS-1: saves a 44 pt row above the value); stacked otherwise and at
    /// AX sizes. VoiceOver order is the same either way.
    @ViewBuilder
    private var matchBlock: some View {
        if !isOnDeviceD && canCorrect && !isAX {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    MatchIndicator(strength: va.match)
                    Spacer(minLength: WW.Space.sm)
                    correctButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    MatchIndicator(strength: va.match)
                    correctButton
                }
            }
            .padding(.top, WW.Space.sm)
        } else {
            if !isOnDeviceD {
                MatchIndicator(strength: va.match)
                    .padding(.top, WW.Space.sm)
            }
            if canCorrect {
                correctButton
            }
        }
    }

    private var correctButton: some View {
        Button("Not the right item?") {
            openCorrection()
        }
        .buttonStyle(WWTertiaryButtonStyle(.accent, .small))
    }

    /// Great find, value card, inline bar (AX), improve card.
    private var valueBlocks: some View {
        VStack(alignment: .leading, spacing: 0) {
            greatFindLine
            ValueCard(
                model: model,
                scanCharged: context.scanCharged,
                spanProgress: revealMode == .full ? spanProgress : 1,
                evidenceShown: revealMode != .full || evidenceSettled || va.level < .fair,
                stampTrigger: stampTrigger,
                onHowWeKnow: { activeSheet = .howItWorks },
                onItIsCollectible: itIsCollectibleAction
            )
            .opacity(cardIsShown ? 1 : 0)
            .offset(y: cardOffset)
            .padding(.top, va.isGreatFind ? WW.Space.sm : (canCorrect ? WW.Space.xs : WW.Space.md))
            inlineActions
            improveCard
        }
    }

    @ViewBuilder
    private var greatFindLine: some View {
        if va.isGreatFind {
            HStack(spacing: WW.Space.xs) {
                WorthwiseMark(size: 22, tone: .accent)
                    .rotationEffect(.degrees(swingAngle), anchor: WW.Motion.swingAnchor)
                Text("That's a good find.")
                    .wwFont(.brandTitle)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(revealMode != .full || greatFindVisible ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("That's a good find.")
            .padding(.top, WW.Space.md)
        }
    }

    @ViewBuilder
    private var inlineActions: some View {
        if let legacyActions {
            legacyActions
                .padding(.top, WW.Space.md)
        } else if isAX && barHasContent {
            actionBar(stacked: true)
                .padding(.top, WW.Space.md)
        }
    }

    @ViewBuilder
    private var improveCard: some View {
        if let advice = improveAdvice {
            ImproveResultCard(
                advice: advice,
                costLine: ImproveResultCard.defaultCostLine,
                onImprove: improveAction
            )
            .padding(.top, WW.Space.md)
        }
    }

    /// Sold Prices, Pro card, Prices Behind This Estimate, Price History, Details.
    private var evidenceBlocks: some View {
        VStack(alignment: .leading, spacing: 0) {
            if va.level != .noPrice {
                if let sold = model.sold {
                    SoldPricesSection(sold: sold)
                        .padding(.top, WW.Space.sectionGap)
                }
                proCard
                    .wwAnimation(.standard, value: isPro)
                if !model.comparables.isEmpty {
                    ListingsSection(
                        comparables: model.comparables,
                        evidenceCount: va.evidenceCount,
                        isExact: va.isExact
                    )
                    .padding(.top, WW.Space.sectionGap)
                }
                if historyIsVisible {
                    PriceHistorySection(history: model.history, pending: model.historyPending, low: model.low, high: model.high)
                        .padding(.top, WW.Space.sectionGap)
                }
            }
            ResultDetailsSection(
                details: model.details,
                category: model.category,
                condition: shownCondition,
                notes: shownNotes,
                onEdit: editDetailsAction
            )
            .wwAnimation(.crossfade, value: shownNotes ?? "")
            .padding(.top, WW.Space.sectionGap)
        }
    }

    private var historyIsVisible: Bool {
        (model.history?.isDrawable ?? false) || model.historyPending
    }

    private var footer: some View {
        Text("Estimates are a guide, not an appraisal. Check recent sales before you buy or sell.")
            .wwFont(.footnote)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, WW.Space.sectionGap)
    }

    // MARK: Toolbar and sheets

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ResultOptionsMenu(model: model, context: context, actions: menuActions)
        }
        if context.isFresh && context.onDone != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    context.onDone?()
                }
                .buttonStyle(.wwBarTextProminent)
                .fontWeight(.semibold)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ResultSheet) -> some View {
        switch sheet {
        case .correction:
            CorrectionSheet(
                currentTitle: model.title,
                candidates: model.candidates,
                costLine: CorrectionSheet.defaultCostLine,
                onRescan: { hint in
                    if let onRescan = context.onRescan { onRescan(.withHint(hint)) }
                },
                onEditPhotos: editPhotosAction
            )
        case .editDetails:
            if let record {
                EditDetailsSheet(
                    record: record,
                    onSave: { grade, isSet, notes in updateDetails(grade: grade, isSet: isSet, notes: notes) },
                    onRescan: rescanWithChangesAction
                )
            }
        case .howItWorks:
            HowItWorksSheet()
        case .share(let items):
            WWActivitySheet(items: items)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    // Optional actions, typed once (no closure literals inside ternaries).

    private var itIsCollectibleAction: (() -> Void)? {
        guard canRescan else { return nil }
        return { openCorrection() }
    }

    private var improveAction: (() -> Void)? {
        guard !barOffersEditPhotos, let onRescan = context.onRescan else { return nil }
        return { onRescan(.editPhotos) }
    }

    private var editDetailsAction: (() -> Void)? {
        guard record != nil else { return nil }
        return { activeSheet = .editDetails }
    }

    private var editPhotosAction: (() -> Void)? {
        guard canRescan, let onRescan = context.onRescan else { return nil }
        return { onRescan(.editPhotos) }
    }

    private var rescanWithChangesAction: (() -> Void)? {
        guard canRescan else { return nil }
        return { rescanWithChanges() }
    }

    private func openCorrection() {
        if let legacyCorrect {
            legacyCorrect()
        } else {
            activeSheet = .correction
        }
    }

    // MARK: Action bar (05 §2.36)

    private var barIsPinned: Bool {
        legacyActions == nil && !isAX && barHasContent
    }

    private var barHasContent: Bool {
        legacyActions == nil && (barPrimary != nil || barSecondary != nil)
    }

    private func actionBar(stacked: Bool) -> some View {
        VStack(spacing: WW.Space.xs) {
            if replacementIsRougher {
                // A re-check that came back rougher (e.g. A → C): replacing is a choice.
                Text("This result is rougher than the saved one.")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            ResultActionBar(
                model: model,
                context: context,
                primary: barPrimary,
                secondary: barSecondary,
                emphasizeSecondary: emphasisOnScanNext,
                stacked: stacked,
                folders: collectionStore.sets,
                onSave: { folderID in save(to: folderID) },
                onSaveToNewFolder: { name in createFolder(name) },
                onReplace: { replaceSavedItem() }
            )
        }
    }

    /// The bar offers "Replace saved item" and this result's level is lower
    /// than the saved record's.
    private var replacementIsRougher: Bool {
        guard case .replace? = barPrimary else { return false }
        guard let oldID = context.replacing, let saved = collectionStore.record(id: oldID) else { return false }
        return va.level < saved.assessment.level
    }

    private var barPrimary: ResultActionBar.Primary? {
        if va.level == .noPrice {
            if let action = recoveryAction { return .recovery(action) }
            return nil
        }
        if context.isFresh {
            if replacedHere { return .saved(savedTitle) }
            if context.replacing != nil && context.recordID != nil { return .replace }
        }
        guard let record else { return nil }
        if record.isInCollection {
            if context.isFresh || savedHere { return .saved(savedTitle) }
            return nil
        }
        return .save
    }

    private var barSecondary: ResultActionBar.Action? {
        guard context.isFresh, let onScanNext = context.onScanNext else { return nil }
        // 00 addition 2: not a collectible has one primary only.
        if isNotCollectibleD { return nil }
        return ResultActionBar.Action(title: "Scan next", systemImage: "camera", perform: onScanNext)
    }

    /// The D recovery action (04 §6.4D), when this host can perform it.
    private var recoveryAction: ResultActionBar.Action? {
        guard let reason = va.noPriceReason else { return nil }
        let title: String = reason.recoveryTitle
        switch reason {
        case .tooWide, .noValue:
            guard canRescan, let onRescan = context.onRescan else { return nil }
            return ResultActionBar.Action(title: title, systemImage: "arrow.uturn.backward", perform: { onRescan(.editPhotos) })
        case .notCollectible:
            guard let onScanNext = context.onScanNext else { return nil }
            return ResultActionBar.Action(title: title, systemImage: "camera", perform: onScanNext)
        case .onDevice(let analysisOff):
            if analysisOff {
                guard let open = context.onOpenSettings else { return nil }
                return ResultActionBar.Action(title: title, systemImage: "gearshape", perform: open)
            }
            guard canRescan, let onRescan = context.onRescan else { return nil }
            return ResultActionBar.Action(title: title, systemImage: "arrow.clockwise", perform: { onRescan(.checkPriceAgain) })
        }
    }

    /// The bar already offers "Edit photos and scan again", so the improve
    /// card shows only its advice (04 §6.4D).
    private var barOffersEditPhotos: Bool {
        guard va.level == .noPrice, let reason = va.noPriceReason, recoveryAction != nil else { return false }
        switch reason {
        case .tooWide, .noValue: return true
        case .notCollectible, .onDevice: return false
        }
    }

    // MARK: Improve card (04 §4.4)

    private var improveAdvice: ImproveResultCard.Advice? {
        guard legacyActions == nil, canRescan else { return nil }
        switch va.level {
        case .strong:
            return nil
        case .fair:
            guard va.match == .possible && !model.hasBackPhoto else { return nil }
        case .rough:
            break
        case .noPrice:
            guard let reason = va.noPriceReason else { return nil }
            switch reason {
            case .notCollectible(let confirmed):
                if confirmed { return nil }
                return ImproveResultCard.Advice(
                    title: "Photograph just the item",
                    detail: "Fill the frame with one item on a plain background, so we can match it to things people collect."
                )
            case .onDevice:
                return nil
            case .tooWide, .noValue:
                break
            }
        }
        if !model.hasBackPhoto {
            return ImproveResultCard.Advice(
                title: "Add a photo of the back",
                detail: "The number, mark or label on the back usually settles the match."
            )
        }
        let notes = (shownNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty {
            return ImproveResultCard.Advice(
                title: "Add what you know",
                detail: "An edition, year, size or signature in Details narrows it down."
            )
        }
        return ImproveResultCard.Advice(
            title: "Crop closer to the item",
            detail: "Tap a photo on the review screen and drag the corners to cut the background."
        )
    }

    // MARK: Pro cards (04 §6.4)

    private var withheldPrices: Int {
        if let count = va.evidenceCount, count > 0 { return count }
        return model.lockedCount
    }

    private var withheldSales: Int { model.sold?.salesLocked ?? 0 }

    /// The result knows it withheld prices or sales (Free scans since WP0).
    private var hasWithheldData: Bool { model.lockedCount > 0 || withheldSales > 0 }

    /// RS-5: a record saved before this build has no `lockedComparableCount`
    /// (nil, read as 0), so a Free scan from then shows no prices after an
    /// upgrade and no reason. Stored + A–C + real evidence + nothing loaded:
    /// it ran on the free plan.
    private var legacyRecordWithoutPrices: Bool {
        guard !context.isFresh, va.level != .noPrice else { return false }
        guard let saved = record, saved.lockedComparableCount == nil else { return false }
        guard let kind = va.evidence, kind != .aiEstimate else { return false }
        guard model.comparables.isEmpty else { return false }
        return model.sold?.sales.isEmpty != false
    }

    @ViewBuilder
    private var proCard: some View {
        if !isPro {
            if let onUnlock = context.onUnlock,
               model.lockedCount > 0 || withheldSales > 0 || model.historyLocked {
                ProEvidenceCard(
                    evidenceCount: withheldPrices,
                    salesLocked: withheldSales,
                    chartLocked: model.historyLocked,
                    onSee: onUnlock
                )
                .transition(.opacity)
                .padding(.top, WW.Space.md)
            }
        } else if canRescan && (hasWithheldData || legacyRecordWithoutPrices) {
            // A legacy record has no counts: the card's clause-less body.
            UpgradedReloadCard(
                evidenceCount: hasWithheldData ? withheldPrices : 0,
                salesLocked: hasWithheldData ? withheldSales : 0,
                onReload: {
                    if let onRescan = context.onRescan { onRescan(.checkPriceAgain) }
                }
            )
            .transition(.opacity)
            .padding(.top, WW.Space.md)
        }
    }

    // MARK: Menu (04 §5.3, 05 §2.35)

    private var menuActions: ResultMenuActions {
        var actions = ResultMenuActions()
        if canCorrect {
            actions.correct = { openCorrection() }
        }
        if !context.isFresh && canRescan, let onRescan = context.onRescan {
            actions.checkPriceAgain = { onRescan(.checkPriceAgain) }
        }
        if va.level != .noPrice {
            actions.share = { prepareShare() }
        }
        guard let record else { return actions }
        actions.editDetails = { activeSheet = .editDetails }
        actions.isSaved = record.isInCollection
        actions.folders = collectionStore.sets
        actions.currentFolderID = currentFolder?.id
        actions.createFolder = { name in createFolder(name) }
        if record.isInCollection {
            actions.move = { folderID in move(to: folderID) }
            actions.remove = { removeFromCollection() }
        } else if va.level == .noPrice || barPrimary == nil {
            // D: Save moves into the menu (04 §6.4D).
            actions.save = { folderID in save(to: folderID) }
        }
        actions.deleteMessage = record.isInCollection
            ? "It's removed from your collection, its folder and Recent scans. This can't be undone."
            : "It's removed from Recent scans. This can't be undone."
        actions.delete = { deleteScan() }
        return actions
    }

    // MARK: Mutations (04 §5.3, 06 §3.2 / §4.4)

    private func save(to folderID: UUID?) {
        guard let id = context.recordID, collectionStore.record(id: id) != nil else { return }
        let store = collectionStore
        let wasEmpty: Bool = store.items.isEmpty
        let hadCounted: Bool = !store.countedItems.isEmpty
        let counts: Bool = va.countsInTotal
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            store.saveToCollection(id: id, folderID: folderID)
            savedHere = true
        }
        Haptics.notify(.success)
        let shownToast: Bool = showFirstSaveToastIfNeeded(wasEmpty: wasEmpty, hadCounted: hadCounted, counts: counts)
        if !shownToast {
            let folderName: String? = folderID.flatMap { fid in store.sets.first(where: { $0.id == fid })?.name }
            announce(folderName.map { "Saved to \($0)" } ?? "Saved to your collection")
        }
        scheduleEmphasisHandoff()
    }

    /// 06 S3: the first save ever, and the first counted item.
    private func showFirstSaveToastIfNeeded(wasEmpty: Bool, hadCounted: Bool, counts: Bool) -> Bool {
        if wasEmpty && !firstSaveShown {
            firstSaveShown = true
            if counts { firstCountedShown = true }
            toast = WWToastModel(message: counts
                ? "Saved. Your collection total starts here."
                : "Saved. Its price is too rough to count in your total yet.")
            return true
        }
        if counts && !hadCounted && !firstCountedShown {
            firstCountedShown = true
            toast = WWToastModel(message: "Added to your total. Only items with a firm price count.")
            return true
        }
        return false
    }

    private func scheduleEmphasisHandoff() {
        let animation: Animation? = WW.Motion.animation(.standard, reduceMotion: reduceMotion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(animation) {
                emphasisOnScanNext = true
            }
        }
    }

    /// RS-replace: the new record goes into the old one's folder, then the old one is deleted.
    private func replaceSavedItem() {
        guard let newID = context.recordID, let oldID = context.replacing, newID != oldID else { return }
        let store = collectionStore
        let folderID: UUID? = store.setContaining(itemID: oldID)?.id
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            store.saveToCollection(id: newID, folderID: folderID)
            store.remove(id: oldID)
            replacedHere = true
            savedHere = true
        }
        Haptics.notify(.success)
        toast = WWToastModel(message: "Updated in your collection")
        scheduleEmphasisHandoff()
    }

    private func move(to folderID: UUID?) {
        guard let id = context.recordID, isSaved else { return }
        let store = collectionStore
        let previous: CollectibleSet? = store.setContaining(itemID: id)
        guard previous?.id != folderID else { return }
        let snapshot = store.membershipSnapshot(for: [id])
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            if let folderID {
                store.assignItems([id], toSetID: folderID)
            } else {
                store.clearSetAssignment(for: id)
            }
        }
        Haptics.notify(.success)
        let message: String
        if let folderID, let name = store.sets.first(where: { $0.id == folderID })?.name {
            message = "Moved to \(name)"
        } else if let previous {
            message = "Taken out of \(previous.name). It's still in Items."
        } else {
            return
        }
        toast = WWToastModel(message: message, actionTitle: "Undo", action: {
            store.restore(snapshot)
            UIAccessibility.post(notification: .announcement, argument: "Undone")
        })
    }

    private func createFolder(_ name: String) {
        let store = collectionStore
        guard let newID = store.createSetReturningID(named: name) else {
            let duplicate: Bool = store.validateSetName(name) == .duplicateName
            toast = WWToastModel(
                message: duplicate ? "A folder with that name already exists." : "Give the folder a name.",
                isSuccess: false
            )
            return
        }
        if isSaved {
            move(to: newID)
        } else {
            save(to: newID)
        }
    }

    private func removeFromCollection() {
        guard let id = context.recordID, isSaved else { return }
        let store = collectionStore
        let snapshot = store.membershipSnapshot(for: [id])
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            store.removeFromCollection(ids: [id])
            savedHere = false
            emphasisOnScanNext = false
        }
        toast = WWToastModel(
            message: "Removed from your collection. It's still in Recent scans.",
            actionTitle: "Undo",
            action: {
                store.restore(snapshot)
                UIAccessibility.post(notification: .announcement, argument: "Undone")
            }
        )
    }

    private func deleteScan() {
        guard let id = context.recordID else { return }
        collectionStore.remove(id: id)
        announce("Scan deleted")
        context.onDeleted?()
    }

    private func updateDetails(grade: ConditionGrade, isSet: Bool, notes: String) {
        guard let id = context.recordID else { return }
        let store = collectionStore
        withAnimation(WW.Motion.animation(.crossfade, reduceMotion: reduceMotion)) {
            store.updateDetails(id: id, condition: grade, conditionSet: isSet, notes: notes)
        }
    }

    /// ED2 "Scan again with changes": the details are already saved; a stored
    /// record scans again from its photos (the flow is seeded from the record),
    /// a fresh one goes back to Review where the new condition can be set.
    private func rescanWithChanges() {
        if context.isFresh {
            context.onRescan?(.editPhotos)
        } else {
            context.onRescan?(.checkPriceAgain)
        }
    }

    @MainActor
    private func prepareShare() {
        let renderer = ImageRenderer(content: ShareCardView(model: model))
        renderer.scale = 3
        var items: [Any] = []
        if let image = renderer.uiImage {
            items.append(image)
        }
        items.append(model.shareText)
        activeSheet = .share(items)
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    // MARK: Reveal (06 §2.4, S2)

    private var revealMode: ResultRevealMode {
        if legacyActions != nil || !context.isFresh { return .still }
        if reduceMotion || UIAccessibility.isVoiceOverRunning { return .reduced }
        return .full
    }

    private var cardIsShown: Bool { revealMode != .full || cardVisible }

    /// A and B rise 8 pt; C and D only fade (06 L1).
    private var cardOffset: CGFloat {
        if revealMode != .full || cardVisible || va.level < .fair { return 0 }
        return WW.Motion.revealOffset
    }

    @MainActor
    private func runReveal() async {
        guard !didStartReveal else { return }
        didStartReveal = true
        let mode: ResultRevealMode = revealMode
        let level: ValueLevel = va.level
        let greatFind: Bool = va.isGreatFind
        switch mode {
        case .still:
            // Stored / reopened: static, no haptic (06 §1.2).
            return
        case .reduced:
            if UIAccessibility.isVoiceOverRunning {
                await pause(0.3)
                identityFocused = true
            } else {
                await pause(0.25)
            }
            Haptics.result(level, greatFind: greatFind)
            return
        case .full:
            break
        }

        // t = 120 ms: the card (rise for A/B, opacity for C/D).
        let cardAnimation: Animation
        if level >= .fair {
            cardAnimation = WW.Motion.animation(.reveal, reduceMotion: false) ?? Animation.easeOut(duration: 0.25)
        } else {
            cardAnimation = Animation.easeOut(duration: 0.25).delay(WW.Motion.revealDelay)
        }
        withAnimation(cardAnimation) {
            cardVisible = true
        }
        // t = 200 ms: the span spreads from the best tick.
        let spread: Animation = (WW.Motion.animation(.spread, reduceMotion: false) ?? Animation.easeOut(duration: 0.4)).delay(0.2)
        withAnimation(spread) {
            spanProgress = 1
        }
        // t = 300 ms: the haptic (a great find waits for the swing).
        await pause(0.3)
        if !greatFind {
            Haptics.result(level)
        }
        // t = 370 ms: the evidence chip settles; A stamps its glyph.
        await pause(0.07)
        if level >= .fair {
            withAnimation(WW.Motion.animation(.settle, reduceMotion: false)) {
                evidenceSettled = true
            }
            if level == .strong {
                stampTrigger += 1
            }
        }
        // t = 450 ms: "That's a good find." + the Tag swing + the one success.
        guard greatFind else { return }
        await pause(0.08)
        withAnimation(Animation.easeOut(duration: 0.2)) {
            greatFindVisible = true
        }
        Haptics.result(level, greatFind: true)
        let angles: [Double] = WW.Motion.swingAngles
        let durations: [Double] = WW.Motion.swingDurations
        for index in angles.indices {
            let duration: Double = index < durations.count ? durations[index] : 0.15
            withAnimation(Animation.easeInOut(duration: duration)) {
                swingAngle = angles[index]
            }
            await pause(duration)
        }
        swingAngle = 0
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Result helpers

private enum ResultRevealMode {
    /// Fresh, motion allowed: the timed reveal.
    case full
    /// Fresh with Reduce Motion or VoiceOver: static, haptic at 250 ms, focus to the title.
    case reduced
    /// Stored or reopened: static, no haptic.
    case still
}

/// The one sheet presenter of `ResultView` (04 §2.2: one per anchor).
private enum ResultSheet: Identifiable {
    case correction
    case editDetails
    case howItWorks
    case share([Any])

    var id: String {
        switch self {
        case .correction: return "correction"
        case .editDetails: return "editDetails"
        case .howItWorks: return "howItWorks"
        case .share: return "share"
        }
    }
}

private extension NoPriceReason {
    var wwIsOnDevice: Bool {
        switch self {
        case .onDevice: return true
        case .notCollectible, .tooWide, .noValue: return false
        }
    }

    var wwIsNotCollectible: Bool {
        switch self {
        case .notCollectible: return true
        case .onDevice, .tooWide, .noValue: return false
        }
    }
}

// MARK: - Photo header and identity (05 §2.34)

/// The photo(s), aspect-fit on `photoBackdrop`, radius 24, page dots for two
/// photos. Nothing is drawn on the photo. Height (RS-1): 30 % of the scroll
/// view's visible height, between 180 and 280 pt, so the value range is in
/// the first viewport above the pinned bar even on 375 × 667; 220 at AX
/// sizes (the bar is inline there).
struct ResultPhotoHeader: View {
    let photos: [UIImage]
    let title: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(photos: [UIImage], title: String) {
        self.photos = photos
        self.title = title
    }

    var body: some View {
        sized
            .background(WW.photoBackdrop)
            .clipShape(RoundedRectangle(cornerRadius: WW.Radius.photo, style: .continuous))
    }

    @ViewBuilder
    private var sized: some View {
        if dynamicTypeSize.isAccessibilitySize {
            content
                .frame(maxWidth: .infinity)
                .frame(height: 220)
        } else {
            // iOS 17: the nearest container is the result's vertical ScrollView,
            // whose length excludes the nav bar and the pinned bar (safe area).
            content
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { length, _ in
                    min(280, max(180, length * 0.30))
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if photos.count > 1 {
            TabView {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    photoView(photo, label: "Photo of \(title), \(index + 1) of \(photos.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        } else if let photo = photos.first {
            photoView(photo, label: "Photo of \(title)")
        } else {
            PhotoPlaceholder()
        }
    }

    private func photoView(_ image: UIImage, label: String) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
    }
}

/// Meta line, title (selectable, up to 3 lines; unlimited at AX) and, when
/// saved, the identity chip "In your collection · Kitchen". One VoiceOver
/// heading (04 §9.2), so focus can land on it when a fresh result appears.
struct ResultIdentity: View {
    let meta: String
    let metaSpoken: String
    let title: String
    let chipText: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(meta: String, metaSpoken: String, title: String, chipText: String? = nil) {
        self.meta = meta
        self.metaSpoken = metaSpoken
        self.title = title
        self.chipText = chipText
    }

    private var spoken: String {
        var parts: [String] = []
        if !metaSpoken.isEmpty { parts.append(metaSpoken) }
        parts.append(title)
        if let chipText { parts.append(chipText) }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !meta.isEmpty {
                Text(meta)
                    .wwFont(.meta)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, WW.Space.xxs)
            }
            Text(title)
                .wwFont(.itemTitle)
                .foregroundStyle(WW.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let chipText {
                identityChip(chipText)
                    .padding(.top, WW.Space.xs)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isHeader)
    }

    private func identityChip(_ text: String) -> some View {
        HStack(spacing: WW.Space.xxs) {
            Image(systemName: "folder")
                .imageScale(.small)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .wwFont(.footnote, weight: .semibold)
        .foregroundStyle(WW.text)
        .padding(.horizontal, WW.Space.xs)
        .padding(.vertical, WW.Space.xxs)
        .background(WW.neutralWash, in: RoundedRectangle(cornerRadius: WW.Radius.chip, style: .continuous))
    }
}

// MARK: - Value card (05 §2.10, 04 §4.4 / §6.4A–D)

/// The value, by level. A/B: 40 pt range, `RangeBar`, best estimate, caveats,
/// evidence; C: "Rough guide" first, 28 pt range, caveats, inline "not an
/// appraisal"; D: no number, a plate, a title and why, and (for too-wide and
/// soft not-a-collectible) a closed "Show the rough range".
struct ValueCard: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @State private var showsRoughRange = false

    let model: ResultModel
    /// `vm.lastScanCharged`: D says "It didn't use a scan." when `false`,
    /// "This used 1 scan." when `true`, nothing when nil.
    let scanCharged: Bool?
    /// 06 spread: 0 → 1 from the best tick.
    let spanProgress: Double
    /// 06: the evidence line settles in at 370 ms (A/B, fresh).
    let evidenceShown: Bool
    /// 06 stamp: bumps the SOLD/GUIDE glyph (A, fresh).
    let stampTrigger: Int
    /// "How we know" → How It Works (00 decision 5). nil hides it.
    let onHowWeKnow: (() -> Void)?
    /// "It is a collectible" → correction (not-a-collectible D).
    let onItIsCollectible: (() -> Void)?

    init(
        model: ResultModel,
        scanCharged: Bool? = nil,
        spanProgress: Double = 1,
        evidenceShown: Bool = true,
        stampTrigger: Int = 0,
        onHowWeKnow: (() -> Void)? = nil,
        onItIsCollectible: (() -> Void)? = nil
    ) {
        self.model = model
        self.scanCharged = scanCharged
        self.spanProgress = spanProgress
        self.evidenceShown = evidenceShown
        self.stampTrigger = stampTrigger
        self.onHowWeKnow = onHowWeKnow
        self.onItIsCollectible = onItIsCollectible
    }

    private var va: ValueAssessment { model.assessment }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .wwCard()
            .wwAnimation(.crossfade, value: displayCurrency)
    }

    @ViewBuilder
    private var content: some View {
        switch va.level {
        case .strong, .fair:
            marketBody
        case .rough:
            roughBody
        case .noPrice:
            noPriceBody
        }
    }

    // MARK: A · strong and B · fair

    private var marketBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            rangeBlock(role: .valueDisplay)
            if showsRangeBar {
                rangeBar
                    .padding(.top, WW.Space.sm)
            }
            estimateLines
                .padding(.top, WW.Space.sm)
            caveatRows
            noteLine
            evidenceLine
            timestamp
            howWeKnow
        }
    }

    private var showsRangeBar: Bool {
        va.level == .strong || (va.level == .fair && va.best != nil)
    }

    private var rangeBar: some View {
        let sold: SoldSummary? = model.sold
        let dots: [Double] = model.dotSalesUSD
        let total: Int? = sold.map { max($0.count, dots.count) }
        return RangeBar(
            lowUSD: va.lowUSD,
            highUSD: va.highUSD,
            bestUSD: va.best?.amountUSD,
            salesUSD: dots,
            salesAreExact: sold?.isExact ?? true,
            windowDays: sold?.windowDays ?? 90,
            totalSales: total,
            spanProgress: spanProgress
        )
    }

    /// Best estimate (A `.headline`, B `.subhead`) and the sold line.
    @ViewBuilder
    private var estimateLines: some View {
        if va.best != nil || secondLine != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let best = va.best {
                    Text(best.headline)
                        .wwFont(va.level == .strong ? WWTextRole.headline : WWTextRole.subhead)
                        .foregroundStyle(WW.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = secondLine {
                    Text(line)
                        .wwFont(.subhead)
                        .foregroundStyle(WW.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(estimateSpoken)
        }
    }

    private var estimateSpoken: String {
        if let best = va.best {
            if let line = soldSentence { return "\(best.spoken). \(line)" }
            return best.spoken
        }
        return secondLine ?? ""
    }

    /// Under the best estimate: its sales detail, or the separate sold line.
    private var secondLine: String? {
        if let best = va.best, let detail = best.detail { return detail }
        return soldSentence
    }

    /// "Recent sales: $0.48 median from 12 sales" when the sales aren't the
    /// best estimate already and no caveat states them (00 addition 3).
    private var soldSentence: String? {
        guard let sold = model.sold, !sold.unavailable, sold.count >= 1 else { return nil }
        if hasSalesCaveat { return nil }
        if let best = va.best, best.detail != nil { return nil }
        let noun: String = sold.count == 1 ? "sale" : "sales"
        if let median = sold.median {
            return "Recent sales: \(WW.money(median)) median from \(sold.count) \(noun)"
        }
        return "\(sold.count) \(noun) in the last \(sold.windowDays) days"
    }

    private var hasSalesCaveat: Bool {
        for caveat in va.caveats {
            switch caveat {
            case .salesHigher, .salesLower:
                return true
            case .wideRange, .unsureMatch, .similarItems, .aiEstimate:
                continue
            }
        }
        return false
    }

    // MARK: C · rough

    private var roughBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            CaveatFlag.roughGuide()
            rangeBlock(role: .valueRough)
                .padding(.top, WW.Space.xxs)
            if let line = soldSentence {
                Text(line)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WW.Space.xs)
            }
            caveatRows
            noteLine
            evidenceLine
            timestamp
            howWeKnow
        }
    }

    // MARK: Shared rows (A–C)

    private func rangeBlock(role: WWTextRole) -> some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            Text("Estimated value")
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
            ValueRangeText(lowUSD: va.lowUSD, highUSD: va.highUSD, role: role)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated value: \(rangeSpoken)")
    }

    private var rangeSpoken: String {
        let low: String = WW.money(min(va.lowUSD, va.highUSD))
        let high: String = WW.money(max(va.lowUSD, va.highUSD))
        return low == high ? low : "between \(low) and \(high)"
    }

    @ViewBuilder
    private var caveatRows: some View {
        if !va.displayCaveats.isEmpty {
            VStack(alignment: .leading, spacing: WW.Space.xs) {
                ForEach(Array(va.displayCaveats.enumerated()), id: \.offset) { _, caveat in
                    CaveatFlag(caveat)
                }
            }
            .padding(.top, WW.Space.sm)
        }
    }

    /// Notes inline: C "A rough guide, not an appraisal." first; A/B the
    /// professional-opinion line first (05 §2.10).
    private var noteSentences: [String] {
        let order: [ValueNote] = va.level == .rough
            ? [.notAnAppraisal, .highValue, .lowValue]
            : [.highValue, .notAnAppraisal, .lowValue]
        var out: [String] = []
        for note in order where va.notes.contains(note) {
            out.append(note.sentence(for: va.level))
        }
        return out
    }

    @ViewBuilder
    private var noteLine: some View {
        if !noteSentences.isEmpty {
            Text(noteSentences.joined(separator: " "))
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, WW.Space.xs)
        }
    }

    @ViewBuilder
    private var evidenceLine: some View {
        if let line = EvidenceLine(assessment: va) {
            line
                .symbolEffect(.bounce.down, options: .nonRepeating, value: stampTrigger)
                .opacity(evidenceShown ? 1 : 0)
                .scaleEffect(evidenceShown ? 1 : 0.94, anchor: .leading)
                .padding(.top, WW.Space.sm)
        }
    }

    private var timestamp: some View {
        Text(model.checkedLine)
            .wwFont(.footnote)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, WW.Space.xs)
    }

    @ViewBuilder
    private var howWeKnow: some View {
        if let onHowWeKnow {
            Button(action: onHowWeKnow) {
                Label("How we know", systemImage: "info.circle")
                    .labelStyle(WWInlineIconLabelStyle(spacing: 6))
            }
            .buttonStyle(WWTertiaryButtonStyle(.accent, .small))
            .accessibilityHint("Explains how to read a result")
            .padding(.top, WW.Space.xxs)
        }
    }

    // MARK: D · no price

    private var reason: NoPriceReason { va.noPriceReason ?? .noValue }

    private var noPriceBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            plate
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                Text(reason.title)
                    .wwFont(.itemTitle)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason.message)
                    .wwFont(.body)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(reason.title). \(reason.message)")
            .accessibilityAddTraits(.isHeader)
            .padding(.top, WW.Space.sm)
            // 02 §7: say whether a scan was used. nil (stored, or unknown) says nothing.
            if scanCharged == false {
                Text("It didn't use a scan.")
                    .wwFont(.subhead)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WW.Space.xs)
            } else if scanCharged == true {
                Text("This used 1 scan.")
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WW.Space.xs)
            }
            if va.notes.contains(.highValue) {
                Text(ValueNote.highValue.sentence(for: .noPrice))
                    .wwFont(.subhead)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WW.Space.xs)
            }
            roughRangeDisclosure
            itIsCollectibleLink
        }
    }

    private var plate: some View {
        let caution: Bool = reason.usesCautionPlate
        return Image(systemName: reason.glyph)
            .font(.system(size: 24, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(caution ? WW.caution : WW.secondaryText)
            .frame(width: WW.Size.plateS, height: WW.Size.plateS)
            .background(caution ? WW.cautionWash : WW.neutralWash,
                        in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var roughRangeDisclosure: some View {
        if reason.showsRoughRange && va.highUSD > 0 {
            DisclosureGroup(isExpanded: $showsRoughRange) {
                Text(NoPriceReason.roughRangeSentence(lowUSD: va.lowUSD, highUSD: va.highUSD))
                    .monospacedDigit()
                    .wwFont(.body)
                    .foregroundStyle(WW.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Show the rough range")
            }
            .disclosureGroupStyle(WWDisclosureStyle(tone: .accent))
            .padding(.top, WW.Space.xxs)
        }
    }

    @ViewBuilder
    private var itIsCollectibleLink: some View {
        if reason.wwIsNotCollectible, let onItIsCollectible {
            Button("It is a collectible", action: onItIsCollectible)
                .buttonStyle(WWTertiaryButtonStyle(.accent, .small))
                .padding(.top, WW.Space.xxs)
        }
    }
}

// MARK: - Options menu (04 §5.3, 05 §2.35)

/// What the options menu offers for this result. A nil action hides its item.
struct ResultMenuActions {
    var correct: (() -> Void)?
    var checkPriceAgain: (() -> Void)?
    var editDetails: (() -> Void)?
    var share: (() -> Void)?
    /// D only (the bar's primary is the recovery action), unsaved records.
    var save: ((UUID?) -> Void)?
    /// Saved records: a folder id, or nil for No Folder.
    var move: ((UUID?) -> Void)?
    /// "New Folder…": creates it, then moves (saved) or saves (unsaved) into it.
    var createFolder: ((String) -> Void)?
    var remove: (() -> Void)?
    var delete: (() -> Void)?
    var isSaved: Bool
    var folders: [CollectibleSet]
    var currentFolderID: UUID?
    var deleteMessage: String

    init() {
        correct = nil
        checkPriceAgain = nil
        editDetails = nil
        share = nil
        save = nil
        move = nil
        createFolder = nil
        remove = nil
        delete = nil
        isSaved = false
        folders = []
        currentFolderID = nil
        deleteMessage = ""
    }
}

/// `ellipsis.circle` "Item options", the same for fresh and stored results.
/// Delete's confirmation and the New Folder alert are attached to this menu
/// (04 §2.2).
struct ResultOptionsMenu: View {
    let model: ResultModel
    let context: ResultContext
    let actions: ResultMenuActions

    @State private var confirmingDelete = false
    @State private var namingFolder = false
    @State private var newFolderName = ""

    init(model: ResultModel, context: ResultContext, actions: ResultMenuActions = ResultMenuActions()) {
        self.model = model
        self.context = context
        self.actions = actions
    }

    var body: some View {
        Menu {
            Section {
                fixItems
            }
            Section {
                keepItems
            }
            Section {
                removeItems
            }
        } label: {
            Label("Item options", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Item options")
        .confirmationDialog("Delete this scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive) {
                actions.delete?()
            }
            Button("Cancel", role: WW.dialogCancelRole) {}
        } message: {
            Text(actions.deleteMessage)
        }
        .alert("New Folder", isPresented: $namingFolder) {
            TextField("Coins, cards, vases…", text: $newFolderName)
            Button(actions.isSaved ? "Create and Move" : "Create") {
                createFolder()
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
    }

    /// Not the Right Item?, Check Price Again, Edit Details.
    @ViewBuilder
    private var fixItems: some View {
        if let correct = actions.correct {
            Button(action: correct) {
                Label("Not the Right Item?", systemImage: "questionmark.circle")
            }
        }
        if let check = actions.checkPriceAgain {
            Button(action: check) {
                Label {
                    Text("Check Price Again")
                    Text("Scans again · uses 1 scan")
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        if let edit = actions.editDetails {
            Button(action: edit) {
                Label("Edit Details", systemImage: "pencil")
            }
        }
    }

    /// Share…, Save to Collection (D), Move to Folder.
    @ViewBuilder
    private var keepItems: some View {
        if let share = actions.share {
            Button(action: share) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        saveItem
        moveItem
    }

    @ViewBuilder
    private var saveItem: some View {
        if let save = actions.save {
            if actions.folders.isEmpty {
                Button {
                    save(nil)
                } label: {
                    Label("Save to Collection", systemImage: "plus.circle")
                }
            } else {
                Menu {
                    Button {
                        startNewFolder()
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }
                    Button {
                        save(nil)
                    } label: {
                        Text("No Folder")
                    }
                    ForEach(actions.folders) { folder in
                        Button {
                            save(folder.id)
                        } label: {
                            Text(folder.name)
                        }
                    }
                } label: {
                    Label("Save to Collection", systemImage: "plus.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var moveItem: some View {
        if let move = actions.move {
            Menu {
                Button {
                    startNewFolder()
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }
                Button {
                    move(nil)
                } label: {
                    folderLabel("No Folder", isCurrent: actions.currentFolderID == nil)
                }
                ForEach(actions.folders) { folder in
                    Button {
                        move(folder.id)
                    } label: {
                        folderLabel(folder.name, isCurrent: folder.id == actions.currentFolderID)
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
        }
    }

    /// Remove from Collection, Delete Scan.
    @ViewBuilder
    private var removeItems: some View {
        if let remove = actions.remove {
            Button(action: remove) {
                Label {
                    Text("Remove from Collection")
                    Text("Stays in Recent scans")
                } icon: {
                    Image(systemName: "minus.circle")
                }
            }
        }
        if actions.delete != nil {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label {
                    Text("Delete Scan")
                    Text("Removes it everywhere")
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func folderLabel(_ name: String, isCurrent: Bool) -> some View {
        if isCurrent {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }

    private func startNewFolder() {
        newFolderName = ""
        namingFolder = true
    }

    private func createFolder() {
        let name: String = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        actions.createFolder?(name)
    }
}

// MARK: - Action bar (05 §2.36, 00 additions 1–2)

/// Save / Saved / Replace / the D recovery action, plus "Scan next". Side by
/// side when both fit, else stacked full width (primary on top); the primary
/// drops its glyph first when space is tight. At AX sizes the host renders it
/// inline (`stacked: true`). The folder dialog and New Folder alert are
/// attached here (04 §2.2).
struct ResultActionBar: View {
    struct Action {
        let title: String
        let systemImage: String?
        let perform: () -> Void

        init(title: String, systemImage: String? = nil, perform: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.perform = perform
        }
    }

    enum Primary {
        case save
        /// "Saved" / "Saved to Kitchen": a success state, not a disabled button.
        case saved(String)
        case replace
        case recovery(Action)
    }

    let model: ResultModel
    let context: ResultContext
    let primary: Primary?
    let secondary: Action?
    /// 06 M15 [P05]: after Save, "Scan next" takes the one Lapis fill.
    let emphasizeSecondary: Bool
    let stacked: Bool
    let folders: [CollectibleSet]
    let onSave: (UUID?) -> Void
    let onSaveToNewFolder: (String) -> Void
    let onReplace: () -> Void

    @State private var choosingFolder = false
    @State private var namingFolder = false
    @State private var newFolderName = ""

    init(
        model: ResultModel,
        context: ResultContext,
        primary: Primary? = nil,
        secondary: Action? = nil,
        emphasizeSecondary: Bool = false,
        stacked: Bool = false,
        folders: [CollectibleSet] = [],
        onSave: @escaping (UUID?) -> Void = { _ in },
        onSaveToNewFolder: @escaping (String) -> Void = { _ in },
        onReplace: @escaping () -> Void = {}
    ) {
        self.model = model
        self.context = context
        self.primary = primary
        self.secondary = secondary
        self.emphasizeSecondary = emphasizeSecondary
        self.stacked = stacked
        self.folders = folders
        self.onSave = onSave
        self.onSaveToNewFolder = onSaveToNewFolder
        self.onReplace = onReplace
    }

    var body: some View {
        layout
            .confirmationDialog("Save to a folder?", isPresented: $choosingFolder, titleVisibility: .visible) {
                ForEach(folders) { folder in
                    Button(folder.name) {
                        onSave(folder.id)
                    }
                }
                Button("New Folder…") {
                    // Let the dialog finish closing before the alert opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        newFolderName = ""
                        namingFolder = true
                    }
                }
                Button("No Folder") {
                    onSave(nil)
                }
                Button("Cancel", role: WW.dialogCancelRole) {}
            } message: {
                Text("It stays in Items either way.")
            }
            .alert("New Folder", isPresented: $namingFolder) {
                TextField("Coins, cards, vases…", text: $newFolderName)
                Button("Create") {
                    createAndSave()
                }
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
            }
    }

    @ViewBuilder
    private var layout: some View {
        if primary != nil && secondary != nil {
            if stacked {
                VStack(spacing: WW.Space.sm) {
                    primaryButton(showsGlyph: true)
                    secondaryButton
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: WW.Space.sm) {
                        primaryButton(showsGlyph: true)
                        secondaryButton
                    }
                    HStack(spacing: WW.Space.sm) {
                        primaryButton(showsGlyph: false)
                        secondaryButton
                    }
                    VStack(spacing: WW.Space.sm) {
                        primaryButton(showsGlyph: true)
                        secondaryButton
                    }
                }
            }
        } else if primary != nil {
            primaryButton(showsGlyph: true)
        } else if secondary != nil {
            secondaryButton
        }
    }

    @ViewBuilder
    private func primaryButton(showsGlyph: Bool) -> some View {
        switch primary {
        case .save?:
            Button {
                startSave()
            } label: {
                buttonLabel("Save to collection", systemImage: showsGlyph ? "plus" : nil)
            }
            .buttonStyle(WWPrimaryButtonStyle(size: .large))
        case .saved(let title)?:
            ResultSavedLabel(title: title)
                .transition(.opacity)
        case .replace?:
            Button(action: onReplace) {
                buttonLabel("Replace saved item", systemImage: showsGlyph ? "arrow.triangle.2.circlepath" : nil)
            }
            .buttonStyle(WWPrimaryButtonStyle(size: .large))
        case .recovery(let action)?:
            Button(action: action.perform) {
                buttonLabel(action.title, systemImage: showsGlyph ? action.systemImage : nil)
            }
            .buttonStyle(WWPrimaryButtonStyle(size: .large))
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        if let secondary {
            if emphasizeSecondary {
                Button(action: secondary.perform) {
                    buttonLabel(secondary.title, systemImage: secondary.systemImage)
                }
                .buttonStyle(WWPrimaryButtonStyle(size: .large))
            } else {
                Button(action: secondary.perform) {
                    buttonLabel(secondary.title, systemImage: secondary.systemImage)
                }
                .buttonStyle(WWSecondaryButtonStyle(size: .large))
            }
        }
    }

    @ViewBuilder
    private func buttonLabel(_ title: String, systemImage: String?) -> some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }

    private func startSave() {
        if folders.isEmpty {
            onSave(nil)
        } else {
            choosingFolder = true
        }
    }

    private func createAndSave() {
        let name: String = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        onSaveToNewFolder(name)
    }
}

/// The "Saved" state: the secondary look, full opacity, not a button.
private struct ResultSavedLabel: View {
    let title: String
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: "checkmark")
        }
        .wwFont(.button)
        .foregroundStyle(WW.text)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(minHeight: WW.Size.buttonLarge)
        .background(WW.fill, in: Capsule())
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

// MARK: - Pro cards (04 §6.4, 05 §2.37)

/// Free only, exactly one per result: what Pro would show for this item.
struct ProEvidenceCard: View {
    let evidenceCount: Int
    let salesLocked: Int
    let chartLocked: Bool
    let onSee: () -> Void

    init(evidenceCount: Int, salesLocked: Int, chartLocked: Bool, onSee: @escaping () -> Void) {
        self.evidenceCount = evidenceCount
        self.salesLocked = salesLocked
        self.chartLocked = chartLocked
        self.onSee = onSee
    }

    /// "12 prices", "18 sales" (a clause is dropped when its count is 0).
    static func clauses(prices: Int, sales: Int) -> [String] {
        var out: [String] = []
        if prices > 0 { out.append("\(prices) \(prices == 1 ? "price" : "prices")") }
        if sales > 0 { out.append("\(sales) \(sales == 1 ? "sale" : "sales")") }
        return out
    }

    private var bodyText: String {
        let objects: [String] = ProEvidenceCard.clauses(prices: evidenceCount, sales: salesLocked)
        if objects.isEmpty {
            return "Pro shows how this item's price moves, in a price chart."
        }
        let tail: String = chartLocked ? ", with dates, links and a price chart." : ", with dates and links."
        return "Pro shows the \(objects.joined(separator: " and ")) behind this estimate\(tail)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("See the evidence with Pro")
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(bodyText)
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WW.Space.xxs)
            Button("See them with Pro", action: onSee)
                .buttonStyle(WWSecondaryButtonStyle(size: .large))
                .padding(.top, WW.Space.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wwCard()
    }
}

/// Pro now, but this scan ran on the free plan (RS-upgraded).
struct UpgradedReloadCard: View {
    let evidenceCount: Int
    let salesLocked: Int
    let onReload: () -> Void

    init(evidenceCount: Int, salesLocked: Int, onReload: @escaping () -> Void) {
        self.evidenceCount = evidenceCount
        self.salesLocked = salesLocked
        self.onReload = onReload
    }

    private var bodyText: String {
        let objects: [String] = ProEvidenceCard.clauses(prices: evidenceCount, sales: salesLocked)
        if objects.isEmpty {
            return "This scan ran on the free plan, so its prices weren't loaded."
        }
        return "This scan ran on the free plan, so its \(objects.joined(separator: " and ")) weren't loaded."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("You're on Pro now")
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(bodyText)
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WW.Space.xxs)
            Button("Check again with Pro", action: onReload)
                .buttonStyle(WWSecondaryButtonStyle(size: .large))
                .padding(.top, WW.Space.md)
            Text("Uses 1 of your Pro scans.")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WW.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wwCard(style: .accentWash)
    }
}

// MARK: - Improve a result (05 §2.37; moved from HomeTipCard by WP0)

/// Shown under a weak result: one concrete thing to add, and a way back to
/// the review step to add it. The first scan stays in Recent scans. Without
/// `onImprove` (D, where the bar already offers it) only the advice shows.
struct ImproveResultCard: View {
    struct Advice {
        let title: String
        let detail: String
    }

    static let defaultCostLine = "Scanning again uses 1 scan. This result stays in Recent scans."

    let advice: Advice
    let costLine: String
    let onImprove: (() -> Void)?

    init(advice: Advice, costLine: String = ImproveResultCard.defaultCostLine, onImprove: (() -> Void)?) {
        self.advice = advice
        self.costLine = costLine
        self.onImprove = onImprove
    }

    var body: some View {
        HStack(alignment: .top, spacing: WW.Space.sm) {
            Image(systemName: "lightbulb")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WW.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Improve this result: \(advice.title.lowercased())")
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(advice.detail)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let onImprove {
                    Button(action: onImprove) {
                        Label("Edit photos and scan again", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(WWSecondaryButtonStyle(size: .large))
                    .padding(.top, WW.Space.md)
                }
                Text(costLine)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WW.Space.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .wwCard()
    }
}

// MARK: - Correct a result (05 §3.7; moved from HomeTipCard by WP0)

/// "Not the right item?": the user says what it is (or picks a server
/// candidate, 04 §10 S6), and the scan runs again with that as a hint.
/// Identification apps that let people correct a match keep their trust
/// when the first answer is wrong.
struct CorrectionSheet: View {
    static let defaultCostLine = "Scanning again uses 1 scan. The first result stays in Recent scans."

    let currentTitle: String
    let candidates: [MatchCandidate]
    let costLine: String
    let onRescan: (String) -> Void
    let onEditPhotos: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hint = ""
    @FocusState private var focused: Bool

    init(
        currentTitle: String,
        candidates: [MatchCandidate] = [],
        costLine: String = CorrectionSheet.defaultCostLine,
        onRescan: @escaping (String) -> Void,
        onEditPhotos: (() -> Void)?
    ) {
        self.currentTitle = currentTitle
        self.candidates = candidates
        self.costLine = costLine
        self.onRescan = onRescan
        self.onEditPhotos = onEditPhotos
    }

    private var trimmed: String { hint.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WWSheetHeader(
                        title: "What is it?",
                        subtitle: "Type its name and anything printed on it: set, number, year, maker. We'll scan again with your hint."
                    )
                    if !candidates.isEmpty {
                        candidateList
                            .padding(.top, WW.Space.xl)
                    }
                    field
                        .padding(.top, WW.Space.xl)
                    buttons
                        .padding(.top, WW.Space.md)
                    Text(costLine)
                        .wwFont(.footnote)
                        .foregroundStyle(WW.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, WW.Space.sm)
                }
                .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                .padding(.top, WW.Space.xs)
                .padding(.bottom, WW.Space.xl)
            }
            .wwSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.wwBarText)
                }
            }
        }
        .tint(WW.text)
        .presentationDetents([.medium, .large])
        .onAppear {
            if candidates.isEmpty { focused = true }
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            Text("Is it one of these?")
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(candidates.prefix(3).enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 {
                        WWHairline()
                            .padding(.leading, WW.Space.md)
                    }
                    candidateRow(candidate)
                }
            }
            .wwCard(padding: 0)
        }
    }

    private func candidateRow(_ candidate: MatchCandidate) -> some View {
        Button {
            finish { onRescan(candidate.title) }
        } label: {
            HStack(spacing: WW.Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .wwFont(.headline)
                        .foregroundStyle(WW.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = candidate.detail, !detail.isEmpty {
                        Text(detail)
                            .wwFont(.subhead)
                            .foregroundStyle(WW.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WW.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, WW.Space.md)
            .padding(.vertical, 10)
            .frame(minHeight: WW.Size.rowTall)
            .contentShape(Rectangle())
        }
        .buttonStyle(WWPressableStyle())
        .accessibilityHint("Scans again with this name")
    }

    private var field: some View {
        TextField("Name and details", text: $hint, prompt: Text(currentTitle).foregroundStyle(WW.secondaryText))
            .focused($focused)
            .submitLabel(.go)
            .onSubmit(rescan)
            .wwField(isFocused: focused)
    }

    private var buttons: some View {
        VStack(spacing: WW.Space.sm) {
            Button(action: rescan) {
                Label("Scan again with this hint", systemImage: "arrow.clockwise")
            }
            .buttonStyle(WWPrimaryButtonStyle(size: .large))
            .disabled(trimmed.isEmpty)
            if let onEditPhotos {
                Button("Edit the photos instead") {
                    finish(onEditPhotos)
                }
                .buttonStyle(WWSecondaryButtonStyle(size: .large))
            }
        }
    }

    private func rescan() {
        guard !trimmed.isEmpty else { return }
        let text: String = trimmed
        finish { onRescan(text) }
    }

    /// Close the sheet first, so a flow the host presents next doesn't race it.
    private func finish(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            action()
        }
    }
}

// MARK: - Edit Details (04 §6.6, 05 §3.7)

/// Condition (with "Not sure"), the user's notes (320 characters), and — when
/// the condition changes on a priced result — "Scan again with changes" (ED2).
struct EditDetailsSheet: View {
    static let notesLimit: Int = 320

    let record: SavedCollectible
    let onSave: (ConditionGrade, Bool, String) -> Void
    let onRescan: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var grade: ConditionGrade
    @State private var isSet: Bool
    @State private var notes: String
    @FocusState private var notesFocused: Bool

    init(record: SavedCollectible, onSave: @escaping (ConditionGrade, Bool, String) -> Void, onRescan: (() -> Void)?) {
        self.record = record
        self.onSave = onSave
        self.onRescan = onRescan
        _grade = State(initialValue: record.condition)
        _isSet = State(initialValue: record.isConditionSet)
        _notes = State(initialValue: record.userProvidedInfo ?? "")
    }

    /// The grade the server priced / would price ("Not sure" is sent as Good).
    private var oldEffective: ConditionGrade { record.isConditionSet ? record.condition : .good }
    private var newEffective: ConditionGrade { isSet ? grade : .good }

    private var showsRepriceNotice: Bool {
        onRescan != nil && record.assessment.level != .noPrice && oldEffective != newEffective
    }

    private var repriceText: String {
        let category: CollectibleCategory = record.probableCategory
        let before: String = record.isConditionSet
            ? "This value was checked for \(record.condition.label(for: category))."
            : "This value was checked without a condition."
        let after: String = isSet
            ? "Scan again to price it as \(grade.label(for: category))."
            : "Scan again to price it without a condition."
        return "\(before) \(after)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WWSheetHeader(title: "Edit Details")
                    ConditionPicker(grade: $grade, isSet: $isSet, category: record.probableCategory)
                        .padding(.top, WW.Space.xl)
                    notesBlock
                        .padding(.top, WW.Space.xl)
                    if showsRepriceNotice {
                        repriceNotice
                            .padding(.top, WW.Space.xl)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                .padding(.top, WW.Space.xs)
                .padding(.bottom, WW.Space.xl)
                .wwAnimation(.standard, value: showsRepriceNotice)
            }
            .wwSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.wwBarText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commit()
                        dismiss()
                    }
                    .buttonStyle(.wwBarTextProminent)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(WW.text)
        .presentationDetents([.medium, .large])
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            Text("Your notes")
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .accessibilityHidden(true)
            TextField(
                "Your notes",
                text: $notes,
                prompt: Text("Edition, signature, where you found it…").foregroundStyle(WW.secondaryText),
                axis: .vertical
            )
            .lineLimit(3...8)
            .focused($notesFocused)
            .wwField(isFocused: notesFocused)
            .onChange(of: notes) { _, newValue in
                if newValue.count > EditDetailsSheet.notesLimit {
                    notes = String(newValue.prefix(EditDetailsSheet.notesLimit))
                }
            }
            Text("\(notes.count)/\(EditDetailsSheet.notesLimit)")
                .monospacedDigit()
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("\(notes.count) of \(EditDetailsSheet.notesLimit) characters")
        }
    }

    private var repriceNotice: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: WW.Space.xs) {
                Image(systemName: "info.circle")
                    .foregroundStyle(WW.secondaryText)
                    .accessibilityHidden(true)
                Text(repriceText)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Scan again with changes") {
                saveAndRescan()
            }
            .buttonStyle(WWSecondaryButtonStyle(size: .compact))
        }
        .wwCard(padding: WW.Space.md)
    }

    private func commit() {
        onSave(isSet ? grade : .good, isSet, notes)
    }

    private func saveAndRescan() {
        commit()
        dismiss()
        guard let onRescan else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onRescan()
        }
    }
}

// MARK: - Prices Behind This Estimate (Pro, 04 §6.4 block 8)

/// The comparables (Pro). Counts follow 04 §4.6: "Showing {k} of {n}", where
/// n is the one evidence count.
struct ListingsSection: View {
    let comparables: [MarketComparable]
    let evidenceCount: Int?
    let isExact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAll = false
    private static let collapsedCount: Int = 5

    init(comparables: [MarketComparable], evidenceCount: Int?, isExact: Bool) {
        self.comparables = comparables
        self.evidenceCount = evidenceCount
        self.isExact = isExact
    }

    private var visible: [MarketComparable] {
        showAll ? comparables : Array(comparables.prefix(ListingsSection.collapsedCount))
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let total = evidenceCount, total > comparables.count {
            parts.append("Showing \(comparables.count) of \(total)")
        }
        if comparables.contains(where: { $0.priceType == .asking }) {
            parts.append("asking prices are what sellers hope for, usually higher")
        }
        if !isExact {
            parts.append("similar items, not this exact piece")
        }
        guard let first = parts.first else { return nil }
        parts[0] = first.prefix(1).uppercased() + first.dropFirst()
        return parts.joined(separator: " · ")
    }

    var body: some View {
        rows
            .wwSection("Prices Behind This Estimate", subtitle: subtitle) {
                trailingAction
            }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if comparables.count > ListingsSection.collapsedCount {
            Button(showAll ? "Show Fewer" : "See All \(comparables.count)") {
                withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
                    showAll.toggle()
                }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, comp in
                if index > 0 {
                    WWHairline()
                        .padding(.leading, WW.Space.md)
                }
                EvidenceRow(
                    kind: EvidenceKind(comp.priceType),
                    title: comp.note.isEmpty ? comp.source : comp.note,
                    detail: comp.note.isEmpty ? nil : comp.source,
                    priceUSD: comp.price,
                    currency: comp.currency,
                    url: comp.url,
                    imageURL: comp.imageURL
                )
            }
        }
        .wwCard(padding: 0)
    }
}

// MARK: - Sold prices (04 §6.4 block 6, 05 §2.42)

/// Completed sales over the last 90 days: average, median and count for
/// everyone; the dot chart and the sales themselves with Pro. Every "sales"
/// count here is `sold.count` (04 §4.6).
struct SoldPricesSection: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sold: SoldSummary

    @State private var showAll = false
    private static let collapsedCount: Int = 5

    init(sold: SoldSummary) {
        self.sold = sold
    }

    private var title: String { sold.isExact ? "Sold Prices" : "Sold Prices, Similar Items" }

    private var subtitle: String {
        var parts: [String] = ["Last \(sold.windowDays) days"]
        if sold.unavailable { return parts[0] }
        if !sold.sources.isEmpty { parts.append(sold.sources.joined(separator: " and ")) }
        if sold.sources.contains("eBay") { parts.append("eBay prices include shipping") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        content
            .wwSection(title, subtitle: subtitle) {
                trailingAction
            }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if !sold.unavailable && sold.sales.count > SoldPricesSection.collapsedCount {
            Button(showAll ? "Show Fewer" : "See All \(sold.sales.count)") {
                withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
                    showAll.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if sold.unavailable {
            messageCard("Sold prices couldn't be loaded for this scan. Scan again in a moment to see them.")
        } else if sold.count == 0 {
            messageCard(emptyText)
        } else {
            VStack(alignment: .leading, spacing: WW.Space.sm) {
                statsCard
                if !sold.sales.isEmpty {
                    if chartIsUseful {
                        chartCard
                    }
                    salesList
                }
            }
        }
    }

    // MARK: Figures

    /// Stacked from xxxLarge up (RS-3): at about 99 pt a column, a long JPY or
    /// EUR median would otherwise wrap inside the number (05 §6).
    private var statsLayout: AnyLayout {
        if dynamicTypeSize >= .xxxLarge {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: WW.Space.xs))
        }
        return AnyLayout(HStackLayout(alignment: .top, spacing: WW.Space.xs))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            statsLayout {
                stat(label: "Average", value: sold.average.map { WW.money($0) } ?? "–")
                stat(label: "Median", value: sold.median.map { WW.money($0) } ?? "–")
                stat(label: "Sales", value: "\(sold.count)")
            }
            if let low = sold.low, let high = sold.high, low != high {
                Text("Lowest \(WW.money(low)) · Highest \(WW.money(high))")
                    .monospacedDigit()
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wwCard()
    }

    /// Best Offer and eBay-floor notes. (The "For reference" note is deleted, 04 §4.6.)
    private var notes: [String] {
        var out: [String] = []
        if sold.bestOfferExcluded, sold.bestOfferCount > 0 {
            let n = sold.bestOfferCount
            out.append("\(n) \(n == 1 ? "sale" : "sales") went through Best Offer: eBay only shows the original listing price, not what the buyer paid, so \(n == 1 ? "it's" : "they're") left out of the average and median.")
        }
        if sold.ebayFloorExcluded {
            out.append("eBay sales are left out for cards under \(WW.money(3)): there they show eBay's minimum price, not the card's value.")
        }
        return out
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
            Text(value)
                .wwFont(.price)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: Chart

    private struct SaleDot: Identifiable {
        let id: Int
        let date: Date
        let price: Double
        let sourceIndex: Int
    }

    /// Sale sources in order of first appearance (shape: circle, square, triangle).
    private var sourceNames: [String] {
        var names: [String] = []
        for sale in sold.sales where !names.contains(sale.source) {
            names.append(sale.source)
        }
        return names
    }

    private var dots: [SaleDot] {
        let sources: [String] = sourceNames
        var out: [SaleDot] = []
        for (index, sale) in sold.sales.enumerated() {
            guard let day = sale.day else { continue }
            let sourceIndex: Int = sources.firstIndex(of: sale.source) ?? 0
            out.append(SaleDot(id: index, date: day, price: sale.price, sourceIndex: sourceIndex))
        }
        return out
    }

    /// Worth drawing: three dated sales on at least two different days.
    private var chartIsUseful: Bool {
        let points: [SaleDot] = dots
        let days = Set(points.map { Calendar.current.startOfDay(for: $0.date) })
        return points.count >= 3 && days.count >= 2
    }

    /// Median per week, drawn as the trend line (mid-week, among that week's dots).
    private var weeklyMedians: [SaleDot] {
        let calendar = Calendar(identifier: .iso8601)
        var groups: [Date: [Double]] = [:]
        for dot in dots {
            let start: Date = calendar.dateInterval(of: .weekOfYear, for: dot.date)?.start ?? dot.date
            groups[start, default: []].append(dot.price)
        }
        let weeks: [Date] = groups.keys.sorted()
        var out: [SaleDot] = []
        for (index, start) in weeks.enumerated() {
            let prices: [Double] = (groups[start] ?? []).sorted()
            guard !prices.isEmpty else { continue }
            let mid: Int = prices.count / 2
            let median: Double = prices.count % 2 == 1 ? prices[mid] : (prices[mid - 1] + prices[mid]) / 2
            out.append(SaleDot(id: index, date: start.addingTimeInterval(3.5 * 86_400), price: median, sourceIndex: 0))
        }
        return out
    }

    static func symbolShape(_ index: Int) -> BasicChartSymbolShape {
        switch index {
        case 1: return .square
        case 2: return .triangle
        default: return .circle
        }
    }

    static func symbolGlyph(_ index: Int) -> String {
        switch index {
        case 1: return "square.fill"
        case 2: return "triangle.fill"
        default: return "circle.fill"
        }
    }

    private var plotHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? WW.Chart.plotHeightAX : WW.Chart.plotHeight
    }

    private var chartCard: some View {
        let points: [SaleDot] = dots
        let trend: [SaleDot] = weeklyMedians
        let hasTrend: Bool = trend.count >= 2
        return VStack(alignment: .leading, spacing: WW.Space.sm) {
            soldChart(points: points, trend: hasTrend ? trend : [])
            if sourceNames.count > 1 || hasTrend || !sold.isExact {
                ChartLegend(items: legendItems(hasTrend: hasTrend))
            }
            Text(hasTrend ? "Each dot is one sale. The line is the weekly median." : "Each dot is one sale.")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .wwCard()
    }

    private func soldChart(points: [SaleDot], trend: [SaleDot]) -> some View {
        Chart {
            if let median = sold.median {
                RuleMark(y: .value("Median", median))
                    .foregroundStyle(WW.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: WW.Chart.medianRuleDash))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Median \(WW.money(median))")
                            .wwFont(.caption)
                            .foregroundStyle(WW.secondaryText)
                    }
            }
            if sold.isExact {
                ForEach(points) { dot in
                    PointMark(x: .value("Date", dot.date), y: .value("Price", dot.price))
                        .symbol(SoldPricesSection.symbolShape(dot.sourceIndex))
                        .symbolSize(WW.Chart.saleSymbolSize)
                        .foregroundStyle(WW.text.opacity(WW.Chart.saleDotOpacity))
                }
            } else {
                ForEach(points) { dot in
                    PointMark(x: .value("Date", dot.date), y: .value("Price", dot.price))
                        .symbol {
                            Circle()
                                .strokeBorder(WW.secondaryText, lineWidth: 1)
                                .frame(width: 6, height: 6)
                        }
                }
            }
            ForEach(trend) { week in
                LineMark(x: .value("Week", week.date), y: .value("Weekly median", week.price))
                    .foregroundStyle(WW.text)
                    .lineStyle(StrokeStyle(lineWidth: WW.Chart.lineWidth, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .modifier(WWChartStyle())
        .frame(height: plotHeight)
        .accessibilityLabel(chartSummary)
        .accessibilityChartDescriptor(
            PriceChartDescriptor(
                title: "Sold prices, last \(sold.windowDays) days",
                summary: chartSummary,
                seriesName: "Sales",
                dates: points.map(\.date),
                prices: points.map(\.price)
            )
        )
    }

    /// "{n} sales, median {m}, lowest {lo}, highest {hi}" (04 §9.2).
    private var chartSummary: String {
        var parts: [String] = ["\(sold.count) \(sold.count == 1 ? "sale" : "sales")"]
        if let median = sold.median { parts.append("median \(WW.money(median))") }
        if let low = sold.low { parts.append("lowest \(WW.money(low))") }
        if let high = sold.high { parts.append("highest \(WW.money(high))") }
        return parts.joined(separator: ", ")
    }

    private func legendItems(hasTrend: Bool) -> [ChartLegendItem] {
        var items: [ChartLegendItem] = []
        if sold.isExact {
            let names: [String] = sourceNames
            if names.count > 1 {
                for (index, name) in names.prefix(3).enumerated() {
                    items.append(ChartLegendItem(id: "source-\(index)", label: name, swatch: .dot(SoldPricesSection.symbolGlyph(index))))
                }
            } else {
                items.append(ChartLegendItem(id: "sale", label: "Sale", swatch: .dot("circle.fill")))
            }
        } else {
            items.append(ChartLegendItem(id: "similar", label: "Similar item", swatch: .hollowDot))
        }
        if hasTrend {
            items.append(ChartLegendItem(id: "trend", label: "Weekly median", swatch: .line(dash: [], color: WW.text)))
        }
        if sold.median != nil {
            items.append(ChartLegendItem(id: "median", label: "Median", swatch: .line(dash: WW.Chart.medianRuleDash, color: WW.secondaryText)))
        }
        return items
    }

    // MARK: Sales

    private var visibleSales: [SoldSale] {
        showAll ? sold.sales : Array(sold.sales.prefix(SoldPricesSection.collapsedCount))
    }

    private var salesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleSales.enumerated()), id: \.offset) { index, sale in
                if index > 0 {
                    WWHairline()
                        .padding(.leading, WW.Space.md)
                }
                EvidenceRow(
                    kind: .sold,
                    title: sale.title.isEmpty ? sale.source : sale.title,
                    detail: detail(sale),
                    priceUSD: sale.price,
                    currency: sale.currency,
                    url: sale.url,
                    imageURL: sale.imageURL
                )
            }
            if sold.salesLocked > 0 {
                WWHairline()
                    .padding(.leading, WW.Space.md)
                Text("+ \(sold.salesLocked) more with Pro")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .padding(.horizontal, WW.Space.md)
                    .frame(maxWidth: .infinity, minHeight: WW.Size.rowMin, alignment: .leading)
            }
        }
        .wwCard(padding: 0)
    }

    private func detail(_ sale: SoldSale) -> String {
        var parts: [String] = [sale.source]
        if let day = sale.day {
            parts.append(day.formatted(.dateTime.day().month(.abbreviated)))
        }
        if sale.bestOffer { parts.append("Best Offer") }
        return parts.joined(separator: " · ")
    }

    // MARK: Unavailable and empty

    private func messageCard(_ text: String) -> some View {
        Text(text)
            .wwFont(.subhead)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wwCard()
    }

    private var emptyText: String {
        if sold.ebayFloorExcluded {
            return "No TCGplayer sales of this card in the last \(sold.windowDays) days. eBay sales are left out for cards under \(WW.money(3)): there they show eBay's minimum price, not the card's value."
        }
        return "No sales of this \(sold.isExact ? "exact item" : "kind of item") in the last \(sold.windowDays) days."
    }
}

// MARK: - Price history (04 §6.4 block 9, 05 §2.42)

/// The price chart (Pro): a line per source (shade and dash, never colour),
/// a dot per dated sale, and today's estimated range as a band. A saved item
/// without a series yet shows the pending card. The lock is gone: the one
/// `ProEvidenceCard` invites Free users (04 §2.6).
struct PriceHistorySection: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    let history: PriceHistory?
    let pending: Bool
    let low: Double
    let high: Double

    enum Window: String, CaseIterable, Identifiable {
        case month = "30D"
        case quarter = "90D"
        case all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .month: return 30
            case .quarter: return 90
            case .all: return nil
            }
        }
    }

    @State private var window: Window = .quarter

    init(history: PriceHistory?, pending: Bool, low: Double, high: Double) {
        self.history = history
        self.pending = pending
        self.low = low
        self.high = high
    }

    var body: some View {
        Group {
            if let history, history.isDrawable {
                chartCard(history)
            } else if pending {
                pendingCard
            }
        }
        .wwSection("Price History")
    }

    // MARK: Data

    private struct HistoryPoint: Identifiable {
        let id: String
        let seriesIndex: Int
        let source: String
        let date: Date
        let price: Double
    }

    private struct Change {
        let percent: Double
        let days: Int
        let source: String
    }

    private var cutoff: Date? {
        guard let days = window.days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }

    private func linePoints(_ history: PriceHistory) -> [HistoryPoint] {
        var out: [HistoryPoint] = []
        let limit: Date? = cutoff
        let shown: [PriceSeries] = Array(history.series.prefix(WW.Chart.maxSeries))
        for (index, series) in shown.enumerated() {
            for point in series.points {
                guard let date = point.date else { continue }
                if let limit, date < limit { continue }
                out.append(HistoryPoint(id: "\(series.source)|\(point.t)", seriesIndex: index, source: series.source, date: date, price: point.p))
            }
        }
        return out
    }

    private func salePoints(_ history: PriceHistory) -> [HistoryPoint] {
        var out: [HistoryPoint] = []
        let limit: Date? = cutoff
        for sale in history.sales {
            guard let date = sale.day else { continue }
            if let limit, date < limit { continue }
            out.append(HistoryPoint(id: sale.id, seriesIndex: -1, source: sale.source ?? "Sales", date: date, price: sale.price))
        }
        return out
    }

    /// Change over the window on the longest series.
    private func change(_ points: [HistoryPoint]) -> Change? {
        var bySeries: [Int: [HistoryPoint]] = [:]
        for point in points {
            bySeries[point.seriesIndex, default: []].append(point)
        }
        guard let main = bySeries.values.max(by: { $0.count < $1.count }), main.count >= 2 else { return nil }
        let sorted: [HistoryPoint] = main.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last, first.price > 0 else { return nil }
        let percent: Double = (last.price - first.price) / first.price * 100
        let days: Int = max(1, Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1)
        return Change(percent: percent, days: days, source: first.source)
    }

    private func label(for index: Int, in history: PriceHistory) -> String {
        guard index >= 0, index < history.series.count else { return "Sales" }
        let series: PriceSeries = history.series[index]
        return series.label.isEmpty ? series.source : series.label
    }

    static func seriesColor(_ index: Int) -> Color {
        switch index {
        case 0: return WW.text
        case 1: return WW.secondaryText
        default: return WW.tertiaryText
        }
    }

    static func seriesDash(_ index: Int) -> [CGFloat] {
        let dashes: [[CGFloat]] = WW.Chart.seriesDashes
        guard index >= 0, index < dashes.count else { return [] }
        return dashes[index]
    }

    private var bandColor: Color { contrast == .increased ? WW.track : WW.fill }

    private var plotHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? WW.Chart.plotHeightAX : WW.Chart.plotHeight
    }

    // MARK: Views

    private func chartCard(_ history: PriceHistory) -> some View {
        let lines: [HistoryPoint] = linePoints(history)
        let sales: [HistoryPoint] = salePoints(history)
        let dates: [Date] = (lines + sales).map(\.date)
        let start: Date = dates.min() ?? Date()
        let end: Date = max(dates.max() ?? Date(), Date())
        let currentChange: Change? = change(lines)
        return VStack(alignment: .leading, spacing: WW.Space.sm) {
            header(currentChange)
            if lines.isEmpty && sales.isEmpty {
                Text("No prices in this period.")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: WW.Chart.emptyMinHeight)
            } else {
                historyChart(lines: lines, sales: sales, start: start, end: end)
                    .accessibilityLabel(summary(currentChange, history: history))
                    .accessibilityChartDescriptor(
                        PriceChartDescriptor(
                            title: "Price history",
                            summary: summary(currentChange, history: history),
                            seriesName: currentChange?.source ?? "Prices",
                            dates: lines.map(\.date) + sales.map(\.date),
                            prices: lines.map(\.price) + sales.map(\.price)
                        )
                    )
                ChartLegend(items: legendItems(history, hasSales: !sales.isEmpty, seriesCount: Set(lines.map(\.seriesIndex)).count))
            }
            Text("Shaded: today's value range.")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wwCard()
    }

    @ViewBuilder
    private func header(_ change: Change?) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WW.Space.xs) {
                changeLine(change)
                periodPicker
            }
        } else {
            HStack(alignment: .center, spacing: WW.Space.xs) {
                changeLine(change)
                Spacer(minLength: WW.Space.xs)
                periodPicker
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $window) {
            ForEach(Window.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    /// Up: `positive` + `arrow.up.right`; down: `secondaryText` (never `danger`); flat: words only.
    @ViewBuilder
    private func changeLine(_ change: Change?) -> some View {
        if let change {
            let rounded: Int = Int(abs(change.percent).rounded())
            let span: String = "\(change.days) \(change.days == 1 ? "day" : "days")"
            if rounded == 0 {
                Text("No change over \(span)")
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: WW.Space.xxs) {
                    Image(systemName: change.percent > 0 ? "arrow.up.right" : "arrow.down.right")
                        .accessibilityHidden(true)
                    Text("\(change.percent > 0 ? "+" : "−")\(rounded)% over \(span)")
                        .monospacedDigit()
                }
                .wwFont(.subhead)
                .foregroundStyle(change.percent > 0 ? WW.positive : WW.secondaryText)
            }
        }
    }

    private func historyChart(lines: [HistoryPoint], sales: [HistoryPoint], start: Date, end: Date) -> some View {
        Chart {
            RectangleMark(
                xStart: .value("From", start),
                xEnd: .value("To", end),
                yStart: .value("Low", low),
                yEnd: .value("High", high)
            )
            .foregroundStyle(bandColor)

            ForEach(lines) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.price),
                    series: .value("Source", point.source)
                )
                .foregroundStyle(PriceHistorySection.seriesColor(point.seriesIndex))
                .lineStyle(StrokeStyle(lineWidth: WW.Chart.lineWidth, lineCap: .round, dash: PriceHistorySection.seriesDash(point.seriesIndex)))
                .interpolationMethod(.monotone)
            }

            ForEach(sales) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.price)
                )
                .symbol(BasicChartSymbolShape.circle)
                .symbolSize(WW.Chart.saleSymbolSize)
                .foregroundStyle(WW.text.opacity(WW.Chart.saleDotOpacity))
            }
        }
        .modifier(WWChartStyle())
        .frame(height: plotHeight)
    }

    /// "Price history, {source}, {change} over {days} days" (04 §9.2).
    private func summary(_ change: Change?, history: PriceHistory) -> String {
        guard let change else { return "Price history" }
        let rounded: Int = Int(abs(change.percent).rounded())
        let movement: String
        if rounded == 0 {
            movement = "no change"
        } else {
            movement = change.percent > 0 ? "up \(rounded) percent" : "down \(rounded) percent"
        }
        return "Price history, \(change.source), \(movement) over \(change.days) days"
    }

    private func legendItems(_ history: PriceHistory, hasSales: Bool, seriesCount: Int) -> [ChartLegendItem] {
        var items: [ChartLegendItem] = []
        let count: Int = min(history.series.count, WW.Chart.maxSeries)
        if count > 0 {
            for index in 0..<count {
                items.append(ChartLegendItem(
                    id: "series-\(index)",
                    label: label(for: index, in: history),
                    swatch: .line(dash: PriceHistorySection.seriesDash(index), color: PriceHistorySection.seriesColor(index))
                ))
            }
        }
        if hasSales {
            items.append(ChartLegendItem(id: "sales", label: "Sales", swatch: .dot("circle.fill")))
        }
        items.append(ChartLegendItem(id: "band", label: "Today's value range", swatch: .band))
        return items
    }

    private var pendingCard: some View {
        HStack(alignment: .top, spacing: WW.Space.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WW.secondaryText)
                .accessibilityHidden(true)
            Text("History starts today. We check this item's price daily, and the chart fills in over the next few days.")
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wwCard()
    }
}

// MARK: - Chart style (05 §2.42 "WWChartStyle"; WP0 provides the constants)

/// Neutral, shape-coded chart chrome: trailing money axis with hairline grid,
/// abbreviated dates, no system legend, axis text capped at xxxLarge.
private struct WWChartStyle: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let gridWidth: CGFloat = WW.Stroke.hairline(displayScale: displayScale)
        return content
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: WW.Chart.axisDesiredCount)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: gridWidth))
                        .foregroundStyle(WW.separator)
                    AxisValueLabel {
                        if let price = value.as(Double.self) {
                            Text(WW.money(price))
                                .monospacedDigit()
                                .wwFont(.caption)
                                .foregroundStyle(WW.secondaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: WW.Chart.axisDesiredCount)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(WW.secondaryText)
                }
            }
            .chartLegend(.hidden)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// One entry of the custom legend under a chart.
private struct ChartLegendItem: Identifiable {
    enum Swatch {
        case line(dash: [CGFloat], color: Color)
        case dot(String)
        case hollowDot
        case band
    }

    let id: String
    let label: String
    let swatch: Swatch
}

/// Custom legend (05 §2.42): swatch + footnote, 12 apart, wraps to a column.
private struct ChartLegend: View {
    let items: [ChartLegendItem]
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WW.Space.sm) {
                ForEach(items) { item in
                    entry(item)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    entry(item)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func entry(_ item: ChartLegendItem) -> some View {
        HStack(spacing: 6) {
            swatch(item.swatch)
            Text(item.label)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func swatch(_ swatch: ChartLegendItem.Swatch) -> some View {
        switch swatch {
        case .line(let dash, let color):
            Path { path in
                path.move(to: CGPoint(x: 1, y: 1))
                path.addLine(to: CGPoint(x: 15, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
            .frame(width: 16, height: 2)
        case .dot(let glyph):
            Image(systemName: glyph)
                .font(.system(size: 7, weight: .regular))
                .foregroundStyle(WW.text.opacity(WW.Chart.saleDotOpacity))
        case .hollowDot:
            Circle()
                .strokeBorder(WW.secondaryText, lineWidth: 1)
                .frame(width: 7, height: 7)
        case .band:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(contrast == .increased ? WW.track : WW.fill)
                .frame(width: 12, height: 8)
        }
    }
}

/// Audio graph for a price chart (04 §9.2).
private struct PriceChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let seriesName: String
    let dates: [Date]
    let prices: [Double]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xs: [Double] = dates.map { $0.timeIntervalSince1970 }
        let minX: Double = xs.min() ?? 0
        var maxX: Double = xs.max() ?? 1
        if maxX <= minX { maxX = minX + 86_400 }
        let minY: Double = prices.min() ?? 0
        var maxY: Double = prices.max() ?? 1
        if maxY <= minY { maxY = minY + 1 }

        let xAxis = AXNumericDataAxisDescriptor(title: "Date", range: minX...maxX, gridlinePositions: []) { value in
            Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .omitted)
        }
        let yAxis = AXNumericDataAxisDescriptor(title: "Price", range: minY...maxY, gridlinePositions: []) { value in
            WW.money(value)
        }
        var points: [AXDataPoint] = []
        let count: Int = min(xs.count, prices.count)
        for index in 0..<count {
            points.append(AXDataPoint(x: xs[index], y: prices[index]))
        }
        let series = AXDataSeriesDescriptor(name: seriesName, isContinuous: false, dataPoints: points)
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

// MARK: - Details (04 §6.4 block 10, 05 §3.5)

/// Attributes (identifiers in SF Mono), "Your condition", and "Your Notes"
/// with an Edit link to Edit Details.
struct ResultDetailsSection: View {
    let details: [ItemAttribute]
    let category: CollectibleCategory
    let condition: ConditionGrade?
    let notes: String?
    let onEdit: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(details: [ItemAttribute], category: CollectibleCategory, condition: ConditionGrade?, notes: String?, onEdit: (() -> Void)?) {
        self.details = details
        self.category = category
        self.condition = condition
        self.notes = notes
        self.onEdit = onEdit
    }

    private var conditionText: String {
        condition?.label(for: category) ?? "Not set"
    }

    private var trimmedNotes: String? {
        let text: String = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            detailsCard
            notesCard
        }
        .wwSection("Details")
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(details.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    WWHairline()
                        .padding(.leading, WW.Space.md)
                }
                detailRow(label: row.label, value: row.value, isIdentifier: ResultModel.isIdentifier(row.label))
            }
            if !details.isEmpty {
                WWHairline()
                    .padding(.leading, WW.Space.md)
            }
            detailRow(label: "Your condition", value: conditionText, isIdentifier: false)
        }
        .wwCard(padding: 0)
    }

    @ViewBuilder
    private func detailRow(label: String, value: String, isIdentifier: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    keyText(label)
                    valueText(value, isIdentifier: isIdentifier, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: WW.Space.md) {
                    keyText(label)
                    Spacer(minLength: WW.Space.xs)
                    valueText(value, isIdentifier: isIdentifier, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, WW.Space.md)
        .padding(.vertical, 11)
        .frame(minHeight: WW.Size.rowMin)
        .accessibilityElement(children: .combine)
    }

    private func keyText(_ label: String) -> some View {
        Text(label)
            .wwFont(.subhead)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueText(_ value: String, isIdentifier: Bool, alignment: TextAlignment) -> some View {
        Text(value)
            .wwFont(isIdentifier ? WWTextRole.identifier : WWTextRole.subhead)
            .foregroundStyle(WW.text)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            HStack(alignment: .center, spacing: WW.Space.xs) {
                Text("Your Notes")
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: WW.Space.xs)
                if let onEdit {
                    Button("Edit", action: onEdit)
                        .buttonStyle(WWTertiaryButtonStyle(.accent, .small))
                        .accessibilityLabel("Edit details")
                }
            }
            if let text = trimmedNotes {
                Text(text)
                    .wwFont(.body)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text("No notes")
                    .wwFont(.body)
                    .foregroundStyle(WW.secondaryText)
            }
        }
        .wwCard(padding: WW.Space.md)
    }
}

// MARK: - Share card (05 §2.40, 00 "always light + match word")

/// The shared image: photo, identity, how sure, value, evidence, date and the
/// wordmark. Always light and at Large text, so every share looks the same.
/// A–C only; no praise (06 S2), no numbers on the photo. Render with
/// `ImageRenderer` at scale 3 (1080 × 1350 px).
struct ShareCardView: View {
    let model: ResultModel

    init(model: ResultModel) {
        self.model = model
    }

    private var va: ValueAssessment { model.assessment }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainContent
                .frame(maxHeight: .infinity, alignment: .top)
            foot
                .padding(.top, WW.Space.sm)
        }
        .padding(WW.Space.xl)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .background(WW.background)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
                .layoutPriority(-1)
            identity
                .padding(.top, WW.Space.md)
            MatchIndicator(strength: va.match)
                .padding(.top, WW.Space.xs)
            value
                .padding(.top, WW.Space.sm)
            stamp
                .padding(.top, WW.Space.xs)
        }
    }

    private var photo: some View {
        ZStack {
            WW.photoBackdrop
            if let image = model.photos.first {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                PhotoPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: WW.Radius.photo, style: .continuous))
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            if !model.meta.isEmpty {
                Text(model.meta)
                    .wwFont(.meta)
                    .foregroundStyle(WW.secondaryText)
                    .lineLimit(1)
            }
            Text(model.title)
                .wwFont(.itemTitle)
                .foregroundStyle(WW.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var value: some View {
        if va.level == .rough {
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                CaveatFlag.roughGuide()
                ValueRangeText(lowUSD: va.lowUSD, highUSD: va.highUSD, role: .valueRough)
            }
        } else {
            ValueRangeText(lowUSD: va.lowUSD, highUSD: va.highUSD, role: .valueDisplay)
        }
    }

    private var stamp: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            if let line = EvidenceLine(assessment: va) {
                line
            }
            Text("Prices checked \(model.checkedAt.formatted(date: .abbreviated, time: .omitted))")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
        }
    }

    private var foot: some View {
        HStack(alignment: .center, spacing: WW.Space.xs) {
            WorthwiseWordmark(markSize: 19, fontSize: 13)
            Spacer(minLength: WW.Space.xs)
            Text("Estimate, not an appraisal")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .lineLimit(1)
        }
    }
}
