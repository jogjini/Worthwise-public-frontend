import SwiftUI
import UIKit

/// First run (04 §5.1, 07 §2): O1 Welcome → O2 "What are you scanning?" →
/// O3 consent. The root then runs the age check (O4, where the law requires
/// it) and shows the onboarding paywall (O5) — but only if photo analysis was
/// allowed: selling cloud scans right after "Not now" would contradict the
/// choice just made (00 decisions, 07 decision 2).
///
/// Short on purpose: long onboarding is where installs die. By the time the
/// consent screen appears the user knows what the app does and what declining
/// costs them, which is the difference between an informed decision and a
/// dismissed dialog.
struct OnboardingFlowView: View {
    /// Called once consent has been decided (it is already stored).
    let onFinish: (_ consentGranted: Bool) -> Void

    private enum Step {
        case welcome, intent, consent
    }

    @State private var step: Step = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WW.background.ignoresSafeArea()
            currentStep
        }
        // Light status bar on brandInk (05 §3.12): hidden on Welcome, the
        // spec's fallback that works on every iOS version.
        .statusBarHidden(step == .welcome)
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .welcome:
            WelcomeStep(onContinue: { go(to: .intent) })
                .transition(stepTransition)
        case .intent:
            IntentStep(onContinue: { intent, kinds in
                AppSettings.shared.applyIntent(intent)
                AppSettings.shared.interests = kinds
                go(to: .consent)
            })
            .transition(stepTransition)
        case .consent:
            ConsentStep(onDecide: { granted in
                AppSettings.shared.setAIConsent(granted)
                onFinish(granted)
            })
            .transition(stepTransition)
        }
    }

    /// 06 M30: push from the trailing edge; a crossfade under Reduce Motion.
    private var stepTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.push(from: .trailing)
    }

    private func go(to next: Step) {
        let token: WW.Motion.Token = reduceMotion ? .crossfade : .standard
        withAnimation(WW.Motion.animation(token, reduceMotion: reduceMotion)) {
            step = next
        }
    }
}

// MARK: - Shared

/// Onboarding copy that differs from the shared model strings. (The O2
/// intent subtitles come from `ScanIntent.subtitle`, US English at the
/// source: 00 addition 8, 09 I2.)
private enum OnboardingCopy {
    static let tagline = "What it's worth, and how we know."
    static let costLine = "Start with 3 free scans. No account needed."
}

/// Side margins: 24 (05 §3.12), 16 at accessibility sizes.
private func onboardingMargin(_ size: DynamicTypeSize) -> CGFloat {
    size.isAccessibilitySize ? 16 : 24
}

// MARK: - O1 Welcome

/// Brand level High: `brandInk` full-bleed in both modes, white Tag 64, New
/// York headline, an example result, three points, and a pinned white
/// "Get started" with the cost line under it (00 addition 4).
///
/// Entrance (06 S1): the mark fades in and its pupil opens, then the words,
/// the example (identity first, then value) and the points. "Get started" is
/// visible and tappable from the first frame. Reduce Motion: one short fade,
/// pupil static. VoiceOver running: everything static.
private struct WelcomeStep: View {
    let onContinue: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var markShown = false
    @State private var pupilOpen = false

    private var isStatic: Bool { voiceOverEnabled }
    private var margin: CGFloat { onboardingMargin(dynamicTypeSize) }
    private var onDarkSecondary: Color { Color.white.opacity(0.85) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            content
                .padding(.horizontal, margin)
                .padding(.top, WW.Space.xl)
                .padding(.bottom, WW.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WW.brandInk.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            welcomeBar
        }
        .onAppear(perform: enter)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            mark
            tagline
                .padding(.top, WW.Space.sm)
            headline
                .padding(.top, WW.Space.xl)
            bodyText
                .padding(.top, WW.Space.sm)
            if !dynamicTypeSize.isAccessibilitySize {
                WelcomeSpecimen(isStatic: isStatic)
                    .padding(.top, WW.Space.xl)
            }
            points
                .padding(.top, WW.Space.xl)
        }
    }

    // S1: 0 ms mark fades in (200 ms); 200 ms the pupil opens.
    private var mark: some View {
        WorthwiseMark(size: 64, tone: .onDark, pupilScale: pupilScale)
            .opacity((isStatic || markShown) ? 1 : 0)
    }

    private var pupilScale: CGFloat {
        (isStatic || reduceMotion || pupilOpen) ? 1 : 0.01
    }

    /// The tagline appears in-app only here and in How It Works (00 decisions).
    private var tagline: some View {
        Text(OnboardingCopy.tagline)
            .wwFont(.subhead, weight: .semibold)
            .foregroundStyle(onDarkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .wwReveal(.crossfade, delay: 0.2, isStatic: isStatic)
    }

    private var headline: some View {
        Text("What's it worth?")
            .wwFont(.brandDisplay)
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .wwReveal(.crossfade, delay: 0.25, isStatic: isStatic)
    }

    private var bodyText: some View {
        Text("Cards, coins, records, watches, the vase from the attic. We identify it, check real sold prices and show you a value range, with the evidence.")
            .wwFont(.body)
            .foregroundStyle(onDarkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .wwReveal(.crossfade, delay: 0.32, isStatic: isStatic)
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            WWInfoRow(
                icon: "checkmark.seal",
                title: "Sold prices first",
                detail: "We show what items actually sold for, and say when we only found asking prices.",
                iconStyle: .onDark
            )
            .wwReveal(.crossfade, delay: pointDelay(0), isStatic: isStatic)

            WWInfoRow(
                icon: "arrow.left.and.right",
                title: "A range, not an appraisal",
                detail: "You'll always see how sure we are and where the number comes from.",
                iconStyle: .onDark
            )
            .wwReveal(.crossfade, delay: pointDelay(1), isStatic: isStatic)

            WWInfoRow(
                icon: "square.grid.2x2",
                title: "Your collection, one total",
                detail: "Save items, sort them into folders and see what it all adds up to.",
                iconStyle: .onDark
            )
            .wwReveal(.crossfade, delay: pointDelay(2), isStatic: isStatic)
        }
    }

    private func pointDelay(_ index: Int) -> Double {
        0.6 + WW.Motion.staggerDelay(index: index, reduceMotion: reduceMotion)
    }

    /// Pinned: white capsule "Get started", then the cost line, on `brandInk`
    /// (no material, no hairline), side margins 24.
    private var welcomeBar: some View {
        VStack(spacing: WW.Space.xs) {
            Button("Get started", action: onContinue)
                .buttonStyle(WelcomeButtonStyle())
            Text(OnboardingCopy.costLine)
                .wwFont(.subhead)
                .foregroundStyle(onDarkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, WW.Space.sm)
        .padding(.horizontal, margin)
        .padding(.bottom, WW.Space.xs)
        .frame(maxWidth: .infinity)
        .background(WW.brandInk.ignoresSafeArea(edges: .bottom))
    }

    private func enter() {
        guard !isStatic, !markShown else { return }
        withAnimation(Animation.easeOut(duration: 0.2)) {
            markShown = true
        }
        guard !reduceMotion else { return }
        let open: Animation = WW.Motion.animation(.open, reduceMotion: false) ?? Animation.easeOut(duration: 0.2)
        withAnimation(open.delay(0.2)) {
            pupilOpen = true
        }
    }
}

/// White capsule with a `brandInk` label (02 §5 "High"), 52 pt, pressed 0.85.
private struct WelcomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WelcomeButtonBody(configuration: configuration)
    }
}

private struct WelcomeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat {
        (configuration.isPressed && !reduceMotion) ? 0.98 : 1
    }

    var body: some View {
        configuration.label
            .wwFont(.button)
            .foregroundStyle(WW.brandInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, WW.Space.xl)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: WW.Size.buttonLarge)
            .background(Color.white, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(scale)
            .animation(WW.Motion.animation(.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// 07's example result (a 1921 Morgan silver dollar): identity → match →
/// range → proof, labelled "Example". Follows the light/dark tokens so it
/// previews the real UI. Hidden at accessibility sizes (the body text still
/// says what a result contains). Money is converted to the display currency
/// and never animates; the rows enter identity first, then value.
private struct WelcomeSpecimen: View {
    let isStatic: Bool
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""

    private let lowUSD: Double = 38
    private let highUSD: Double = 52

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            identityRow
            valueRow
                .wwReveal(.crossfade, delay: 0.52, isStatic: isStatic)
        }
        .wwCard(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .wwReveal(.crossfade, delay: 0.40, isStatic: isStatic)
    }

    private var accessibilityText: String {
        "Example result: Morgan silver dollar, 1921. Close match. Between \(WW.money(lowUSD)) and \(WW.money(highUSD)), based on 14 sold prices."
    }

    private var identityRow: some View {
        HStack(alignment: .center, spacing: WW.Space.sm) {
            photoTile
            VStack(alignment: .leading, spacing: 2) {
                Text("Example · Coin · 1921")
                    .wwFont(.meta)
                    .foregroundStyle(WW.secondaryText)
                Text("Morgan silver dollar")
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                MatchIndicator(strength: .close)
            }
        }
    }

    /// The coin follows the display currency, like its money (00 default).
    private var photoTile: some View {
        Image(systemName: WW.coinSymbol())
            .font(.system(size: 30, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.white)
            .frame(width: WW.Size.thumb, height: WW.Size.thumb)
            .background(WW.photoBackdrop, in: RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous))
    }

    private var valueRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ValueRangeText(lowUSD: lowUSD, highUSD: highUSD, role: .priceLarge)
            EvidenceLine(kind: .sold, text: "14 sold prices · checked today", isExact: true)
        }
    }
}

// MARK: - O2 "What are you scanning?"

/// One optional intent (single-select) and optional kinds of things
/// (multi-select). Saves `AppSettings.intent` (via `applyIntent`, which turns
/// photo review off for "Things to sell") and `AppSettings.interests`.
/// The echo line says the one real effect of the answer (07).
private struct IntentStep: View {
    let onContinue: (_ intent: ScanIntent?, _ kinds: [String]) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var intent: ScanIntent?
    @State private var kinds: Set<String> = []

    private var margin: CGFloat { onboardingMargin(dynamicTypeSize) }
    private var nothingPicked: Bool { intent == nil && kinds.isEmpty }

    /// Kinds in grid order, so Home shows them the same way.
    private var orderedKinds: [String] {
        CategoryGuide.all.map(\.id).filter { kinds.contains($0) }
    }

    private var columns: [GridItem] {
        let count: Int = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                intentRows
                    .padding(.top, WW.Space.xl)
                kindsLabel
                    .padding(.top, WW.Space.xxl)
                kindsGrid
                    .padding(.top, WW.Space.sm)
            }
            .padding(.horizontal, margin)
            .padding(.top, WW.Space.xl)
            .padding(.bottom, WW.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WW.background.ignoresSafeArea())
        .wwBottomBar {
            barContent
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            Text("What are you scanning?")
                .wwFont(.brandDisplay)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Pick what fits. We'll tailor tips and your first screen.")
                .wwFont(.callout)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var intentRows: some View {
        VStack(spacing: 10) {
            ForEach(ScanIntent.allCases) { option in
                IntentRow(intent: option, isSelected: intent == option) {
                    select(option)
                }
            }
        }
    }

    private var kindsLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: WW.Space.xxs) {
                kindsTitle
                kindsOptional
            }
            VStack(alignment: .leading, spacing: 2) {
                kindsTitle
                kindsOptional
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var kindsTitle: some View {
        Text("What kinds of things?")
            .wwFont(.headline)
            .foregroundStyle(WW.text)
    }

    private var kindsOptional: some View {
        Text("(optional)")
            .wwFont(.subhead)
            .foregroundStyle(WW.secondaryText)
    }

    private var kindsGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(CategoryGuide.all) { guide in
                KindTile(
                    name: guide.name,
                    glyph: guide.id == "coins" ? WW.coinSymbol() : guide.icon,
                    isSelected: kinds.contains(guide.id)
                ) {
                    toggle(guide.id)
                }
            }
        }
    }

    /// 07 echo line: selling wins over kinds; nothing picked, no line.
    private var echoLine: String? {
        if intent == .selling {
            return "Scans will start as soon as you take the photo. You can change this in Settings."
        }
        let names: [String] = CategoryGuide.all.filter { kinds.contains($0.id) }.map(\.name)
        switch names.count {
        case 0:
            return nil
        case 1:
            return "We'll put the \(names[0]) guide first."
        case 2:
            return "We'll put the \(names[0]) and \(names[1]) guides first."
        default:
            return "We'll put your \(names.count) kinds first."
        }
    }

    @ViewBuilder
    private var barContent: some View {
        if let echoLine {
            Text(echoLine)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        Button(nothingPicked ? "Skip" : "Continue") {
            onContinue(intent, orderedKinds)
        }
        .buttonStyle(WWPrimaryButtonStyle())
    }

    private func select(_ option: ScanIntent) {
        Haptics.selection()
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            intent = (intent == option) ? nil : option
        }
    }

    private func toggle(_ id: String) {
        Haptics.selection()
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            if kinds.contains(id) {
                kinds.remove(id)
            } else {
                kinds.insert(id)
            }
        }
    }
}

/// O2 intent row (05 §2.43): `surface`, r 16, min 56; selected = `accentWash`
/// fill + `checkmark.circle.fill` in `accent` + `.isSelected`.
private struct IntentRow: View {
    let intent: ScanIntent
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 28

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(WWPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: some View {
        HStack(spacing: WW.Space.sm) {
            Image(systemName: intent.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? WW.accent : WW.text)
                .frame(width: glyphWidth)
                .accessibilityHidden(true)
            texts
            Spacer(minLength: WW.Space.xs)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? WW.accent : WW.track)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, WW.Space.md)
        .frame(maxWidth: .infinity, minHeight: WW.Size.rowTall, alignment: .leading)
        .background(isSelected ? WW.accentWash : WW.surface, in: shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
            }
        }
        .contentShape(shape)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(intent.title)
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = intent.subtitle {
                Text(subtitle)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// O2 kind tile (05 §2.43): 2 columns (1 at AX), `surface`, r 16, min 56;
/// selected = `accentWash` fill + `checkmark` in `accent` + `.isSelected`.
private struct KindTile: View {
    let name: String
    let glyph: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 24

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(WWPressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: glyph)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? WW.accent : WW.text)
                .frame(width: glyphWidth)
                .accessibilityHidden(true)
            Text(name)
                .wwFont(.subhead, weight: .semibold)
                .foregroundStyle(WW.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: WW.Space.xxs)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WW.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, WW.Space.sm)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: WW.Size.rowTall, alignment: .leading)
        .background(isSelected ? WW.accentWash : WW.surface, in: shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
            }
        }
        .contentShape(shape)
    }
}

// MARK: - O3 Consent

/// The reason the rest of this flow exists.
///
/// App Store Guideline 5.1.2(i) (updated 13 Nov 2025) requires disclosure of
/// what data is shared and with whom, **and permission before it is sent**. A
/// paragraph the user swipes past is disclosure, not permission, so this is a
/// stop with two explicit, equal buttons and no way around it.
///
/// Brand level None (02): no Lapis, no serif, no motion, no haptic on either
/// choice (06). Plain language first (one sentence), the route, then the
/// details behind a disclosure. Declining is a supported state, not a
/// punishment: the app opens in on-device mode.
private struct ConsentStep: View {
    let onDecide: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var plateSize: CGFloat = 52
    @State private var showDetails = false
    @State private var showDeclineConfirmation = false

    private var margin: CGFloat { onboardingMargin(dynamicTypeSize) }
    private var plate: CGFloat { min(plateSize, WW.Size.plateS * WW.Size.graphicScaleCap) }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, margin)
                .padding(.top, WW.Space.xl)
                .padding(.bottom, WW.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WW.background.ignoresSafeArea())
        .wwBottomBar {
            consentBar
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(WW.text)
                .frame(width: plate, height: plate)
                .background(WW.fill, in: Circle())
                .accessibilityHidden(true)

            Text("Photos are analyzed in the cloud")
                .wwFont(.pageTitle)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, WW.Space.lg)

            Text(AIConsentExplanation.summary)
                .wwFont(.body)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WW.Space.sm)

            ConsentRouteDiagram()
                .padding(.top, WW.Space.xl)

            DisclosureGroup("Details", isExpanded: $showDetails) {
                AIConsentExplanation()
                    .padding(.top, WW.Space.xs)
            }
            .disclosureGroupStyle(WWDisclosureStyle(tone: .neutral))
            .padding(.top, WW.Space.xl)
        }
    }

    /// Two equal neutral buttons (04 §1), 12 apart, then the footnote.
    private var consentBar: some View {
        VStack(spacing: WW.Space.sm) {
            Button("Allow photo analysis") {
                onDecide(true)
            }
            .buttonStyle(WWSecondaryButtonStyle())

            Button("Not now") {
                showDeclineConfirmation = true
            }
            .buttonStyle(WWSecondaryButtonStyle())
            .confirmationDialog(
                "Continue without photo analysis?",
                isPresented: $showDeclineConfirmation,
                titleVisibility: .visible
            ) {
                // Default role, not `.destructive`: red would be a nudge (07).
                Button("Continue Without It") {
                    onDecide(false)
                }
                Button("Go Back", role: WW.dialogCancelRole) {}
            } message: {
                Text("We'll only read text and barcodes on your iPhone. We won't identify items or check prices. You can turn analysis on any time in Settings.")
            }

            consentFootnote
        }
    }

    /// "Privacy Policy · You can change this any time in Settings." The link
    /// is `text`, underlined, with a 44 pt target.
    private var consentFootnote: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: WW.Space.xxs) {
                privacyLink
                Text("· You can change this any time in Settings.")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize()
            }
            VStack(spacing: 0) {
                privacyLink
                Text("You can change this any time in Settings.")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyLink: some View {
        Link(destination: AppConfig.privacyURL) {
            Text("Privacy Policy")
                .underline()
                .foregroundStyle(WW.text)
                .wwFont(.footnote, weight: .semibold)
                .frame(minHeight: WW.Size.minTarget)
        }
        .accessibilityHint("Opens in Safari")
    }
}

/// "Where your photo goes" (07 O3): phone → cloud → result, with "We don't
/// keep the photo" under the cloud. One VoiceOver element. A vertical list
/// at accessibility sizes. It claims only what `AIConsentExplanation` states.
private struct ConsentRouteDiagram: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var nodeSize: CGFloat = 44

    private var node: CGFloat { min(nodeSize, 44 * WW.Size.graphicScaleCap) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                vertical
            } else {
                horizontal
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your photo is sent to identify and price the item. Your result comes back. We don't keep the photo.")
    }

    private var horizontal: some View {
        HStack(alignment: .top, spacing: 0) {
            nodeColumn(glyph: "iphone", label: "Your photo", showsCaption: false)
            connector
            nodeColumn(glyph: "cloud", label: "Identified and priced", showsCaption: true)
            connector
            nodeColumn(glyph: "list.bullet.rectangle", label: "Your result comes back", showsCaption: false)
        }
        .frame(maxWidth: .infinity)
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            verticalRow(glyph: "iphone", label: "Your photo")
            downArrow
            verticalRow(glyph: "cloud", label: "Identified and priced")
            caption(centered: false)
                .padding(.leading, node + WW.Space.sm)
            downArrow
            verticalRow(glyph: "list.bullet.rectangle", label: "Your result comes back")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nodeColumn(glyph: String, label: String, showsCaption: Bool) -> some View {
        VStack(spacing: WW.Space.xs) {
            circle(glyph)
            Text(label)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showsCaption {
                caption(centered: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func verticalRow(glyph: String, label: String) -> some View {
        HStack(spacing: WW.Space.sm) {
            circle(glyph)
            Text(label)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func circle(_ glyph: String) -> some View {
        Image(systemName: glyph)
            .font(.title3)
            .foregroundStyle(WW.text)
            .frame(width: node, height: node)
            .background(WW.fill, in: Circle())
    }

    private var connector: some View {
        ZStack {
            Rectangle()
                .fill(WW.track)
                .frame(height: 1)
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WW.tertiaryText)
                .padding(.horizontal, 2)
                .background(WW.background)
        }
        .frame(width: 28, height: node)
    }

    private var downArrow: some View {
        Image(systemName: "arrow.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WW.tertiaryText)
            .frame(width: node)
    }

    private func caption(centered: Bool) -> some View {
        Label {
            Text("We don't keep the photo")
        } icon: {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.semibold))
        }
        .labelStyle(WWInlineIconLabelStyle(spacing: WW.Space.xxs))
        .wwFont(.footnote)
        .foregroundStyle(WW.text)
        .multilineTextAlignment(centered ? .center : .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
