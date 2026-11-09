import SwiftUI
import UIKit

// MARK: - Worthwise design system (WP0 · Foundation)
//
// Tokens, type roles, motion, shared components and cross-package contracts
// for the "Lapis" redesign (specs 04 §7–§9, 05 §1–§2 and §5, 06 §2–§3).
//
// Rules for every screen:
// - Views read tokens only: no hex, no literal radii, no `.font(.system(size:))`
//   for text (icons in fixed shapes are the exception).
// - Money is always `text`, tabular, never animated, never below 0.9 scale,
//   never `.lineLimit(1)`. Render ranges with `ValueRangeText`.
// - One `accentFill` (Lapis) element per screen. Bars and toolbars stay
//   monochrome (`.tint(WW.text)`).
// - Every money view declares `@AppStorage(DisplayCurrency.codeKey)` so a
//   currency change redraws it.

// MARK: - Colour specs

/// One colour role: light / dark, optional Increase Contrast variants and
/// alphas. Asset-free; resolved per trait collection by `Color.ww(_:)`.
struct WWColorSpec: Sendable {
    let light: UInt32
    let dark: UInt32
    var lightHC: UInt32?
    var darkHC: UInt32?
    var lightAlpha: CGFloat
    var darkAlpha: CGFloat
    var lightHCAlpha: CGFloat?
    var darkHCAlpha: CGFloat?

    init(
        light: UInt32,
        dark: UInt32,
        lightHC: UInt32? = nil,
        darkHC: UInt32? = nil,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1,
        lightHCAlpha: CGFloat? = nil,
        darkHCAlpha: CGFloat? = nil
    ) {
        self.light = light
        self.dark = dark
        self.lightHC = lightHC
        self.darkHC = darkHC
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
        self.lightHCAlpha = lightHCAlpha
        self.darkHCAlpha = darkHCAlpha
    }

    /// The hex and alpha for one appearance.
    func resolved(dark isDark: Bool, highContrast: Bool) -> (hex: UInt32, alpha: CGFloat) {
        if isDark {
            let hex: UInt32 = highContrast ? (darkHC ?? dark) : dark
            let alpha: CGFloat = highContrast ? (darkHCAlpha ?? darkAlpha) : darkAlpha
            return (hex, alpha)
        }
        let hex: UInt32 = highContrast ? (lightHC ?? light) : light
        let alpha: CGFloat = highContrast ? (lightHCAlpha ?? lightAlpha) : lightAlpha
        return (hex, alpha)
    }
}

extension Color {
    /// A token colour that follows light/dark and Increase Contrast.
    static func ww(_ spec: WWColorSpec) -> Color {
        Color(uiColor: UIColor.ww(spec))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The same token for UIKit (camera, crop editor).
    static func ww(_ spec: WWColorSpec) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            let value = spec.resolved(dark: isDark, highContrast: isHighContrast)
            return UIColor(hex: value.hex).withAlphaComponent(value.alpha)
        }
    }
}

/// Every colour role, one `WWColorSpec` each. All hex values live here.
/// Defaults are Lapis (02 §4.1, 05 §1.1); `evolvedGraphite` overrides only
/// the accent and brand roles (04 §8.2).
struct WWPalette: Sendable {
    var background = WWColorSpec(light: 0xF2F2F7, dark: 0x000000)
    var surface = WWColorSpec(light: 0xFFFFFF, dark: 0x1C1C1E)
    var elevated = WWColorSpec(light: 0xFFFFFF, dark: 0x2C2C2E)
    var photoBackdrop = WWColorSpec(light: 0x141416, dark: 0x141416)
    var scrim = WWColorSpec(light: 0x000000, dark: 0x000000,
                            lightAlpha: 0.45, darkAlpha: 0.45, lightHCAlpha: 0.60, darkHCAlpha: 0.60)
    var text = WWColorSpec(light: 0x0B0B0C, dark: 0xF5F5F7, lightHC: 0x000000, darkHC: 0xFFFFFF)
    var secondaryText = WWColorSpec(light: 0x55555D, dark: 0xA6A6AD, lightHC: 0x45454C, darkHC: 0xC4C4CA)
    var tertiaryText = WWColorSpec(light: 0x6C6C74, dark: 0x94949B, lightHC: 0x55555D, darkHC: 0xABABB2)
    var inverseText = WWColorSpec(light: 0xFFFFFF, dark: 0x0B0B0C)
    var separator = WWColorSpec(light: 0xD8D8DE, dark: 0x38383C, lightHC: 0xB8B8C0, darkHC: 0x5A5A60)
    var fill = WWColorSpec(light: 0x000000, dark: 0xFFFFFF,
                           lightAlpha: 0.06, darkAlpha: 0.10, lightHCAlpha: 0.10, darkHCAlpha: 0.16)
    var track = WWColorSpec(light: 0x000000, dark: 0xFFFFFF,
                            lightAlpha: 0.16, darkAlpha: 0.22, lightHCAlpha: 0.28, darkHCAlpha: 0.34)
    var accent = WWColorSpec(light: 0x3341D1, dark: 0x8E9AFF, lightHC: 0x2532B0, darkHC: 0xA9B2FF)
    var accentFill = WWColorSpec(light: 0x3341D1, dark: 0x4A58E6, lightHC: 0x2532B0, darkHC: 0x3B4AD6)
    var onAccent = WWColorSpec(light: 0xFFFFFF, dark: 0xFFFFFF)
    var accentWash = WWColorSpec(light: 0xEBECFA, dark: 0x2E3042)
    var positive = WWColorSpec(light: 0x16774A, dark: 0x4CCB8A, lightHC: 0x0F5E3A, darkHC: 0x6FE0A6)
    var caution = WWColorSpec(light: 0x8A5300, dark: 0xF2A93B, lightHC: 0x6E4200, darkHC: 0xFFC061)
    var danger = WWColorSpec(light: 0xC4231A, dark: 0xFF6B61, lightHC: 0xA51B13, darkHC: 0xFF8A82)
    var positiveWash = WWColorSpec(light: 0xE3EFE9, dark: 0x24382F)
    var cautionWash = WWColorSpec(light: 0xF1EAE0, dark: 0x3E3323)
    var dangerWash = WWColorSpec(light: 0xF8E5E4, dark: 0x402929)
    var neutralWash = WWColorSpec(light: 0xF0F0F0, dark: 0x323234)
    var soldFill = WWColorSpec(light: 0x16774A, dark: 0x3DBE7E, lightHC: 0x0F5E3A, darkHC: 0x6FE0A6)
    var onSoldFill = WWColorSpec(light: 0xFFFFFF, dark: 0x04170B)
    var brandInk = WWColorSpec(light: 0x1B2585, dark: 0x1B2585)
    var brandMist = WWColorSpec(light: 0xE9EBFB, dark: 0xE9EBFB)

    /// Recommended direction (02): neutral gallery wall, one pigment.
    static let lapis = WWPalette()

    /// Alternative (02 §4.5): black-and-white accent, same evidence colours.
    static let evolvedGraphite: WWPalette = {
        var palette = WWPalette()
        palette.accent = WWColorSpec(light: 0x0B0B0C, dark: 0xF5F5F7, lightHC: 0x000000, darkHC: 0xFFFFFF)
        palette.accentFill = WWColorSpec(light: 0x0B0B0C, dark: 0xF5F5F7, lightHC: 0x000000, darkHC: 0xFFFFFF)
        palette.onAccent = WWColorSpec(light: 0xFFFFFF, dark: 0x0B0B0C)
        palette.accentWash = palette.neutralWash
        palette.brandInk = WWColorSpec(light: 0x1C1C1E, dark: 0x1C1C1E)
        palette.brandMist = WWColorSpec(light: 0xF2F2F7, dark: 0xF2F2F7)
        return palette
    }()
}

// MARK: - Tokens

enum WW {
    /// The ONLY line that changes the brand direction: `.lapis` or `.evolvedGraphite`.
    static let palette: WWPalette = .lapis

    // Colour roles (05 §1.1). Components never test which palette is active.
    static let background = Color.ww(palette.background)
    static let surface = Color.ww(palette.surface)
    static let elevated = Color.ww(palette.elevated)
    /// Behind every user photo, in both modes.
    static let photoBackdrop = Color.ww(palette.photoBackdrop)
    /// Circles behind on-photo glyphs, saved badge, selection circle.
    static let scrim = Color.ww(palette.scrim)
    /// Primary text and all money.
    static let text = Color.ww(palette.text)
    static let secondaryText = Color.ww(palette.secondaryText)
    /// Chevrons, footer, AI-chip stroke. Never anything about money.
    static let tertiaryText = Color.ww(palette.tertiaryText)
    /// Glyphs and numerals on a `text`-coloured fill.
    static let inverseText = Color.ww(palette.inverseText)
    static let separator = Color.ww(palette.separator)
    static let fill = Color.ww(palette.fill)
    static let track = Color.ww(palette.track)
    /// Links, tertiary buttons, the mark, selection strokes and checks.
    static let accent = Color.ww(palette.accent)
    /// The one primary button per screen.
    static let accentFill = Color.ww(palette.accentFill)
    static let onAccent = Color.ww(palette.onAccent)
    static let accentWash = Color.ww(palette.accentWash)
    /// Price-history "up" only. Never the value itself.
    static let positive = Color.ww(palette.positive)
    /// Wide range, possible/unsure match, ASKING, Rough guide.
    static let caution = Color.ww(palette.caution)
    /// Destructive actions and failures. Never uncertainty.
    static let danger = Color.ww(palette.danger)
    static let positiveWash = Color.ww(palette.positiveWash)
    static let cautionWash = Color.ww(palette.cautionWash)
    static let dangerWash = Color.ww(palette.dangerWash)
    static let neutralWash = Color.ww(palette.neutralWash)
    static let soldFill = Color.ww(palette.soldFill)
    static let onSoldFill = Color.ww(palette.onSoldFill)
    /// Onboarding Welcome and marketing only.
    static let brandInk = Color.ww(palette.brandInk)
    static let brandMist = Color.ww(palette.brandMist)

    // Deprecated aliases (04 §8.8). They keep old call sites compiling.

    @available(*, deprecated, message: "Use WW.inverseText on text-coloured fills, or WW.onAccent on accentFill.")
    static let onPrimary = Color.ww(palette.inverseText)

    @available(*, deprecated, message: "Use WW.caution.")
    static let warning = Color.ww(palette.caution)

    @available(*, deprecated, message: "Use WW.Radius.control.")
    static let radiusControl: CGFloat = 10

    @available(*, deprecated, message: "Use WW.Radius.tile.")
    static let radiusTile: CGFloat = 16

    @available(*, deprecated, message: "Use WW.Radius.card.")
    static let radiusCard: CGFloat = 20

    @available(*, deprecated, message: "Use WW.Radius.photo.")
    static let radiusPhoto: CGFloat = 24

    /// Screen side inset (20). At accessibility sizes use `WW.margin(for:)` (16).
    static let margin: CGFloat = 20

    // MARK: Money

    /// "$38", "€1,240", "£4.50" — whole units from 10 up. USD amounts (every
    /// price the server sends) are shown in the user's display currency
    /// (Settings → Currency); any other currency is shown as it is.
    static func money(_ value: Double, code: String = "USD") -> String {
        var amount = value
        var currency = code
        if code.uppercased() == "USD" {
            let converted = DisplayCurrency.fromUSD(value)
            amount = converted.amount
            currency = converted.code
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = amount >= 10 ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(Int(amount))"
    }

    /// "$38 – $52", or a single price when both ends match.
    static func range(_ low: Double, _ high: Double) -> String {
        let lo = money(low), hi = money(high)
        return lo == hi ? lo : "\(lo) – \(hi)"
    }

    /// A USD threshold in the display currency, rounded UP to 1, 2 or 5 × 10ⁿ
    /// so a sentence like "sell for under €10" stays true and never reads
    /// "€8.92" (04 §6.4C). $10 → "€10", "£10", "¥2,000".
    static func niceCeilingMoney(usd: Double) -> String {
        let converted = DisplayCurrency.fromUSD(usd)
        let nice = niceCeiling(converted.amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = converted.code
        formatter.maximumFractionDigits = nice >= 1 ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: nice)) ?? "\(converted.code) \(Int(nice))"
    }

    /// The smallest 1, 2 or 5 × 10ⁿ that is ≥ `value` (0 for non-positive input).
    static func niceCeiling(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        let magnitude: Double = pow(10.0, floor(log10(value)))
        let steps: [Double] = [1, 2, 5, 10]
        for step in steps {
            let candidate = step * magnitude
            if candidate >= value * (1 - 1e-9) { return candidate }
        }
        return 10 * magnitude
    }

    /// The Coins glyph follows the display currency (05 §2.43):
    /// `dollarsign.circle` / `eurosign.circle` / `sterlingsign.circle` / `yensign.circle`.
    static func coinSymbol(filled: Bool = false) -> String {
        let base: String
        switch DisplayCurrency.code {
        case "EUR": base = "eurosign"
        case "GBP": base = "sterlingsign"
        case "JPY": base = "yensign"
        default: base = "dollarsign"
        }
        return base + (filled ? ".circle.fill" : ".circle")
    }

    // MARK: Dialogs

    /// The role for the Cancel / Go Back / Keep … button of every
    /// `confirmationDialog` (one rule for the app). iOS 26 shows a
    /// confirmation dialog as a popover anchored to its button, and a popover
    /// drops `.cancel`-role buttons (tapping outside cancels); with no role
    /// the button stays visible. iOS 17–25 show an action sheet, where
    /// `.cancel` is right. Alerts keep `.cancel`.
    static var dialogCancelRole: ButtonRole? {
        let iOS26 = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(iOS26) ? nil : .cancel
    }
}

// MARK: - Metrics (04 §8.4, 05 §1.5–§1.8)

extension WW {
    /// Spacing. Every binding is annotated: `static let a: CGFloat = 4, b = 8`
    /// would make `b` an Int.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
        /// Screen side inset (16 at AX sizes: `WW.margin(for:)`).
        static let margin: CGFloat = 20
        /// `.wwCard()` default (16 at AX sizes: `WW.cardPadding(for:)`).
        static let cardPadding: CGFloat = 20
        static let tilePadding: CGFloat = 16
        static let blockGap: CGFloat = 16
        static let sectionGap: CGFloat = 32
        /// Top inset of `.page` empty states.
        static let emptyStateTop: CGFloat = 48
    }

    /// Corner radii. Buttons, the plan pill and segmented controls are Capsules.
    enum Radius {
        static let chip: CGFloat = 6
        static let control: CGFloat = 10
        static let tile: CGFloat = 16
        static let card: CGFloat = 20
        static let photo: CGFloat = 24
        static let sheet: CGFloat = 28
        /// Bars ≤ 6 pt tall (meter segments, range track): fully rounded.
        static let bar: CGFloat = 3
    }

    /// Control, hit-area and plate sizes.
    enum Size {
        static let minTarget: CGFloat = 44
        static let buttonLarge: CGFloat = 52
        static let buttonCompact: CGFloat = 44
        static let rowMin: CGFloat = 44
        static let rowTall: CGFloat = 56
        static let evidenceRow: CGFloat = 62
        static let thumb: CGFloat = 56
        static let thumbAX: CGFloat = 72
        static let chipMin: CGFloat = 22
        static let fieldMin: CGFloat = 48
        static let infoIcon: CGFloat = 34
        static let plateS: CGFloat = 52
        static let plateM: CGFloat = 64
        static let plateL: CGFloat = 72
        static let onPhoto: CGFloat = 32
        static let selectionCircle: CGFloat = 24
        static let stepNode: CGFloat = 24
        static let stepNodeTimeline: CGFloat = 28
        static let toastMaxWidth: CGFloat = 500
        /// Fixed graphics scale with Dynamic Type up to about AX1.
        static let graphicScaleCap: CGFloat = 1.6
    }

    /// Stroke widths and dash patterns.
    enum Stroke {
        /// Increase Contrast stroke on cards, tiles, secondary buttons.
        static let hc: CGFloat = 1
        /// ASKING / AI ESTIMATE chips.
        static let outline: CGFloat = 1
        static let outlineHC: CGFloat = 1.5
        /// "Add back" slot, "New folder" row.
        static let dashedSlot: CGFloat = 1.5
        /// Selected plan card, selected intent row.
        static let selected: CGFloat = 2
        /// Focused / error text field.
        static let fieldFocused: CGFloat = 1.5
        /// Selected item tile image (inner).
        static let tileSelected: CGFloat = 3
        static let dashSlot: [CGFloat] = [6, 5]
        static let dashAI: [CGFloat] = [3, 2]

        /// One physical pixel.
        static func hairline(displayScale: CGFloat) -> CGFloat {
            1 / max(displayScale, 1)
        }
    }

    /// Screen side inset: 20, or 16 at accessibility sizes (05 §1.5).
    static func margin(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 16 : Space.margin
    }

    /// Card padding: 20, or 16 at accessibility sizes (05 D14).
    static func cardPadding(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 16 : Space.cardPadding
    }

    /// Shared chart values (05 §2.42). Charts are neutral and shape-coded:
    /// never `foregroundStyle(by:)` with the default scale.
    enum Chart {
        static let plotHeight: CGFloat = 180
        static let plotHeightAX: CGFloat = 220
        static let emptyMinHeight: CGFloat = 120
        static let lineWidth: CGFloat = 2
        /// Source 1 solid, source 2 [5, 3], source 3 [1, 3] (round caps).
        static let seriesDashes: [[CGFloat]] = [[], [5, 3], [1, 3]]
        static let medianRuleDash: [CGFloat] = [4, 4]
        static let saleSymbolSize: CGFloat = 30
        static let saleDotOpacity: Double = 0.55
        static let axisDesiredCount: Int = 4
        static let maxSeries: Int = 3
    }
}

// MARK: - Motion (04 §8.6, 06 §2.1)
//
// Money never moves: no count-up, no `numericText` on amounts. Use
// `numericText` only for counts (items, selected, scans).

extension WW {
    enum Motion {
        enum Token: CaseIterable {
            /// State changes, selection, layout reflow.
            case standard
            /// Press feedback.
            case quick
            /// Flow steps, every change of a money value.
            case crossfade
            /// Value card after identity: opacity + 8 pt rise, 0.12 s delay.
            case reveal
            /// Arrivals: chips, tiles, toasts, failure card.
            case settle
            /// `RangeBar` span spreading from the best tick.
            case spread
            /// Scanning pupil (one phase).
            case breathe
            /// The Tag's pupil opening (Welcome, "You're Pro").
            case open
            /// Great-find Tag swing (approximation; use the keyframes below).
            case swing
            case toastIn
            case toastOut
        }

        /// Per-element delay in a group of arrivals, at most `staggerCap` elements.
        static let stagger: Double = 0.05
        static let staggerCap: Int = 6
        static let revealDelay: Double = 0.12
        static let revealOffset: CGFloat = 8
        static let toastOffset: CGFloat = 12
        /// Toast hold times (06 M21).
        static let toastHold: Double = 4
        static let toastHoldWithAction: Double = 6
        static let toastHoldVoiceOver: Double = 10
        /// Scanning pupil phases for `PhaseAnimator` (0.8 s each, 1.6 s cycle).
        static let breathePhases: [CGFloat] = [1.0, 0.6]
        static let breathePhaseDuration: Double = 0.8
        /// Great-find swing keyframes (degrees / seconds), about the eyelet.
        static let swingAngles: [Double] = [6, -4, 2, 0]
        static let swingDurations: [Double] = [0.12, 0.18, 0.15, 0.15]
        static let swingAnchor = UnitPoint(x: 0.5, y: 0.3125)

        /// The curve for a token. Under Reduce Motion: an opacity-safe curve,
        /// or nil for tokens that are off (spread, breathe, swing).
        static func animation(_ token: Token, reduceMotion: Bool) -> Animation? {
            if reduceMotion {
                return reducedAnimation(token)
            }
            switch token {
            case .standard:
                return Animation.spring(response: 0.35, dampingFraction: 0.9)
            case .quick:
                return Animation.easeOut(duration: 0.18)
            case .crossfade:
                return Animation.easeInOut(duration: 0.25)
            case .reveal:
                return Animation.easeOut(duration: 0.25).delay(revealDelay)
            case .settle, .toastIn:
                return Animation.spring(response: 0.4, dampingFraction: 0.8)
            case .spread:
                return Animation.easeOut(duration: 0.4)
            case .breathe:
                return Animation.easeInOut(duration: breathePhaseDuration)
            case .open:
                return Animation.spring(response: 0.45, dampingFraction: 0.72)
            case .swing:
                return Animation.easeInOut(duration: 0.6)
            case .toastOut:
                return Animation.easeIn(duration: 0.2)
            }
        }

        private static func reducedAnimation(_ token: Token) -> Animation? {
            switch token {
            case .standard, .settle, .toastIn, .toastOut:
                return Animation.easeInOut(duration: 0.2)
            case .quick:
                return Animation.easeOut(duration: 0.18)
            case .crossfade:
                return Animation.easeInOut(duration: 0.25)
            case .reveal, .open:
                return Animation.easeOut(duration: 0.2)
            case .spread, .breathe, .swing:
                return nil
            }
        }

        /// Delay for the n-th element of a group of arrivals (0 under Reduce Motion).
        static func staggerDelay(index: Int, reduceMotion: Bool) -> Double {
            guard !reduceMotion else { return 0 }
            let capped = min(max(index, 0), staggerCap - 1)
            return Double(capped) * stagger
        }
    }
}

private struct WWAnimationModifier<Value: Equatable>: ViewModifier {
    let token: WW.Motion.Token
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(WW.Motion.animation(token, reduceMotion: reduceMotion), value: value)
    }
}

private struct WWRevealModifier: ViewModifier {
    let token: WW.Motion.Token
    let delay: Double
    let isStatic: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .opacity(isStatic || isShown ? 1 : 0)
            .offset(y: offsetY)
            .onAppear(perform: reveal)
    }

    private var offsetY: CGFloat {
        if isStatic || reduceMotion || isShown { return 0 }
        return WW.Motion.revealOffset
    }

    private func reveal() {
        guard !isStatic, !isShown else { return }
        let base: Animation = WW.Motion.animation(token, reduceMotion: reduceMotion) ?? Animation.easeOut(duration: 0.2)
        let curve: Animation = (reduceMotion || delay <= 0) ? base : base.delay(delay)
        withAnimation(curve) {
            isShown = true
        }
    }
}

extension View {
    /// An implicit animation scoped to `value`, with the Reduce Motion fallback.
    func wwAnimation<V: Equatable>(_ token: WW.Motion.Token, value: V) -> some View {
        modifier(WWAnimationModifier(token: token, value: value))
    }

    /// Entrance: opacity 0→1 (+ 8 pt rise unless Reduce Motion) on appear.
    /// `isStatic` (VoiceOver running, stored result) shows it at once.
    /// Layout is reserved from the first frame, so nothing reflows.
    func wwReveal(_ token: WW.Motion.Token = .reveal, delay: Double = 0, isStatic: Bool) -> some View {
        modifier(WWRevealModifier(token: token, delay: delay, isStatic: isStatic))
    }

    /// The only allowed way to use `.sensoryFeedback`: it honours Settings › Haptics.
    /// (The 0.3 s spacing rule applies only to `Haptics`.)
    func wwSensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        sensoryFeedback(trigger: trigger) { _, _ in
            Haptics.isEnabledSetting ? feedback : nil
        }
    }
}

// MARK: - Typography (04 §8.3, 05 §1.4)

/// A type role. Apply with `.wwFont(_:weight:)`. Sizes scale with Dynamic
/// Type relative to the nearest text style, each role has its own cap.
enum WWTextRole: CaseIterable {
    case valueDisplay, valueRough, total, priceLarge
    case brandDisplay, brandTitle, wordmark
    case pageTitle, itemTitle, sectionTitle
    case headline, body, callout, subhead, footnote, caption
    case meta, chip
    case price, priceSmall, priceCompact
    case identifier
    case button, buttonSmall

    var spec: WWTextSpec {
        switch self {
        case .valueDisplay:
            return WWTextSpec(size: 40, weight: .bold, tabular: true, tracking: -0.6, maxSize: .accessibility2)
        case .valueRough:
            return WWTextSpec(size: 28, weight: .semibold, tabular: true, tracking: -0.3, maxSize: .accessibility2)
        case .total:
            return WWTextSpec(size: 34, weight: .bold, tabular: true, tracking: -0.6, maxSize: .accessibility2)
        case .priceLarge:
            return WWTextSpec(size: 24, weight: .bold, tabular: true, tracking: -0.4)
        case .brandDisplay:
            return WWTextSpec(size: 30, weight: .semibold, design: .serif, tracking: -0.3, lineSpacing: 2, maxSize: .accessibility1)
        case .brandTitle:
            return WWTextSpec(size: 26, weight: .semibold, design: .serif, tracking: -0.2, lineSpacing: 2, maxSize: .accessibility1)
        case .wordmark:
            return WWTextSpec(size: 19, weight: .semibold, design: .serif, tracking: -0.2, maxSize: .xxLarge)
        case .pageTitle:
            return WWTextSpec(size: 28, weight: .bold, tracking: -0.4, lineSpacing: 1)
        case .itemTitle:
            return WWTextSpec(size: 22, weight: .semibold, tracking: -0.2, lineSpacing: 2)
        case .sectionTitle:
            return WWTextSpec(size: 20, weight: .semibold, lineSpacing: 1)
        case .headline:
            return WWTextSpec(size: 17, weight: .semibold, lineSpacing: 2)
        case .body:
            return WWTextSpec(size: 17, lineSpacing: 2)
        case .callout:
            return WWTextSpec(size: 16, lineSpacing: 2)
        case .subhead:
            return WWTextSpec(size: 15, lineSpacing: 2)
        case .footnote:
            return WWTextSpec(size: 13, lineSpacing: 2)
        case .caption:
            return WWTextSpec(size: 12, lineSpacing: 2)
        case .meta:
            return WWTextSpec(size: 12, weight: .semibold, tracking: 0.6, uppercase: true, maxSize: .accessibility2)
        case .chip:
            return WWTextSpec(size: 11, weight: .semibold, tracking: 0.4, uppercase: true, maxSize: .accessibility2)
        case .price:
            return WWTextSpec(size: 17, weight: .semibold, tabular: true)
        case .priceSmall:
            return WWTextSpec(size: 15, weight: .semibold, tabular: true)
        case .priceCompact:
            return WWTextSpec(size: 13, weight: .semibold, tabular: true)
        case .identifier:
            return WWTextSpec(size: 15, design: .monospaced, lineSpacing: 2)
        case .button:
            return WWTextSpec(size: 17, weight: .semibold, lineSpacing: 2)
        case .buttonSmall:
            return WWTextSpec(size: 15, weight: .semibold, lineSpacing: 2)
        }
    }

    /// One step smaller, for `ValueRangeText`'s last fallback (05 §2.8).
    var stepDown: WWTextRole {
        switch self {
        case .valueDisplay: return .valueRough
        case .valueRough: return .priceLarge
        case .total: return .priceLarge
        case .priceLarge: return .price
        case .price: return .priceSmall
        case .priceSmall: return .priceCompact
        case .priceCompact: return .caption
        default: return self
        }
    }
}

/// The values behind a role (05 §1.4). Build one directly only for sizes no
/// role covers (the wordmark at a custom size, a 0.9 money fallback).
struct WWTextSpec {
    var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design
    /// Tabular digits (`monospacedDigit`).
    var tabular: Bool
    var tracking: CGFloat
    /// Extra leading for multi-line text, at the default size.
    var lineSpacing: CGFloat
    var uppercase: Bool
    /// Dynamic Type cap for this role.
    var maxSize: DynamicTypeSize

    init(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        tabular: Bool = false,
        tracking: CGFloat = 0,
        lineSpacing: CGFloat = 0,
        uppercase: Bool = false,
        maxSize: DynamicTypeSize = .accessibility3
    ) {
        self.size = size
        self.weight = weight
        self.design = design
        self.tabular = tabular
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.uppercase = uppercase
        self.maxSize = maxSize
    }

    /// The same spec at `factor` × size (used for the 0.9 money fallback).
    func scaled(_ factor: CGFloat) -> WWTextSpec {
        var copy = self
        copy.size = size * factor
        copy.lineSpacing = lineSpacing * factor
        return copy
    }
}

/// A system font at a design size that scales with the user's text size
/// (Settings › Display & Brightness › Text Size, and the accessibility sizes),
/// relative to the nearest Apple text style. At the default size it renders
/// exactly the design size, so layouts look as designed; at larger sizes it
/// grows the way Apple's own text styles do.
struct WWScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let baseSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let monospacedDigit: Bool
    private let lineSpacing: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, monospacedDigit: Bool, lineSpacing: CGFloat = 0) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(for: size))
        self.baseSize = size
        self.weight = weight
        self.design = design
        self.monospacedDigit = monospacedDigit
        self.lineSpacing = lineSpacing
    }

    private var font: Font {
        let base = Font.system(size: size, weight: weight, design: design)
        return monospacedDigit ? base.monospacedDigit() : base
    }

    private var scaledLineSpacing: CGFloat {
        lineSpacing * size / max(baseSize, 1)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        // Only roles set leading, so a legacy `.wwFont(15).lineSpacing(2)` keeps its own.
        if lineSpacing > 0 {
            content.font(font).lineSpacing(scaledLineSpacing)
        } else {
            content.font(font)
        }
    }

    /// Apple's text-style sizes at the default setting: caption2 11, caption 12,
    /// footnote 13, subheadline 15, callout 16, body 17, title3 20, title2 22,
    /// title 28, largeTitle 34.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<16: return .subheadline
        case ..<17: return .callout
        case ..<20: return .body
        case ..<22: return .title3
        case ..<28: return .title2
        case ..<34: return .title
        default: return .largeTitle
        }
    }
}

/// Tracking and case, applied only when the role sets them, so host
/// modifiers outside still work for roles that don't.
private struct WWTextStyleModifier: ViewModifier {
    let tracking: CGFloat
    let uppercase: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if uppercase && tracking != 0 {
            content.tracking(tracking).textCase(.uppercase)
        } else if uppercase {
            content.textCase(.uppercase)
        } else if tracking != 0 {
            content.tracking(tracking)
        } else {
            content
        }
    }
}

extension View {
    /// Apply a type role: size, weight, design, tabular digits, tracking,
    /// case, leading and the role's Dynamic Type cap. `weight` is the one
    /// sanctioned override (e.g. `.wwFont(.subhead, weight: .semibold)` for
    /// tile titles); never use it on serif or money roles.
    func wwFont(_ role: WWTextRole, weight: Font.Weight? = nil) -> some View {
        var spec = role.spec
        if let weight { spec.weight = weight }
        return wwFont(spec: spec)
    }

    /// Apply an explicit spec (see `WWTextSpec`).
    func wwFont(spec: WWTextSpec) -> some View {
        modifier(WWScaledFont(size: spec.size, weight: spec.weight, design: spec.design,
                              monospacedDigit: spec.tabular, lineSpacing: spec.lineSpacing))
            .modifier(WWTextStyleModifier(tracking: spec.tracking, uppercase: spec.uppercase))
            // Outside the font modifier, so its @ScaledMetric sees the cap.
            .dynamicTypeSize(...spec.maxSize)
    }

    /// `.font(.system(size:weight:))` that follows Dynamic Type (pre-redesign API).
    @available(*, deprecated, message: "Use .wwFont(_ role:, weight:) with a WWTextRole.")
    func wwFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default, monospacedDigit: Bool = false) -> some View {
        modifier(WWScaledFont(size: size, weight: weight, design: design, monospacedDigit: monospacedDigit))
    }
}

// MARK: - Environment

/// Where a card sits: on a screen canvas, or inside a sheet (05 D16).
enum WWSurfaceLevel {
    case base
    case elevated
}

private struct WWSurfaceLevelKey: EnvironmentKey {
    static let defaultValue: WWSurfaceLevel = .base
}

private struct WWPressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// `.elevated` inside `wwSheetBackground()`: `.surface` cards resolve to
    /// `WW.elevated` (dark #2C2C2E; light stays #FFFFFF).
    var wwSurfaceLevel: WWSurfaceLevel {
        get { self[WWSurfaceLevelKey.self] }
        set { self[WWSurfaceLevelKey.self] = newValue }
    }

    /// Set by `WWPressableStyle` / `WWOnPhotoButtonStyle` while the button is
    /// pressed, so labels (on-photo, icon) can show their pressed look.
    var wwIsPressed: Bool {
        get { self[WWPressedKey.self] }
        set { self[WWPressedKey.self] = newValue }
    }
}

private struct WWSheetBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.wwSurfaceLevel, .elevated)
            .background(colorScheme == .dark ? WW.surface : WW.background)
    }
}

extension View {
    /// Sheet canvas: `background` (light) / `surface` (dark), and cards inside
    /// become `elevated` in dark, matching iOS grouped sheets (05 D16).
    /// Apply to the sheet's root scroll view.
    func wwSheetBackground() -> some View {
        modifier(WWSheetBackgroundModifier())
    }
}

// MARK: - Buttons (04 §7, 05 §2.1–§2.3, §5.5)

/// Primary / secondary / destructive button size.
enum WWControlSize {
    /// Full width, min height 52.
    case large
    /// Hugs its label, min height 44.
    case compact
}

/// The shared capsule body of primary, secondary and destructive buttons.
private struct WWCapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: WWControlSize
    let isLoading: Bool
    let fill: Color
    let labelColor: Color
    let pressedOpacity: Double
    let contrastStroke: Color
    let pressedScale: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        labelLayer
            .padding(.horizontal, size == .large ? 24 : 20)
            .padding(.vertical, size == .large ? 14 : 10)
            .frame(maxWidth: maxWidth)
            .frame(minHeight: minHeight)
            .background(fill, in: Capsule())
            .overlay { strokeLayer }
            .contentShape(Capsule())
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(WW.Motion.animation(.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
            .allowsHitTesting(!isLoading)
            .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }

    private var labelLayer: some View {
        configuration.label
            .wwFont(.button)
            .foregroundStyle(labelColor)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView().tint(labelColor)
                }
            }
    }

    @ViewBuilder
    private var strokeLayer: some View {
        if contrast == .increased {
            Capsule().strokeBorder(contrastStroke, lineWidth: WW.Stroke.hc)
        }
    }

    private var maxWidth: CGFloat? {
        size == .large ? CGFloat.infinity : nil
    }

    private var minHeight: CGFloat {
        size == .large ? WW.Size.buttonLarge : WW.Size.buttonCompact
    }

    private var scale: CGFloat {
        (configuration.isPressed && !reduceMotion) ? pressedScale : 1
    }

    private var opacity: Double {
        guard isEnabled else { return 0.35 }
        return configuration.isPressed ? pressedOpacity : 1
    }
}

/// The one Lapis button per screen: `accentFill` capsule, `onAccent` label.
/// Pressed 0.85 (+ 0.98 scale), disabled 0.35, loading spinner. Increase
/// Contrast adds a 1 pt `accent` stroke (05 D13).
struct WWPrimaryButtonStyle: ButtonStyle {
    var size: WWControlSize
    var isLoading: Bool

    init(size: WWControlSize = .large, isLoading: Bool = false) {
        self.size = size
        self.isLoading = isLoading
    }

    /// Pre-redesign API: < 48 pt maps to `.compact`, otherwise `.large`.
    @available(*, deprecated, message: "Use WWPrimaryButtonStyle(size:isLoading:).")
    init(height: CGFloat) {
        self.size = height < 48 ? .compact : .large
        self.isLoading = false
    }

    func makeBody(configuration: Configuration) -> some View {
        WWCapsuleButtonBody(
            configuration: configuration,
            size: size,
            isLoading: isLoading,
            fill: WW.accentFill,
            labelColor: WW.onAccent,
            pressedOpacity: 0.85,
            contrastStroke: WW.accent,
            pressedScale: 0.98
        )
    }
}

/// The default second choice: `fill` capsule, `text` label. Consent uses two.
struct WWSecondaryButtonStyle: ButtonStyle {
    var size: WWControlSize
    var isLoading: Bool

    init(size: WWControlSize = .large, isLoading: Bool = false) {
        self.size = size
        self.isLoading = isLoading
    }

    /// Pre-redesign API: < 48 pt maps to `.compact`, otherwise `.large`.
    @available(*, deprecated, message: "Use WWSecondaryButtonStyle(size:isLoading:).")
    init(height: CGFloat) {
        self.size = height < 48 ? .compact : .large
        self.isLoading = false
    }

    func makeBody(configuration: Configuration) -> some View {
        WWCapsuleButtonBody(
            configuration: configuration,
            size: size,
            isLoading: isLoading,
            fill: WW.fill,
            labelColor: WW.text,
            pressedOpacity: 0.70,
            contrastStroke: WW.separator,
            pressedScale: 1
        )
    }
}

/// Destructive action as a button: `danger` label on a `dangerWash` capsule.
struct WWDestructiveButtonStyle: ButtonStyle {
    var size: WWControlSize

    init(size: WWControlSize = .large) {
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        WWCapsuleButtonBody(
            configuration: configuration,
            size: size,
            isLoading: false,
            fill: WW.dangerWash,
            labelColor: WW.danger,
            pressedOpacity: 0.70,
            contrastStroke: WW.danger,
            pressedScale: 1
        )
    }
}

/// Text-only button: links, "Not now", "Restore purchases", "See All".
/// Leading-aligned, min height 44, pressed 0.5. No underline.
struct WWTertiaryButtonStyle: ButtonStyle {
    enum Tone {
        /// `accent` (links, tappable content).
        case accent
        /// `text` (neutral rows, "Restore purchases").
        case neutral
    }

    enum TextSize {
        /// `.button` (17 Semibold).
        case regular
        /// `.buttonSmall` (15 Semibold): "See All", "Not the right item?", "Turn on".
        case small
    }

    var tone: Tone
    var size: TextSize

    init(tone: Tone = .accent, size: TextSize = .regular) {
        self.tone = tone
        self.size = size
    }

    /// Shorthand: `WWTertiaryButtonStyle(.accent, .small)`.
    init(_ tone: Tone, _ size: TextSize = .regular) {
        self.tone = tone
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        WWTertiaryButtonBody(configuration: configuration, tone: tone, size: size)
    }
}

private struct WWTertiaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tone: WWTertiaryButtonStyle.Tone
    let size: WWTertiaryButtonStyle.TextSize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .wwFont(size == .small ? WWTextRole.buttonSmall : WWTextRole.button)
            .foregroundStyle(tone == .accent ? WW.accent : WW.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: WW.Size.minTarget, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.35)
    }
}

/// Tiles, plan cards, folder rows, snapshot card, category/kind tiles, icon
/// buttons: the label dims to 0.70 while pressed (05 §2.45).
struct WWPressableStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        WWPressableBody(configuration: configuration)
    }
}

private struct WWPressableBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .environment(\.wwIsPressed, configuration.isPressed)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .animation(WW.Motion.animation(.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// For `WWOnPhotoButtonLabel`: no dimming; the label darkens its scrim instead.
struct WWOnPhotoButtonStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.wwIsPressed, configuration.isPressed)
    }
}

extension ButtonStyle where Self == WWPrimaryButtonStyle {
    static var wwPrimary: WWPrimaryButtonStyle { WWPrimaryButtonStyle() }
    static func wwPrimary(size: WWControlSize, isLoading: Bool = false) -> WWPrimaryButtonStyle {
        WWPrimaryButtonStyle(size: size, isLoading: isLoading)
    }
}

extension ButtonStyle where Self == WWSecondaryButtonStyle {
    static var wwSecondary: WWSecondaryButtonStyle { WWSecondaryButtonStyle() }
    static func wwSecondary(size: WWControlSize, isLoading: Bool = false) -> WWSecondaryButtonStyle {
        WWSecondaryButtonStyle(size: size, isLoading: isLoading)
    }
}

extension ButtonStyle where Self == WWTertiaryButtonStyle {
    static var wwTertiary: WWTertiaryButtonStyle { WWTertiaryButtonStyle() }
    static func wwTertiary(tone: WWTertiaryButtonStyle.Tone, size: WWTertiaryButtonStyle.TextSize = .regular) -> WWTertiaryButtonStyle {
        WWTertiaryButtonStyle(tone: tone, size: size)
    }
}

extension ButtonStyle where Self == WWDestructiveButtonStyle {
    static var wwDestructive: WWDestructiveButtonStyle { WWDestructiveButtonStyle() }
}

extension ButtonStyle where Self == WWPressableStyle {
    static var wwPressable: WWPressableStyle { WWPressableStyle() }
}

/// Text buttons in toolbars and bottom bars (plan pill, Select, Done, Cancel,
/// Save, Move, Remove). A custom style, so iOS doesn't draw its Button Shapes
/// underline under the label. When Button Shapes is on, a capsule is drawn
/// instead, so people who turned the setting on still get a visible shape.
/// Colour comes from the tint (danger for the destructive role).
struct WWBarTextButtonStyle: ButtonStyle {
    var prominent: Bool

    init(prominent: Bool = false) {
        self.prominent = prominent
    }

    func makeBody(configuration: Configuration) -> some View {
        WWBarTextButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct WWBarTextButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

    var body: some View {
        configuration.label
            .fontWeight(prominent ? .semibold : nil)
            .foregroundStyle(foreground)
            .lineLimit(1)
            // Full width: in a sheet's toolbar iOS 26 offered the label an
            // icon-sized slot and "Cancel" showed as "Ca…".
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, showsButtonShapes ? WW.Space.sm : 0)
            .frame(minHeight: 32)
            .background {
                if showsButtonShapes {
                    Capsule().fill(WW.fill)
                }
            }
            .opacity(configuration.isPressed ? 0.5 : (isEnabled ? 1 : 0.4))
            .contentShape(Rectangle())
    }

    private var foreground: AnyShapeStyle {
        if configuration.role == .destructive {
            return AnyShapeStyle(WW.danger)
        }
        return AnyShapeStyle(TintShapeStyle())
    }
}

extension ButtonStyle where Self == WWBarTextButtonStyle {
    static var wwBarText: WWBarTextButtonStyle { WWBarTextButtonStyle() }
    static var wwBarTextProminent: WWBarTextButtonStyle { WWBarTextButtonStyle(prominent: true) }
}

/// White glyph on a `scrim` circle, on top of a photo (05 §2.2). 44 pt hit
/// area. Inside a `Button`, use `.buttonStyle(WWOnPhotoButtonStyle())` so the
/// scrim darkens while pressed. Always give the button an explicit
/// accessibility label ("Crop photo", "Remove back photo").
struct WWOnPhotoButtonLabel: View {
    let systemImage: String
    let diameter: CGFloat
    /// An 8 pt white dot at the top trailing edge (e.g. "crop applied").
    let showsBadge: Bool

    @Environment(\.wwIsPressed) private var isPressed
    @Environment(\.colorSchemeContrast) private var contrast

    init(systemImage: String, diameter: CGFloat = WW.Size.onPhoto, showsBadge: Bool = false) {
        self.systemImage = systemImage
        self.diameter = diameter
        self.showsBadge = showsBadge
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14 * diameter / WW.Size.onPhoto, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: diameter, height: diameter)
            .background { scrimLayer }
            .overlay(alignment: .topTrailing) { badgeLayer }
            .frame(width: max(WW.Size.minTarget, diameter), height: max(WW.Size.minTarget, diameter))
            .contentShape(Rectangle())
    }

    private var scrimLayer: some View {
        ZStack {
            Circle().fill(WW.scrim)
            if isPressed {
                // α .45 → .62 (HC .60 → .75), 05 §1.2.
                Circle().fill(Color.black.opacity(contrast == .increased ? 0.375 : 0.31))
            }
        }
    }

    @ViewBuilder
    private var badgeLayer: some View {
        if showsBadge {
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .offset(x: 1, y: -1)
                .accessibilityHidden(true)
        }
    }
}

/// Pre-redesign name, moved from ContentView (04 §11.1 move 2).
typealias PhotoOverlayButtonLabel = WWOnPhotoButtonLabel

/// Round icon button on a `fill` circle, 44 pt hit area (content only;
/// toolbar icons stay system). Inside a `Button` with `WWPressableStyle`.
struct WWIconButtonLabel: View {
    let systemImage: String
    let size: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    init(systemImage: String, size: CGFloat = 36) {
        self.systemImage = systemImage
        self.size = size
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WW.text)
            .frame(width: size, height: size)
            .background(WW.fill, in: Circle())
            .overlay { strokeLayer }
            .frame(minWidth: WW.Size.minTarget, minHeight: WW.Size.minTarget)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var strokeLayer: some View {
        if contrast == .increased {
            Circle().strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
        }
    }
}

// MARK: - Surfaces (05 §2.15, §1.10)

/// Card fills. Increase Contrast adds a 1 pt stroke in the listed colour.
enum WWCardStyle {
    /// `surface` (`elevated` inside a sheet in dark); stroke `separator`.
    case surface
    /// `elevated`; stroke `separator`.
    case elevated
    /// `cautionWash`; stroke `caution`.
    case caution
    /// `accentWash`; stroke `separator`.
    case accentWash
    /// `dangerWash`; stroke `danger`.
    case danger
}

private struct WWCardModifier: ViewModifier {
    let padding: CGFloat?
    let style: WWCardStyle
    @Environment(\.wwSurfaceLevel) private var surfaceLevel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .padding(padding ?? WW.cardPadding(for: dynamicTypeSize))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fillColor, in: shape)
            .overlay { strokeLayer }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WW.Radius.card, style: .continuous)
    }

    @ViewBuilder
    private var strokeLayer: some View {
        if contrast == .increased {
            shape.strokeBorder(strokeColor, lineWidth: WW.Stroke.hc)
        }
    }

    private var fillColor: Color {
        switch style {
        case .surface: return surfaceLevel == .elevated ? WW.elevated : WW.surface
        case .elevated: return WW.elevated
        case .caution: return WW.cautionWash
        case .accentWash: return WW.accentWash
        case .danger: return WW.dangerWash
        }
    }

    private var strokeColor: Color {
        switch style {
        case .surface, .elevated, .accentWash: return WW.separator
        case .caution: return WW.caution
        case .danger: return WW.danger
        }
    }
}

private struct WWFloatingBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(WW.elevated, in: shape)
                .overlay { shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc) }
        } else {
            translucent(content)
        }
    }

    @ViewBuilder
    private func translucent(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hairline(displayScale: displayScale)) }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

private struct WWBarBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.bar, ignoresSafeAreaEdges: .bottom)
            .overlay(alignment: .top) { WWHairline() }
    }
}

extension View {
    /// The standard card: padding (20, or 16 at AX sizes when nil), full
    /// width, radius 20, no shadow. Increase Contrast adds a 1 pt stroke.
    /// Grouped rows: `.wwCard(padding: 0)` + rows with 16 pt side padding.
    func wwCard(padding: CGFloat? = nil, style: WWCardStyle = .surface) -> some View {
        modifier(WWCardModifier(padding: padding, style: style))
    }

    /// Small group label inside a card (15 Semibold, `secondaryText`),
    /// e.g. "Your collection" in the Home snapshot.
    func wwOverline() -> some View {
        self
            .wwFont(.subhead, weight: .semibold)
            .foregroundStyle(WW.secondaryText)
    }

    /// Floating surface (toast): Liquid Glass on iOS 26, `.regularMaterial` +
    /// hairline on iOS 17–25, solid `elevated` + stroke with Reduce Transparency.
    func wwFloatingBackground(cornerRadius: CGFloat = WW.Radius.tile) -> some View {
        modifier(WWFloatingBackgroundModifier(cornerRadius: cornerRadius))
    }

    /// iOS 17–25 bottom-bar look: `.bar` material + top hairline.
    func wwBarBackground() -> some View {
        modifier(WWBarBackgroundModifier())
    }
}

/// A one-pixel `separator` line. Use instead of `Divider()`, which ignores our colour.
struct WWHairline: View {
    @Environment(\.displayScale) private var displayScale

    init() {}

    var body: some View {
        Rectangle()
            .fill(WW.separator)
            .frame(height: WW.Stroke.hairline(displayScale: displayScale))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - Section header (05 §2.16)

/// Title Case section header (20 Semibold, `.isHeader`) + optional trailing
/// action, styled as a small accent tertiary button. Stacks at AX sizes.
struct WWSectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            titleRow
            if let subtitle {
                Text(subtitle)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var titleRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                titleText
                trailingContent
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: WW.Space.xs) {
                titleText
                Spacer(minLength: WW.Space.xs)
                trailingContent
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .wwFont(.sectionTitle)
            .foregroundStyle(WW.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var trailingContent: some View {
        trailing()
            .buttonStyle(WWTertiaryButtonStyle(tone: .accent, size: .small))
    }
}

extension WWSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

extension View {
    /// Header → 12 → content. Sections are 32 apart (`WW.Space.sectionGap`).
    func wwSection(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSectionHeader(title: title, subtitle: subtitle)
            self
        }
    }

    /// Header with a trailing action ("See All") → 12 → content.
    func wwSection<T: View>(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> T) -> some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSectionHeader(title: title, subtitle: subtitle, trailing: trailing)
            self
        }
    }
}

// MARK: - Money: range text (05 §2.8)

/// A value range that never truncates. Fallback chain (first that fits):
/// one line → two lines (break after the en dash) → two lines at 0.9 size →
/// two lines one role smaller → two lines that wrap. Tabular, never animated.
/// VoiceOver: "between $310 and $420" (hosts prefix "Estimated value: ").
struct ValueRangeText: View {
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let lowUSD: Double
    let highUSD: Double
    let role: WWTextRole
    let tone: Color
    let alignment: HorizontalAlignment

    init(lowUSD: Double, highUSD: Double, role: WWTextRole = .valueDisplay, tone: Color = WW.text,
         alignment: HorizontalAlignment = .leading) {
        self.lowUSD = lowUSD
        self.highUSD = highUSD
        self.role = role
        self.tone = tone
        self.alignment = alignment
    }

    private var lowText: String { WW.money(min(lowUSD, highUSD)) }
    private var highText: String { WW.money(max(lowUSD, highUSD)) }
    private var isSingle: Bool { lowText == highText }

    private var stepDownSpec: WWTextSpec {
        if role == .priceCompact {
            var spec = WWTextRole.caption.spec
            spec.weight = .semibold
            spec.tabular = true
            return spec
        }
        return role.stepDown.spec
    }

    private var textAlignment: TextAlignment {
        if alignment == .trailing { return .trailing }
        if alignment == .center { return .center }
        return .leading
    }

    private var accessibilityText: String {
        isSingle ? lowText : "between \(lowText) and \(highText)"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            oneLine(spec: role.spec)
            twoLines(spec: role.spec, fixed: true)
            twoLines(spec: role.spec.scaled(0.9), fixed: true)
            twoLines(spec: stepDownSpec, fixed: true)
            twoLines(spec: stepDownSpec, fixed: false)
        }
        .foregroundStyle(tone)
        .multilineTextAlignment(textAlignment)
        .contentTransition(.identity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func oneLine(spec: WWTextSpec) -> some View {
        Text(WW.range(lowUSD, highUSD))
            .wwFont(spec: spec)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func twoLines(spec: WWTextSpec, fixed: Bool) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            line(isSingle ? lowText : lowText + " –", spec: spec, fixed: fixed)
            if !isSingle {
                line(highText, spec: spec, fixed: fixed)
            }
        }
    }

    @ViewBuilder
    private func line(_ string: String, spec: WWTextSpec, fixed: Bool) -> some View {
        if fixed {
            Text(string)
                .wwFont(spec: spec)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text(string)
                .wwFont(spec: spec)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Money: range bar (05 §2.9, 07 §4.2)

/// The evidence strip: track, the range span (`text` α .30), a best tick with
/// a knockout gap (05 D12) and, on Pro, one dot per sale. Neutral colours
/// only. The graphic is hidden from VoiceOver; the best-estimate and sold
/// lines say it in words. Animate `spanProgress` 0 → 1 for 06's "spread".
struct RangeBar: View, Animatable {
    let lowUSD: Double
    let highUSD: Double
    let bestUSD: Double?
    let salesUSD: [Double]
    let salesAreExact: Bool
    let windowDays: Int
    let totalSales: Int?
    var spanProgress: Double

    var animatableData: Double {
        get { spanProgress }
        set { spanProgress = newValue }
    }

    /// Most recent sales drawn as dots.
    static let maxDots: Int = 40

    /// - Parameters:
    ///   - salesUSD: newest first (Pro). Empty = no dots and no caption.
    ///   - salesAreExact: false draws hollow dots (similar items).
    ///   - totalSales: for "showing 40 of 112"; defaults to `salesUSD.count`.
    ///   - spanProgress: 0…1, the span spreads from the best tick (06 M13).
    init(lowUSD: Double, highUSD: Double, bestUSD: Double?, salesUSD: [Double] = [], salesAreExact: Bool = true,
         windowDays: Int = 90, totalSales: Int? = nil, spanProgress: Double = 1) {
        self.lowUSD = lowUSD
        self.highUSD = highUSD
        self.bestUSD = bestUSD
        self.salesUSD = salesUSD
        self.salesAreExact = salesAreExact
        self.windowDays = windowDays
        self.totalSales = totalSales
        self.spanProgress = spanProgress
    }

    private var shownSales: [Double] {
        Array(salesUSD.filter { $0.isFinite && $0 > 0 }.prefix(RangeBar.maxDots))
    }

    private var barHeight: CGFloat {
        // 3 rows of dots at a 7 pt pitch need 34 pt above the track's base.
        shownSales.isEmpty ? 14 : 34
    }

    private var caption: String? {
        let shown = shownSales.count
        guard shown > 0 else { return nil }
        let base = "Each dot is one sale · last \(windowDays) days"
        let total = max(totalSales ?? salesUSD.count, shown)
        if total > shown { return base + " · showing \(shown) of \(total)" }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar
            if let caption {
                Text(caption)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bar: some View {
        let layout = RangeBarLayout(low: lowUSD, high: highUSD, best: bestUSD, sales: shownSales,
                                    exact: salesAreExact, progress: spanProgress)
        let colors = RangeBarColors(track: WW.track, span: WW.text.opacity(0.30), tick: WW.text,
                                    dot: WW.text.opacity(0.55), hollow: WW.secondaryText, chevron: WW.tertiaryText)
        return Canvas { context, size in
            layout.draw(in: &context, size: size, colors: colors)
        }
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct RangeBarColors {
    let track: Color
    let span: Color
    let tick: Color
    let dot: Color
    let hollow: Color
    let chevron: Color
}

private struct RangeBarLayout {
    let low: Double
    let high: Double
    let best: Double?
    let sales: [Double]
    let exact: Bool
    let progress: Double

    func draw(in context: inout GraphicsContext, size: CGSize, colors: RangeBarColors) {
        let width = size.width
        guard width > 8, size.height >= 14 else { return }
        let lo = min(low, high)
        let hi = max(low, high)
        let domain = RangeBarLayout.domain(low: lo, high: hi, sales: sales)
        let trackMidY = size.height - 7

        // Track: 6 pt, full width, bottom-aligned.
        let trackRect = CGRect(x: 0, y: trackMidY - 3, width: width, height: 6)
        context.fill(Path(roundedRect: trackRect, cornerRadius: WW.Radius.bar), with: .color(colors.track))

        // Span: x(low)…x(high), min 8 pt, spreading from the best tick.
        let xLow = RangeBarLayout.x(lo, domain: domain, width: width)
        let xHigh = RangeBarLayout.x(hi, domain: domain, width: width)
        var anchor = (xLow + xHigh) / 2
        if let best {
            anchor = RangeBarLayout.x(best, domain: domain, width: width)
        }
        let p = CGFloat(max(0, min(1, progress)))
        var spanStart = anchor - (anchor - xLow) * p
        var spanEnd = anchor + (xHigh - anchor) * p
        if spanEnd - spanStart < 8 {
            let centre = (spanStart + spanEnd) / 2
            spanStart = max(0, centre - 4)
            spanEnd = min(width, spanStart + 8)
        }
        let spanRect = CGRect(x: spanStart, y: trackMidY - 3, width: spanEnd - spanStart, height: 6)
        context.fill(Path(roundedRect: spanRect, cornerRadius: WW.Radius.bar), with: .color(colors.span))

        // Best tick, with a 1.5 pt knockout on both sides (05 D12).
        if let best {
            let tickX = min(max(RangeBarLayout.x(best, domain: domain, width: width), 1), width - 1)
            context.blendMode = .clear
            context.fill(Path(CGRect(x: tickX - 2.5, y: trackMidY - 5, width: 5, height: 10)), with: .color(Color.black))
            context.blendMode = .normal
            let tickRect = CGRect(x: tickX - 1, y: trackMidY - 7, width: 2, height: 14)
            context.fill(Path(roundedRect: tickRect, cornerRadius: 1), with: .color(colors.tick))
        }

        if !sales.isEmpty {
            drawDots(in: &context, width: width, trackMidY: trackMidY, low: lo, high: hi, domain: domain, colors: colors)
        }
    }

    private func drawDots(in context: inout GraphicsContext, width: CGFloat, trackMidY: CGFloat,
                          low: Double, high: Double, domain: RangeBarDomain, colors: RangeBarColors) {
        let binWidth: CGFloat = 6
        let pitch: CGFloat = 7
        let firstRowY = trackMidY - 3 - 7
        let binCount = max(1, Int(width / binWidth))
        var stacks = [Int](repeating: 0, count: binCount)
        var pinnedLeft = false
        var pinnedRight = false

        for sale in sales {
            let x: CGFloat
            if sale > high * 2 {
                x = width - 3 - 8
                pinnedRight = true
            } else if sale < low / 2 {
                x = 3 + 8
                pinnedLeft = true
            } else {
                x = RangeBarLayout.x(sale, domain: domain, width: width)
            }
            let bin = max(0, min(binCount - 1, Int(x / binWidth)))
            let row = min(stacks[bin], 2)
            stacks[bin] += 1
            let cx = min(max((CGFloat(bin) + 0.5) * binWidth, 3), width - 3)
            let cy = firstRowY - CGFloat(row) * pitch
            let rect = CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6)
            if exact {
                context.fill(Path(ellipseIn: rect), with: .color(colors.dot))
            } else {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(colors.hollow), lineWidth: 1)
            }
        }

        if pinnedRight {
            drawChevron(in: &context, x: width - 3, y: firstRowY, pointsRight: true, color: colors.chevron)
        }
        if pinnedLeft {
            drawChevron(in: &context, x: 3, y: firstRowY, pointsRight: false, color: colors.chevron)
        }
    }

    private func drawChevron(in context: inout GraphicsContext, x: CGFloat, y: CGFloat, pointsRight: Bool, color: Color) {
        let dx: CGFloat = pointsRight ? -2 : 2
        var path = Path()
        path.move(to: CGPoint(x: x + dx, y: y - 4))
        path.addLine(to: CGPoint(x: x - dx, y: y))
        path.addLine(to: CGPoint(x: x + dx, y: y + 4))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    /// `[min(low, sales), max(high, sales)]`, padded 8 % (10 % of high when
    /// flat), clamped at 0. Sales beyond ½ low … 2 × high are pinned instead.
    static func domain(low: Double, high: Double, sales: [Double]) -> RangeBarDomain {
        var lo = low
        var hi = high
        for sale in sales where sale >= low / 2 && sale <= high * 2 {
            lo = min(lo, sale)
            hi = max(hi, sale)
        }
        let spread = hi - lo
        let pad: Double = spread > 0 ? spread * 0.08 : max(hi, 1) * 0.10
        return RangeBarDomain(lo: max(0, lo - pad), hi: hi + pad)
    }

    static func x(_ value: Double, domain: RangeBarDomain, width: CGFloat) -> CGFloat {
        let span = domain.hi - domain.lo
        guard span > 0 else { return width / 2 }
        let t = (value - domain.lo) / span
        return CGFloat(max(0, min(1, t))) * width
    }
}

private struct RangeBarDomain {
    let lo: Double
    let hi: Double
}

// MARK: - Evidence (04 §4.6, 05 §2.11–§2.12, §2.19)

/// SOLD solid → GUIDE tinted → ASKING outline → AI ESTIMATE dashed. A
/// rectangle (r 6), never a capsule; glyph + word; hugs its content; never
/// tappable. VoiceOver speaks `kind.spoken`, never the letters.
struct EvidenceBadge: View {
    let kind: EvidenceKind
    @Environment(\.colorSchemeContrast) private var contrast

    init(kind: EvidenceKind) {
        self.kind = kind
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.glyph)
                .imageScale(.small)
            Text(kind.chip)
        }
        .wwFont(.chip)
        .foregroundStyle(labelColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: WW.Size.chipMin)
        .background { fillLayer }
        .overlay { strokeLayer }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.spoken)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WW.Radius.chip, style: .continuous)
    }

    private var strokeWidth: CGFloat {
        contrast == .increased ? WW.Stroke.outlineHC : WW.Stroke.outline
    }

    private var labelColor: Color {
        switch kind {
        case .sold: return WW.onSoldFill
        case .guide: return WW.text
        case .asking: return WW.caution
        case .aiEstimate: return WW.secondaryText
        }
    }

    @ViewBuilder
    private var fillLayer: some View {
        switch kind {
        case .sold: shape.fill(WW.soldFill)
        case .guide: shape.fill(WW.neutralWash)
        case .asking, .aiEstimate: Color.clear
        }
    }

    @ViewBuilder
    private var strokeLayer: some View {
        switch kind {
        case .sold:
            EmptyView()
        case .guide:
            if contrast == .increased {
                shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
            }
        case .asking:
            shape.strokeBorder(WW.caution, lineWidth: strokeWidth)
        case .aiEstimate:
            shape.strokeBorder(WW.tertiaryText, style: StrokeStyle(lineWidth: strokeWidth, dash: WW.Stroke.dashAI))
        }
    }
}

/// Pre-redesign API, kept as a wrapper (04 §8.8).
struct PriceTypeBadge: View {
    let type: PriceType

    init(type: PriceType) {
        self.type = type
    }

    var body: some View {
        EvidenceBadge(kind: EvidenceKind(type))
    }
}

/// Chip + the evidence sentence (`priceSummary` verbatim, else the fallback),
/// with the asking / similar-items suffixes in `secondaryText`. The chip moves
/// above the text at AX sizes. VoiceOver: "Evidence: {spoken}. {text}".
struct EvidenceLine: View {
    let kind: EvidenceKind
    let text: String
    let isExact: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(kind: EvidenceKind, text: String, isExact: Bool) {
        self.kind = kind
        self.text = text
        self.isExact = isExact
    }

    /// From an assessment (nil in D, which has no evidence line).
    init?(assessment: ValueAssessment) {
        guard let kind = assessment.evidence, let text = assessment.evidenceText else { return nil }
        self.init(kind: kind, text: text, isExact: assessment.isExact)
    }

    private var suffix: String {
        var parts = ""
        if kind == .asking { parts += " · treat the top as a ceiling" }
        if !isExact { parts += " · similar items, not this exact piece" }
        return parts
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    EvidenceBadge(kind: kind)
                    sentence
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: WW.Space.xs) {
                    EvidenceBadge(kind: kind)
                    sentence
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evidence: \(kind.spoken). \(text)\(suffix)")
    }

    private var sentence: some View {
        let main: Text = Text(text).foregroundStyle(WW.text)
        let tail: Text = Text(suffix).foregroundStyle(WW.secondaryText)
        let combined: Text = main + tail
        return combined
            .wwFont(.subhead)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One sold price or listing (05 §2.19): chip · title/detail · price · link.
/// The whole row is a `Link` when `url` is set. Put rows in
/// `.wwCard(padding: 0)` with `WWHairline().padding(.leading, 16)` between.
struct EvidenceRow: View {
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let kind: EvidenceKind
    let title: String
    let detail: String?
    /// The amount in `currency` (USD for every server price; converted for display).
    let priceUSD: Double
    let currency: String
    let url: URL?
    /// The listing's photo, when the source has one (eBay).
    let imageURL: URL?

    init(kind: EvidenceKind, title: String, detail: String? = nil, priceUSD: Double, currency: String = "USD", url: URL? = nil, imageURL: URL? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.priceUSD = priceUSD
        self.currency = currency
        self.url = url
        self.imageURL = imageURL
    }

    private var priceText: String { WW.money(priceUSD, code: currency) }

    private var spokenText: String {
        var parts: [String] = [kind.spoken, title, priceText]
        if let detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if let url {
            Link(destination: url) {
                rowContent(showsLinkGlyph: true)
            }
            .buttonStyle(WWPressableStyle())
            .accessibilityAddTraits(.isLink)
            .accessibilityHint("Opens the listing")
        } else {
            rowContent(showsLinkGlyph: false)
        }
    }

    @ViewBuilder
    private func rowContent(showsLinkGlyph: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    if let imageURL { EvidenceThumbnail(url: imageURL) }
                    EvidenceBadge(kind: kind)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        titleText
                        if showsLinkGlyph { linkGlyph }
                    }
                    detailText
                    priceLabel
                }
            } else {
                HStack(alignment: .center, spacing: WW.Space.sm) {
                    if let imageURL { EvidenceThumbnail(url: imageURL) }
                    EvidenceBadge(kind: kind)
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                        detailText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    priceLabel
                    if showsLinkGlyph { linkGlyph }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, WW.Space.md)
        .frame(minHeight: WW.Size.evidenceRow)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var titleText: some View {
        Text(title)
            .wwFont(.subhead, weight: .semibold)
            .foregroundStyle(WW.text)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var detailText: some View {
        if let detail, !detail.isEmpty {
            Text(detail)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var priceLabel: some View {
        Text(priceText)
            .wwFont(.price)
            .foregroundStyle(WW.text)
            .fixedSize()
    }

    private var linkGlyph: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WW.tertiaryText)
            .accessibilityHidden(true)
    }
}

/// A listing's or sale's photo in an `EvidenceRow`, so the user can see what a
/// price is for. Decorative to VoiceOver: the row's label names the item.
private struct EvidenceThumbnail: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(phase.error == nil ? 0 : 0.5))
            }
        }
        .frame(width: 52, height: 52)
        .background(WW.photoBackdrop)
        .clipShape(RoundedRectangle(cornerRadius: WW.radiusControl, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Match (05 §2.13)

/// Three segments + the match word, on its own line. Close: `text`;
/// Possible / Unsure: `caution` (05 D1). The word never wraps.
/// VoiceOver: label "Match", value "Close"/"Possible"/"Unsure".
struct MatchIndicator: View {
    let strength: MatchStrength
    @ScaledMetric(relativeTo: .subheadline) private var segmentWidth: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var segmentHeight: CGFloat = 6

    init(strength: MatchStrength) {
        self.strength = strength
    }

    private var tint: Color { strength == .close ? WW.text : WW.caution }
    private var width: CGFloat { min(segmentWidth, 16 * WW.Size.graphicScaleCap) }
    private var height: CGFloat { min(segmentHeight, 6 * WW.Size.graphicScaleCap) }

    var body: some View {
        HStack(alignment: .center, spacing: WW.Space.xs) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(index < strength.filledSegments ? tint : WW.track)
                        .frame(width: width, height: height)
                }
            }
            Text(strength.label)
                .wwFont(.subhead, weight: .semibold)
                .foregroundStyle(tint)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Match")
        .accessibilityValue(strength.word)
        .accessibilityHint("How sure we are that this is your item")
    }
}

/// Pre-redesign API, kept as a wrapper (04 §8.8). Same thresholds as everywhere.
struct MatchMeter: View {
    let confidence: Double

    init(confidence: Double) {
        self.confidence = confidence
    }

    var body: some View {
        MatchIndicator(strength: MatchStrength(confidence: confidence))
    }
}

// MARK: - Caveats (05 §2.14)

/// A plain flag. `.row`: `cautionWash` row with glyph + sentence (r 10);
/// `.inline`: glyph + word in the tone colour (C header, tile price line).
/// VoiceOver: "Caution: {sentence}".
struct CaveatFlag: View {
    enum Tone {
        case caution
        case neutral
    }

    enum Style {
        case row
        case inline
    }

    private enum Source {
        case caveat(ValueCaveat)
        case custom(glyph: String, text: String)
    }

    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @Environment(\.colorSchemeContrast) private var contrast
    private let source: Source
    private let tone: Tone
    private let style: Style

    /// A caveat from `ValueAssessment.displayCaveats` (money in the display currency).
    init(_ caveat: ValueCaveat, style: Style = .row) {
        self.source = .caveat(caveat)
        self.tone = .caution
        self.style = style
    }

    init(glyph: String, text: String, tone: Tone = .caution, style: Style = .row) {
        self.source = .custom(glyph: glyph, text: text)
        self.tone = tone
        self.style = style
    }

    /// The C header / tile word (05 D8): "Rough guide" ⚠ by default.
    static func roughGuide(_ word: String = "Rough guide", glyph: String = "exclamationmark.triangle") -> CaveatFlag {
        CaveatFlag(glyph: glyph, text: word, tone: .caution, style: .inline)
    }

    private var glyph: String {
        switch source {
        case .caveat(let caveat): return caveat.glyph
        case .custom(let glyph, _): return glyph
        }
    }

    private var text: String {
        switch source {
        case .caveat(let caveat): return caveat.sentence
        case .custom(_, let text): return text
        }
    }

    private var toneColor: Color { tone == .caution ? WW.caution : WW.secondaryText }
    private var washColor: Color { tone == .caution ? WW.cautionWash : WW.neutralWash }
    private var strokeColor: Color { tone == .caution ? WW.caution : WW.separator }

    var body: some View {
        switch style {
        case .row:
            row
        case .inline:
            inline
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: WW.Space.xs) {
            Image(systemName: glyph)
                .wwFont(.subhead, weight: .semibold)
                .foregroundStyle(toneColor)
                .accessibilityHidden(true)
            Text(text)
                .wwFont(.subhead)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, WW.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(washColor, in: RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous))
        .overlay { rowStroke }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Caution: \(text)")
    }

    @ViewBuilder
    private var rowStroke: some View {
        if contrast == .increased {
            RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: WW.Stroke.hc)
        }
    }

    private var inline: some View {
        Label(text, systemImage: glyph)
            .labelStyle(WWInlineIconLabelStyle(spacing: 6))
            .wwFont(.subhead, weight: .semibold)
            .foregroundStyle(toneColor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

// MARK: - Result copy (04 §6.4, 06 §4.2) — one wording everywhere

extension ValueCaveat {
    var glyph: String {
        switch self {
        case .salesHigher: return "arrow.up.right"
        case .salesLower: return "arrow.down.right"
        case .wideRange: return "arrow.left.and.right"
        case .unsureMatch: return "exclamationmark.triangle"
        case .similarItems: return "square.on.square"
        case .aiEstimate: return "circle.dashed"
        }
    }

    /// The flag sentence, money in the display currency.
    var sentence: String {
        switch self {
        case .salesHigher(let median, let count):
            return "Recent sales are higher: \(WW.money(median)) median from \(count) sales."
        case .salesLower(let median, let count):
            return "Recent sales are lower: \(WW.money(median)) median from \(count) sales."
        case .wideRange:
            return "Wide range: similar items sell for very different amounts."
        case .unsureMatch:
            return "Unsure match. Check the name before you rely on this value."
        case .similarItems:
            return "Similar items, not this exact piece."
        case .aiEstimate:
            return "AI estimate: no market prices were found for this item."
        }
    }
}

extension ValueNote {
    /// The note sentence for a level ("…not an appraisal" differs in C).
    func sentence(for level: ValueLevel) -> String {
        switch self {
        case .lowValue:
            let ceiling = WW.niceCeilingMoney(usd: ValueAssessment.T.lowValueUSD)
            return "Not much resale demand. Most like this sell for under \(ceiling)."
        case .highValue:
            return "Worth a professional opinion before you sell."
        case .notAnAppraisal:
            return level == .rough ? "A rough guide, not an appraisal." : "Estimates are a guide, not an appraisal."
        }
    }
}

extension NoPriceReason {
    /// D title (04 §6.4D).
    var title: String {
        switch self {
        case .tooWide: return "Too uncertain to price from a photo"
        case .notCollectible(let confirmed):
            return confirmed ? "This doesn't look like a collectible" : "This may not be a collectible"
        case .onDevice(let analysisOff):
            return analysisOff ? "Photo analysis is off" : "This scan wasn't priced"
        case .noValue: return "We couldn't find a price for this"
        }
    }

    /// D body. "It didn't use a scan." is separate (only when known).
    var message: String {
        switch self {
        case .tooWide:
            return "Similar items sell for very different amounts, so a range here wouldn't help you."
        case .notCollectible(let confirmed):
            return confirmed
                ? "Worthwise values objects, not people or places. Try one item on a plain background."
                : "We couldn't match it to anything people collect and sell. If it is one, try a closer photo of just the item."
        case .onDevice(let analysisOff):
            return analysisOff
                ? "We read the text on your photo, but we couldn't identify the item or check prices."
                : "It was made without a connection."
        case .noValue:
            return "No sold prices, guides or listings matched it."
        }
    }

    /// D glyph plate symbol (05 §2.10).
    var glyph: String {
        switch self {
        case .tooWide: return "arrow.left.and.right"
        case .notCollectible: return "questionmark.square.dashed"
        case .onDevice(let analysisOff): return analysisOff ? "eye.slash" : "wifi.slash"
        case .noValue: return "magnifyingglass"
        }
    }

    /// `.tooWide` uses a `cautionWash` plate with a `caution` glyph; the rest neutral.
    var usesCautionPlate: Bool { self == .tooWide }

    /// The bar's recovery action (04 §6.4D).
    var recoveryTitle: String {
        switch self {
        case .tooWide, .noValue: return "Edit photos and scan again"
        case .notCollectible: return "Scan something else"
        case .onDevice(let analysisOff): return analysisOff ? "Turn on photo analysis" : "Check price again"
        }
    }

    /// Content of "Show the rough range": "Similar items: €112 – €25,054. Too wide to rely on."
    static func roughRangeSentence(lowUSD: Double, highUSD: Double) -> String {
        "Similar items: \(WW.range(lowUSD, highUSD)). Too wide to rely on."
    }
}

extension BestEstimate {
    /// "Usually sells for $365" / "Best estimate $340".
    var headline: String {
        switch source {
        case .soldMedian: return "Usually sells for \(WW.money(amountUSD))"
        case .engineMid, .compsMedian: return "Best estimate \(WW.money(amountUSD))"
        }
    }

    /// "18 sales in the last 90 days" for a sold median, else nil.
    var detail: String? {
        switch source {
        case .soldMedian(let count, let windowDays):
            return "\(count) \(count == 1 ? "sale" : "sales") in the last \(windowDays) days"
        case .engineMid, .compsMedian:
            return nil
        }
    }

    /// One VoiceOver sentence: "Usually sells for $365, from 18 sales in the last 90 days".
    var spoken: String {
        if let detail { return "\(headline), from \(detail)" }
        return headline
    }
}

// MARK: - Rows (05 §2.17–§2.18, §5.6)

/// Icon + title (+ detail) aligned to the first baseline. For the caveat
/// inline flag, the "not counted" line, the identity chip, legend items.
struct WWInlineIconLabelStyle: LabelStyle {
    var spacing: CGFloat

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// A 34 pt icon circle + title (`.headline`) + detail (`.subhead`), one
/// VoiceOver element. Replaces benefit rows, onboarding points, consent rows,
/// How-it-works / How-it-values rows.
struct WWInfoRow: View {
    enum IconStyle: Equatable {
        /// `fill` circle, `text` glyph.
        case neutral
        /// `accentWash` circle, `accent` glyph.
        case accent
        /// White α .12 circle, white glyph, white / white α .85 text (O1 on `brandInk`).
        case onDark
        /// 22 pt `text` circle with a numeral in `inverseText` (guide steps, anatomy).
        case number(Int)
    }

    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var numberSize: CGFloat = 22
    let icon: String
    let title: String
    let detail: String?
    let iconStyle: IconStyle

    init(icon: String, title: String, detail: String? = nil, iconStyle: IconStyle = .neutral) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.iconStyle = iconStyle
    }

    /// Numbered variant.
    init(number: Int, title: String, detail: String? = nil) {
        self.icon = ""
        self.title = title
        self.detail = detail
        self.iconStyle = .number(number)
    }

    private var isNumber: Bool {
        if case .number = iconStyle { return true }
        return false
    }

    private var titleColor: Color { iconStyle == .onDark ? Color.white : WW.text }
    private var detailColor: Color { iconStyle == .onDark ? Color.white.opacity(0.85) : WW.secondaryText }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .wwFont(.headline)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .wwFont(.subhead)
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, isNumber ? 0 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badge: some View {
        switch iconStyle {
        case .number(let value):
            numberBadge(value)
        case .neutral:
            iconBadge(circle: WW.fill, glyph: WW.text)
        case .accent:
            iconBadge(circle: WW.accentWash, glyph: WW.accent)
        case .onDark:
            iconBadge(circle: Color.white.opacity(0.12), glyph: Color.white)
        }
    }

    private func iconBadge(circle: Color, glyph: Color) -> some View {
        let side = min(circleSize, WW.Size.infoIcon * WW.Size.graphicScaleCap)
        return Image(systemName: icon)
            .font(.system(size: 15 * side / WW.Size.infoIcon, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: side, height: side)
            .background(circle, in: Circle())
            .accessibilityHidden(true)
    }

    private func numberBadge(_ value: Int) -> some View {
        let side = min(numberSize, 22 * WW.Size.graphicScaleCap)
        return Text("\(value)")
            .font(.system(size: 12 * side / 22, weight: .semibold).monospacedDigit())
            .foregroundStyle(WW.inverseText)
            .frame(width: side, height: side)
            .background(WW.text, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A list row: 56 pt thumbnail (r 10) + title (2 lines) + subtitle, optional
/// accessory under the subtitle (e.g. a price line) and trailing view or
/// chevron. Includes 16 pt side padding: stack rows in `.wwCard(padding: 0)`
/// with `WWHairline().padding(.leading, 84)` between them. At AX sizes the
/// trailing view moves under the subtitle.
struct WWListRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let thumbnail: UIImage?
    let title: String
    let subtitle: String?
    let accessory: AnyView?
    let trailing: AnyView?
    let showsChevron: Bool

    init(thumbnail: UIImage?, title: String, subtitle: String? = nil, accessory: AnyView? = nil,
         trailing: AnyView? = nil, showsChevron: Bool = false) {
        self.thumbnail = thumbnail
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.trailing = trailing
        self.showsChevron = showsChevron
    }

    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: .center, spacing: WW.Space.sm) {
            thumb
            textColumn
            if !isAX {
                if let trailing {
                    trailing
                }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WW.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, WW.Space.xs)
        .padding(.horizontal, WW.Space.md)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let accessory {
                accessory
            }
            if isAX {
                if let trailing {
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thumb: some View {
        Color.clear
            .frame(width: WW.Size.thumb, height: WW.Size.thumb)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    PhotoPlaceholder()
                }
            }
            .background(WW.photoBackdrop)
            .clipShape(RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Empty states (05 §2.22, 07 §3)

/// `.page`: brand plate (72, `accentWash`) or illustration → New York title
/// → message → optional details (info rows card) → one primary → footnote.
/// `.inline`: a card with a leading visual (≤ 64 × 52) + title + message +
/// optional tertiary action. Plates/illustrations are decorative and hidden
/// at AX3 (page) / AX sizes (inline).
struct WWEmptyState: View {
    enum Style {
        case page
        case inline
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let glyph: String?
    let showsMark: Bool
    let title: String
    let message: String
    let actionTitle: String?
    let actionImage: String?
    let action: (() -> Void)?
    let style: Style
    let footnote: String?
    /// Replaces the plate (07: the Collection "empty shelf", ghost tiles).
    let illustration: AnyView?
    /// Page style: content between message and action (e.g. 3 `WWInfoRow`s in a card).
    let details: AnyView?

    init(glyph: String? = nil, showsMark: Bool = false, title: String, message: String,
         actionTitle: String? = nil, actionImage: String? = nil, action: (() -> Void)? = nil,
         style: Style = .page, footnote: String? = nil, illustration: AnyView? = nil, details: AnyView? = nil) {
        self.glyph = glyph
        self.showsMark = showsMark
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionImage = actionImage
        self.action = action
        self.style = style
        self.footnote = footnote
        self.illustration = illustration
        self.details = details
    }

    var body: some View {
        switch style {
        case .page:
            page
        case .inline:
            inline
        }
    }

    // MARK: Page

    private var page: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize < .accessibility3 {
                pageVisual
                    .padding(.bottom, WW.Space.lg)
                    .accessibilityHidden(true)
            }
            Text(title)
                .wwFont(.brandTitle)
                .foregroundStyle(WW.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .wwFont(.body)
                .foregroundStyle(WW.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
                .padding(.top, WW.Space.xs)
            if let details {
                details
                    .padding(.top, WW.Space.xl)
            }
            pageAction
            if let footnote {
                Text(footnote)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WW.Space.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WW.Space.emptyStateTop)
    }

    @ViewBuilder
    private var pageVisual: some View {
        if let illustration {
            illustration
        } else if showsMark {
            plate {
                WorthwiseMark(size: 36, tone: .accent)
            }
        } else if let glyph {
            plate {
                Image(systemName: glyph)
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WW.accent)
            }
        }
    }

    private func plate<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: WW.Size.plateL, height: WW.Size.plateL)
            .background(WW.accentWash, in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
    }

    @ViewBuilder
    private var pageAction: some View {
        if let actionTitle, let action {
            Button(action: action) {
                actionLabel(actionTitle)
            }
            .buttonStyle(WWPrimaryButtonStyle())
            .frame(maxWidth: 360)
            .padding(.top, WW.Space.xl)
        }
    }

    @ViewBuilder
    private func actionLabel(_ text: String) -> some View {
        if let actionImage {
            Label(text, systemImage: actionImage)
        } else {
            Text(text)
        }
    }

    // MARK: Inline

    private var inline: some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                inlineVisual
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                inlineAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .wwCard(padding: WW.Space.md)
    }

    @ViewBuilder
    private var inlineVisual: some View {
        if let illustration {
            illustration
                .frame(maxWidth: 64, maxHeight: 52)
        } else if showsMark {
            WorthwiseMark(size: 28, tone: .accent)
                .frame(width: WW.Size.plateS, height: WW.Size.plateS)
                .background(WW.accentWash, in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
        } else if let glyph {
            Image(systemName: glyph)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WW.accent)
                .frame(width: WW.Size.plateS, height: WW.Size.plateS)
                .background(WW.accentWash, in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
        }
    }

    @ViewBuilder
    private var inlineAction: some View {
        if let actionTitle, let action {
            Button(action: action) {
                actionLabel(actionTitle)
            }
            .buttonStyle(WWTertiaryButtonStyle(tone: .accent, size: .small))
        }
    }
}

/// 07's ghost tiles for `WWEmptyState(.inline)` (Home "Your scans appear here"):
/// three 34 pt squares overlapping −10, with 2 pt rings in the card colour.
struct WWGhostTiles: View {
    @Environment(\.wwSurfaceLevel) private var surfaceLevel

    init() {}

    var body: some View {
        HStack(spacing: -10) {
            tile(WW.track.opacity(0.6))
            tile(WW.track.opacity(0.4))
            tile(WW.fill)
        }
        .accessibilityHidden(true)
    }

    private func tile(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous)
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay {
                RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous)
                    .strokeBorder(surfaceLevel == .elevated ? WW.elevated : WW.surface, lineWidth: 2)
            }
    }
}

/// Shown where an item has no stored photo.
struct PhotoPlaceholder: View {
    let systemImage: String

    init(systemImage: String = "photo") {
        self.systemImage = systemImage
    }

    var body: some View {
        ZStack {
            WW.photoBackdrop
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Toast (05 §2.23, 06 M21)

private struct WWToastView: View {
    let model: WWToastModel
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: WW.Space.sm) {
            if model.isSuccess {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(WW.text)
                    .accessibilityHidden(true)
            }
            Text(model.message)
                .wwFont(.subhead)
                .foregroundStyle(WW.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let title = model.actionTitle, model.action != nil {
                Button(title, action: onAction)
                    .buttonStyle(WWTertiaryButtonStyle(tone: .accent, size: .small))
            }
        }
        .padding(.horizontal, WW.Space.md)
        .padding(.vertical, WW.Space.sm)
        .frame(minHeight: 52)
        .wwFloatingBackground(cornerRadius: WW.Radius.tile)
        .frame(maxWidth: WW.Size.toastMaxWidth)
    }
}

private struct WWToastModifier: ViewModifier {
    @Binding var toast: WWToastModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                toastLayer
            }
            .task(id: toast?.id) {
                await runToast()
            }
    }

    private var transition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.offset(y: WW.Motion.toastOffset).combined(with: .opacity)
    }

    private var toastLayer: some View {
        ZStack {
            if let current = toast {
                WWToastView(model: current, onAction: { perform(current) })
                    .padding(.horizontal, WW.Space.margin)
                    .padding(.bottom, WW.Space.sm)
                    .gesture(dismissGesture)
                    .transition(transition)
            }
        }
        .animation(WW.Motion.animation(.toastIn, reduceMotion: reduceMotion), value: toast?.id)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                if value.translation.height > 20 {
                    toast = nil
                }
            }
    }

    private func perform(_ model: WWToastModel) {
        model.action?()
        toast = nil
    }

    @MainActor
    private func runToast() async {
        guard let current = toast else { return }
        let toastID: UUID = current.id
        let message: String = current.message
        let hasAction: Bool = current.actionTitle != nil && current.action != nil
        let hold: Double = await MainActor.run { () -> Double in
            UIAccessibility.post(notification: .announcement, argument: message)
            if UIAccessibility.isVoiceOverRunning { return WW.Motion.toastHoldVoiceOver }
            return hasAction ? WW.Motion.toastHoldWithAction : WW.Motion.toastHold
        }
        try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
        if Task.isCancelled { return }
        if toast?.id == toastID {
            toast = nil
        }
    }
}

extension View {
    /// Shows `toast` above the bottom of this view for 4 s (6 s with an
    /// action, 10 s with VoiceOver), announces it, and clears the binding.
    /// A swipe down dismisses it; a new toast replaces the current one.
    /// Apply it inside `.wwBottomBar` / the tab content so it sits above the bar.
    func wwToast(_ toast: Binding<WWToastModel?>) -> some View {
        modifier(WWToastModifier(toast: toast))
    }
}

// MARK: - Sheets (05 §2.24, §2.7, §2.31)

/// Sheet content header: optional 52 pt plate + title (`.itemTitle`, or
/// New York `.brandTitle` when `brand`) + subtitle (`.callout`). The nav bar
/// stays untitled; use with `.wwSheetBackground()`.
struct WWSheetHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String?
    let brand: Bool
    let systemImage: String?

    init(title: String, subtitle: String? = nil, brand: Bool = false, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.brand = brand
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: WW.Space.sm) {
                    if dynamicTypeSize < .accessibility3 { plate }
                    texts
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    plate
                    texts
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plate: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WW.accent)
                .frame(width: WW.Size.plateS, height: WW.Size.plateS)
                .background(WW.accentWash, in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            Text(title)
                .wwFont(brand ? WWTextRole.brandTitle : WWTextRole.itemTitle)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .wwFont(.callout)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WWFieldModifier: ViewModifier {
    let isFocused: Bool
    let isError: Bool
    @Environment(\.wwSurfaceLevel) private var surfaceLevel

    func body(content: Content) -> some View {
        content
            .wwFont(.body)
            .foregroundStyle(WW.text)
            .tint(WW.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: WW.Size.fieldMin)
            .background(surfaceLevel == .elevated ? WW.elevated : WW.surface, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: borderWidth)
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous)
    }

    private var borderColor: Color {
        if isError { return WW.danger }
        return isFocused ? WW.accent : WW.separator
    }

    private var borderWidth: CGFloat {
        (isError || isFocused) ? WW.Stroke.fieldFocused : WW.Stroke.hc
    }
}

extension View {
    /// Text field container (05 §2.7): `surface` (`elevated` in dark sheets),
    /// r 10, min 48; border `separator` / focused 1.5 `accent` / error 1.5
    /// `danger`. Use `TextField(_, text:, prompt: Text(…).foregroundStyle(WW.secondaryText))`.
    /// The host shows any error message under it.
    func wwField(isFocused: Bool, isError: Bool = false) -> some View {
        modifier(WWFieldModifier(isFocused: isFocused, isError: isError))
    }
}

/// Disclosure row (05 §2.31): rotating chevron + small label, min 44, content
/// 8 below. `.accent` for "Show the rough range" / "More plans"; `.neutral`
/// for consent "Details". Use `.disclosureGroupStyle(WWDisclosureStyle())`.
struct WWDisclosureStyle: DisclosureGroupStyle {
    enum Tone {
        case accent
        case neutral
    }

    var tone: Tone

    init(tone: Tone = .accent) {
        self.tone = tone
    }

    func makeBody(configuration: Configuration) -> some View {
        WWDisclosureBody(configuration: configuration, tone: tone)
    }
}

private struct WWDisclosureBody: View {
    let configuration: DisclosureGroupStyleConfiguration
    let tone: WWDisclosureStyle.Tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { tone == .accent ? WW.accent : WW.text }

    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            Button {
                withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                labelRow
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content
                    .transition(contentTransition)
            }
        }
    }

    private var labelRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                .accessibilityHidden(true)
            configuration.label
                .wwFont(.buttonSmall)
        }
        .foregroundStyle(color)
        .frame(minHeight: WW.Size.minTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var contentTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.opacity.combined(with: .move(edge: .top))
    }
}

/// Condition as a menu row (04 §6.2, 05 §2.28): "Not sure" + the 5 grades
/// with subtitles; card wording when `category` is `.tradingCard`.
/// "Not sure" sets `isSet = false` and `grade = .good` (the neutral grade sent
/// to the server). Each pick plays `Haptics.selection()`.
struct ConditionPicker: View {
    @Binding var grade: ConditionGrade
    @Binding var isSet: Bool
    let category: CollectibleCategory?
    @Environment(\.wwSurfaceLevel) private var surfaceLevel
    @Environment(\.colorSchemeContrast) private var contrast

    init(grade: Binding<ConditionGrade>, isSet: Binding<Bool>, category: CollectibleCategory? = nil) {
        _grade = grade
        _isSet = isSet
        self.category = category
    }

    private var valueText: String {
        isSet ? grade.label(for: category) : "Not sure"
    }

    var body: some View {
        Menu {
            Toggle(isOn: notSureBinding) {
                Text("Not sure")
                Text("We'll price it as typical")
            }
            ForEach(ConditionGrade.menuOrder) { option in
                Toggle(isOn: binding(for: option)) {
                    Text(option.label(for: category))
                    Text(option.detail)
                }
            }
        } label: {
            rowLabel
        }
        .accessibilityLabel("Condition")
        .accessibilityValue(valueText)
        .accessibilityHint("Double-tap to change")
    }

    private var rowLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                titleText
                Spacer(minLength: WW.Space.xs)
                valueGroup
            }
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                titleText
                valueGroup
            }
        }
        .padding(.horizontal, WW.Space.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: WW.Size.rowTall, alignment: .leading)
        .background(surfaceLevel == .elevated ? WW.elevated : WW.surface, in: rowShape)
        .overlay { rowStroke }
        .contentShape(Rectangle())
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
    }

    @ViewBuilder
    private var rowStroke: some View {
        if contrast == .increased {
            rowShape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
        }
    }

    private var titleText: some View {
        Text("Condition")
            .wwFont(.body)
            .foregroundStyle(WW.text)
    }

    private var valueGroup: some View {
        HStack(spacing: 6) {
            Text(valueText)
                .wwFont(.body)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WW.tertiaryText)
                .accessibilityHidden(true)
        }
    }

    private var notSureBinding: Binding<Bool> {
        Binding(
            get: { !isSet },
            set: { newValue in
                guard newValue else { return }
                isSet = false
                grade = .good
                Haptics.selection()
            }
        )
    }

    private func binding(for option: ConditionGrade) -> Binding<Bool> {
        Binding(
            get: { isSet && grade == option },
            set: { newValue in
                guard newValue else { return }
                grade = option
                isSet = true
                Haptics.selection()
            }
        )
    }
}

/// One step of a `StepList`.
struct StepItem: Hashable {
    let title: String
    let detail: String?
    /// Timeline glyph (Today `checkmark`, `calendar`, `creditcard`).
    let icon: String?

    init(title: String, detail: String? = nil, icon: String? = nil) {
        self.title = title
        self.detail = detail
        self.icon = icon
    }
}

/// `.progress` (Scanning, 05 D2): done = `text` circle + check, active =
/// spinner (static `circle.dashed` under Reduce Motion), pending = ring;
/// each step speaks "…, done / in progress / not started" and a new active
/// step is announced. `.timeline` (paywall trial): 28 pt nodes, the first
/// in `accentFill`, joined by a 2 pt `track` line, inside a card.
struct StepList: View {
    enum Style {
        case progress
        case timeline
    }

    private enum StepState {
        case done
        case active
        case pending

        var spoken: String {
            switch self {
            case .done: return "done"
            case .active: return "in progress"
            case .pending: return "not started"
            }
        }
    }

    let steps: [StepItem]
    /// Index of the active step (`.progress`). Steps before it are done.
    let current: Int
    let style: Style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(steps: [StepItem], current: Int = 0, style: Style = .progress) {
        self.steps = steps
        self.current = current
        self.style = style
    }

    var body: some View {
        switch style {
        case .progress:
            progressList
        case .timeline:
            timelineList
        }
    }

    private func state(for index: Int) -> StepState {
        if index < current { return .done }
        if index == current { return .active }
        return .pending
    }

    // MARK: Progress

    private var progressList: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                progressRow(index: index, step: step)
            }
        }
        .animation(WW.Motion.animation(.standard, reduceMotion: reduceMotion), value: current)
        .onChange(of: current) { _, newValue in
            guard steps.indices.contains(newValue) else { return }
            UIAccessibility.post(notification: .announcement, argument: steps[newValue].title)
        }
    }

    private func progressRow(index: Int, step: StepItem) -> some View {
        let rowState = state(for: index)
        return HStack(alignment: .top, spacing: 14) {
            progressNode(rowState)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .wwFont(.headline)
                    .foregroundStyle(rowState == .pending ? WW.secondaryText : WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = step.detail {
                    Text(detail)
                        .wwFont(.footnote)
                        .foregroundStyle(WW.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title), \(rowState.spoken)")
    }

    @ViewBuilder
    private func progressNode(_ nodeState: StepState) -> some View {
        ZStack {
            switch nodeState {
            case .done:
                Circle().fill(WW.text)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WW.inverseText)
            case .active:
                if reduceMotion {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(WW.text)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WW.text)
                }
            case .pending:
                Circle().strokeBorder(WW.track, lineWidth: 2)
            }
        }
        .frame(width: WW.Size.stepNode, height: WW.Size.stepNode)
        .accessibilityHidden(true)
    }

    // MARK: Timeline

    private var timelineList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                timelineRow(index: index, step: step, isLast: index == steps.count - 1)
            }
        }
        .wwCard(padding: WW.Space.md)
    }

    private func timelineRow(index: Int, step: StepItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                timelineNode(index: index, icon: step.icon)
                if !isLast {
                    Rectangle()
                        .fill(WW.track)
                        .frame(width: 2)
                        .frame(minHeight: 16, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = step.detail {
                    Text(detail)
                        .wwFont(.subhead)
                        .foregroundStyle(WW.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 3)
            .padding(.bottom, isLast ? 0 : WW.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timelineNode(index: Int, icon: String?) -> some View {
        let isFirst = index == 0
        return Image(systemName: icon ?? "circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isFirst ? WW.onAccent : WW.text)
            .frame(width: WW.Size.stepNodeTimeline, height: WW.Size.stepNodeTimeline)
            .background(isFirst ? WW.accentFill : WW.fill, in: Circle())
    }
}

/// The system share / activity sheet (UIActivityViewController), for files
/// and rendered images. Present it in a `.sheet`.
struct WWActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    init(items: [Any]) {
        self.items = items
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Bottom bar (05 §2.29)

private struct WWBottomBarModifier<Bar: View>: ViewModifier {
    let pinned: Bool
    let bar: () -> Bar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if !pinned {
            content
        } else {
            pinnedBar(content)
        }
    }

    @ViewBuilder
    private func pinnedBar(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // The bar's only separation on iOS 26 is the scroll edge effect,
            // so it is switched back on here even if an ancestor hid it.
            content
                .scrollEdgeEffectHidden(false, for: .bottom)
                .safeAreaBar(edge: .bottom) {
                    barContent
                }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                barContent
                    .wwBarBackground()
            }
        }
    }

    private var barContent: some View {
        VStack(spacing: WW.Space.xs) {
            bar()
        }
        .padding(.top, WW.Space.sm)
        .padding(.horizontal, WW.margin(for: dynamicTypeSize))
        .padding(.bottom, WW.Space.xs)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    /// A pinned bottom bar (Review, Result, Paywall, guide sheet). Content is
    /// stacked 8 apart: optional banner/failure card, primary, cost line,
    /// secondary. iOS 26: `safeAreaBar` (scroll-edge effect, no fill);
    /// iOS 17–25: `safeAreaInset` + `.bar` material + top hairline.
    /// `pinned: false` draws nothing: the host renders the same content
    /// inline (Result at AX sizes).
    func wwBottomBar<Bar: View>(pinned: Bool = true, @ViewBuilder content: @escaping () -> Bar) -> some View {
        modifier(WWBottomBarModifier(pinned: pinned, bar: content))
    }
}

// MARK: - Mark and wordmark (02 §4.3, 05 §2.27, 06 S1)

/// The Tag: an upright price tag whose eyelet is a lens. 24-unit grid,
/// scaled by `min(w, h) / 24` and centred. Fill with `FillStyle(eoFill: true)`:
/// silhouette, a transparent ring (r 1.75–3.5) and, with `pupil`, a solid pupil.
struct TagShape: Shape {
    var pupil: Bool

    init(pupil: Bool = true) {
        self.pupil = pupil
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        let corners: [(CGPoint, CGFloat)] = [
            (p(15, 1.5), 1.5), (p(19.5, 6), 1.5), (p(19.5, 22.5), 3),
            (p(4.5, 22.5), 3), (p(4.5, 6), 1.5), (p(9, 1.5), 1.5),
        ]
        var path = Path()
        path.move(to: p(12, 1.5))
        for index in corners.indices {
            let next: CGPoint = index + 1 < corners.count ? corners[index + 1].0 : p(12, 1.5)
            path.addArc(tangent1End: corners[index].0, tangent2End: next, radius: corners[index].1 * s)
        }
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: ox + 8.5 * s, y: oy + 4 * s, width: 7 * s, height: 7 * s))
        if pupil {
            path.addEllipse(in: CGRect(x: ox + 10.25 * s, y: oy + 5.75 * s, width: 3.5 * s, height: 3.5 * s))
        }
        return path
    }
}

/// Mark colours (02: accent on app backgrounds, white on dark/photos, ink in mono).
enum MarkTone {
    /// `accent`: nav wordmark, paywall, Settings, empty-state plates.
    case accent
    /// White: Welcome on `brandInk`, share card on a scrim.
    case onDark
    /// `text`: monochrome contexts (Home footer at 35 %).
    case ink

    var color: Color {
        switch self {
        case .accent: return WW.accent
        case .onDark: return Color.white
        case .ink: return WW.text
        }
    }
}

/// The Worthwise mark (the Tag). Minimum 16 pt; decorative (hidden from
/// VoiceOver). `pupilScale` animates the pupil (06 S1: breathe while
/// scanning, open on Welcome / "You're Pro"); at 1 it is the static mark.
struct WorthwiseMark: View {
    let size: CGFloat
    let tone: MarkTone
    let pupilScale: CGFloat

    init(size: CGFloat = 32, tone: MarkTone = .accent, pupilScale: CGFloat = 1) {
        self.size = size
        self.tone = tone
        self.pupilScale = pupilScale
    }

    private var side: CGFloat { max(size, 16) }
    private var pupilDiameter: CGFloat { side * 3.5 / 24 }
    /// The eyelet centre (12, 7.5) relative to the frame centre (12, 12).
    private var pupilOffset: CGFloat { side * (7.5 - 12) / 24 }

    var body: some View {
        ZStack {
            TagShape(pupil: false)
                .fill(tone.color, style: FillStyle(eoFill: true))
            Circle()
                .fill(tone.color)
                .frame(width: pupilDiameter, height: pupilDiameter)
                .scaleEffect(pupilScale)
                .offset(y: pupilOffset)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The mark with its pupil breathing (Scanning, 06 M8). Static under Reduce Motion.
struct WWBreathingMark: View {
    let size: CGFloat
    let tone: MarkTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGFloat = 28, tone: MarkTone = .accent) {
        self.size = size
        self.tone = tone
    }

    var body: some View {
        if reduceMotion {
            WorthwiseMark(size: size, tone: tone)
        } else {
            PhaseAnimator(WW.Motion.breathePhases) { phase in
                WorthwiseMark(size: size, tone: tone, pupilScale: phase)
            } animation: { _ in
                Animation.easeInOut(duration: WW.Motion.breathePhaseDuration)
            }
        }
    }
}

/// Mark + "Worthwise" in New York Semibold. Mark = 1.45 × font size; visible
/// gap 0.3 × mark; the mark is centred on the cap height. Both sizes scale
/// with Dynamic Type (cap it in bars: `WWBrandTitle` uses `...xxLarge`).
/// One VoiceOver element: "Worthwise".
struct WorthwiseWordmark: View {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    let markSize: CGFloat
    let fontSize: CGFloat
    let tone: MarkTone

    init(markSize: CGFloat = 28, fontSize: CGFloat = 19, tone: MarkTone = .accent) {
        self.markSize = markSize
        self.fontSize = fontSize
        self.tone = tone
    }

    private var scaledMark: CGFloat { markSize * scale }
    private var scaledFont: CGFloat { fontSize * scale }
    private var textColor: Color { tone == .onDark ? Color.white : WW.text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.1125 * scaledMark) {
            WorthwiseMark(size: scaledMark, tone: tone)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions.height / 2 + 0.35 * scaledFont
                }
            Text("Worthwise")
                .font(.system(size: scaledFont, weight: .semibold, design: .serif))
                .tracking(-0.2)
                .foregroundStyle(textColor)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Worthwise")
    }
}

// MARK: - Contracts (04 §2.1, §7) — shared by WP1–WP5

/// The three tabs. Moved verbatim from ContentView (04 §11.1 move 3).
enum AppTab: Hashable {
    case scan, collection, settings
}

/// Why the paywall is opening, which decides its headline.
enum PaywallRoute: String, Identifiable {
    case general, limitReached, listings
    var id: String { rawValue }

    var context: ProPaywallView.Context {
        switch self {
        case .general: return .general
        case .limitReached: return .limitReached
        case .listings: return .unlockListings
        }
    }
}

/// Where a new scan's photo comes from.
enum ScanSource: Equatable {
    case camera
    case library
}

/// How a stored record is scanned again (04 §5.3).
enum RescanMode: Equatable {
    /// Back to Review with the stored photos.
    case editPhotos
    /// "Not the right item?": scan again at once with the user's hint.
    case withHint(String)
    /// "Check Price Again": scan again at once, result replaces the record.
    case checkPriceAgain
}

/// App-wide navigation, injected by `ContentView` as an environment object.
/// `ContentView` sets the closures; everyone else calls them.
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .scan
    /// Root paywall sheet. Never used while `ScanFlowView` is up.
    @Published var paywall: PaywallRoute? = nil
    /// Applies the scan gate (04 §5.2) before any camera or picker opens.
    var startScan: (ScanSource) -> Void = { _ in }
    /// Seeds the scan flow from a stored record.
    var rescan: (_ recordID: UUID, _ mode: RescanMode) -> Void = { _, _ in }
    /// Closes any flow and selects the Settings tab.
    var openSettings: () -> Void = {}

    init() {}
}

/// What a `ResultView` host passes in (04 §7). `ResultView` performs record
/// mutations itself through `CollectionStore`; hosts pass navigation only.
struct ResultContext {
    enum Origin: Equatable {
        case freshScan
        case stored
    }

    var origin: Origin
    /// `vm.resultRecordID` (fresh) or the stored record's id.
    var recordID: UUID?
    /// Set when this result re-checks a stored record ("Replace saved item").
    var replacing: UUID?
    /// `vm.lastScanCharged` (04 §10 S4): D copy says "It didn't use a scan."
    /// only when this is `false`. nil = unknown. (Addition to 04's list.)
    var scanCharged: Bool?
    /// Fresh only: "Done".
    var onDone: (() -> Void)?
    var onScanNext: (() -> Void)?
    /// Fresh: back to Review (+ hint); stored: `router.rescan`.
    var onRescan: ((RescanMode) -> Void)?
    /// nil when Pro.
    var onUnlock: (() -> Void)?
    /// The host closes (fresh) or pops (stored).
    var onDeleted: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(
        origin: Origin,
        recordID: UUID? = nil,
        replacing: UUID? = nil,
        scanCharged: Bool? = nil,
        onDone: (() -> Void)? = nil,
        onScanNext: (() -> Void)? = nil,
        onRescan: ((RescanMode) -> Void)? = nil,
        onUnlock: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.origin = origin
        self.recordID = recordID
        self.replacing = replacing
        self.scanCharged = scanCharged
        self.onDone = onDone
        self.onScanNext = onScanNext
        self.onRescan = onRescan
        self.onUnlock = onUnlock
        self.onDeleted = onDeleted
        self.onOpenSettings = onOpenSettings
    }

    var isFresh: Bool { origin == .freshScan }
}

/// A short confirmation with an optional action ("Undo"). Show it with
/// `.wwToast($toast)`; setting a new one replaces the current one.
struct WWToastModel: Identifiable, Equatable {
    let id: UUID
    let message: String
    /// Shows the `checkmark.circle` glyph.
    var isSuccess: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    init(message: String, isSuccess: Bool = true, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.id = UUID()
        self.message = message
        self.isSuccess = isSuccess
        self.actionTitle = actionTitle
        self.action = action
    }

    static func == (lhs: WWToastModel, rhs: WWToastModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - iOS 26 layer (04 §8.5)

extension View {
    /// Removed in the redesign (04 §2.4): the tab bar no longer minimises.
    /// Kept as a no-op so ContentView compiles until WP1 deletes the call.
    @available(*, deprecated, message: "Removed in the redesign (04 §2.4). Delete the call.")
    func wwTabBarMinimizesOnScroll() -> some View {
        self
    }

    /// iOS 26: no scroll edge effect under the floating tab bar. On the
    /// pure-black dark background the effect reads as an opaque black band,
    /// and the glass tab bar sits half in and half out of it. The glass keeps
    /// its own labels legible, so content simply scrolls under it.
    /// Apply it to a tab's ROOT scroll view or list only (directly on it,
    /// before its `.sheet` / `.navigationDestination` modifiers), never to the
    /// tab or its NavigationStack: pushed screens and sheets must keep the
    /// edge effect, which is the only separation of an iOS 26 bottom bar.
    @ViewBuilder
    func wwContentUnderTabBar() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            self
        }
    }

    /// A compact navigation bar with the Worthwise mark and name on the
    /// leading side instead of a title. `title` stays the screen's name for
    /// VoiceOver and back-button menus but is not drawn (iOS 18+).
    /// On iOS 26 the brand sits directly on the bar, not inside a glass
    /// capsule: it is a label, not a button.
    @ViewBuilder
    func wwBrandNavigationBar(title: String) -> some View {
        let base = self.navigationBarTitleDisplayMode(.inline)
        if #available(iOS 26.0, *) {
            base
                .navigationTitle(title)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { WWBrandTitle() }
                        .sharedBackgroundVisibility(.hidden)
                }
        } else if #available(iOS 18.0, *) {
            base
                .navigationTitle(title)
                .toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { WWBrandTitle() }
                }
        } else {
            base
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { WWBrandTitle() }
                }
        }
    }
}

/// The brand as it appears in the navigation bar.
private struct WWBrandTitle: View {
    var body: some View {
        WorthwiseWordmark(markSize: 28, fontSize: 19)
            // A bar has a fixed height: let the name grow a little, not wrap.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Previews (light, dark, AX3; Increase Contrast via Environment Overrides)

#if DEBUG
private struct WWComponentGallery: View {
    @State private var grade: ConditionGrade = .good
    @State private var gradeIsSet = false
    @State private var toast: WWToastModel? = WWToastModel(message: "Moved to Kitchen", actionTitle: "Undo", action: {})

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WW.Space.sectionGap) {
                brandSection
                buttonSection
                valueSection
                evidenceSection
                rowSection
                stateSection
            }
            .padding(.horizontal, WW.Space.margin)
            .padding(.vertical, WW.Space.xl)
        }
        .background(WW.background)
        .wwToast($toast)
    }

    private var brandSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WorthwiseWordmark()
            HStack(spacing: WW.Space.md) {
                WorthwiseMark(size: 40)
                WorthwiseMark(size: 22, tone: .ink)
                WWBreathingMark()
            }
        }
        .wwSection("Brand")
    }

    private var buttonSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            Button("Save to collection") {}.buttonStyle(.wwPrimary)
            Button("Scan next") {}.buttonStyle(.wwSecondary)
            Button("Delete My Data") {}.buttonStyle(.wwDestructive)
            Button("Not the right item?") {}.buttonStyle(WWTertiaryButtonStyle(.accent, .small))
            Button {} label: { WWOnPhotoButtonLabel(systemImage: "crop", showsBadge: true) }
                .buttonStyle(WWOnPhotoButtonStyle())
                .background(WW.photoBackdrop)
        }
        .wwSection("Buttons")
    }

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            Text("Estimated value").wwFont(.subhead).foregroundStyle(WW.secondaryText)
            ValueRangeText(lowUSD: 310, highUSD: 420)
            RangeBar(lowUSD: 310, highUSD: 420, bestUSD: 365, salesUSD: [300, 340, 365, 370, 380, 410, 520])
            ValueRangeText(lowUSD: 19_781, highUSD: 4_442_869, role: .priceCompact)
                .frame(width: 111, alignment: .leading)
            CaveatFlag.roughGuide()
            CaveatFlag(.salesHigher(medianUSD: 0.48, count: 12))
            MatchIndicator(strength: .close)
            MatchIndicator(strength: .possible)
        }
        .wwCard()
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            HStack(spacing: WW.Space.xs) {
                EvidenceBadge(kind: .sold)
                EvidenceBadge(kind: .guide)
                EvidenceBadge(kind: .asking)
                EvidenceBadge(kind: .aiEstimate)
            }
            EvidenceLine(kind: .asking, text: "From 6 listings", isExact: false)
            EvidenceRow(kind: .sold, title: "Sep 30 · eBay", detail: "Near mint", priceUSD: 365,
                        url: URL(string: "https://www.ebay.com"))
                .wwCard(padding: 0)
        }
        .wwSection("Evidence")
    }

    private var rowSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            WWInfoRow(icon: "checkmark.seal", title: "Sold prices first", detail: "We say when we only found asking prices.")
            WWInfoRow(number: 2, title: "Check the market")
            ConditionPicker(grade: $grade, isSet: $gradeIsSet, category: .tradingCard)
            StepList(steps: [StepItem(title: "Reading the photo", detail: "Names, numbers and marks"),
                             StepItem(title: "Identifying the item"),
                             StepItem(title: "Checking prices")], current: 1)
            StepList(steps: [StepItem(title: "Today", detail: "Full Pro access, free.", icon: "checkmark"),
                             StepItem(title: "Oct 20", detail: "Your trial ends.", icon: "creditcard")],
                     style: .timeline)
        }
        .wwSection("Rows")
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            WWEmptyState(glyph: "folder", title: "Nothing in Kitchen yet",
                         message: "Add items from your collection. They stay in Items too.",
                         actionTitle: "Add items", actionImage: "plus", action: {})
            WWEmptyState(title: "Your scans appear here",
                         message: "Save the ones you want to keep. We hold on to your last 50 unsaved scans.",
                         style: .inline, illustration: AnyView(WWGhostTiles()))
            WWSheetHeader(title: "What is it?", subtitle: "Type its name and anything printed on it.",
                          systemImage: "questionmark.circle")
        }
    }
}

#Preview("Components · light") {
    WWComponentGallery()
}

#Preview("Components · dark") {
    WWComponentGallery()
        .preferredColorScheme(.dark)
}

#Preview("Components · AX3") {
    WWComponentGallery()
        .dynamicTypeSize(.accessibility3)
}
#endif
