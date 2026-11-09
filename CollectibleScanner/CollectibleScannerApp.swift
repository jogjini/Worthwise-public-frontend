#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
import RevenueCat
import SwiftUI
import UIKit

@main
struct CollectibleScannerApp: App {
    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .error
        #endif
        Purchases.configure(withAPIKey: AppConfig.revenueCatPublicKey)

        // Belt and braces: the "Check release config" build phase already fails a
        // Release build with placeholders, but if that phase is ever removed this
        // leaves a trail in the device log instead of a silent dead app.
        if AppConfig.hasUnfilledPlaceholders {
            Telemetry.log(.configPlaceholdersPresent)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                // Pages scroll up and down only. iOS 27 lets a vertical scroll
                // view rubber-band sideways even when its content fits the
                // screen; this keeps sideways bounce to content that is wider.
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }
}

/// The app, with first-run onboarding (04 §2.1, §5.1) and the age gate on top.
///
/// `AppRouter` is owned and injected by `ContentView` (04 §2.1, WP0 §9), so
/// nothing here creates one. Tint: Lapis is the default for interactive
/// controls; the tab bar and toolbars stay monochrome because `ContentView`'s
/// TabView and each toolbar set `.tint(WW.text)` (02, 05 §0). No custom tab
/// bar or navigation bar backgrounds.
private struct RootContainerView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var collectionStore = CollectionStore()
    @StateObject private var creditManager = CreditManager()
    @StateObject private var authManager = AuthManager()
    @StateObject private var ageAssurance = AgeAssuranceManager()
    @Environment(\.scenePhase) private var scenePhase
    /// O5: the Pro paywall, offered once at the end of onboarding ("Start with
    /// 3 free scans" or ✕ closes it).
    @State private var showOnboardingPaywall = false

    var body: some View {
        ZStack {
            ContentView()
                .environmentObject(collectionStore)
                .environmentObject(creditManager)
                .environmentObject(authManager)
                .environmentObject(settings)

            if !settings.hasSeenOnboarding {
                OnboardingFlowView { consentGranted in
                    finishOnboarding(consentGranted: consentGranted)
                }
                // 06 M30: the overlay hands over to the app with a 350 ms fade.
                .transition(.opacity)
                .zIndex(4)
            }

            if ageAssurance.mustBlock {
                AgeRangeRequiredView {
                    Task { await ageAssurance.check() }
                }
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .tint(WW.accent)
        // Text follows the user's Dynamic Type size, up to the third accessibility
        // size; beyond that the card layouts stop being usable.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        // The whole app, including every sheet, honours the Appearance setting.
        // The `WW` colours adapt to the colour scheme, so overriding it here is
        // the entire implementation.
        .preferredColorScheme(settings.theme.colorScheme)
        .fullScreenCover(isPresented: $showOnboardingPaywall) {
            ProPaywallView(context: .onboarding)
                .environmentObject(creditManager)
                .environmentObject(authManager)
                .environmentObject(settings)
                .environmentObject(collectionStore)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        .task {
            await creditManager.start()
            await authManager.validateCredential()
            // New installs are checked at the end of onboarding instead.
            if settings.hasSeenOnboarding {
                await ageAssurance.check()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await creditManager.refresh()
                    await authManager.validateCredential()
                }
            }
        }
    }

    /// O3 → [O4] → O5 (04 §5.1). The paywall is skipped when photo analysis
    /// was declined (00 decisions, 07 decision 2), for Pro users, and when the
    /// age gate blocks the app (04 §2.6 entry 1).
    private func finishOnboarding(consentGranted: Bool) {
        withAnimation(Animation.easeInOut(duration: 0.35)) {
            settings.hasSeenOnboarding = true
        }
        Task {
            await ageAssurance.check()
            if consentGranted && !creditManager.isPro && !ageAssurance.mustBlock {
                showOnboardingPaywall = true
            }
        }
    }
}

// MARK: - Age assurance (US state App Store Accountability Acts)
//
// Texas, Utah, Louisiana and Alabama (California from 2027) require apps to get
// the user's age category from the App Store. Apple shares it through the
// Declared Age Range API only where the law applies (`isEligibleForAgeFeatures`),
// and handles parental consent for downloads and purchases itself.
//
// What this app does with it:
//  - Nothing changes for adults or minors: the App has no age-restricted content,
//    and a minor's subscription purchase already goes through Apple's
//    parental approval (Ask to Buy).
//  - Where sharing is required and the person declines, the App is blocked until
//    they share, as Apple's guidance asks.
//  - The age category stays on the device. It is never sent to our server
//    (the laws limit its use to age assurance), and it never changes tone,
//    layout or features (09 I6).
//
// Future "significant updates" (new features that change what a minor can do)
// need parental consent through PermissionKit's SignificantAppUpdateTopic; not
// needed for this release, which is the first one under these laws.
//
// Requires the Declared Age Range capability (com.apple.developer.declared-age-range)
// and the iOS 26.2 SDK (Xcode 26.2+). Older iOS versions skip the check: Apple
// only enforces these laws on iOS 26.2 and later.

@MainActor
final class AgeAssuranceManager: ObservableObject {
    enum Status: Equatable {
        case unknown
        /// Not in a region that requires age assurance (or iOS too old).
        case notRequired
        case adult
        case minor(lowerBound: Int?, upperBound: Int?)
        case declined
        /// The service could not answer (offline, Apple outage). Never blocks.
        case unavailable
    }

    @Published private(set) var status: Status = .unknown
    /// True where the law requires the person to share their age range.
    @Published private(set) var sharingRequired = false

    /// Block the App only when sharing is required and the person declined.
    var mustBlock: Bool { sharingRequired && status == .declined }

    private var isChecking = false

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        #if canImport(DeclaredAgeRange)
        guard #available(iOS 26.2, *) else {
            status = .notRequired
            return
        }
        do {
            let service = AgeRangeService.shared
            guard try await service.isEligibleForAgeFeatures else {
                status = .notRequired
                sharingRequired = false
                return
            }
            // Every region Apple marks eligible (Texas, Utah, Louisiana, Alabama)
            // requires the age range to be shared. (iOS 26.4's
            // `requiredRegulatoryFeatures` can refine this once the project
            // builds with that SDK.)
            sharingRequired = true

            guard let presenter = Self.topViewController() else {
                status = .unavailable
                return
            }
            // Gates at 13, 16 and 18 match the age categories in the laws.
            let response = try await service.requestAgeRange(ageGates: 13, 16, 18, in: presenter)
            switch response {
            case .declinedSharing:
                status = .declined
            case .sharing(let range):
                if let upper = range.upperBound, upper < 18 {
                    status = .minor(lowerBound: range.lowerBound, upperBound: upper)
                } else {
                    status = .adult
                }
            @unknown default:
                status = .unavailable
            }
        } catch {
            #if DEBUG
            print("[AgeAssurance] \(error.localizedDescription)")
            #endif
            status = .unavailable
        }
        #else
        status = .notRequired
        #endif
    }

    /// The view controller currently on top, to present Apple's age sheet from.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// O4 (05 §3.12): shown only where the law requires age sharing and the
/// person declined. Neutral: `neutralWash` plate with `hand.raised`, SF page
/// title, secondary-style action. Scrolls when the text is very large.
private struct AgeRangeRequiredView: View {
    let onShare: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var plateSize: CGFloat = 72

    private var plate: CGFloat { min(plateSize, WW.Size.plateL * WW.Size.graphicScaleCap) }
    private var margin: CGFloat { dynamicTypeSize.isAccessibilitySize ? 16 : 28 }

    var body: some View {
        ZStack {
            WW.background.ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                content
                ScrollView {
                    content
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: WW.Space.md) {
            if dynamicTypeSize < .accessibility3 {
                Image(systemName: "hand.raised")
                    .font(.system(size: 30 * plate / WW.Size.plateL, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WW.secondaryText)
                    .frame(width: plate, height: plate)
                    .background(WW.neutralWash, in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text("Share your age range to continue")
                .wwFont(.pageTitle)
                .foregroundStyle(WW.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("The law where you live requires apps to receive your age range from the App Store. Apple shares only an age range, never your birthday, and it stays on this iPhone.")
                .wwFont(.body)
                .foregroundStyle(WW.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Share age range", action: onShare)
                .buttonStyle(WWSecondaryButtonStyle())
                .padding(.top, WW.Space.xs)
        }
        .padding(.horizontal, margin)
        .padding(.vertical, WW.Space.emptyStateTop)
        .frame(maxWidth: .infinity)
    }
}
