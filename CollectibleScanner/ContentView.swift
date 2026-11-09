import AVFoundation
import PhotosUI
import StoreKit
import SwiftUI
import UIKit

// MARK: - Root

/// Three native tabs (no minimise-on-scroll, 04 §2.4). The scan flow, the
/// camera, the library picker and the root paywall are presented here, so any
/// tab can start or redo a scan through `AppRouter` (04 §2.1).
struct ContentView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.requestReview) private var requestReview

    @StateObject private var viewModel = ScannerViewModel()
    @StateObject private var router = AppRouter()
    /// Router closures only write here (reference types), and this view
    /// reacts in `onChange`, so no closure ever holds a stale copy of the view.
    @StateObject private var requests = ScanRequests()

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    /// "Choose from library" inside the camera: open the picker once the camera is gone.
    @State private var libraryAfterCamera = false
    @State private var rootAlert: RootAlert?
    /// What to do once the scan flow has fully closed ("Scan next").
    @State private var afterFlow: ScanSource?

    var body: some View {
        withAlerts
            .onAppear(perform: wireUp)
            .onChange(of: requests.scan) { _, request in
                guard let request else { return }
                requests.scan = nil
                startScan(request.source)
            }
            .onChange(of: requests.rescan) { _, request in
                guard let request else { return }
                requests.rescan = nil
                rescan(request.id, request.mode)
            }
            .onChange(of: requests.settingsToken) { _, _ in
                openSettings()
            }
    }

    // MARK: Layers (split so each stays quick to type-check)

    private var tabs: some View {
        // `.wwContentUnderTabBar()` sits on each tab's root scroll view, not
        // here, so pushed screens and sheets keep their bottom edge effect.
        TabView(selection: $router.tab) {
            ScanHomeView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
                .tag(AppTab.scan)

            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
                .tag(AppTab.collection)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(WW.text)
        .environmentObject(router)
    }

    private var withCamera: some View {
        tabs
            .fullScreenCover(isPresented: $showCamera, onDismiss: cameraDidDismiss) {
                CameraPicker(image: $capturedImage, onChooseLibrary: { libraryAfterCamera = true })
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images, photoLibrary: .shared())
            .onChange(of: libraryItem) { _, item in
                loadLibraryItem(item)
            }
    }

    private var withPaywall: some View {
        withCamera
            .sheet(item: $router.paywall) { route in
                ProPaywallView(context: route.context)
                    .environmentObject(creditManager)
                    .environmentObject(authManager)
                    .environmentObject(settings)
                    .environmentObject(router)
            }
    }

    private var withFlow: some View {
        withPaywall
            .fullScreenCover(isPresented: flowBinding, onDismiss: flowDidDismiss) {
                ScanFlowView(
                    viewModel: viewModel,
                    onScanNext: scanNextFromFlow,
                    onOpenSettings: { requests.settingsToken += 1 }
                )
                .environmentObject(collectionStore)
                .environmentObject(creditManager)
                .environmentObject(authManager)
                .environmentObject(settings)
                .environmentObject(router)
            }
    }

    private var withAlerts: some View {
        withFlow
            .alert(Text(rootAlert?.title ?? ""), isPresented: alertBinding, presenting: rootAlert) { alert in
                alertActions(alert)
            } message: { alert in
                Text(alert.message)
            }
    }

    // MARK: Bindings

    /// The scan flow is open whenever there is a photo to work on.
    private var flowBinding: Binding<Bool> {
        Binding(
            get: { viewModel.selectedImage != nil },
            set: { isOpen in
                if !isOpen { viewModel.reset() }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { rootAlert != nil },
            set: { isShown in
                if !isShown { rootAlert = nil }
            }
        )
    }

    @ViewBuilder
    private func alertActions(_ alert: RootAlert) -> some View {
        switch alert {
        case .camera(let problem):
            if problem == .denied {
                Button("Open Settings") { CameraAccess.openAppSettings() }
            }
            Button("Choose from Library") { openLibraryAfterAlert() }
            Button("Cancel", role: .cancel) {}
        case .proLimit:
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Router wiring

    private func wireUp() {
        viewModel.creditManager = creditManager
        viewModel.collectionStore = collectionStore
        let requests = self.requests
        router.startScan = { source in
            requests.scan = ScanRequests.Scan(source: source)
        }
        router.rescan = { id, mode in
            requests.rescan = ScanRequests.Rescan(id: id, mode: mode)
        }
        router.openSettings = {
            requests.settingsToken += 1
        }
        #if DEBUG
        if DemoData.opensScan, viewModel.selectedImage == nil {
            viewModel.setImage(DemoData.scanEntry?.image)
        }
        #endif
    }

    // MARK: Scan gate (04 §5.2)

    /// 0 free scans → paywall; Pro cap → alert. Returns true when the scan
    /// must not start. With photo analysis off, scans are free and never gated.
    /// An unknown free count (first credit check failed) never blocks: the
    /// server decides at scan time and its 402 opens the paywall.
    private func gateBlocksScan() -> Bool {
        guard settings.aiConsentGranted else { return false }
        if creditManager.isOutOfFreeScans {
            router.paywall = .limitReached
            return true
        }
        if creditManager.isPro && creditManager.proScansLeft == 0 {
            rootAlert = .proLimit(limit: creditManager.scanLimit, resetsAt: creditManager.periodEndsAt)
            return true
        }
        return false
    }

    private func startScan(_ source: ScanSource) {
        guard viewModel.selectedImage == nil else { return }
        guard !gateBlocksScan() else { return }
        switch source {
        case .library:
            showLibrary = true
        case .camera:
            openCamera()
        }
    }

    private func openCamera() {
        CameraAccess.request { result in
            switch result {
            case .granted:
                showCamera = true
            case .denied:
                rootAlert = .camera(.denied)
            case .unavailable:
                rootAlert = .camera(.unavailable)
            }
        }
    }

    /// An alert button can't present a sheet while the alert is still closing.
    private func openLibraryAfterAlert() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            showLibrary = true
        }
    }

    // MARK: Photo in → flow

    /// The camera is fully gone before the scan flow opens on top.
    private func cameraDidDismiss() {
        if libraryAfterCamera {
            libraryAfterCamera = false
            showLibrary = true
            return
        }
        guard let image = capturedImage else { return }
        capturedImage = nil
        beginFlow(with: image)
    }

    private func loadLibraryItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = ImageDownsampler.image(from: data) {
                beginFlow(with: image)
            }
            libraryItem = nil
        }
    }

    /// "Review Photos Before Scanning" off: the scan starts at once with
    /// condition "Not sure" and no details (04 §5.2 step 4).
    private func beginFlow(with image: UIImage) {
        viewModel.setImage(image)
        if !settings.reviewBeforeScan {
            viewModel.scan()
        }
    }

    // MARK: Leaving the flow

    private func scanNextFromFlow() {
        afterFlow = .camera
        viewModel.reset()
    }

    private func flowDidDismiss() {
        if let next = afterFlow {
            afterFlow = nil
            startScan(next)
            return
        }
        if ReviewPrompter.shared.shouldAskOnClose() {
            // A beat after the cover has gone, so the prompt lands on the
            // home screen rather than over the closing result.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                requestReview()
            }
        }
    }

    /// Closes any flow or paywall and selects Settings (04 §2.1).
    private func openSettings() {
        afterFlow = nil
        router.paywall = nil
        router.tab = .settings
        if viewModel.selectedImage != nil {
            viewModel.reset()
        }
    }

    // MARK: Rescan a stored record (04 §5.3, §11.3)

    private func rescan(_ id: UUID, _ mode: RescanMode) {
        guard viewModel.selectedImage == nil,
              let record = collectionStore.record(id: id),
              let front = collectionStore.image(for: id) else { return }
        var photos: [UIImage] = [front]
        if let back = collectionStore.secondImage(for: id) {
            photos.append(back)
        }
        let scansNow = mode != .editPhotos
        if scansNow && gateBlocksScan() { return }
        Task { @MainActor in
            // Let a sheet or menu that asked for this finish closing first.
            try? await Task.sleep(for: .milliseconds(350))
            viewModel.load(record: record, photos: photos)
            switch mode {
            case .editPhotos:
                break
            case .withHint(let hint):
                viewModel.applyHint(hint)
                viewModel.scan()
            case .checkPriceAgain:
                viewModel.scan()
            }
        }
    }
}

/// Requests from `AppRouter` closures, observed by `ContentView`.
@MainActor
private final class ScanRequests: ObservableObject {
    struct Scan: Equatable {
        let source: ScanSource
        let token = UUID()
    }

    struct Rescan: Equatable {
        let id: UUID
        let mode: RescanMode
        let token = UUID()
    }

    @Published var scan: Scan?
    @Published var rescan: Rescan?
    @Published var settingsToken = 0
}

/// The one alert the root shows (04 §2.2: one alert per node).
private enum RootAlert: Equatable {
    case camera(CameraAccess.Problem)
    case proLimit(limit: Int?, resetsAt: Date?)

    var title: String {
        switch self {
        case .camera(let problem):
            return problem.title
        case .proLimit(let limit, let resetsAt):
            return ScanFailure.proLimit(limit: limit, resetsAt: resetsAt).title
        }
    }

    var message: String {
        switch self {
        case .camera(let problem):
            return problem.message
        case .proLimit(let limit, let resetsAt):
            return ScanFailure.proLimit(limit: limit, resetsAt: resetsAt).message
        }
    }
}

// MARK: - Scan home

/// Composition only (04 §6.1, 05 §3.1): intro, hero, consent notice,
/// snapshot, recent scans, photo guides, how Worthwise values, footer.
struct ScanHomeView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var sheet: HomeSheet?
    /// "Scan {category}" in a guide: the camera opens once the guide has closed.
    @State private var scanAfterSheet = false
    /// "Hide from Recent Scans" on a Home recent (06 toast with Undo).
    @State private var toast: WWToastModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                    .padding(.bottom, WW.Space.xl)
            }
            .wwContentUnderTabBar()
            .background(WW.background)
            .wwToast($toast)
            // Compact bar: brand on the left, plan on the right. The greeting
            // below carries the welcome, so no large title repeats the name.
            .wwBrandNavigationBar(title: "Worthwise")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PlanPill()
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ItemDetailView(itemID: id)
            }
            .navigationDestination(for: RecentScansRoute.self) { _ in
                RecentScansView()
            }
        }
        .sheet(item: $sheet, onDismiss: sheetDidDismiss) { item in
            sheetContent(item)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeIntro()
                .padding(.top, WW.Space.xxs)
            hero
                .padding(.top, WW.Space.md)
            if !settings.aiConsentGranted {
                ConsentOffNotice { router.openSettings() }
                    .padding(.top, WW.Space.sm)
            }
            if !collectionStore.items.isEmpty {
                CollectionSnapshotCard { router.tab = .collection }
                    .padding(.top, WW.Space.md)
                    .transition(.opacity)
            }
            HomeRecentSection(toast: $toast)
                .padding(.top, WW.Space.sectionGap)
            guidesSection
                .padding(.top, WW.Space.sectionGap)
            howItValuesSection
                .padding(.top, WW.Space.sectionGap)
            HomeFooter()
                .padding(.top, WW.Space.sectionGap)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ScanHeroCard(
            state: heroState,
            costLine: heroCostLine,
            onCamera: { router.startScan(.camera) },
            onLibrary: { router.startScan(.library) },
            onPlans: { router.paywall = .limitReached }
        )
    }

    private var heroState: ScanHeroCard.Mode {
        guard settings.aiConsentGranted else { return .ready }
        if creditManager.isPro {
            return creditManager.proScansLeft == 0 ? .proCapReached : .ready
        }
        if creditManager.isOutOfFreeScans {
            return .outOfScans
        }
        return .ready
    }

    private var heroCostLine: String {
        if !settings.aiConsentGranted {
            return "Photo analysis is off: scans stay on this iPhone"
        }
        if creditManager.isPro {
            guard let left = creditManager.proScansLeft else { return "" }
            if left == 0 { return proCapLine }
            if left <= 20 { return "\(left) Pro \(left == 1 ? "scan" : "scans") left this period" }
            return ""
        }
        // Unknown count (offline first launch): no cost line rather than a guess.
        guard creditManager.hasServerCount else { return "" }
        let left = creditManager.freeScansLeft
        if left >= 2 { return "\(left) free scans left · No account needed" }
        if left == 1 { return "1 free scan left" }
        return ""
    }

    private var proCapLine: String {
        let count = creditManager.scanLimit.map { "all \($0)" } ?? "all your"
        var line = "You've used \(count) Pro scans for this period."
        if let date = creditManager.periodEndsAt {
            line += " More on \(ScanFailure.shortDate(date))."
        }
        return line
    }

    // MARK: Sections

    private var guidesSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSectionHeader(title: "Photo Guides")
            CategoryGrid(interests: settings.interests, intent: settings.intent) { guide in
                sheet = .guide(guide)
            }
        }
    }

    private var howItValuesSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            WWSectionHeader(title: "How Worthwise Values")
            HowItValuesCard { sheet = .howItWorks }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ item: HomeSheet) -> some View {
        switch item {
        case .guide(let guide):
            CategoryGuideSheet(guide: guide) { scanAfterSheet = true }
        case .howItWorks:
            HowItWorksSheet()
        }
    }

    private func sheetDidDismiss() {
        guard scanAfterSheet else { return }
        scanAfterSheet = false
        router.startScan(.camera)
    }
}

/// The two sheets Home opens (one presenter, 04 §2.2).
private enum HomeSheet: Identifiable {
    case guide(CategoryGuide)
    case howItWorks

    var id: String {
        switch self {
        case .guide(let guide): return "guide." + guide.id
        case .howItWorks: return "howItWorks"
        }
    }
}

/// "Recent Scans": 6 tiles in 3 columns (2 at xxxLarge, list rows at AX
/// sizes), or the inline empty state (04 H1/H2, 05 §3.1 block 5).
/// Long-press Delete Scan confirms (06 §4.6, same dialog as Recent Scans);
/// Hide posts the 06 toast with Undo.
private struct HomeRecentSection: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var toast: WWToastModel?
    /// The recent scan whose "Delete Scan" waits for confirmation.
    @State private var pendingDelete: UUID?

    init(toast: Binding<WWToastModel?>) {
        self._toast = toast
    }

    var body: some View {
        let recent: [SavedCollectible] = Array(collectionStore.recentScans.prefix(6))
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            header(hasScans: !recent.isEmpty)
            if recent.isEmpty {
                RecentEmptyCard()
                    .transition(.opacity)
            } else if dynamicTypeSize.isAccessibilitySize {
                list(recent)
                    .transition(.opacity)
            } else {
                grid(recent)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .wwAnimation(.settle, value: recent.isEmpty)
        // One presenter for the section (04 §2.2).
        .confirmationDialog(
            "Delete this scan?",
            isPresented: deleteBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { id in
            Button("Delete Scan", role: .destructive) { delete(id) }
            Button("Cancel", role: WW.dialogCancelRole) {}
        } message: { _ in
            Text("It's removed from Recent scans. This can't be undone.")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { isPresented in
                if !isPresented { pendingDelete = nil }
            }
        )
    }

    private func menu(for item: SavedCollectible) -> some View {
        RecentScanMenu(
            item: item,
            onDelete: { pendingDelete = item.id },
            onHide: { hide(item) }
        )
    }

    private func hide(_ item: SavedCollectible) {
        let store = collectionStore
        let snapshot = store.membershipSnapshot(for: [item.id])
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            store.removeFromRecents(id: item.id)
        }
        toast = WWToastModel(
            message: "Hidden from Recent Scans. It's still in your collection.",
            actionTitle: "Undo",
            action: {
                store.restore(snapshot)
                UIAccessibility.post(notification: .announcement, argument: "Undone")
            }
        )
    }

    private func delete(_ id: UUID) {
        pendingDelete = nil
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            collectionStore.remove(id: id)
        }
        UIAccessibility.post(notification: .announcement, argument: "Scan deleted")
    }

    @ViewBuilder
    private func header(hasScans: Bool) -> some View {
        if hasScans {
            WWSectionHeader(title: "Recent Scans") {
                NavigationLink(value: RecentScansRoute()) {
                    Text("See All")
                }
            }
        } else {
            WWSectionHeader(title: "Recent Scans")
        }
    }

    private func grid(_ recent: [SavedCollectible]) -> some View {
        let count: Int = dynamicTypeSize >= .xxxLarge ? 2 : 3
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: count)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: WW.Space.md) {
            ForEach(recent) { item in
                NavigationLink(value: item.id) {
                    ItemTile(item: item, compact: true, showsSavedState: true)
                }
                .buttonStyle(.wwPressable)
                .contextMenu { menu(for: item) }
            }
        }
    }

    private func list(_ recent: [SavedCollectible]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    WWHairline()
                        .padding(.leading, WW.Space.md)
                }
                NavigationLink(value: item.id) {
                    row(item)
                }
                .buttonStyle(.wwPressable)
                .contextMenu { menu(for: item) }
            }
        }
        .wwCard(padding: 0)
    }

    private func row(_ item: SavedCollectible) -> some View {
        WWListRow(
            thumbnail: collectionStore.thumbnail(for: item.id),
            title: item.title,
            subtitle: item.isInCollection ? "In your collection" : nil,
            accessory: AnyView(RecentPriceLine(item: item)),
            showsChevron: true
        )
    }
}

/// The level-aware price line for a recent row at AX sizes (04 §4.4).
private struct RecentPriceLine: View {
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let item: SavedCollectible

    var body: some View {
        let assessment: ValueAssessment = item.assessment
        switch assessment.level {
        case .strong, .fair:
            ValueRangeText(lowUSD: assessment.lowUSD, highUSD: assessment.highUSD, role: .priceSmall)
        case .rough:
            CaveatFlag(glyph: assessment.roughGlyph, text: assessment.roughWord, style: .inline)
        case .noPrice:
            Text("No price")
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
        }
    }
}

// MARK: - Plan pill

/// "{n} free scans" / "1 free scan" / "No free scans" / "Pro" (05 §2.4).
/// iOS 26: a plain toolbar button (the system draws the glass capsule).
/// iOS 17–25: our own `fill` capsule. Monochrome either way.
struct PlanPill: View {
    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorSchemeContrast) private var contrast

    init() {}

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: open) {
                pillText
            }
            .buttonStyle(.wwBarText)
            .tint(WW.text)
            .accessibilityLabel(spokenLabel)
            .accessibilityHint(spokenHint)
        } else {
            Button(action: open) {
                capsuleLabel
            }
            .buttonStyle(.wwPressable)
            .accessibilityLabel(spokenLabel)
            .accessibilityHint(spokenHint)
        }
    }

    private var pillText: some View {
        Text(title)
            .wwFont(.buttonSmall)
            .foregroundStyle(WW.text)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .fixedSize()
    }

    private var capsuleLabel: some View {
        pillText
            .padding(.horizontal, WW.Space.sm)
            .frame(minHeight: 32)
            .background(WW.fill, in: Capsule())
            .overlay {
                if contrast == .increased {
                    Capsule().strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
                }
            }
            .frame(minHeight: WW.Size.minTarget)
            .contentShape(Rectangle())
    }

    private var title: String {
        if creditManager.isPro { return "Pro" }
        // Unknown count (first credit check failed): the plan, not a number.
        guard creditManager.hasServerCount else { return "Free" }
        let left = creditManager.freeScansLeft
        if left == 0 { return "No free scans" }
        if left == 1 { return "1 free scan" }
        return "\(left) free scans"
    }

    private var spokenLabel: String {
        if creditManager.isPro { return "Worthwise Pro" }
        guard creditManager.hasServerCount else { return "Free plan" }
        let left = creditManager.freeScansLeft
        if left == 0 { return "No free scans left" }
        if left == 1 { return "1 free scan left" }
        return "\(left) free scans left"
    }

    private var spokenHint: String {
        creditManager.isPro ? "Opens your plan." : "Opens plans."
    }

    private func open() {
        if creditManager.isOutOfFreeScans {
            router.paywall = .limitReached
        } else {
            // Pro: the general paywall shows the plan status.
            router.paywall = .general
        }
    }
}

// MARK: - Scan hero

/// The one capture card on Home (05 §2.32). Its primary is the only Lapis
/// on the screen.
struct ScanHeroCard: View {
    enum Mode: Equatable {
        case ready
        case outOfScans
        case proCapReached
    }

    let state: Mode
    /// `.ready`: "3 free scans left · No account needed" etc. `.proCapReached`:
    /// the cap sentence. Empty hides it. `.outOfScans` shows 06's reassurance.
    let costLine: String
    let onCamera: () -> Void
    let onLibrary: () -> Void
    let onPlans: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var plateSize: CGFloat = 64

    init(state: Mode, costLine: String, onCamera: @escaping () -> Void, onLibrary: @escaping () -> Void,
         onPlans: @escaping () -> Void) {
        self.state = state
        self.costLine = costLine
        self.onCamera = onCamera
        self.onLibrary = onLibrary
        self.onPlans = onPlans
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            buttons
                .padding(.top, WW.Space.lg)
            footnote
        }
        .wwCard()
    }

    @ViewBuilder
    private var top: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WW.Space.sm) {
                if dynamicTypeSize < .accessibility3 {
                    plate
                }
                message
            }
        } else {
            HStack(alignment: .top, spacing: WW.Space.md) {
                plate
                message
            }
        }
    }

    private var plate: some View {
        let side: CGFloat = min(plateSize, WW.Size.plateM * WW.Size.graphicScaleCap)
        return Image(systemName: "camera.fill")
            .font(.system(size: 28 * side / WW.Size.plateM, weight: .regular))
            .foregroundStyle(WW.accent)
            .frame(width: side, height: side)
            .background(WW.accentWash, in: RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var message: some View {
        switch state {
        case .outOfScans:
            VStack(alignment: .leading, spacing: WW.Space.xxs) {
                Text("You've used your 3 free scans")
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Worthwise Pro gives you 250 scans a month, with the sold and listed prices behind each value.")
                    .wwFont(.body)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .ready, .proCapReached:
            Text("Take a photo of one item. We'll identify it, check real sold prices and show you a value range.")
                .wwFont(.body)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch state {
        case .outOfScans:
            Button(action: onPlans) {
                Text("See Pro plans")
            }
            .buttonStyle(.wwPrimary)
        case .ready, .proCapReached:
            VStack(spacing: WW.Space.sm) {
                Button(action: onCamera) {
                    Label("Take photo", systemImage: "camera")
                }
                .buttonStyle(.wwPrimary)

                Button(action: onLibrary) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.wwSecondary)
            }
            .disabled(state == .proCapReached)
        }
    }

    @ViewBuilder
    private var footnote: some View {
        let text: String = state == .outOfScans
            ? "Your collection and recent scans stay just as they are."
            : costLine
        if !text.isEmpty {
            Text(text)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, WW.Space.sm)
        }
    }
}

// MARK: - Scan flow

/// Full-screen flow: review the photos, then scanning, then the result.
/// Which step shows follows the view model's state; steps crossfade.
struct ScanFlowView: View {
    @ObservedObject var viewModel: ScannerViewModel
    var onScanNext: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var paywall: PaywallRoute?

    private enum Step: Equatable {
        case review
        case scanning
        case result
    }

    private var step: Step {
        if viewModel.isScanning { return .scanning }
        if viewModel.profile != nil && viewModel.estimate != nil { return .result }
        return .review
    }

    var body: some View {
        stepContent
            .animation(WW.Motion.animation(.crossfade, reduceMotion: reduceMotion), value: step)
            .sheet(item: $paywall) { route in
                ProPaywallView(context: route.context)
                    .environmentObject(creditManager)
                    .environmentObject(authManager)
            }
            .onChange(of: viewModel.showPaywall) { _, show in
                if show { presentLimitPaywall() }
            }
            .onAppear {
                if viewModel.showPaywall { presentLimitPaywall() }
            }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .scanning:
            ScanningView(viewModel: viewModel)
                .transition(.opacity)
        case .result:
            if let profile = viewModel.profile, let estimate = viewModel.estimate {
                ScanResultScreen(
                    viewModel: viewModel,
                    profile: profile,
                    estimate: estimate,
                    onUnlockListings: { paywall = .listings },
                    onScanNext: onScanNext,
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)
            }
        case .review:
            ReviewView(viewModel: viewModel, onOpenSettings: onOpenSettings)
                .transition(.opacity)
        }
    }

    /// 402 from the server (or 0 free scans at "Get value"): the paywall over
    /// Review, photos kept (04 §2.6 #4).
    private func presentLimitPaywall() {
        viewModel.showPaywall = false
        paywall = .limitReached
    }
}

// MARK: Review

struct ReviewView: View {
    @ObservedObject var viewModel: ScannerViewModel
    var onOpenSettings: () -> Void = {}

    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var replacing: PhotoSlot?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var libraryAfterCamera = false
    @State private var cameraProblem: CameraAccess.Problem?
    @State private var cropping: PhotoSlot?
    @State private var confirmDiscard = false
    @FocusState private var detailsFocused: Bool

    enum PhotoSlot: Identifiable {
        case front, back
        var id: Self { self }
        var side: ScannerViewModel.PhotoSide { self == .front ? .front : .back }
    }

    var body: some View {
        NavigationStack {
            scrollContent
                .scrollDismissesKeyboard(.interactively)
                .background(WW.background)
                .navigationTitle("Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        cancelButton
                    }
                }
                .wwBottomBar {
                    ReviewBar(
                        failure: viewModel.failure,
                        costLine: costLine,
                        canScan: viewModel.selectedImage != nil,
                        outOfScans: isOutOfScans,
                        onPrimary: primaryAction,
                        onOpenSettings: onOpenSettings
                    )
                }
        }
        .tint(WW.text)
        .fullScreenCover(isPresented: $showCamera, onDismiss: cameraDidDismiss) {
            CameraPicker(image: $capturedImage, onChooseLibrary: { libraryAfterCamera = true })
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images, photoLibrary: .shared())
        .onChange(of: libraryItem) { _, item in
            loadLibraryItem(item)
        }
        .alert(Text(cameraProblem?.title ?? ""), isPresented: problemBinding, presenting: cameraProblem) { problem in
            problemActions(problem)
        } message: { problem in
            Text(problem.message)
        }
    }

    private var margin: CGFloat { WW.margin(for: dynamicTypeSize) }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photosBlock
                hint
                    .padding(.top, WW.Space.sm)
                ConditionPicker(grade: conditionBinding, isSet: conditionSetBinding)
                    .padding(.top, WW.Space.xl)
                detailsBlock
                    .padding(.top, WW.Space.xl)
            }
            .padding(.horizontal, margin)
            .padding(.top, WW.Space.xs)
            .padding(.bottom, WW.Space.xl)
        }
        .fullScreenCover(item: $cropping) { slot in
            cropEditor(slot)
        }
    }

    // MARK: Cancel

    /// Dirty edits get "Discard this photo?" (04 R3), attached to the button.
    private var cancelButton: some View {
        Button("Cancel") {
            if viewModel.isDirty {
                confirmDiscard = true
            } else {
                viewModel.reset()
            }
        }
        .buttonStyle(.wwBarText)
        .confirmationDialog("Discard this photo?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Photo", role: .destructive) { viewModel.reset() }
            Button("Keep Editing", role: WW.dialogCancelRole) {}
        } message: {
            Text("Your crop, condition and details will be lost.")
        }
    }

    // MARK: Photos

    private var photosBlock: some View {
        HStack(alignment: .top, spacing: WW.Space.sm) {
            frontColumn
            backColumn
        }
    }

    private var frontColumn: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            frontTile
                .modifier(ReviewPhotoLanding())
                .id(frontKey)
            Text("Front")
                .wwFont(.footnote, weight: .semibold)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The landing (06 M4) replays only for a new photo, not for a crop.
    private var frontKey: ObjectIdentifier? {
        viewModel.originalImage(for: .front).map { ObjectIdentifier($0) }
    }

    private var frontTile: some View {
        photoTile(viewModel.selectedImage, slot: .front)
            .overlay(alignment: .topTrailing) {
                sourceMenu(for: .front) {
                    WWOnPhotoButtonLabel(systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel("Replace front photo")
                .padding(2)
            }
    }

    private var backColumn: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            backTile
            Text(viewModel.secondaryImage == nil ? "Recommended" : "Back")
                .wwFont(.footnote, weight: .semibold)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wwAnimation(.settle, value: viewModel.secondaryImage != nil)
    }

    @ViewBuilder
    private var backTile: some View {
        if let back = viewModel.secondaryImage {
            photoTile(back, slot: .back)
                .overlay(alignment: .topTrailing) {
                    Button {
                        viewModel.setSecondaryImage(nil)
                    } label: {
                        WWOnPhotoButtonLabel(systemImage: "xmark")
                    }
                    .buttonStyle(WWOnPhotoButtonStyle())
                    .accessibilityLabel("Remove back photo")
                    .padding(2)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            sourceMenu(for: .back) {
                AddBackSlot()
            }
            .accessibilityLabel("Add back photo")
            .transition(.opacity)
        }
    }

    /// Shows the whole (possibly cropped) photo, so the user sees exactly what
    /// will be analysed. Tap to crop.
    private func photoTile(_ image: UIImage?, slot: PhotoSlot) -> some View {
        let isCropped: Bool = viewModel.crop(for: slot.side) != nil
        let hasImage: Bool = image != nil
        let shape = RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { tileImage(image) }
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture {
                if image != nil { cropping = slot }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(slot == .front ? "Front photo" : "Back photo")
            .accessibilityHint(hasImage ? "Double-tap to crop" : "")
            .accessibilityAddTraits(hasImage ? AccessibilityTraits.isButton : AccessibilityTraits())
            .overlay(alignment: .bottomTrailing) {
                cropButton(slot: slot, hasImage: hasImage, isCropped: isCropped)
            }
    }

    @ViewBuilder
    private func tileImage(_ image: UIImage?) -> some View {
        if let image {
            ZStack {
                WW.photoBackdrop
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            PhotoPlaceholder()
        }
    }

    @ViewBuilder
    private func cropButton(slot: PhotoSlot, hasImage: Bool, isCropped: Bool) -> some View {
        if hasImage {
            Button {
                cropping = slot
            } label: {
                WWOnPhotoButtonLabel(systemImage: "crop", showsBadge: isCropped)
            }
            .buttonStyle(WWOnPhotoButtonStyle())
            .accessibilityLabel(isCropped ? "Adjust crop" : "Crop photo")
            .padding(2)
        }
    }

    private func sourceMenu<MenuLabel: View>(for slot: PhotoSlot, @ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            Button {
                replacing = slot
                openCamera()
            } label: {
                Label("Take photo", systemImage: "camera")
            }
            Button {
                replacing = slot
                showLibrary = true
            } label: {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }
        } label: {
            label()
        }
    }

    private var hint: some View {
        Text("Tap a photo to crop it to the item. The back is where most of the accuracy comes from: the number on a card, the reverse of a coin, the mark under a vase.")
            .wwFont(.footnote)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Condition and details

    private var conditionBinding: Binding<ConditionGrade> {
        Binding(
            get: { viewModel.condition },
            set: { viewModel.updateCondition($0) }
        )
    }

    private var conditionSetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.conditionIsSet },
            set: { viewModel.conditionIsSet = $0 }
        )
    }

    private var detailsBinding: Binding<String> {
        Binding(
            get: { viewModel.userProvidedInfo },
            set: { viewModel.updateUserProvidedInfo($0) }
        )
    }

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: WW.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: WW.Space.xxs) {
                Text("Details")
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                Text("(optional)")
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
            }
            .accessibilityHidden(true)
            TextField(
                "Details",
                text: detailsBinding,
                prompt: Text("Edition, year, signature, where it came from…"),
                axis: .vertical
            )
            .lineLimit(1...4)
            .focused($detailsFocused)
            .submitLabel(.done)
            .onSubmit { detailsFocused = false }
            .wwField(isFocused: detailsFocused)
            .accessibilityLabel("Details (optional)")
        }
    }

    // MARK: Primary and cost line (04 §6.2)

    /// Free, analysis on, and the server says 0 free scans (RV-1): reached
    /// from a stored item's "Edit photos", which skips the gate. The bar
    /// offers the plans instead of a "Get value" that could only open them.
    private var isOutOfScans: Bool {
        settings.aiConsentGranted && creditManager.isOutOfFreeScans
    }

    private func primaryAction() {
        detailsFocused = false
        if isOutOfScans {
            // ScanFlowView presents the limit paywall over Review, photos kept.
            viewModel.showPaywall = true
        } else {
            viewModel.scan()
        }
    }

    private var costLine: String {
        if !settings.aiConsentGranted {
            return "Photo analysis is off: we'll only read text on your iPhone. No scan used."
        }
        if creditManager.isPro {
            if let left = creditManager.proScansLeft {
                return "\(left) Pro \(left == 1 ? "scan" : "scans") left this period"
            }
            return "Included in Pro"
        }
        // Unknown count (first credit check failed): no number we can't stand behind.
        guard creditManager.hasServerCount else { return "Uses 1 free scan" }
        if isOutOfScans { return "Your photos and edits stay here." }
        let left = creditManager.freeScansLeft
        if left >= 2 { return "Uses 1 free scan · \(left - 1) left" }
        if left == 1 { return "This is your last free scan" }
        return "No free scans left"
    }

    // MARK: Camera, library, crop

    private var problemBinding: Binding<Bool> {
        Binding(
            get: { cameraProblem != nil },
            set: { isShown in
                if !isShown { cameraProblem = nil }
            }
        )
    }

    @ViewBuilder
    private func problemActions(_ problem: CameraAccess.Problem) -> some View {
        if problem == .denied {
            Button("Open Settings") { CameraAccess.openAppSettings() }
        }
        Button("Choose from Library") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                showLibrary = true
            }
        }
        Button("Cancel", role: .cancel) { replacing = nil }
    }

    @ViewBuilder
    private func cropEditor(_ slot: PhotoSlot) -> some View {
        if let original = viewModel.originalImage(for: slot.side) {
            CropEditorView(
                image: original,
                initialCrop: viewModel.crop(for: slot.side),
                onCancel: { cropping = nil },
                onDone: { rect in
                    viewModel.applyCrop(rect, to: slot.side)
                    cropping = nil
                }
            )
        }
    }

    private func openCamera() {
        CameraAccess.request { result in
            switch result {
            case .granted: showCamera = true
            case .denied: cameraProblem = .denied
            case .unavailable: cameraProblem = .unavailable
            }
        }
    }

    private func cameraDidDismiss() {
        if libraryAfterCamera {
            libraryAfterCamera = false
            showLibrary = true
            return
        }
        guard let image = capturedImage else { return }
        capturedImage = nil
        apply(image, to: replacing)
    }

    private func loadLibraryItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let slot = replacing
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = ImageDownsampler.image(from: data) {
                apply(image, to: slot)
            }
            libraryItem = nil
        }
    }

    private func apply(_ image: UIImage, to slot: PhotoSlot?) {
        switch slot ?? .back {
        case .front:
            // Keep the back photo (and its crop), condition and details.
            viewModel.replaceFrontImage(image)
        case .back:
            viewModel.setSecondaryImage(image)
        }
        replacing = nil
    }
}

/// 06 M4: the photo lands on Review (opacity 0 → 1, scale 1.03 → 1).
private struct ReviewPhotoLanding: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .opacity(landed ? 1 : 0)
            .scaleEffect(landed || reduceMotion ? 1 : 1.03)
            .onAppear {
                withAnimation(WW.Motion.animation(.settle, reduceMotion: reduceMotion)) {
                    landed = true
                }
            }
    }
}

/// The dashed "Add back" slot (05 §2.45).
private struct AddBackSlot: View {
    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
        let side: CGFloat = min(circleSize, 40 * WW.Size.graphicScaleCap)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: WW.Space.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 18 * side / 40, weight: .semibold))
                        .foregroundStyle(WW.text)
                        .frame(width: side, height: side)
                        .background(WW.fill, in: Circle())
                    Text("Add back")
                        .wwFont(.subhead, weight: .semibold)
                        .foregroundStyle(WW.text)
                        .multilineTextAlignment(.center)
                }
                .padding(WW.Space.xs)
            }
            .background(WW.surface, in: shape)
            .overlay {
                shape.strokeBorder(WW.track, style: StrokeStyle(lineWidth: WW.Stroke.dashedSlot, dash: WW.Stroke.dashSlot))
            }
            .contentShape(shape)
    }
}

/// Review's pinned bar (05 §3.3): failure card, "Get value" / "Try again"
/// (05 D10) / "See Pro plans" (0 free scans, RV-1), cost line.
private struct ReviewBar: View {
    let failure: ScanFailure?
    let costLine: String
    let canScan: Bool
    let outOfScans: Bool
    let onPrimary: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryTitle: String {
        if outOfScans { return "See Pro plans" }
        return (failure?.canRetry ?? false) ? "Try again" : "Get value"
    }

    private var isBlocked: Bool {
        if case .proLimit = failure { return true }
        return false
    }

    var body: some View {
        VStack(spacing: WW.Space.xs) {
            if let failure {
                ScanFailureCard(failure: failure, onOpenSettings: onOpenSettings)
                    .transition(failureTransition)
            }
            Button(action: onPrimary) {
                Text(primaryTitle)
            }
            .buttonStyle(.wwPrimary)
            .disabled(!canScan || isBlocked)

            if !costLine.isEmpty {
                Text(costLine)
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .wwAnimation(.settle, value: failure)
    }

    private var failureTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.opacity.combined(with: .scale(scale: 0.94))
    }
}

// MARK: Scan failure card

/// A failed scan, said plainly (04 §6.2, 05 §2.33). No retry button inside:
/// the Review bar's primary reads "Try again" (05 D10). `onRetry` is kept for
/// the 04 §7 signature and unused.
struct ScanFailureCard: View {
    let failure: ScanFailure
    let onRetry: (() -> Void)?
    let onOpenSettings: () -> Void

    init(failure: ScanFailure, onRetry: (() -> Void)? = nil, onOpenSettings: @escaping () -> Void = {}) {
        self.failure = failure
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    private var style: WWCardStyle {
        switch failure {
        case .offline, .server: return .danger
        case .proLimit: return .caution
        case .nothingToRead: return .surface
        }
    }

    private var glyphColor: Color {
        switch failure {
        case .offline, .server: return WW.danger
        case .proLimit: return WW.caution
        case .nothingToRead: return WW.secondaryText
        }
    }

    private var spoken: String {
        if case .proLimit = failure {
            return "Limit reached: \(failure.title). \(failure.message)"
        }
        return "Error: \(failure.title). \(failure.message)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: failure.glyph)
                .wwFont(.headline)
                .foregroundStyle(glyphColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                texts
                if failure == .nothingToRead {
                    Button("Turn on photo analysis", action: onOpenSettings)
                        .buttonStyle(WWTertiaryButtonStyle(tone: .accent, size: .small))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .wwCard(padding: WW.Space.md, style: style)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: spoken)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(failure.title)
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(failure.message)
                .wwFont(.subhead)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: Scanning

/// Honest progress (04 §6.3, 05 §3.4, 06 M8–M12): the photo on the backdrop
/// (no laser sweep), the Tag's pupil breathing, real step 1, timed steps 2–3,
/// step 4 waits for the result. Long-wait copy at 20 s / 60 s, one
/// "Good to know" tip at 8 s (cloud scans only).
struct ScanningView: View {
    @ObservedObject var viewModel: ScannerViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("ww.scanTipIndex") private var tipIndex = 0

    @State private var current = 0
    /// 0 default, 1 after 20 s, 2 after 60 s.
    @State private var waitLevel = 0
    @State private var showsTip = false
    @State private var tip = ScanningView.tips[0]
    @State private var confirmStop = false

    static let tips: [String] = [
        "Sold prices count most. Sellers often ask more than items actually sell for.",
        "A photo of the back often settles the match: a number, a mark, a label.",
        "A wide range isn't a broken result. It means similar items sell for very different amounts.",
        "Every value shows where it comes from: sold prices, a price guide, asking prices or an AI estimate.",
        "We don't keep your photo once the scan is done.",
    ]

    private var isCloud: Bool { !viewModel.lastScanWasLocalByChoice }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                photo
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                panel(height: geo.size.height * 0.75)
            }
        }
        .background(WW.photoBackdrop.ignoresSafeArea())
        .statusBarHidden()
        .onAppear(perform: pickTip)
        .task { await runClock() }
        .task(id: viewModel.stage) { await followStage() }
    }

    // MARK: Layers

    @ViewBuilder
    private var photo: some View {
        if let image = viewModel.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(WW.Space.md)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func panel(height: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                panelContent
            }
            .frame(height: height)
            .background { panelBackground }
        } else {
            panelContent
                .background { panelBackground }
        }
    }

    private var panelBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: WW.Radius.sheet, topTrailingRadius: WW.Radius.sheet, style: .continuous)
            .fill(WW.elevated)
            .ignoresSafeArea(edges: .bottom)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            StepList(steps: steps, current: current, style: .progress)
                .padding(.top, WW.Space.lg)
            if isCloud {
                tipLine
                    .padding(.top, WW.Space.lg)
            }
            cancelButton
                .padding(.top, WW.Space.xl)
        }
        .padding(.horizontal, WW.Space.xl)
        .padding(.top, WW.Space.xl)
        .padding(.bottom, WW.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            HStack(alignment: .center, spacing: 10) {
                WWBreathingMark(size: 28, tone: .accent)
                Text("Valuing your item")
                    .wwFont(.itemTitle)
                    .foregroundStyle(WW.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(subtitle)
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .wwAnimation(.crossfade, value: waitLevel)
        }
    }

    private var subtitle: String {
        if waitLevel >= 2 { return "Still working. You can stop and try again later." }
        if waitLevel == 1 { return "Taking a little longer than usual. Some items need more searching." }
        if !isCloud { return "Reading the text on your photo, on this iPhone." }
        return "We check real prices, so this takes a moment."
    }

    private var steps: [StepItem] {
        if !isCloud {
            return [StepItem(title: "Reading the photo", detail: "Text and barcodes, on this iPhone")]
        }
        return [
            StepItem(title: "Reading the photo", detail: "Names, numbers and marks"),
            StepItem(title: "Identifying the item", detail: "Matching it against catalogs"),
            StepItem(title: "Checking prices", detail: "Sold prices, price guides and listings"),
            StepItem(title: "Building your value range", detail: "Strongest evidence first"),
        ]
    }

    /// Space is reserved from the first frame, so nothing moves when it fades in.
    private var tipLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Good to know")
                .wwFont(.footnote, weight: .semibold)
                .foregroundStyle(WW.text)
            Text(tip)
                .wwFont(.footnote)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(showsTip ? 1 : 0)
        .wwAnimation(.crossfade, value: showsTip)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!showsTip)
    }

    /// Before send: back to Review at once (nothing was sent). After send:
    /// "Stop this scan?" (04 SC5/SC6), attached to the button.
    private var cancelButton: some View {
        Button("Cancel") {
            if viewModel.stage == .waitingForServer {
                confirmStop = true
            } else {
                viewModel.cancelScan()
            }
        }
        .buttonStyle(.wwSecondary)
        .confirmationDialog("Stop this scan?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop Scan", role: .destructive) { viewModel.cancelScan() }
            Button("Keep Waiting", role: WW.dialogCancelRole) {}
        } message: {
            Text("We've already sent your photo, so stopping now may still use a scan.")
        }
    }

    // MARK: Clock

    private func pickTip() {
        guard isCloud else { return }
        let count = Self.tips.count
        tip = Self.tips[((tipIndex % count) + count) % count]
        tipIndex += 1
    }

    /// Step 1 completes for real when the photo is sent; 2 and 3 follow
    /// +2 s / +3 s; 4 never completes before the result.
    private func followStage() async {
        switch viewModel.stage {
        case .idle, .reading:
            current = 0
        case .waitingForServer:
            current = 1
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            current = 2
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            current = 3
        }
    }

    private func runClock() async {
        let start: Date = viewModel.scanStartedAt ?? Date()
        if isCloud {
            await pause(until: start.addingTimeInterval(8))
            guard !Task.isCancelled else { return }
            showsTip = true
        }
        await pause(until: start.addingTimeInterval(20))
        guard !Task.isCancelled else { return }
        setWaitLevel(1)
        await pause(until: start.addingTimeInterval(60))
        guard !Task.isCancelled else { return }
        setWaitLevel(2)
    }

    private func setWaitLevel(_ level: Int) {
        waitLevel = level
        UIAccessibility.post(notification: .announcement, argument: subtitle)
    }

    private func pause(until date: Date) async {
        let interval: TimeInterval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

// MARK: Result after a scan

/// Hosts WP2's `ResultView` for a fresh scan and handles the actions that
/// route back into the flow (04 §5.3).
struct ScanResultScreen: View {
    @ObservedObject var viewModel: ScannerViewModel
    let profile: CollectibleProfile
    let estimate: ValueEstimate
    let onUnlockListings: () -> Void
    var onScanNext: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @EnvironmentObject private var creditManager: CreditManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: ResultModel {
        var photos: [UIImage] = []
        if let front = viewModel.selectedImage { photos.append(front) }
        if let back = viewModel.secondaryImage { photos.append(back) }
        return ResultModel(
            profile: profile,
            estimate: estimate,
            // "Not sure" reads as "Not set" on the result.
            condition: viewModel.conditionIsSet ? viewModel.condition : nil,
            photos: photos,
            onDeviceReason: viewModel.lastScanWasLocalByChoice ? .analysisDisabled : .networkFallback
        )
    }

    private var context: ResultContext {
        let vm = viewModel
        return ResultContext(
            origin: .freshScan,
            recordID: vm.resultRecordID,
            replacing: vm.replacingRecordID,
            scanCharged: vm.lastScanCharged,
            onDone: { vm.reset() },
            onScanNext: onScanNext,
            onRescan: { mode in rescan(mode) },
            onUnlock: creditManager.isPro ? nil : onUnlockListings,
            onDeleted: { vm.reset() },
            onOpenSettings: onOpenSettings
        )
    }

    var body: some View {
        NavigationStack {
            ResultView(model: model, context: context)
        }
        .tint(WW.text)
    }

    /// Fresh result: back to Review (+ hint), or scan again at once.
    private func rescan(_ mode: RescanMode) {
        let animation: Animation? = WW.Motion.animation(.crossfade, reduceMotion: reduceMotion)
        switch mode {
        case .editPhotos:
            withAnimation(animation) { viewModel.backToReview() }
        case .withHint(let hint):
            viewModel.applyHint(hint)
            viewModel.backToReview()
            viewModel.scan()
        case .checkPriceAgain:
            viewModel.backToReview()
            viewModel.scan()
        }
    }
}

// MARK: - Camera access

enum CameraAccess {
    enum Result { case granted, denied, unavailable }

    enum Problem: String, Identifiable {
        case denied, unavailable
        var id: String { rawValue }

        /// 06 §4.8 copy.
        var title: String {
            switch self {
            case .denied: return "Allow camera access"
            case .unavailable: return "Camera unavailable"
            }
        }

        var message: String {
            switch self {
            case .denied:
                return "Worthwise uses the camera only to photograph your items. You can also choose a photo from your library."
            case .unavailable:
                return "You can choose a photo from your library instead."
            }
        }
    }

    @MainActor
    static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @MainActor
    static func request(_ completion: @escaping @MainActor (Result) -> Void) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            completion(.unavailable)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(.granted)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    completion(granted ? .granted : .denied)
                }
            }
        case .denied, .restricted:
            completion(.denied)
        @unknown default:
            completion(.unavailable)
        }
    }
}

// MARK: - Shapes

/// Four rounded corner brackets, like a camera viewfinder.
struct ViewfinderCorners: Shape {
    var length: CGFloat = 26
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length, r = radius
        // Top left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // Top right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // Bottom right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // Bottom left
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}
