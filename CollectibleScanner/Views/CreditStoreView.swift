import RevenueCat
import SwiftUI
import UIKit

/// The Pro paywall (this file used to hold the credit-pack store; it keeps its
/// file name so the Xcode project did not need editing). WP4 · 04 §2.6, §3.7,
/// §5.5, §6.9 · 05 §2.26, §2.41, §3.11 · 06 M22–M25 · 07 O5.
///
/// Entry points (04 §2.6): end of onboarding (`.onboarding`, full-screen
/// cover), the plan pill, the scan gate and the Home hero at 0 scans
/// (`.limitReached` / `.general` through `router.paywall`), a 402 mid-scan
/// (`.limitReached`), the result's Pro card (`.unlockListings`) and Settings
/// (`.general`). Pro users see their plan (`proStatusScreen`) instead.
///
/// Apple guideline 3.1.2 asks the purchase screen itself to show: the price and
/// billing period of each plan, what happens after a free trial, that it
/// renews automatically, how to cancel, and working Terms and Privacy links.
/// All of that is below; keep it when restyling. Restore stays reachable in
/// every state: loading, failed, plans, the no-entitlement banner, Pro status.
///
/// Motion (06): the screen is still when untouched. Only plan selection,
/// banners and the "You're Pro" swap move. Prices and the badge never animate.
struct ProPaywallView: View {
    enum Context: Equatable {
        /// End of onboarding: the user hasn't scanned yet.
        case onboarding
        /// The free scans are used up.
        case limitReached
        /// Tapped "See them with Pro" on a free result (`PaywallRoute.listings`).
        case unlockListings
        /// Opened from Settings or the plan pill.
        case general
    }

    let context: Context

    @EnvironmentObject private var creditManager: CreditManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offerings: Offerings? = nil
    @State private var loadFailed: Bool = false
    @State private var selectedID: String? = nil
    @State private var trialEligible: [String: Bool] = [:]
    @State private var isPurchasing: Bool = false
    @State private var isRestoring: Bool = false
    @State private var banner: PaywallBanner? = nil
    @State private var result: PaywallResultView.Kind? = nil
    @State private var showsMorePlans: Bool = false
    /// PW-2 measurements: the presented height, the bar without its banner,
    /// and the banner. None depends on where the banner sits, so the choice
    /// (`bannerInContent`) can't flip back and forth.
    @State private var screenHeight: CGFloat = 0
    @State private var barBaseHeight: CGFloat = 0
    @State private var bannerHeight: CGFloat = 0

    init(context: Context = .general) {
        self.context = context
    }

    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// Johan's default (00): Weekly is listed third and never preselected, in
    /// every context. Set to true to put it behind a "More plans" disclosure
    /// in onboarding instead (04 §6.9, 05 §3.11 block 4b).
    private static let weeklyBehindMorePlansInOnboarding = false

    private static let bannerAnchor = "paywall-banner"

    private static let legalText = "Payment is charged to your Apple ID when you confirm, or when the free trial ends. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings › your name › Subscriptions. Fair use: 250 scans a month on monthly and yearly plans, 60 a week on the weekly plan."

    // MARK: - Derived state

    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isCover: Bool { context == .onboarding }
    private var isBusy: Bool { isPurchasing || isRestoring }
    private var margin: CGFloat { WW.margin(for: dynamicTypeSize) }

    private var packages: [Package] { CreditManager.proPackages(from: offerings) }

    private var selectedPackage: Package? {
        packages.first { $0.identifier == selectedID } ?? packages.first
    }

    private var hidesWeekly: Bool {
        Self.weeklyBehindMorePlansInOnboarding
            && context == .onboarding
            && packages.contains { $0.packageType != .weekly }
    }

    /// Plans shown as cards (yearly, monthly, weekly).
    private var visiblePackages: [Package] {
        guard hidesWeekly else { return packages }
        return packages.filter { $0.packageType != .weekly }
    }

    /// Plans behind "More plans" (empty unless the flag above is on).
    private var morePackages: [Package] {
        guard hidesWeekly else { return [] }
        return packages.filter { $0.packageType == .weekly }
    }

    private var selectedHasTrial: Bool {
        guard let package = selectedPackage else { return false }
        return trialText(for: package) != nil
    }

    /// The banner sits at the top of the content instead of in the pinned
    /// bar at accessibility sizes, or when bar + banner would take more than
    /// 45 % of the screen (375 × 667 at Large), so both buttons stay visible
    /// and the plans stay in view (05 §6).
    private var bannerInContent: Bool {
        if isAX { return true }
        guard screenHeight > 0, barBaseHeight > 0, bannerHeight > 0 else { return false }
        // The bar's own padding (top 12 + bottom 8) and the 8 above the primary.
        let barChrome: CGFloat = WW.Space.sm + WW.Space.xs + WW.Space.xs
        return barBaseHeight + bannerHeight + barChrome > screenHeight * 0.45
    }

    /// The free count for onboarding copy. Unknown (the first credit check
    /// failed, e.g. an offline first launch) reads as a new install's
    /// allowance, never as 0: the server still decides at scan time (H-2).
    private var onboardingFreeLeft: Int {
        creditManager.hasServerCount ? creditManager.freeScansLeft : CreditManager.freeScanAllowance
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            screen
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { closeToolbarItem }
        }
        .modifier(PaywallHeightReader(height: $screenHeight))
        .tint(WW.text)
        .interactiveDismissDisabled(isBusy)
        .task {
            Telemetry.log(.paywallShown)
            await loadOfferings()
        }
        .onChange(of: creditManager.isPro) { _, nowPro in
            guard nowPro else { return }
            // An error banner must not contradict a Pro that switched on later.
            if banner?.tone == .danger {
                banner = nil
            }
            // Ask to Buy approved while "Waiting for approval" is showing.
            if result == .pending {
                showResult(.success(context))
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        if let result {
            resultScreen(result)
        } else if creditManager.isPro && !isBusy {
            proStatusScreen
                .transition(.opacity)
        } else {
            paywallScreen
                .transition(.opacity)
        }
    }

    private var closeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                // Onboarding: exactly what "Start with 3 free scans" does (07 O5).
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Close")
            .disabled(isBusy)
        }
    }

    // MARK: - Paywall (P1–P8, P10)

    private var paywallScreen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                paywallContent
                    .padding(.horizontal, margin)
                    .padding(.top, WW.Space.xs)
                    .padding(.bottom, WW.Space.xl)
            }
            .onChange(of: banner) { _, newValue in
                // When the banner sits at the top of the content, bring it into view.
                guard bannerInContent, newValue != nil else { return }
                withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(Self.bannerAnchor, anchor: .top)
                }
            }
            .onChange(of: bannerInContent) { _, inContent in
                // Moved there once it was measured (PW-2).
                guard inContent, banner != nil else { return }
                withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(Self.bannerAnchor, anchor: .top)
                }
            }
        }
        .wwBottomBar {
            paywallBar
        }
        .modifier(PaywallCanvas(isCover: isCover))
    }

    private var paywallContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            contentBanner
            paywallHeader
            plansSection
                .padding(.top, WW.Space.xl)
            timelineSection
            benefitsSection
                .padding(.top, WW.Space.xl)
            restoreButton
                .padding(.top, WW.Space.xl)
            legalSection
                .padding(.top, WW.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Banners live in the pinned bar; at accessibility sizes, or when the bar
    /// would get too tall (`bannerInContent`), they move to the top of the
    /// content so the bar stays short enough for the free path.
    @ViewBuilder
    private var contentBanner: some View {
        if let banner, bannerInContent {
            bannerView(banner)
                .modifier(PaywallHeightReader(height: $bannerHeight))
                .id(Self.bannerAnchor)
                .padding(.bottom, WW.Space.md)
                .transition(bannerTransition)
        }
    }

    // MARK: Header

    private var paywallHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorthwiseMark(size: 40, tone: .accent)
                .padding(.top, WW.Space.xs)
            Text(headline)
                .wwFont(.brandTitle)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, WW.Space.md)
            Text(subheadline)
                .wwFont(.callout)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .padding(.top, WW.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        switch context {
        case .onboarding:
            return Self.onboardingHeadline(intent: AppSettings.shared.intent, interests: AppSettings.shared.interests)
        case .limitReached:
            return "You've used your free scans"
        case .unlockListings:
            return "See the evidence behind every value"
        case .general:
            return "Worthwise Pro"
        }
    }

    private var subheadline: String {
        switch context {
        case .onboarding:
            return onboardingSubheadline
        case .limitReached:
            return "Pro gives you 250 scans a month, with the sold and listed prices behind each value."
        case .unlockListings:
            return "Pro shows the sold and listed prices we matched to your item, each with its source, date and a link."
        case .general:
            return "Every scan, with the evidence behind the price."
        }
    }

    /// "No payment today" only while the selected plan really starts with a
    /// free trial; the free-scan count is the real one.
    private var onboardingSubheadline: String {
        let left = onboardingFreeLeft
        let freeLine: String
        if left == 1 {
            freeLine = "Your free scan doesn't need a card."
        } else if left > 1 {
            freeLine = "Your \(left) free scans don't need a card."
        } else {
            freeLine = ""
        }
        if selectedHasTrial && !freeLine.isEmpty {
            return "No payment today. " + freeLine
        }
        if selectedHasTrial {
            return "No payment today, and you can cancel before the trial ends."
        }
        if !freeLine.isEmpty {
            return freeLine
        }
        return "Every scan, with the evidence behind the price."
    }

    /// 04 §6.9: by intent; "Just curious" / skipped uses the one interest's noun.
    private static func onboardingHeadline(intent: ScanIntent?, interests: [String]) -> String {
        switch intent {
        case .some(.collection):
            return "See what your collection is worth"
        case .some(.selling):
            return "Know what it sells for"
        case .some(.inherited):
            return "Know what each piece is worth"
        case .some(.curious), .none:
            if interests.count == 1, let noun = interestNoun(interests[0]) {
                return "See what your \(noun) are worth"
            }
            return "See what your things are worth"
        }
    }

    /// Plural nouns for "See what your {noun} are worth". A private copy of the
    /// guide ids (HomeTipCard is WP1's file); unknown ids get the generic line.
    private static func interestNoun(_ id: String) -> String? {
        let key = id.lowercased()
        switch key {
        case "cards", "tradingcards", "trading_cards": return "cards"
        case "coins": return "coins"
        case "comics": return "comics"
        case "vinyl", "records": return "records"
        case "watches": return "watches"
        case "sneakers": return "sneakers"
        case "toys": return "toys"
        case "games": return "games"
        case "antiques", "ceramics": return "antiques"
        case "stamps": return "stamps"
        default:
            if key.contains("jewel") || key.contains("silver") {
                return "jewelry and silver"
            }
            return nil
        }
    }

    // MARK: Plans

    @ViewBuilder
    private var plansSection: some View {
        if offerings == nil && !loadFailed {
            plansLoading
        } else if packages.isEmpty {
            plansFailed
        } else {
            planList
        }
    }

    /// P1.
    private var plansLoading: some View {
        VStack(spacing: WW.Space.xs) {
            ProgressView()
                .tint(WW.text)
                .accessibilityLabel("Loading plans")
            Text("Loading plans…")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    /// P2.
    private var plansFailed: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                Text("Plans couldn't load.")
                    .wwFont(.subhead, weight: .semibold)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Check your connection, then try again.")
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button {
                retryLoading()
            } label: {
                Text("Try again")
            }
            .buttonStyle(WWSecondaryButtonStyle(size: .compact))
            .disabled(isBusy)
        }
        .wwCard()
    }

    /// P3: Yearly (preselected), Monthly, Weekly, 12 apart.
    private var planList: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            ForEach(visiblePackages, id: \.identifier) { package in
                planCard(package)
            }
            if !morePackages.isEmpty {
                morePlans
            }
        }
    }

    private var morePlans: some View {
        DisclosureGroup(isExpanded: $showsMorePlans) {
            VStack(alignment: .leading, spacing: WW.Space.sm) {
                ForEach(morePackages, id: \.identifier) { package in
                    planCard(package)
                }
            }
        } label: {
            Text("More plans")
        }
        .disclosureGroupStyle(WWDisclosureStyle())
    }

    private func planCard(_ package: Package) -> some View {
        PlanCard(
            name: Self.planName(package),
            price: package.localizedPriceString,
            period: Self.periodWord(package),
            detail: detail(for: package),
            badge: badge(for: package),
            isSelected: package.identifier == selectedPackage?.identifier,
            action: { select(package) }
        )
        .disabled(isBusy)
    }

    private func select(_ package: Package) {
        guard package.identifier != selectedPackage?.identifier else { return }
        Haptics.selection()
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            selectedID = package.identifier
        }
    }

    /// "7-day free trial · $5.00/month" (yearly), "60 scans a week" (weekly).
    private func detail(for package: Package) -> String? {
        var parts: [String] = []
        if let trial = trialText(for: package) {
            parts.append(trial)
        }
        if package.packageType == .annual, let perMonth = package.storeProduct.localizedPricePerMonth {
            parts.append("\(perMonth)/month")
        }
        if package.packageType == .weekly {
            parts.append("60 scans a week")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Save 50%" on the yearly card, only when it saves 10 % or more.
    /// No fallback badge: no "best value" / "most popular" (06 §4.7).
    private func badge(for package: Package) -> String? {
        guard package.packageType == .annual,
              let savings = Self.annualSavingsPercent(in: packages),
              savings >= 10
        else { return nil }
        return "Save \(savings)%"
    }

    /// Yearly vs paying monthly for a year, from the store's own prices.
    static func annualSavingsPercent(in packages: [Package]) -> Int? {
        guard let annual = packages.first(where: { $0.packageType == .annual }),
              let monthly = packages.first(where: { $0.packageType == .monthly })
        else { return nil }
        return savingsPercent(annualPrice: annual.storeProduct.price, monthlyPrice: monthly.storeProduct.price)
    }

    /// Rounded to the nearest whole percent (04 §5.5; was `.rounded(.down)`,
    /// which showed 49): $59.99 vs 12 × $9.99 = 49.96 % → 50.
    static func savingsPercent(annualPrice: Decimal, monthlyPrice: Decimal) -> Int? {
        let yearOfMonthly: Decimal = monthlyPrice * 12
        guard yearOfMonthly > 0, annualPrice > 0 else { return nil }
        let ratio: Double = NSDecimalNumber(decimal: annualPrice / yearOfMonthly).doubleValue
        let percent: Int = Int(((1 - ratio) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    /// "7-day free trial" when the product has one and this Apple ID can still use it.
    private func trialText(for package: Package) -> String? {
        guard let intro = package.storeProduct.introductoryDiscount,
              intro.paymentMode == .freeTrial,
              trialEligible[package.storeProduct.productIdentifier] != false
        else { return nil }
        return "\(Self.durationText(intro.subscriptionPeriod)) free trial"
    }

    private static func planName(_ package: Package) -> String {
        switch package.packageType {
        case .annual: return "Yearly"
        case .monthly: return "Monthly"
        case .weekly: return "Weekly"
        default: return package.storeProduct.localizedTitle
        }
    }

    private static func periodWord(_ package: Package) -> String {
        guard let period = package.storeProduct.subscriptionPeriod else { return "purchase" }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    private static func durationText(_ period: SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return "\(period.value)-day"
        case .week: return period.value == 1 ? "7-day" : "\(period.value)-week"
        case .month: return "\(period.value)-month"
        case .year: return "\(period.value)-year"
        @unknown default: return "\(period.value)-period"
        }
    }

    // MARK: Trial timeline

    /// Only while the selected plan has a free trial this Apple ID can use.
    @ViewBuilder
    private var timelineSection: some View {
        if let package = selectedPackage, let steps = trialSteps(for: package) {
            StepList(steps: steps, style: .timeline)
                .padding(.top, WW.Space.xl)
                .transition(timelineTransition)
        }
    }

    /// What happens when, in plain words (04 §6.9). No reminder is promised
    /// because none is sent. "Any time before" is the day before the trial
    /// ends: Apple renews from 24 hours before the end, so the promise
    /// "you pay nothing" holds on the date we print.
    private func trialSteps(for package: Package) -> [StepItem]? {
        guard trialText(for: package) != nil,
              let intro = package.storeProduct.introductoryDiscount
        else { return nil }
        let end: Date = Self.trialEndDate(intro.subscriptionPeriod, from: Date())
        let cancelBy: Date = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        let price = "\(package.localizedPriceString) per \(Self.periodWord(package))"
        return [
            StepItem(title: "Today", detail: "Full Pro access, free.", icon: "checkmark"),
            StepItem(title: "Any time before \(Self.shortDate(cancelBy))",
                     detail: "Cancel in Settings › your name › Subscriptions and you pay nothing.",
                     icon: "calendar"),
            StepItem(title: Self.shortDate(end),
                     detail: "Your trial ends and \(price) starts.",
                     icon: "creditcard"),
        ]
    }

    private static func trialEndDate(_ period: SubscriptionPeriod, from start: Date) -> Date {
        var components = DateComponents()
        switch period.unit {
        case .day: components.day = period.value
        case .week: components.day = period.value * 7
        case .month: components.month = period.value
        case .year: components.year = period.value
        @unknown default: components.day = period.value
        }
        return Calendar.current.date(byAdding: components, to: start) ?? start
    }

    /// "Oct 20".
    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Oct 20, 2026".
    private static func longDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: Benefits, restore, legal

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            WWInfoRow(
                icon: "camera.viewfinder",
                title: "250 scans a month",
                detail: "Cards, coins, records, watches and more. 60 a week on the weekly plan."
            )
            WWInfoRow(
                icon: "list.bullet.rectangle.portrait",
                title: "Every price behind the value",
                detail: "Every result shows its evidence and date. Pro lists the sold and asking prices we matched, each with its source and a link."
            )
            WWInfoRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Price history for your collection",
                detail: "When a price guide covers a saved item, Pro checks its price daily and charts it."
            )
        }
    }

    /// Apple requires restore wherever purchases are made.
    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            Text(isRestoring ? "Restoring…" : "Restore purchases")
        }
        .buttonStyle(WWTertiaryButtonStyle(.neutral, .small))
        .disabled(isBusy)
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.legalText)
                .wwFont(.caption)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WW.Space.xs) {
                    legalLink("Terms of Use", url: AppConfig.termsURL)
                    Text("·")
                        .wwFont(.caption)
                        .foregroundStyle(WW.secondaryText)
                        .accessibilityHidden(true)
                    legalLink("Privacy Policy", url: AppConfig.privacyURL)
                }
                VStack(alignment: .leading, spacing: 0) {
                    legalLink("Terms of Use", url: AppConfig.termsURL)
                    legalLink("Privacy Policy", url: AppConfig.privacyURL)
                }
            }
        }
    }

    private func legalLink(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            Text(title)
                .underline()
                .wwFont(.caption, weight: .semibold)
                .foregroundStyle(WW.text)
                .frame(minHeight: WW.Size.minTarget)
                .contentShape(Rectangle())
        }
        .accessibilityHint("Opens in Safari")
    }

    // MARK: Pinned bar (PaywallBar)

    /// Banner (unless `bannerInContent`) · primary · what you'll be charged ·
    /// free path. The last three are measured together (PW-2).
    @ViewBuilder
    private var paywallBar: some View {
        if let banner, !bannerInContent {
            bannerView(banner)
                .modifier(PaywallHeightReader(height: $bannerHeight))
                .transition(bannerTransition)
        }
        VStack(spacing: WW.Space.xs) {
            primaryButton
            if let line = priceDisclosure {
                Text(line)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
            }
            freePathButton
        }
        .modifier(PaywallHeightReader(height: $barBaseHeight))
    }

    private var primaryTitle: String {
        selectedHasTrial ? "Start free trial" : "Continue"
    }

    private var primaryButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            Text(primaryTitle)
                .contentTransition(.opacity)
        }
        .buttonStyle(WWPrimaryButtonStyle(isLoading: isPurchasing))
        .disabled(selectedPackage == nil || isRestoring)
        .accessibilityLabel(isPurchasing ? "Waiting for the App Store" : primaryTitle)
    }

    /// What the user will be charged, in plain words, right under the button.
    private var priceDisclosure: String? {
        guard let package = selectedPackage else { return nil }
        let price = "\(package.localizedPriceString)/\(Self.periodWord(package))"
        if let trial = trialText(for: package) {
            return "\(trial), then \(price). Cancel anytime."
        }
        return "\(price), renews automatically. Cancel anytime."
    }

    /// The free path: same width as the primary (07 O5 checklist).
    @ViewBuilder
    private var freePathButton: some View {
        if let title = freePathTitle {
            Button {
                dismiss()
            } label: {
                Text(title)
            }
            .buttonStyle(WWSecondaryButtonStyle())
            .disabled(isBusy)
        }
    }

    private var freePathTitle: String? {
        switch context {
        case .onboarding:
            let left = onboardingFreeLeft
            if left == 1 { return "Start with 1 free scan" }
            if left > 1 { return "Start with \(left) free scans" }
            return "Not now"
        case .limitReached, .unlockListings:
            return "Not now"
        case .general:
            return nil
        }
    }

    // MARK: Banners (P7, P8, P10)

    private func bannerView(_ banner: PaywallBanner) -> some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: banner.tone == .danger ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(banner.tone == .danger ? WW.danger : WW.text)
                    .accessibilityHidden(true)
                Text(banner.message)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if banner.showsRestore || banner.showsSupport {
                bannerActions(banner)
            }
        }
        .wwCard(padding: WW.Space.sm, style: banner.tone == .danger ? .danger : .surface)
    }

    private func bannerActions(_ banner: PaywallBanner) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WW.Space.md) {
                bannerRestore(banner)
                bannerSupport(banner)
            }
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                bannerRestore(banner)
                bannerSupport(banner)
            }
        }
    }

    /// P8: Restore comes first when the payment went through without Pro.
    @ViewBuilder
    private func bannerRestore(_ banner: PaywallBanner) -> some View {
        if banner.showsRestore {
            Button {
                Task { await restore() }
            } label: {
                Text("Restore purchases")
            }
            .buttonStyle(WWSecondaryButtonStyle(size: .compact, isLoading: isRestoring))
            .disabled(isPurchasing)
        }
    }

    @ViewBuilder
    private func bannerSupport(_ banner: PaywallBanner) -> some View {
        if banner.showsSupport {
            Button {
                openURL(AppConfig.supportURL)
            } label: {
                Text("Help & Support")
            }
            .buttonStyle(WWTertiaryButtonStyle(.accent, .small))
            .accessibilityHint("Opens in Safari")
        }
    }

    private var bannerTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.opacity.combined(with: AnyTransition.offset(y: -8))
    }

    private var timelineTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.opacity.combined(with: AnyTransition.move(edge: .top))
    }

    // MARK: - Already Pro (P11)

    private var proStatusScreen: some View {
        ScrollView {
            proStatusContent
                .padding(.horizontal, margin)
                .padding(.top, WW.Space.xs)
                .padding(.bottom, WW.Space.xl)
        }
        .modifier(PaywallCanvas(isCover: isCover))
    }

    private var proStatusContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner {
                bannerView(banner)
                    .padding(.bottom, WW.Space.md)
                    .transition(bannerTransition)
            }
            WorthwiseMark(size: 40, tone: .accent)
                .padding(.top, WW.Space.xs)
            Text("You're on Worthwise Pro")
                .wwFont(.brandTitle)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, WW.Space.md)
            Text("Thanks for supporting Worthwise.")
                .wwFont(.callout)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WW.Space.xs)
            PaywallPlanFactsCard(facts: planFacts)
                .padding(.top, WW.Space.xl)
            if let note = trialNote {
                Text(note)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WW.Space.xs)
            }
            Button {
                openURL(Self.manageSubscriptionsURL)
            } label: {
                Text("Manage Subscription")
            }
            .buttonStyle(WWSecondaryButtonStyle())
            .padding(.top, WW.Space.xl)
            restoreButton
                .padding(.top, WW.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The plan as the device and our server know it. Only facts we have:
    /// rows with no data are left out rather than guessed.
    private var planFacts: [PaywallPlanFact] {
        var facts: [PaywallPlanFact] = []
        if let plan = Self.planName(productID: creditManager.activeProductID) {
            let value = creditManager.isInTrial ? "\(plan), free trial" : plan
            facts.append(PaywallPlanFact(label: "Plan", value: value))
        }
        if let used = creditManager.scansUsed, let limit = creditManager.scanLimit {
            facts.append(PaywallPlanFact(label: "Scans this period", value: "\(used) of \(limit)"))
        } else {
            facts.append(PaywallPlanFact(label: "Scans", value: Self.allowance(productID: creditManager.activeProductID)))
        }
        if let resets = creditManager.periodEndsAt {
            facts.append(PaywallPlanFact(label: "Scan count resets", value: Self.longDate(resets)))
        }
        if let expires = creditManager.proExpiresAt {
            facts.append(PaywallPlanFact(label: expiryLabel, value: Self.longDate(expires)))
        }
        return facts
    }

    /// During a trial the entitlement's expiry is the trial's last day.
    private var expiryLabel: String {
        if creditManager.isInTrial { return "Trial ends" }
        return creditManager.willRenew ? "Renews" : "Ends"
    }

    private var trialNote: String? {
        guard creditManager.isInTrial, creditManager.willRenew else { return nil }
        return "To avoid being charged, cancel at least 24 hours before your trial ends, in Settings › your name › Subscriptions."
    }

    private static func planName(productID: String?) -> String? {
        guard let id = productID?.lowercased() else { return nil }
        if id.contains("year") || id.contains("annual") { return "Yearly" }
        if id.contains("month") { return "Monthly" }
        if id.contains("week") { return "Weekly" }
        return nil
    }

    /// Fair-use allowance by plan, shown until the server reports the counters.
    private static func allowance(productID: String?) -> String {
        if productID?.lowercased().contains("week") == true { return "60 a week" }
        return "250 a month"
    }

    // MARK: - Result (P6, P9)

    @ViewBuilder
    private func resultScreen(_ kind: PaywallResultView.Kind) -> some View {
        let view = PaywallResultView(state: kind, facts: planFacts) {
            dismiss()
        }
        .modifier(PaywallCanvas(isCover: isCover))
        if reduceMotion {
            view.transition(.opacity)
        } else {
            view.transition(.blurReplace)
        }
    }

    // MARK: - Actions

    private func loadOfferings() async {
        loadFailed = false
        do {
            let loaded = try await Purchases.shared.offerings()
            let pkgs = CreditManager.proPackages(from: loaded)
            let ids = pkgs.map { $0.storeProduct.productIdentifier }
            var eligibility: [String: Bool] = [:]
            if !ids.isEmpty {
                // Checked before the plans show, so a trial is never offered
                // to an Apple ID that already used it.
                let checked = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: ids)
                eligibility = checked.mapValues { $0.status != .ineligible }
            }
            trialEligible = eligibility
            if selectedID == nil || !pkgs.contains(where: { $0.identifier == selectedID }) {
                // Yearly first: best value, and it carries the free trial.
                selectedID = (pkgs.first { $0.packageType == .annual } ?? pkgs.first)?.identifier
            }
            offerings = loaded
            #if DEBUG
            print("[Paywall] current offering: \(loaded.current?.identifier ?? "none")")
            for pkg in pkgs {
                print("[Paywall]   \(pkg.identifier): \(pkg.storeProduct.productIdentifier) \(pkg.localizedPriceString)")
            }
            #endif
        } catch {
            #if DEBUG
            print("[Paywall] Failed to load offerings: \(error.localizedDescription)")
            #endif
            loadFailed = true
        }
    }

    private func retryLoading() {
        offerings = nil
        loadFailed = false
        Task { await loadOfferings() }
    }

    /// Every outcome is visible (04 §5.5): cancelled → nothing; Pro → "You're
    /// Pro"; paid without entitlement → banner + Restore; Ask to Buy →
    /// "Waiting for approval"; failure → plain-language banner, never raw text.
    private func purchase() async {
        guard let package = selectedPackage, !isBusy else { return }
        let productID = package.storeProduct.productIdentifier
        setBanner(nil)
        isPurchasing = true
        Telemetry.log(.purchaseStarted(productID: productID))

        do {
            let outcome = try await creditManager.purchase(package: package)
            switch outcome {
            case .pro:
                Telemetry.log(.purchaseCompleted(productID: productID))
                showResult(.success(context))
            case .cancelled:
                break
            case .noEntitlement:
                Telemetry.log(.purchaseFailed(reason: "no_entitlement"))
                Haptics.notify(.error)
                setBanner(PaywallBanner.noEntitlement)
            }
        } catch let error as RevenueCat.ErrorCode where error == .paymentPendingError {
            // Ask to Buy: a parent or guardian has to approve. In the US states with
            // App Store age laws this is how every minor's purchase works. Not an
            // error: RevenueCat's customer info stream flips the app to Pro on approval.
            Telemetry.log(.purchaseFailed(reason: "pending_approval"))
            showResult(.pending)
        } catch {
            let wasCancelled = (error as? RevenueCat.ErrorCode) == .purchaseCancelledError
            if !wasCancelled {
                Telemetry.log(.purchaseFailed(reason: String((error as NSError).code)))
                Haptics.notify(.error)
                setBanner(PaywallBanner.purchaseFailed(error))
            }
        }

        withAnimation(WW.Motion.animation(.crossfade, reduceMotion: reduceMotion)) {
            isPurchasing = false
        }
    }

    /// Restore never dismisses on its own: the result stays on screen (a
    /// banner; Pro status when found) until the person closes the paywall.
    private func restore() async {
        guard !isBusy else { return }
        isRestoring = true

        do {
            let isPro = try await creditManager.restorePurchases()
            if isPro {
                Haptics.notify(.success)
                setBanner(PaywallBanner.restored)
            } else {
                setBanner(PaywallBanner.restoreFoundNothing)
            }
        } catch {
            Haptics.notify(.error)
            setBanner(PaywallBanner.restoreFailed)
        }

        withAnimation(WW.Motion.animation(.crossfade, reduceMotion: reduceMotion)) {
            isRestoring = false
        }
    }

    private func setBanner(_ newBanner: PaywallBanner?) {
        withAnimation(WW.Motion.animation(.settle, reduceMotion: reduceMotion)) {
            banner = newBanner
        }
        if let message = newBanner?.message {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func showResult(_ kind: PaywallResultView.Kind) {
        withAnimation(WW.Motion.animation(.crossfade, reduceMotion: reduceMotion)) {
            banner = nil
            result = kind
        }
    }
}

// MARK: - Banner model

/// A message at the top of the paywall bar (05 §2.41): danger for failures,
/// surface for restore results. Copy is fixed (04 §5.5); raw error text never shows.
private struct PaywallBanner: Equatable {
    enum Tone: Equatable {
        case danger
        case neutral
    }

    let tone: Tone
    let message: String
    let showsRestore: Bool
    let showsSupport: Bool

    init(tone: Tone, message: String, showsRestore: Bool = false, showsSupport: Bool = false) {
        self.tone = tone
        self.message = message
        self.showsRestore = showsRestore
        self.showsSupport = showsSupport
    }

    static let noEntitlement = PaywallBanner(
        tone: .danger,
        message: "Your payment went through, but Pro hasn't switched on yet. Tap Restore purchases. If that doesn't help, contact support.",
        showsRestore: true,
        showsSupport: true
    )

    static let restored = PaywallBanner(tone: .neutral, message: "Pro restored.")

    static let restoreFoundNothing = PaywallBanner(
        tone: .neutral,
        message: "We couldn't find a Pro subscription for this Apple ID."
    )

    static let restoreFailed = PaywallBanner(
        tone: .danger,
        message: "Restore didn't finish. Check your connection and try again."
    )

    private static let networkFailure = PaywallBanner(
        tone: .danger,
        message: "No connection. Check your signal and try again."
    )

    static func purchaseFailed(_ error: Error) -> PaywallBanner {
        if let code = error as? RevenueCat.ErrorCode {
            switch code {
            case .purchaseNotAllowedError:
                return PaywallBanner(tone: .danger, message: "Purchases are turned off on this iPhone. Check Screen Time settings.")
            case .networkError:
                return networkFailure
            case .storeProblemError:
                return PaywallBanner(tone: .danger, message: "The App Store didn't respond. Try again in a moment.")
            case .productAlreadyPurchasedError:
                return PaywallBanner(
                    tone: .danger,
                    message: "This Apple ID already has Pro. Tap Restore purchases to turn it on.",
                    showsRestore: true
                )
            default:
                break
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return networkFailure
        }
        return PaywallBanner(tone: .danger, message: "The purchase didn't go through, and you weren't charged. Try again.")
    }
}

// MARK: - Canvas

/// Onboarding cover: `background` canvas. Sheets: `wwSheetBackground()`
/// (cards become `elevated` in dark, 05 D16), extended under the bars.
private struct PaywallCanvas: ViewModifier {
    let isCover: Bool
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCover {
            content
                .background(WW.background.ignoresSafeArea())
        } else {
            content
                .wwSheetBackground()
                .background(sheetCanvas.ignoresSafeArea())
        }
    }

    private var sheetCanvas: Color {
        colorScheme == .dark ? WW.surface : WW.background
    }
}

/// Writes the height of the view it is applied to into `height` (iOS 17: a
/// background GeometryReader, so the view's own layout is unchanged).
private struct PaywallHeightReader: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in
                        height = newValue
                    }
            }
        }
    }
}

// MARK: - Plan card (05 §2.26)

/// One plan. Selected: 2 pt `accent` stroke and a filled check (✓ glyph, so
/// colour never carries the selection alone); the price moves under the name
/// at accessibility sizes. Prices and the badge never animate (06 M22).
struct PlanCard: View {
    let name: String
    let price: String
    /// "year", "month", "week": shown as "/year", spoken "per year".
    let period: String
    let detail: String?
    /// "Save 50%" (rendered upper case by the chip role).
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.wwSurfaceLevel) private var surfaceLevel

    init(name: String, price: String, period: String, detail: String?, badge: String?,
         isSelected: Bool, action: @escaping () -> Void) {
        self.name = name
        self.price = price
        self.period = period
        self.detail = detail
        self.badge = badge
        self.isSelected = isSelected
        self.action = action
    }

    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
    }

    private var fillColor: Color {
        surfaceLevel == .elevated ? WW.elevated : WW.surface
    }

    var body: some View {
        Button(action: action) {
            cardBody
        }
        .buttonStyle(WWPressableStyle())
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: WW.Space.sm) {
            selectionGlyph
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                nameRow
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .wwFont(.subhead)
                        .foregroundStyle(WW.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isAX {
                    priceStack(alignment: .leading)
                        .padding(.top, WW.Space.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isAX {
                priceStack(alignment: .trailing)
            }
        }
        .padding(WW.Space.md)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(fillColor, in: shape)
        .overlay { strokeLayer }
        .contentShape(shape)
        .wwAnimation(.standard, value: isSelected)
    }

    private var selectionGlyph: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isSelected ? WW.accent : WW.track)
            .contentTransition(glyphTransition)
            .accessibilityHidden(true)
    }

    private var glyphTransition: ContentTransition {
        reduceMotion ? ContentTransition.opacity : ContentTransition.symbolEffect(.replace)
    }

    @ViewBuilder
    private var nameRow: some View {
        if let badge {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: WW.Space.xs) {
                    nameText
                    badgeView(badge)
                }
                VStack(alignment: .leading, spacing: WW.Space.xxs) {
                    nameText
                    badgeView(badge)
                }
            }
        } else {
            nameText
        }
    }

    private var nameText: some View {
        Text(name)
            .wwFont(.headline)
            .foregroundStyle(WW.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func badgeView(_ text: String) -> some View {
        Text(text)
            .wwFont(.chip)
            .foregroundStyle(WW.accent)
            .padding(.horizontal, WW.Space.xs)
            .padding(.vertical, WW.Space.xxs)
            .frame(minHeight: WW.Size.chipMin)
            .background(WW.accentWash, in: RoundedRectangle(cornerRadius: WW.Radius.chip, style: .continuous))
            .fixedSize()
    }

    private func priceStack(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(price)
                .wwFont(.price)
                .foregroundStyle(WW.text)
                .contentTransition(.identity)
                .fixedSize(horizontal: !isAX, vertical: true)
            Text("/\(period)")
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var strokeLayer: some View {
        if isSelected {
            shape.strokeBorder(WW.accent, lineWidth: WW.Stroke.selected)
        } else if contrast == .increased {
            shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
        }
    }

    /// "Yearly, $59.99 per year, 7-day free trial, $5.00/month, save 50%".
    private var spokenLabel: String {
        var parts: [String] = ["\(name), \(price) per \(period)"]
        if let detail, !detail.isEmpty {
            parts.append(detail.replacingOccurrences(of: " · ", with: ", "))
        }
        if let badge {
            parts.append(badge.lowercased())
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Plan facts

/// One key/value row of the plan card in "You're Pro" / Pro status.
struct PaywallPlanFact: Hashable {
    let label: String
    let value: String
}

/// Plan rows in `.wwCard(padding: 0)`; key and value stack at AX sizes (04 §9.1).
private struct PaywallPlanFactsCard: View {
    let facts: [PaywallPlanFact]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 {
                    WWHairline()
                        .padding(.leading, WW.Space.md)
                }
                row(fact)
            }
        }
        .wwCard(padding: 0)
    }

    private func row(_ fact: PaywallPlanFact) -> some View {
        rowContent(fact)
            .padding(.horizontal, WW.Space.md)
            .padding(.vertical, WW.Space.sm)
            .frame(maxWidth: .infinity, minHeight: WW.Size.rowMin, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rowContent(_ fact: PaywallPlanFact) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                labelText(fact.label)
                valueText(fact.value)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: WW.Space.xs) {
                labelText(fact.label)
                Spacer(minLength: WW.Space.xs)
                valueText(fact.value)
            }
        }
    }

    private func labelText(_ text: String) -> some View {
        Text(text)
            .wwFont(.subhead)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .wwFont(.subhead, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(WW.text)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Purchase result (05 §2.41, 06 M24)

/// "You're Pro" after a purchase, or "Waiting for approval" (Ask to Buy).
/// Replaces the paywall's content. Never dismisses on its own: Done is
/// visible and tappable from the first frame.
struct PaywallResultView: View {
    enum Kind: Equatable {
        case success(ProPaywallView.Context)
        case pending
    }

    let state: Kind
    let facts: [PaywallPlanFact]
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pupilScale: CGFloat = 0
    @State private var textShown: Bool = false
    @State private var didAppear: Bool = false
    @AccessibilityFocusState private var titleFocused: Bool

    init(state: Kind, facts: [PaywallPlanFact] = [], onDone: @escaping () -> Void) {
        self.state = state
        self.facts = facts
        self.onDone = onDone
    }

    private var isSuccess: Bool {
        if case .success = state { return true }
        return false
    }

    private var title: String {
        isSuccess ? "You're Pro" : "Waiting for approval"
    }

    /// Only what the server does: scans include the prices it finds; an item
    /// opened before paying is checked again with a Pro scan.
    private var message: String {
        switch state {
        case .success(let context):
            let base = "New scans show the sold and listed prices we find, each with its source and date."
            if context == .unlockListings {
                return base + " To see the prices for the item you were looking at, check it again from its screen. That uses 1 of your Pro scans."
            }
            return base
        case .pending:
            return "We've sent this to your parent or guardian. Pro turns on as soon as they approve."
        }
    }

    private var topInset: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? WW.Space.xl : 64
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                .padding(.top, topInset)
                .padding(.bottom, WW.Space.xl)
        }
        .wwBottomBar {
            doneButton
        }
        .onAppear(perform: appear)
    }

    private var content: some View {
        VStack(spacing: 0) {
            visual
            texts
                .padding(.top, WW.Space.lg)
                .opacity(textShown ? 1 : 0)
            if isSuccess && !facts.isEmpty {
                PaywallPlanFactsCard(facts: facts)
                    .padding(.top, WW.Space.xl)
                    .opacity(textShown ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var visual: some View {
        switch state {
        case .success:
            WorthwiseMark(size: 56, tone: .accent, pupilScale: pupilScale)
        case .pending:
            Image(systemName: "hourglass")
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WW.secondaryText)
                .frame(width: WW.Size.plateL, height: WW.Size.plateL)
                .background(WW.neutralWash, in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var texts: some View {
        VStack(spacing: WW.Space.xs) {
            Text(title)
                .wwFont(.brandTitle)
                .foregroundStyle(WW.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(message)
                .wwFont(.body)
                .foregroundStyle(WW.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360)
    }

    private var doneButton: some View {
        Button {
            onDone()
        } label: {
            Text("Done")
        }
        .buttonStyle(WWPrimaryButtonStyle())
    }

    /// 06 M24: pupil opens at 150 ms with the success haptic, text fades in at
    /// 200 ms. Reduce Motion or VoiceOver: everything static at once, and
    /// VoiceOver focus moves to the title (no announcement).
    private func appear() {
        guard !didAppear else { return }
        didAppear = true

        if reduceMotion || voiceOverEnabled || !isSuccess {
            pupilScale = 1
            textShown = true
        } else {
            withAnimation(WW.Motion.animation(.open, reduceMotion: false)?.delay(0.15)) {
                pupilScale = 1
            }
            withAnimation(Animation.easeOut(duration: 0.2).delay(0.2)) {
                textShown = true
            }
        }

        if isSuccess {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                Haptics.notify(.success)
            }
        }

        if voiceOverEnabled {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                titleFocused = true
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Plan cards") {
    VStack(spacing: 12) {
        PlanCard(name: "Yearly", price: "$59.99", period: "year", detail: "7-day free trial · $5.00/month",
                 badge: "Save 50%", isSelected: true, action: {})
        PlanCard(name: "Monthly", price: "$9.99", period: "month", detail: nil,
                 badge: nil, isSelected: false, action: {})
        PlanCard(name: "Weekly", price: "$4.99", period: "week", detail: "60 scans a week",
                 badge: nil, isSelected: false, action: {})
    }
    .padding(20)
    .background(WW.background)
}

#Preview("Plan cards · AX3") {
    VStack(spacing: 12) {
        PlanCard(name: "Yearly", price: "$59.99", period: "year", detail: "7-day free trial · $5.00/month",
                 badge: "Save 50%", isSelected: true, action: {})
        PlanCard(name: "Monthly", price: "$9.99", period: "month", detail: nil,
                 badge: nil, isSelected: false, action: {})
    }
    .padding(16)
    .background(WW.background)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("You're Pro") {
    NavigationStack {
        PaywallResultView(
            state: .success(.unlockListings),
            facts: [
                PaywallPlanFact(label: "Plan", value: "Yearly, free trial"),
                PaywallPlanFact(label: "Scans this period", value: "0 of 250"),
                PaywallPlanFact(label: "Trial ends", value: "Oct 21, 2026"),
            ]
        ) {}
    }
}

#Preview("Waiting for approval") {
    NavigationStack {
        PaywallResultView(state: .pending) {}
    }
    .preferredColorScheme(.dark)
}
#endif
