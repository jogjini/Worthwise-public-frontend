import SwiftUI
import UIKit

/// The Settings tab: plan, account, scanning, appearance, prices, collection,
/// support and data (04 §6.11, 05 §2.30 / §3.13).
///
/// Two rows here are compliance obligations rather than conveniences:
/// **Cloud Photo Analysis** must be revocable after first run (Guideline
/// 5.1.2(i), GDPR Art. 7(3)), and **Delete My Data / Delete Account** must
/// exist and be findable (Guideline 5.1.1(v), GDPR Art. 17).
///
/// Dialog rule (04 §2.2, the fix for the GDPR bug): every alert and
/// confirmation dialog is attached to the control that triggers it, never to
/// the NavigationStack, and no view carries more than one of each. Two
/// dialogs chained on one NavigationStack meant only one of them could ever
/// show, so consent could not be turned off.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.openURL) private var openURL

    @State private var showPaywall = false
    @State private var showConsentDetails = false
    @State private var showHowItWorks = false
    @State private var showConsentRevokeAlert = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var isRestoring = false
    @State private var isExporting = false
    @State private var exportFile: SettingsExportFile?
    @State private var planMessage: SettingsStatusLine?
    @State private var accountMessage: SettingsStatusLine?
    @State private var collectionMessage: SettingsStatusLine?
    @State private var dataMessage: SettingsStatusLine?

    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            settingsList
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
        }
        .onDisappear {
            // Messages answer the last tap; they don't outlive the visit (12 Oct run, bug 11).
            planMessage = nil
            accountMessage = nil
            collectionMessage = nil
        }
    }

    /// Native inset-grouped list with system colours (05 §2.30: don't
    /// override `scrollContentBackground`). The navigation layer stays
    /// monochrome: `.tint(WW.text)`.
    private var settingsList: some View {
        List {
            brandHeader
            planSection
            accountSection
            scanningSection
            appearanceSection
            pricesSection
            collectionSection
            supportSection
            dataSection
        }
        .listStyle(.insetGrouped)
        .tint(WW.text)
        // The tab root only, applied before the paywall `.sheet` so the
        // sheet's pinned bar keeps its edge effect on iOS 26.
        .wwContentUnderTabBar()
        // The paywall lives on the list, not on the "See Pro plans" row: that row
        // disappears the moment a purchase succeeds, and must not take the
        // paywall's "You're Pro" state down with it.
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(context: .general)
                .environmentObject(creditManager)
                .environmentObject(authManager)
                .environmentObject(settings)
                .environmentObject(collectionStore)
        }
    }

    // MARK: - Brand header

    /// Wordmark at font 26 → mark 38 (05 D11). No tagline here: in-app the
    /// tagline appears only on Welcome and in How It Works (00 decisions).
    /// Long-pressing the Tag makes it look around (06 E2).
    private var brandHeader: some View {
        Section {
            SettingsBrandHeader()
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WW.Space.xs)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: - Plan (ST1)

    private var planSection: some View {
        Section {
            if creditManager.isPro {
                proPlanRow
                manageSubscriptionRow
            } else {
                freePlanRow
            }
            restoreRow
            if let planMessage {
                statusText(planMessage)
            }
        } header: {
            sectionHeader("Plan")
        }
    }

    private var freeScansText: String {
        // Unknown count (first credit check failed): no number we can't stand behind.
        guard creditManager.hasServerCount else { return "" }
        let n = creditManager.freeScansLeft
        if n <= 0 { return "No free scans" }
        if n == 1 { return "1 free scan" }
        return "\(n) free scans"
    }

    /// "Free" + "{n} free scans", then the one Lapis button on this screen.
    private var freePlanRow: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            LabeledContent {
                Text(freeScansText)
                    .wwFont(.body)
                    .foregroundStyle(WW.secondaryText)
            } label: {
                Text("Free")
                    .wwFont(.body)
                    .foregroundStyle(WW.text)
            }
            Button("See Pro plans") {
                showPaywall = true
            }
            .buttonStyle(WWPrimaryButtonStyle(size: .compact))
        }
        .padding(.vertical, WW.Space.xxs)
    }

    private var proPlanName: String {
        switch creditManager.activeProductID {
        case let id? where id.contains("week"): return "Pro · Weekly"
        case let id? where id.contains("month"): return "Pro · Monthly"
        case let id? where id.contains("year") || id.contains("annual"): return "Pro · Yearly"
        default: return "Pro"
        }
    }

    private var renewalText: String? {
        guard let date = creditManager.proExpiresAt else { return nil }
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        // Same words as the paywall's Pro status (during a trial the
        // entitlement's expiry is the trial's last day).
        if creditManager.isInTrial { return "Trial ends \(formatted)" }
        return creditManager.willRenew ? "Renews \(formatted)" : "Ends \(formatted)"
    }

    /// "12 of 250 scans used · resets Nov 1".
    private var usageText: String? {
        guard let used = creditManager.scansUsed, let limit = creditManager.scanLimit, limit > 0 else { return nil }
        var text = "\(min(used, limit)) of \(limit) scans used"
        if let reset = creditManager.periodEndsAt {
            text += " · resets " + reset.formatted(.dateTime.month(.abbreviated).day())
        }
        return text
    }

    private var proPlanRow: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(proPlanName)
                    .wwFont(.body)
                    .foregroundStyle(WW.text)
                if let renewalText {
                    Text(renewalText)
                        .wwFont(.subhead)
                        .foregroundStyle(WW.secondaryText)
                }
            }
            if let usageText, let used = creditManager.scansUsed, let limit = creditManager.scanLimit, limit > 0 {
                ProgressView(value: Double(min(used, limit)), total: Double(limit))
                    .tint(WW.text)
                    .accessibilityHidden(true)
                Text(usageText)
                    .wwFont(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, WW.Space.xxs)
        .accessibilityElement(children: .combine)
    }

    private var manageSubscriptionRow: some View {
        Button {
            if let url = Self.manageSubscriptionsURL {
                openURL(url)
            }
        } label: {
            SettingsRowLabel(title: "Manage Subscription", systemImage: "creditcard", external: true)
        }
        .accessibilityHint("Opens your App Store subscriptions")
    }

    private var restoreRow: some View {
        Button {
            Task { await restorePurchases() }
        } label: {
            HStack {
                Label(isRestoring ? "Restoring…" : "Restore Purchases", systemImage: "arrow.clockwise")
                    .foregroundStyle(WW.text)
                if isRestoring {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isRestoring)
    }

    // MARK: - Account (ST2, ST3)

    private var accountSection: some View {
        Section {
            if authManager.isSignedIn {
                LabeledContent("Apple ID", value: shortAppleID)
                Button {
                    authManager.signOut()
                    setMessage(SettingsStatusLine("Signed out. Sign in again any time to restore your plan."), for: .account)
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(WW.text)
                }
                .disabled(isDeletingAccount)
            } else {
                AppleSignInButton(onStart: { accountMessage = nil }) { outcome in
                    handleSignIn(outcome)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            if let accountMessage {
                statusText(accountMessage)
            }
        } header: {
            sectionHeader("Account")
        } footer: {
            if !authManager.isSignedIn {
                footerText("Optional. Keeps your plan linked to your Apple ID across reinstalls and devices. Pro can always be restored with Restore Purchases.")
            }
        }
    }

    /// The Apple user identifier is long and opaque; the last few characters are
    /// enough to tell two Apple IDs apart without showing the whole token.
    private var shortAppleID: String {
        guard let id = authManager.appleUserID, id.count > 6 else { return "Linked" }
        return "…" + String(id.suffix(6))
    }

    private func handleSignIn(_ outcome: AppleSignInButton.Outcome) {
        switch outcome {
        case .signedIn:
            setMessage(SettingsStatusLine("Signed in. Your plan is now synced."), for: .account)
        case .cancelled:
            accountMessage = nil
        case .failed:
            // Fixed copy, never the raw error (04 ST3, 06 §4.3).
            setMessage(SettingsStatusLine(AppleSignInButton.failureMessage, isError: true), for: .account)
        }
    }

    // MARK: - Scanning (ST4)

    private var scanningSection: some View {
        Section {
            consentToggle
            whatWeSendRow
            reviewToggle
        } header: {
            sectionHeader("Scanning")
        } footer: {
            footerText(settings.aiConsentGranted
                       ? "Your photos are sent to AI and image-search services to identify the item."
                       : "Off: scans run on this iPhone only. We can't identify items or check prices.")
        }
    }

    /// ON → OFF asks first (the toggle stays on until confirmed); OFF → ON
    /// needs no confirmation (04 §5.6). The alert is attached to this Toggle
    /// and nothing else (04 §2.2).
    private var consentBinding: Binding<Bool> {
        Binding(
            get: { settings.aiConsentGranted },
            set: { newValue in
                if newValue {
                    settings.setAIConsent(true)
                } else {
                    showConsentRevokeAlert = true
                }
            }
        )
    }

    private var consentToggle: some View {
        Toggle(isOn: consentBinding) {
            Text("Cloud Photo Analysis")
                .wwFont(.body)
                .foregroundStyle(WW.text)
        }
        .tint(Color(uiColor: .systemGreen))
        .alert("Turn off photo analysis?", isPresented: $showConsentRevokeAlert) {
            // Not `.destructive`: withdrawing consent must be as easy and as
            // neutral as giving it (GDPR Art. 7(3); 02: no nudging on consent).
            Button("Turn Off") {
                settings.setAIConsent(false)
            }
            Button("Keep On", role: .cancel) {}
        } message: {
            Text("We'll only read text and barcodes on this iPhone. We won't identify items or check prices.")
        }
    }

    private var whatWeSendRow: some View {
        Button {
            showConsentDetails = true
        } label: {
            SettingsRowLabel(title: "What We Send", systemImage: "info.circle")
        }
        .sheet(isPresented: $showConsentDetails) {
            AIConsentSheet()
        }
    }

    private var reviewToggle: some View {
        Toggle(isOn: $settings.reviewBeforeScan) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Photos Before Scanning")
                    .wwFont(.body)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Off: the scan starts as soon as you take the photo. You can edit the condition and notes on the result.")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color(uiColor: .systemGreen))
    }

    // MARK: - Appearance

    /// Turning haptics on plays one selection tick as a sample (06 M32).
    /// Turning them off does nothing.
    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { settings.hapticsEnabled },
            set: { newValue in
                settings.hapticsEnabled = newValue
                if newValue {
                    Haptics.selection()
                }
            }
        )
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $settings.theme) {
                ForEach(AppSettings.Theme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            } label: {
                Text("Theme")
                    .wwFont(.body)
                    .foregroundStyle(WW.text)
            }
            .pickerStyle(.menu)

            Toggle(isOn: hapticsBinding) {
                Text("Haptics")
                    .wwFont(.body)
                    .foregroundStyle(WW.text)
            }
            .tint(Color(uiColor: .systemGreen))
        } header: {
            sectionHeader("Appearance")
        }
    }

    // MARK: - Prices

    private var pricesSection: some View {
        Section {
            Picker(selection: $settings.displayCurrency) {
                ForEach(DisplayCurrency.supported, id: \.self) { code in
                    Text("\(DisplayCurrency.name(code)) (\(code))").tag(code)
                }
            } label: {
                Text("Currency")
                    .wwFont(.body)
                    .foregroundStyle(WW.text)
            }
            .pickerStyle(.navigationLink)
        } header: {
            sectionHeader("Prices")
        } footer: {
            footerText("Prices are found in many currencies and converted with the European Central Bank's rates of \(DisplayCurrency.ratesDate). Your collection converts too.")
        }
    }

    // MARK: - Collection (ST7)

    private var collectionSection: some View {
        Section {
            exportRow
            if let collectionMessage {
                statusText(collectionMessage)
            }
        } header: {
            sectionHeader("Collection")
        } footer: {
            if collectionStore.items.isEmpty {
                footerText("Save an item to your collection to enable export.")
            }
        }
    }

    private var exportRow: some View {
        Button {
            startExport()
        } label: {
            HStack {
                Label(isExporting ? "Preparing…" : "Export Spreadsheet", systemImage: "square.and.arrow.up")
                if isExporting {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(collectionStore.items.isEmpty || isExporting)
        .sheet(item: $exportFile) { file in
            // Same item as Collection's export: Mail gets the 06 §4.4 subject.
            WWActivitySheet(items: [CollectionCSVActivityItem(url: file.url)])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        Section {
            Button {
                showHowItWorks = true
            } label: {
                SettingsRowLabel(title: "How It Works", systemImage: "questionmark.circle")
            }
            .sheet(isPresented: $showHowItWorks) {
                HowItWorksSheet()
            }

            Link(destination: AppConfig.supportURL) {
                SettingsRowLabel(title: "Help & Support", systemImage: "lifepreserver", external: true)
            }
            .accessibilityHint("Opens in Safari")

            Link(destination: AppConfig.privacyURL) {
                SettingsRowLabel(title: "Privacy Policy", systemImage: "hand.raised", external: true)
            }
            .accessibilityHint("Opens in Safari")

            Link(destination: AppConfig.termsURL) {
                SettingsRowLabel(title: "Terms of Use", systemImage: "doc.text", external: true)
            }
            .accessibilityHint("Opens in Safari")
        } header: {
            sectionHeader("Support")
        }
    }

    // MARK: - Data (ST5, ST6)

    private var deleteTitle: String {
        authManager.isSignedIn ? "Delete Account" : "Delete My Data"
    }

    private var deleteDialogTitle: String {
        authManager.isSignedIn ? "Delete your account?" : "Delete your data from our server?"
    }

    private var deleteDialogMessage: String {
        let base: String = authManager.isSignedIn
            ? "This permanently deletes your account data and signs you out. Items on this iPhone stay."
            : "This erases your free-scan count and plan link for this install. Items on this iPhone stay."
        guard creditManager.isPro else { return base }
        return base + " It doesn't cancel Worthwise Pro. Cancel it in Settings › your name › Subscriptions."
    }

    private var deleteFooter: String {
        authManager.isSignedIn
            ? "Permanently deletes your account data and revokes Sign in with Apple. It doesn't cancel Worthwise Pro. Items on this iPhone stay."
            : "Erases the data we hold for this install on our server. It doesn't cancel Worthwise Pro. Items on this iPhone stay."
    }

    private var dataSection: some View {
        Section {
            deleteButton
            if let dataMessage {
                statusText(dataMessage)
            }
        } header: {
            sectionHeader("Data")
        } footer: {
            VStack(alignment: .leading, spacing: WW.Space.md) {
                footerText(deleteFooter)
                Text("Worthwise \(versionString)")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, WW.Space.xs)
            }
        }
    }

    /// Guideline 5.1.1(v) / GDPR Art. 17. Named "Delete My Data" when not
    /// signed in. The dialog is attached to this button (04 §2.2), so on iOS 26
    /// its popover points at the row, and it always shows a Cancel button.
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack {
                Text(isDeletingAccount ? "Deleting…" : deleteTitle)
                    .wwFont(.body)
                    .foregroundStyle(WW.danger)
                if isDeletingAccount {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isDeletingAccount)
        .confirmationDialog(deleteDialogTitle, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(deleteTitle, role: .destructive) {
                Task { await deleteData() }
            }
            Button("Cancel", role: WW.dialogCancelRole) {}
        } message: {
            Text(deleteDialogMessage)
        }
    }

    // MARK: - Shared row pieces

    /// Title Case on iOS 17 and 26 (iOS 17 uppercases headers by default).
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .textCase(nil)
    }

    /// Footers use `secondaryText` explicitly (system secondaryLabel is weaker in light).
    private func footerText(_ text: String) -> some View {
        Text(text)
            .wwFont(.footnote)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusText(_ line: SettingsStatusLine) -> some View {
        Text(line.text)
            .wwFont(.footnote)
            .foregroundStyle(line.isError ? WW.danger : WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private enum MessageSlot {
        case plan, account, collection, data
    }

    /// Sets a status line and reads it out for VoiceOver.
    private func setMessage(_ line: SettingsStatusLine, for slot: MessageSlot) {
        switch slot {
        case .plan: planMessage = line
        case .account: accountMessage = line
        case .collection: collectionMessage = line
        case .data: dataMessage = line
        }
        UIAccessibility.post(notification: .announcement, argument: line.text)
    }

    // MARK: - Actions

    private func restorePurchases() async {
        isRestoring = true
        planMessage = nil

        do {
            let isPro = try await creditManager.restorePurchases()
            if isPro {
                Haptics.notify(.success)
                setMessage(SettingsStatusLine("Pro restored."), for: .plan)
            } else {
                setMessage(SettingsStatusLine("We couldn't find a Pro subscription for this Apple ID."), for: .plan)
            }
        } catch {
            Haptics.notify(.error)
            setMessage(SettingsStatusLine("Restore didn't finish. Check your connection and try again.", isError: true), for: .plan)
        }

        isRestoring = false
    }

    /// "Preparing…" first, then the share sheet (06 §4.4). The file is built
    /// on tap, not on every visit to Settings.
    private func startExport() {
        guard !isExporting else { return }
        isExporting = true
        collectionMessage = nil
        Task { @MainActor in
            // Let "Preparing…" draw before the (synchronous) export runs.
            try? await Task.sleep(nanoseconds: 60_000_000)
            let url: URL? = collectionStore.exportCSVFile()
            isExporting = false
            if let url {
                exportFile = SettingsExportFile(url: url)
            } else {
                setMessage(SettingsStatusLine("Couldn't create the spreadsheet. Try again.", isError: true), for: .collection)
            }
        }
    }

    private func deleteData() async {
        isDeletingAccount = true
        dataMessage = nil

        do {
            let result = try await authManager.deleteAccount()
            creditManager.resetLocal()
            Telemetry.log(.accountDeleted(appleRevoked: result.appleCredentialRevoked ?? false))
            setMessage(SettingsStatusLine("Your data was deleted from our server."), for: .data)
        } catch AuthManager.DeletionError.reauthorizationCancelled {
            setMessage(SettingsStatusLine("Nothing was deleted. Confirm with Apple to delete your account.", isError: true), for: .data)
        } catch {
            // Fixed copy, never `error.localizedDescription` (06 §4.3).
            setMessage(SettingsStatusLine("Couldn't delete your data. Check your connection and try again.", isError: true), for: .data)
        }

        isDeletingAccount = false
    }
}

// MARK: - Small types

/// One line of feedback under a row ("Pro restored.", a failure).
private struct SettingsStatusLine: Equatable {
    let text: String
    let isError: Bool

    init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }
}

/// The CSV handed to the share sheet.
private struct SettingsExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Row label

/// Icon + title + chevron (or an outbound arrow for links that leave the app).
private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var external = false

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(WW.text)
            Spacer(minLength: WW.Space.xs)
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WW.tertiaryText)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Brand header and E2 "The Tag looks around"

/// The Settings lockup (05 §2.27 geometry, at font 26 → mark 38), built here
/// rather than with `WorthwiseWordmark` so the Tag's pupil can move for 06 E2.
/// One VoiceOver element, "Worthwise"; the easter egg is decorative.
private struct SettingsBrandHeader: View {
    /// Scales like the wordmark's 26 pt text (title2); the host caps it at xxLarge.
    @ScaledMetric(relativeTo: .title2) private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lookCount = 0

    private let markSize: CGFloat = 38
    private let fontSize: CGFloat = 26

    private var scaledMark: CGFloat { markSize * scale }
    private var scaledFont: CGFloat { fontSize * scale }

    private var wordSpec: WWTextSpec {
        WWTextSpec(size: fontSize, weight: .semibold, design: .serif, tracking: -0.2, maxSize: .xxLarge)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0.1125 * scaledMark) {
            LookingTag(size: scaledMark, trigger: lookCount, reduceMotion: reduceMotion)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions.height / 2 + 0.35 * scaledFont
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.5) {
                    lookCount += 1
                }
            Text("Worthwise")
                .wwFont(spec: wordSpec)
                .foregroundStyle(WW.text)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Worthwise")
    }
}

/// The pupil's pose for E2, in 24-grid units for the offset.
private struct TagPose {
    var pupilX: Double = 0
    var pupilScale: Double = 1
    var pupilOpacity: Double = 1
}

/// The Tag with a pupil that glances left, right, back, then blinks
/// (06 E2, 1.2 s). The glance stays inside the ring gap (pupil r 1.75 + 1.0
/// < eyelet r 3.5). Reduce Motion: only the blink, as an opacity dip.
/// No haptic, no copy.
private struct LookingTag: View {
    let size: CGFloat
    let trigger: Int
    let reduceMotion: Bool

    private var side: CGFloat { max(size, 16) }

    var body: some View {
        Group {
            if reduceMotion {
                blinkOnly
            } else {
                lookAround
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var lookAround: some View {
        KeyframeAnimator(initialValue: TagPose(), trigger: trigger) { pose in
            mark(pose)
        } keyframes: { _ in
            KeyframeTrack(\TagPose.pupilX) {
                CubicKeyframe(-1.0, duration: 0.25)
                LinearKeyframe(-1.0, duration: 0.1)
                CubicKeyframe(1.0, duration: 0.35)
                CubicKeyframe(0.0, duration: 0.2)
                LinearKeyframe(0.0, duration: 0.3)
            }
            KeyframeTrack(\TagPose.pupilScale) {
                LinearKeyframe(1.0, duration: 0.9)
                CubicKeyframe(0.0, duration: 0.15)
                CubicKeyframe(1.0, duration: 0.15)
            }
        }
    }

    private var blinkOnly: some View {
        KeyframeAnimator(initialValue: TagPose(), trigger: trigger) { pose in
            mark(pose)
        } keyframes: { _ in
            KeyframeTrack(\TagPose.pupilOpacity) {
                LinearKeyframe(0.0, duration: 0.15)
                LinearKeyframe(1.0, duration: 0.15)
            }
        }
    }

    private func mark(_ pose: TagPose) -> some View {
        let unit: CGFloat = side / 24
        let pupilDiameter: CGFloat = side * 3.5 / 24
        let pupilY: CGFloat = side * (7.5 - 12) / 24
        return ZStack {
            TagShape(pupil: false)
                .fill(WW.accent, style: FillStyle(eoFill: true))
            Circle()
                .fill(WW.accent)
                .frame(width: pupilDiameter, height: pupilDiameter)
                .scaleEffect(CGFloat(pose.pupilScale))
                .opacity(pose.pupilOpacity)
                .offset(x: CGFloat(pose.pupilX) * unit, y: pupilY)
        }
        .frame(width: side, height: side)
    }
}
