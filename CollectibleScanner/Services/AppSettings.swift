import SwiftUI
import UIKit

/// Every user-facing preference, in one place.
///
/// Backed by `UserDefaults` directly rather than `@AppStorage` because
/// `ScannerViewModel` has to read the AI-consent flag too, and a property
/// wrapper that only works inside a `View` would mean two sources of truth for
/// the one value that decides whether a photo leaves the device.
@MainActor
final class AppSettings: ObservableObject {
    /// The instance the app runs on. `ScannerViewModel` reaches for this rather
    /// than taking an injected optional, because a missed injection would
    /// silently fail *open* on the consent check.
    static let shared = AppSettings()

    enum Theme: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        /// `nil` hands the decision back to iOS.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    private enum Key {
        static let theme = "app_theme"
        static let haptics = "haptics_enabled"
        static let aiConsent = "ai_consent_granted"
        static let lastScanBasis = "last_scan_basis"
        static let tipCollapsed = "home_tip_collapsed"
        static let hasSeenOnboarding = "has_seen_onboarding"
        static let interests = "collecting_interests"
        static let intent = "scan_intent"
        static let reviewBeforeScan = "review_before_scan"
    }

    @Published var theme: Theme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    /// App Store Guideline 5.1.2(i), as amended 13 Nov 2025: personal data may
    /// not be shared with a third-party AI provider without the user's prior
    /// permission. A scan photograph is personal data and it goes to Google and
    /// OpenAI, so this gates every cloud call in `ScannerViewModel.scan()`.
    ///
    /// Defaults to **false**. Never default this to true, and never grant it
    /// from anywhere except an explicit tap by the user.
    @Published private(set) var aiConsentGranted: Bool {
        didSet { defaults.set(aiConsentGranted, forKey: Key.aiConsent) }
    }

    /// What the most recent scan turned out to be, so the home tip card can say
    /// something relevant on the next launch rather than repeating day-one copy.
    @Published private(set) var lastScanBasis: ValuationBasis? {
        didSet { defaults.set(lastScanBasis?.rawValue, forKey: Key.lastScanBasis) }
    }

    @Published var tipCollapsed: Bool {
        didSet { defaults.set(tipCollapsed, forKey: Key.tipCollapsed) }
    }

    @Published var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: Key.hasSeenOnboarding) }
    }

    /// What the user said they collect during onboarding (`CategoryGuide` ids),
    /// used to put their categories and tips first. Empty = no preference.
    @Published var interests: [String] {
        didSet { defaults.set(interests, forKey: Key.interests) }
    }

    /// Why the user is scanning (onboarding O2, 04 §5.1). nil = skipped.
    /// Drives the onboarding paywall headline, the order of Home guides and
    /// the `reviewBeforeScan` default. Nothing else. Set it with `applyIntent(_:)`.
    @Published var intent: ScanIntent? {
        didSet { defaults.set(intent?.rawValue, forKey: Key.intent) }
    }

    /// Settings › Scanning › "Review Photos Before Scanning". Off: the scan
    /// starts as soon as the photo is taken. Defaults to on.
    @Published var reviewBeforeScan: Bool {
        didSet { defaults.set(reviewBeforeScan, forKey: Key.reviewBeforeScan) }
    }

    /// Currency prices are shown in (Settings → Currency). Not written until the
    /// user picks one, so the default keeps following the phone's region.
    @Published var displayCurrency: String {
        didSet { defaults.set(displayCurrency, forKey: DisplayCurrency.codeKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Theme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        // Absent key reads as false, which would silently disable haptics for
        // everyone on first launch — so the default is written, not inferred.
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        aiConsentGranted = defaults.bool(forKey: Key.aiConsent)
        lastScanBasis = (defaults.string(forKey: Key.lastScanBasis)).flatMap(ValuationBasis.init(rawValue:))
        tipCollapsed = defaults.bool(forKey: Key.tipCollapsed)
        hasSeenOnboarding = defaults.bool(forKey: Key.hasSeenOnboarding)
        interests = defaults.stringArray(forKey: Key.interests) ?? []
        intent = defaults.string(forKey: Key.intent).flatMap(ScanIntent.init(rawValue:))
        // Absent key must read as true (review stays on by default).
        reviewBeforeScan = defaults.object(forKey: Key.reviewBeforeScan) as? Bool ?? true
        displayCurrency = defaults.string(forKey: DisplayCurrency.codeKey)
            .flatMap { DisplayCurrency.supported.contains($0) ? $0 : nil } ?? DisplayCurrency.regionDefault
    }

    /// Onboarding O2: stores the intent, and "Things to sell" turns photo
    /// review off (04 §1, §5.1). The user can turn it back on in Settings.
    func applyIntent(_ newIntent: ScanIntent?) {
        intent = newIntent
        if newIntent == .selling {
            reviewBeforeScan = false
        }
    }

    /// The only way consent changes. Routed through one method so the telemetry
    /// and the audit trail can't drift apart from the stored value.
    func setAIConsent(_ granted: Bool) {
        guard aiConsentGranted != granted else { return }
        aiConsentGranted = granted
        Telemetry.log(.aiConsentSet(granted: granted))
    }

    func recordScanBasis(_ basis: ValuationBasis) {
        lastScanBasis = basis
    }
}

/// Why the user is scanning (onboarding O2, 04 §5.1).
enum ScanIntent: String, CaseIterable, Identifiable {
    case collection
    case selling
    case inherited
    case curious

    var id: String { rawValue }

    /// O2 row title.
    var title: String {
        switch self {
        case .collection: return "My collection"
        case .selling: return "Things to sell"
        case .inherited: return "Something I inherited or found"
        case .curious: return "Just curious"
        }
    }

    /// O2 row subtitle (none for "Just curious").
    var subtitle: String? {
        switch self {
        case .collection: return "Cards, coins, records and more"
        case .selling: return "Garage sales, flea markets, resale"
        case .inherited: return "Sorting a house or an attic box"
        case .curious: return nil
        }
    }

    /// O2 row glyph (05 §4).
    var systemImage: String {
        switch self {
        case .collection: return "square.grid.2x2"
        case .selling: return "tag"
        case .inherited: return "shippingbox"
        case .curious: return "magnifyingglass"
        }
    }
}

/// Feedback that honours the Settings toggle.
///
/// Every haptic in the app goes through here; calling `UIFeedbackGenerator`
/// directly anywhere else would make the setting a lie. SwiftUI's
/// `.sensoryFeedback` is only allowed through `View.wwSensoryFeedback`.
///
/// One haptic per event, at least `minimumSpacing` apart (06 law L4): a call
/// that lands sooner than that after the previous one is dropped.
@MainActor
enum Haptics {
    /// 06 L4: one gesture per moment.
    static let minimumSpacing: TimeInterval = 0.3

    private static var lastFiredAt: TimeInterval = 0
    /// Retained so the shutter fires without the generator's warm-up lag.
    private static var shutterGenerator: UIImpactFeedbackGenerator?

    /// Settings › Haptics, readable from any context (e.g. a
    /// `.sensoryFeedback` closure). Same key as `AppSettings.hapticsEnabled`.
    nonisolated static var isEnabledSetting: Bool {
        UserDefaults.standard.object(forKey: "haptics_enabled") as? Bool ?? true
    }

    /// The toggle and the spacing rule. Records the fire time when allowed.
    private static func shouldFire() -> Bool {
        guard AppSettings.shared.hapticsEnabled else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if lastFiredAt > 0 && now - lastFiredAt < minimumSpacing { return false }
        lastFiredAt = now
        return true
    }

    /// Kept for existing call sites: an impact (light by default).
    /// For selection changes use `selection()`.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        impact(style)
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        guard shouldFire() else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: max(0, min(1, intensity)))
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard shouldFire() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// A choice changed: plan card, intent row, kind tile, condition pick,
    /// select-mode toggle, Select All (once).
    static func selection() {
        guard shouldFire() else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// The result reveal (06 §1.2), fresh results only, never for stored ones:
    /// A/B `.success` (a great find gets the same single success, fired at the
    /// swing), C a light tap, D a soft tap (never `.warning`).
    static func result(_ level: ValueLevel, greatFind: Bool = false) {
        switch level {
        case .strong, .fair:
            notify(.success)
        case .rough:
            impact(.light)
        case .noPrice:
            impact(.soft, intensity: 0.6)
        }
    }

    /// Call when the camera appears, so the first shutter is instant.
    static func prepareShutter() {
        if shutterGenerator == nil {
            shutterGenerator = UIImpactFeedbackGenerator(style: .rigid)
        }
        shutterGenerator?.prepare()
    }

    /// The shutter (rigid, 0.7), at `willCapturePhotoFor`.
    static func shutter() {
        guard shouldFire() else { return }
        let generator = shutterGenerator ?? UIImpactFeedbackGenerator(style: .rigid)
        shutterGenerator = generator
        generator.impactOccurred(intensity: 0.7)
    }
}

// MARK: - Review prompt

/// Decides when to ask for an App Store rating.
///
/// Ratings feed App Store search ranking, so the app asks, but only at a calm
/// moment after a result that went well: a level A ("strong") result, closed
/// with Done. Never on the first good scan, at most once per app version and
/// once every 120 days. iOS adds its own cap (3 prompts a year) and may
/// decide to show nothing.
@MainActor
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    static let minimumGoodScans = 2
    static let minimumDaysBetweenAsks: Double = 120

    private enum Key {
        static let goodScans = "review_good_scan_count"
        static let lastAskedVersion = "review_last_asked_version"
        static let lastAskedAt = "review_last_asked_at"
    }

    private let defaults: UserDefaults
    /// Whether the result now on screen went well. Memory only.
    private var currentResultIsGood = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A new scan started: whatever was on screen before no longer counts.
    func scanStarted() {
        currentResultIsGood = false
    }

    func recordResult(profile: CollectibleProfile, estimate: ValueEstimate) {
        let assessment = ValueAssessment(ValueInputs(profile: profile, estimate: estimate, analysisOff: false))
        recordResult(level: assessment.level)
    }

    /// "Good result" = level A (04 §4.4).
    func recordResult(level: ValueLevel) {
        let good = level == .strong
        currentResultIsGood = good
        if good {
            defaults.set(defaults.integer(forKey: Key.goodScans) + 1, forKey: Key.goodScans)
        }
    }

    /// Call when the result screen closes. `true` means ask now, and it is
    /// recorded as asked.
    func shouldAskOnClose(now: Date = Date()) -> Bool {
        defer { currentResultIsGood = false }
        guard currentResultIsGood,
              defaults.integer(forKey: Key.goodScans) >= Self.minimumGoodScans else { return false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if defaults.string(forKey: Key.lastAskedVersion) == version { return false }
        let lastAsked = defaults.double(forKey: Key.lastAskedAt)
        if lastAsked > 0, now.timeIntervalSince1970 - lastAsked < Self.minimumDaysBetweenAsks * 86_400 {
            return false
        }
        defaults.set(version, forKey: Key.lastAskedVersion)
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastAskedAt)
        return true
    }
}

// MARK: - Display currency

/// The currency prices are shown in. Every price arrives from the server in
/// USD and is converted here, at display time, with the European Central Bank
/// rates the server sends with each scan (`fx`). Saved items stay in USD on
/// disk, so changing the currency re-prices everything at once.
enum DisplayCurrency {
    /// Shared with `@AppStorage` in the views that show prices, so they redraw
    /// when the currency changes.
    static let codeKey = "display_currency"
    private static let ratesKey = "fx_per_usd"
    private static let ratesDateKey = "fx_rates_date"

    static let supported: [String] = ["USD", "EUR", "GBP", "CAD", "AUD", "CHF", "JPY", "SEK", "NOK", "DKK", "PLN", "NZD"]

    /// ECB reference rates of 9 Oct 2026 (units per 1 USD), used until a scan
    /// brings newer ones.
    static let builtInPerUSD: [String: Double] = [
        "USD": 1, "EUR": 0.89238, "GBP": 0.75641, "CAD": 1.4226, "AUD": 1.4324, "CHF": 0.83107,
        "JPY": 158.25, "SEK": 9.9656, "NOK": 9.5623, "DKK": 6.6706, "PLN": 3.9117, "NZD": 1.7813,
    ]
    static let builtInDate = "2026-10-09"

    /// The phone's region currency when supported (Belgium → EUR), else USD.
    static var regionDefault: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return supported.contains(code) ? code : "USD"
    }

    static var code: String {
        if let stored = UserDefaults.standard.string(forKey: codeKey), supported.contains(stored) { return stored }
        return regionDefault
    }

    /// "2026-10-09": the day of the rates in use.
    static var ratesDate: String { UserDefaults.standard.string(forKey: ratesDateKey) ?? builtInDate }

    static func perUSD(_ code: String) -> Double? {
        if code == "USD" { return 1 }
        if let stored = UserDefaults.standard.dictionary(forKey: ratesKey)?[code] as? Double, stored > 0 { return stored }
        return builtInPerUSD[code]
    }

    /// A USD amount in the display currency; stays USD when no rate is known.
    static func fromUSD(_ usd: Double, to target: String = DisplayCurrency.code) -> (amount: Double, code: String) {
        guard target != "USD", let rate = perUSD(target) else { return (usd, "USD") }
        return (usd * rate, target)
    }

    /// Rates sent by the server with a scan. A block without the euro is ignored.
    static func store(perUSD: [String: Double], date: String?) {
        let clean = perUSD.filter { supported.contains($0.key) && $0.value.isFinite && $0.value > 0 }
        guard clean["EUR"] != nil else { return }
        UserDefaults.standard.set(clean, forKey: ratesKey)
        if let date, !date.isEmpty { UserDefaults.standard.set(date, forKey: ratesDateKey) }
    }

    /// "Euro", "British Pound", in the phone's language.
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}
