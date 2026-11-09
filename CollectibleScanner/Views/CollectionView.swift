import SwiftUI
import UIKit

// MARK: - Collection tab (04 §6.7, 05 §3.8)

struct CollectionView: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    /// Transition only: when ContentView passes a closure it is used for
    /// "Scan your first item"; otherwise the router starts a gated scan
    /// (04 §2.5: `router.tab = .scan; router.startScan(.camera)`).
    var onScan: (() -> Void)? = nil

    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Segment: String, CaseIterable, Identifiable {
        case items = "Items"
        case folders = "Folders"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case value = "Highest Value"
        case name = "Name"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .items
    /// Per-viewer convenience: the last sort survives relaunch.
    @AppStorage("ww.collectionSort") private var sort: SortOrder = .newest
    @State private var search = ""

    // Select mode (04 §5.4, CL7)
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var showMoveNewFolder = false
    @State private var moveFolderName = ""
    @State private var confirmRemove = false

    // New Folder from the options menu / the dashed row
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    // Export (CL8)
    @State private var isExporting = false
    @State private var exportFile: CollectionExportFile?

    @State private var toast: WWToastModel?

    init(onScan: (() -> Void)? = nil) {
        self.onScan = onScan
    }

    private var margin: CGFloat { WW.margin(for: dynamicTypeSize) }

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var visibleItems: [SavedCollectible] {
        let filtered = CollectionView.filter(collectionStore.items, query: query)
        return CollectionView.sorted(filtered, by: sort)
    }

    private var visibleFolders: [CollectibleSet] {
        guard !query.isEmpty else { return collectionStore.sets }
        return collectionStore.sets.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Selected ids that still exist, in screen order.
    private var selectedIDs: [UUID] {
        visibleItems.filter { selection.contains($0.id) }.map(\.id)
    }

    private var allVisibleSelected: Bool {
        let items = visibleItems
        return !items.isEmpty && items.allSatisfy { selection.contains($0.id) }
    }

    private var navigationTitleText: String {
        isSelecting ? "\(selectedIDs.count) Selected" : "Collection"
    }

    private var selectAllTitle: String {
        allVisibleSelected ? "Deselect All" : "Select All"
    }

    private var exportTitle: String {
        isExporting ? "Preparing…" : "Export Spreadsheet…"
    }

    var body: some View {
        NavigationStack {
            screen
                .navigationDestination(for: UUID.self) { id in
                    ItemDetailView(itemID: id)
                }
                .navigationDestination(for: FolderRoute.self) { route in
                    FolderDetailView(folderID: route.id, onFolderDeleted: showFolderDeletedToast)
                }
        }
    }

    // MARK: Screen

    private var screen: some View {
        scroll
            .background(WW.background)
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your collection")
            .toolbar { toolbarContent }
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .wwToast($toast)
            // Pro: price histories for saved items, and their daily tracking
            // on the server. Throttled inside the store.
            .task(id: creditManager.isPro) {
                guard creditManager.isPro else { return }
                await collectionStore.refreshHistories(appUserID: creditManager.appUserID)
            }
            .onAppear(perform: settleArrivals)
            .onChange(of: collectionStore.justSaved) { _, _ in settleArrivals() }
            .onChange(of: collectionStore.items.isEmpty) { _, isEmpty in
                if isEmpty { exitSelectMode() }
            }
            .sheet(item: $exportFile) { file in
                WWActivitySheet(items: [CollectionCSVActivityItem(url: file.url)])
                    .ignoresSafeArea()
                    .presentationDetents([.medium, .large])
            }
    }

    private var scroll: some View {
        ScrollView {
            scrollContent
                .padding(.horizontal, margin)
                .padding(.bottom, WW.Space.xl)
        }
        // Keeps the last row and "Scan your first item" clear of the
        // floating tab bar on iOS 26 (00 addition 5).
        .contentMargins(.bottom, WW.Space.xl, for: .scrollContent)
        // The tab root only: pushed screens and sheets keep their edge effect.
        .wwContentUnderTabBar()
    }

    @ViewBuilder
    private var scrollContent: some View {
        if collectionStore.items.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 0) {
                CollectionTotalCard(items: collectionStore.items, folders: collectionStore.sets.count)
                    .padding(.top, WW.Space.xxs)
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isSelecting)
                .padding(.top, WW.Space.md)
                segmentContent
                    .padding(.top, WW.Space.md)
            }
        }
    }

    @ViewBuilder
    private var segmentContent: some View {
        if segment == .items || isSelecting {
            itemsSection
        } else {
            foldersSection
        }
    }

    // MARK: Items

    @ViewBuilder
    private var itemsSection: some View {
        let items = visibleItems
        if items.isEmpty {
            CollectionSearchEmpty(query: query)
        } else {
            CollectionItemGrid(
                items: items,
                isSelecting: isSelecting,
                selection: selection,
                arriving: collectionStore.justSaved,
                onToggle: toggle
            )
        }
    }

    // MARK: Folders

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: WW.Space.sm) {
            CollectionNewFolderRow {
                newFolderName = ""
                showNewFolder = true
            }
            if collectionStore.sets.isEmpty {
                Text("Folders group items your way, like coins, records or one room of a house. Items stay in Items too.")
                    .wwFont(.subhead)
                    .foregroundStyle(WW.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if visibleFolders.isEmpty {
                CollectionSearchEmpty(query: query)
            }
            ForEach(visibleFolders) { folder in
                NavigationLink(value: FolderRoute(id: folder.id)) {
                    FolderRow(folder: folder)
                }
                .buttonStyle(WWPressableStyle())
            }
        }
    }

    // MARK: Empty (CL1, 07 §3)

    private var emptyState: some View {
        WWEmptyState(
            title: "Nothing saved yet",
            message: "Scan something you own and save it here. You'll see what it all adds up to.",
            actionTitle: "Scan your first item",
            actionImage: "camera",
            action: startFirstScan,
            footnote: collectionStore.recentScans.isEmpty ? nil : "Or open a recent scan and tap Save to collection.",
            illustration: AnyView(CollectionEmptyShelf()),
            details: AnyView(CollectionEmptyInfoRows())
        )
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(selectAllTitle) {
                    toggleSelectAll()
                }
                .buttonStyle(.wwBarText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { exitSelectMode() }
                    .buttonStyle(.wwBarTextProminent)
                    .fontWeight(.semibold)
            }
            SelectionBar(
                count: selectedIDs.count,
                context: .collection,
                folders: collectionStore.sets,
                showNewFolder: $showMoveNewFolder,
                newFolderName: $moveFolderName,
                confirmRemove: $confirmRemove,
                onMove: move(to:),
                onCreateAndMove: createFolderAndMove,
                onRemove: removeSelected
            )
        }
        if !isSelecting && !collectionStore.items.isEmpty {
            if isExporting {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .accessibilityLabel("Preparing spreadsheet")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { enterSelectMode() }
                    .buttonStyle(.wwBarText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                newFolderName = ""
                showNewFolder = true
            } label: {
                Label("New Folder…", systemImage: "folder.badge.plus")
            }
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(SortOrder.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            Button {
                startExport()
            } label: {
                Label(exportTitle, systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting)
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Collection options")
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Coins, cards, vases…", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    // MARK: Actions

    private func startFirstScan() {
        if let onScan {
            onScan()
        } else {
            router.tab = .scan
            router.startScan(.camera)
        }
    }

    private var standardAnimation: Animation? {
        WW.Motion.animation(.standard, reduceMotion: reduceMotion)
    }

    private func enterSelectMode() {
        withAnimation(standardAnimation) {
            segment = .items
            selection = []
            isSelecting = true
        }
    }

    private func exitSelectMode() {
        guard isSelecting || !selection.isEmpty else { return }
        withAnimation(standardAnimation) {
            isSelecting = false
            selection = []
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(standardAnimation) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        }
        Haptics.selection()
    }

    private func toggleSelectAll() {
        let ids = Set(visibleItems.map(\.id))
        withAnimation(standardAnimation) {
            if allVisibleSelected {
                selection = []
            } else {
                selection = ids
            }
        }
        Haptics.selection()
    }

    private func move(to folderID: UUID?) {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        var result: WWToastModel? = nil
        withAnimation(standardAnimation) {
            result = CollectionSelectionActions.move(ids, to: folderID, store: collectionStore)
        }
        exitSelectMode()
        if let result { toast = result }
    }

    private func createFolderAndMove() {
        let ids = selectedIDs
        let name = moveFolderName
        moveFolderName = ""
        guard !ids.isEmpty else { return }
        var outcome: CollectionSelectionActions.Outcome = .failed(nil)
        withAnimation(standardAnimation) {
            outcome = CollectionSelectionActions.createFolderAndMove(ids, name: name, store: collectionStore)
        }
        switch outcome {
        case .done(let model):
            exitSelectMode()
            toast = model
        case .failed(let model):
            if let model { toast = model }
        }
    }

    private func removeSelected() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        var result: WWToastModel? = nil
        withAnimation(standardAnimation) {
            result = CollectionSelectionActions.removeFromCollection(ids, store: collectionStore)
        }
        exitSelectMode()
        if let result { toast = result }
    }

    private func createFolder() {
        let name = newFolderName
        newFolderName = ""
        switch collectionStore.createSet(named: name) {
        case .success:
            withAnimation(standardAnimation) { segment = .folders }
        case .emptyName:
            toast = WWToastModel(message: "Give the folder a name.", isSuccess: false)
        case .duplicateName:
            toast = WWToastModel(message: "A folder with that name already exists.", isSuccess: false)
        }
    }

    private func showFolderDeletedToast() {
        toast = WWToastModel(message: "Folder deleted. Its items are still in Items.")
    }

    /// 06 M16: tiles saved since this screen last appeared settle in once;
    /// then their marks are cleared.
    private func settleArrivals() {
        let ids = collectionStore.justSaved
        guard !ids.isEmpty else { return }
        let store = collectionStore
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            store.clearJustSaved(ids)
        }
    }

    /// CL8: "Preparing…" while the CSV is built off the main thread, then
    /// the share sheet; a toast if it fails.
    private func startExport() {
        guard !isExporting else { return }
        isExporting = true
        let items = collectionStore.items
        let sets = collectionStore.sets
        let code = DisplayCurrency.code
        let locale = Locale.current
        Task { @MainActor in
            let url: URL? = await Task.detached(priority: .userInitiated) { () -> URL? in
                let csv = CollectionStore.csv(items: items, sets: sets, locale: locale, currencyCode: code)
                return CollectionStore.writeCSVFile(csv, date: Date())
            }.value
            isExporting = false
            if let url {
                exportFile = CollectionExportFile(url: url)
            } else {
                toast = WWToastModel(message: "Couldn't create the spreadsheet. Try again.", isSuccess: false)
            }
        }
    }

    // MARK: Filtering and sorting (shared with folders)

    /// Search looks at names, makers and categories (07 §3 CL5).
    static func filter(_ items: [SavedCollectible], query: String) -> [SavedCollectible] {
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.probableCategory.rawValue.localizedCaseInsensitiveContains(query)
                || (item.brand ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    /// 04 §4.4: "Highest Value" keeps C and D out of the top.
    static func sorted(_ items: [SavedCollectible], by order: SortOrder) -> [SavedCollectible] {
        switch order {
        case .newest:
            return items.sorted { $0.savedAt > $1.savedAt }
        case .value:
            return CollectionStore.sortByValue(items)
        case .name:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}

struct FolderRoute: Hashable {
    let id: UUID
}

// MARK: - Select mode (04 §5.4, 05 §2.39, 06 M18–M20)

/// What a bulk action did, as a toast (with Undo where 06 allows it).
@MainActor
private enum CollectionSelectionActions {
    enum Outcome {
        case done(WWToastModel)
        /// Nothing changed; an optional error toast.
        case failed(WWToastModel?)
    }

    /// Move to a folder, or out of every folder (`folderID == nil`).
    static func move(_ ids: [UUID], to folderID: UUID?, store: CollectionStore) -> WWToastModel? {
        guard !ids.isEmpty else { return nil }
        let snapshot = store.membershipSnapshot(for: ids)
        let count = ids.count
        if let folderID {
            guard let folder = store.sets.first(where: { $0.id == folderID }) else { return nil }
            store.assignItems(ids, toSetID: folderID)
            Haptics.notify(.success)
            let message = count == 1 ? "Moved to \(folder.name)" : "Moved \(count) items to \(folder.name)"
            return undoToast(message, snapshot: snapshot, store: store)
        }

        // No Folder: "Taken out of {folder}. It's still in Items."
        var folderNames: [String] = []
        for id in ids {
            if let folder = store.setContaining(itemID: id), !folderNames.contains(folder.name) {
                folderNames.append(folder.name)
            }
        }
        guard !folderNames.isEmpty else { return nil }
        for id in ids {
            store.clearSetAssignment(for: id)
        }
        Haptics.notify(.success)
        let message: String
        if folderNames.count == 1 {
            message = count == 1
                ? "Taken out of \(folderNames[0]). It's still in Items."
                : "Taken out of \(folderNames[0]). They're still in Items."
        } else {
            message = "Taken out of their folders. They're still in Items."
        }
        return undoToast(message, snapshot: snapshot, store: store)
    }

    /// "New Folder…" › Create and Move.
    static func createFolderAndMove(_ ids: [UUID], name: String, store: CollectionStore) -> Outcome {
        switch store.validateSetName(name) {
        case .emptyName:
            return .failed(WWToastModel(message: "Give the folder a name.", isSuccess: false))
        case .duplicateName:
            return .failed(WWToastModel(message: "A folder with that name already exists.", isSuccess: false))
        case .success:
            break
        }
        guard let folderID = store.createSetReturningID(named: name) else { return .failed(nil) }
        guard let model = move(ids, to: folderID, store: store) else { return .failed(nil) }
        return .done(model)
    }

    /// Remove from Collection: never deletes; items stay in Recent scans.
    static func removeFromCollection(_ ids: [UUID], store: CollectionStore) -> WWToastModel? {
        guard !ids.isEmpty else { return nil }
        let snapshot = store.membershipSnapshot(for: ids)
        store.removeFromCollection(ids: ids)
        let message = ids.count == 1
            ? "Removed from your collection. It's still in Recent scans."
            : "Removed \(ids.count) items. They're still in Recent scans."
        return undoToast(message, snapshot: snapshot, store: store)
    }

    /// Remove from Folder: no dialog (reversible), toast with Undo.
    static func removeFromFolder(_ ids: [UUID], folder: CollectibleSet, store: CollectionStore) -> WWToastModel? {
        guard !ids.isEmpty else { return nil }
        let snapshot = store.membershipSnapshot(for: ids)
        store.removeItems(ids, fromSetID: folder.id)
        let message = ids.count == 1
            ? "Removed from \(folder.name)"
            : "Removed \(ids.count) items from \(folder.name)"
        return undoToast(message, snapshot: snapshot, store: store)
    }

    /// Undo puts everything back and says "Undone" (no toast, 06 §4.4).
    static func undoToast(_ message: String, snapshot: CollectionStore.MembershipSnapshot, store: CollectionStore) -> WWToastModel {
        WWToastModel(message: message, actionTitle: "Undo", action: {
            store.restore(snapshot)
            UIAccessibility.post(notification: .announcement, argument: "Undone")
        })
    }
}

/// The select-mode bottom toolbar (05 §2.39): Move to Folder ▸ on the
/// leading side; Remove (collection, with a dialog) or Remove from Folder
/// (folder, no dialog) on the trailing side. Disabled at 0 selected. The
/// host hides the tab bar while it shows. Its alert and dialog are attached
/// to the controls that trigger them (04 §2.2).
struct SelectionBar: ToolbarContent {
    enum Context: Equatable {
        case collection
        case folder(UUID)
    }

    let count: Int
    let context: Context
    let folders: [CollectibleSet]
    @Binding var showNewFolder: Bool
    @Binding var newFolderName: String
    @Binding var confirmRemove: Bool
    /// nil = No Folder.
    let onMove: (UUID?) -> Void
    let onCreateAndMove: () -> Void
    let onRemove: () -> Void

    init(count: Int, context: Context, folders: [CollectibleSet],
         showNewFolder: Binding<Bool>, newFolderName: Binding<String>, confirmRemove: Binding<Bool>,
         onMove: @escaping (UUID?) -> Void, onCreateAndMove: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.count = count
        self.context = context
        self.folders = folders
        self._showNewFolder = showNewFolder
        self._newFolderName = newFolderName
        self._confirmRemove = confirmRemove
        self.onMove = onMove
        self.onCreateAndMove = onCreateAndMove
        self.onRemove = onRemove
    }

    private var currentFolderID: UUID? {
        if case .folder(let id) = context { return id }
        return nil
    }

    private var destinations: [CollectibleSet] {
        folders.filter { $0.id != currentFolderID }
    }

    private var removeTitle: String {
        count == 1 ? "Remove 1 item from your collection?" : "Remove \(count) items from your collection?"
    }

    private var removeButtonTitle: String {
        count == 1 ? "Remove 1 Item" : "Remove \(count) Items"
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            moveMenu
            Spacer()
            removeControl
        }
    }

    private var moveMenu: some View {
        Menu {
            Section {
                Button {
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }
                Button {
                    onMove(nil)
                } label: {
                    Label("No Folder", systemImage: "tray")
                }
            }
            Section {
                ForEach(destinations) { folder in
                    Button(folder.name) { onMove(folder.id) }
                }
            }
        } label: {
            Text("Move to Folder")
        }
        .menuStyle(.button)
        .buttonStyle(.wwBarText)
        .disabled(count == 0)
        .accessibilityHint("Choose a folder for the selected items")
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Coins, cards, vases…", text: $newFolderName)
            Button("Create and Move") { onCreateAndMove() }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    @ViewBuilder
    private var removeControl: some View {
        switch context {
        case .collection:
            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Text("Remove")
            }
            .buttonStyle(.wwBarText)
            .disabled(count == 0)
            .confirmationDialog(removeTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(removeButtonTitle, role: .destructive) { onRemove() }
                Button("Cancel", role: WW.dialogCancelRole) {}
            } message: {
                Text(count == 1 ? "It stays in Recent scans." : "They stay in Recent scans.")
            }
        case .folder:
            Button {
                onRemove()
            } label: {
                Text("Remove from Folder")
            }
            .buttonStyle(.wwBarText)
            .disabled(count == 0)
        }
    }
}

// MARK: - Grid (shared by Collection, Folder, Add Items)

/// 2 columns (1 at accessibility sizes), 12 apart, rows 20 apart, top-aligned
/// so tiles with one-line prices don't stretch (05 §2.20, §3.8).
private struct CollectionItemGrid: View {
    let items: [SavedCollectible]
    let isSelecting: Bool
    let selection: Set<UUID>
    /// `CollectionStore.justSaved`: these tiles settle in once (06 M16).
    let arriving: Set<UUID>
    /// Add Items: "In {other folder}" under a tile's title.
    var folderNote: ((SavedCollectible) -> String?)? = nil
    let onToggle: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: WW.Space.sm, alignment: .top), count: count)
    }

    /// Stagger order among the arriving tiles, at most 6 (06 §2.1).
    private var arrivalOrder: [UUID: Int] {
        var order: [UUID: Int] = [:]
        var next = 0
        for item in items where arriving.contains(item.id) {
            order[item.id] = next
            next += 1
        }
        return order
    }

    private var leaveTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.opacity.combined(with: .scale(scale: 0.92))
    }

    var body: some View {
        let order = arrivalOrder
        LazyVGrid(columns: columns, alignment: .leading, spacing: WW.Space.lg) {
            ForEach(items) { item in
                cell(item)
                    .modifier(CollectionTileArrival(isArriving: order[item.id] != nil, index: order[item.id] ?? 0))
                    .transition(leaveTransition)
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: SavedCollectible) -> some View {
        let note: String? = folderNote?(item)
        if isSelecting {
            Button {
                onToggle(item.id)
            } label: {
                ItemTile(
                    item: item,
                    selection: selection.contains(item.id) ? .selected : .unselected,
                    folderNote: note
                )
            }
            .buttonStyle(WWPressableStyle())
        } else {
            NavigationLink(value: item.id) {
                ItemTile(item: item, folderNote: note)
            }
            .buttonStyle(WWPressableStyle())
        }
    }
}

/// 06 M16: opacity 0 → 1 and scale .94 → 1, staggered 0.05 s (opacity only
/// under Reduce Motion). Tiles that aren't arriving render as usual.
private struct CollectionTileArrival: ViewModifier {
    let isArriving: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasSettled = false

    private var isVisible: Bool { !isArriving || hasSettled }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.94)
            .onAppear(perform: settle)
    }

    private func settle() {
        guard isArriving, !hasSettled else { return }
        let base: Animation = WW.Motion.animation(.settle, reduceMotion: reduceMotion) ?? Animation.easeOut(duration: 0.2)
        let delay = WW.Motion.staggerDelay(index: index, reduceMotion: reduceMotion)
        withAnimation(base.delay(delay)) {
            hasSettled = true
        }
    }
}

/// CL5 (07 §3): stays native.
private struct CollectionSearchEmpty: View {
    let query: String

    var body: some View {
        ContentUnavailableView {
            Label("No results for “\(query)”", systemImage: "magnifyingglass")
        } description: {
            Text("Search looks at names, makers and categories. Try fewer words.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, WW.Space.xl)
    }
}

/// The dashed "New folder" row (05 §2.21).
private struct CollectionNewFolderRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New folder", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: WW.Size.rowTall)
                .overlay {
                    RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
                        .strokeBorder(WW.track, style: StrokeStyle(lineWidth: WW.Stroke.dashedSlot, dash: WW.Stroke.dashSlot))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(WWTertiaryButtonStyle(tone: .accent))
    }
}

/// 07's empty shelf (220 × 104 `accentWash`, r 20): three `surface` tiles,
/// the middle one carrying the Tag. Decorative.
private struct CollectionEmptyShelf: View {
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: WW.Space.sm) {
            tile(side: 48) {
                Image(systemName: WW.coinSymbol())
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(WW.tertiaryText)
            }
            tile(side: 60) {
                WorthwiseMark(size: 28, tone: .accent)
            }
            tile(side: 48) {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(WW.tertiaryText)
            }
        }
        .frame(width: 220, height: 104)
        .background(WW.accentWash, in: RoundedRectangle(cornerRadius: WW.Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }

    private func tile<Content: View>(side: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: side, height: side)
            .background(WW.surface, in: RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous))
    }
}

/// CL1 info rows (07 §3).
private struct CollectionEmptyInfoRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WW.Space.md) {
            WWInfoRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "A running total",
                detail: "Only items with a firm price count, so the total means something."
            )
            WWInfoRow(
                icon: "folder",
                title: "Folders your way",
                detail: "Group items like coins, records or one room of a house."
            )
            WWInfoRow(
                icon: "lock",
                title: "Kept on your iPhone",
                detail: "Saved items and their photos stay on this device."
            )
        }
        .wwCard(padding: WW.Space.md)
    }
}

// MARK: - Export (CL8)

private struct CollectionExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The CSV file for the activity sheet, with the mail subject
/// "My Worthwise collection" (06 §4.4).
/// Internal, not private: Settings › Export Spreadsheet shares the same item.
final class CollectionCSVActivityItem: NSObject, UIActivityItemSource {
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        "My Worthwise collection"
    }
}

// MARK: - Total card (04 §6.7 CL3/CL4, 05 §2.38, 06 M17)

/// "Estimated value" + the counted total (A and B only) + counts + the
/// "aren't counted" line. CL4: "No total yet". The folder header uses the
/// same card at `.priceLarge`. Money crossfades and never rolls.
struct CollectionTotalCard: View {
    enum Style {
        case collection
        case folder
    }

    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let items: [SavedCollectible]
    let folders: Int
    let style: Style

    init(items: [SavedCollectible], folders: Int = 0, style: Style = .collection) {
        self.items = items
        self.folders = folders
        self.style = style
    }

    var body: some View {
        let totals = CollectionStore.totals(for: items)
        VStack(alignment: .leading, spacing: 0) {
            if totals.hasTotal {
                valueBlock(totals)
            } else {
                noTotalBlock
            }
            Text(countLine)
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WW.Space.xs)
            if totals.hasTotal && totals.uncounted > 0 {
                uncountedLine(totals.uncounted)
                    .padding(.top, WW.Space.sm)
                    .transition(.opacity)
            }
        }
        .wwAnimation(.crossfade, value: items.count)
        .wwAnimation(.standard, value: totals.uncounted)
        .wwCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(totals))
    }

    private func valueBlock(_ totals: CollectionStore.Totals) -> some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            Text("Estimated value")
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
            ZStack(alignment: .leading) {
                ValueRangeText(
                    lowUSD: totals.low,
                    highUSD: totals.high,
                    role: style == .folder ? .priceLarge : .total
                )
                .id(moneyKey(totals))
                .transition(.opacity)
            }
            .wwAnimation(.crossfade, value: moneyKey(totals))
        }
    }

    private var noTotalBlock: some View {
        VStack(alignment: .leading, spacing: WW.Space.xxs) {
            Text("No total yet")
                .wwFont(.itemTitle)
                .foregroundStyle(WW.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(style == .folder
                 ? "None of the items in this folder has a firm enough price to add up."
                 : "None of your items has a firm enough price to add up.")
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func uncountedLine(_ count: Int) -> some View {
        Label {
            Text(CollectionTotalCard.uncountedSentence(count))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .labelStyle(WWInlineIconLabelStyle(spacing: 6))
        .wwFont(.footnote)
        .foregroundStyle(WW.secondaryText)
    }

    /// Changes whenever the shown money changes (values or currency).
    private func moneyKey(_ totals: CollectionStore.Totals) -> String {
        "\(totals.low)|\(totals.high)|\(displayCurrency)"
    }

    private var countLine: String {
        let itemsText = items.count == 1 ? "1 item" : "\(items.count) items"
        guard style == .collection, folders > 0 else { return itemsText }
        let foldersText = folders == 1 ? "1 folder" : "\(folders) folders"
        return "\(itemsText) · \(foldersText)"
    }

    static func uncountedSentence(_ count: Int) -> String {
        count == 1
            ? "1 item isn't counted: its price is rough or missing."
            : "\(count) items aren't counted: their prices are rough or missing."
    }

    private func spokenSummary(_ totals: CollectionStore.Totals) -> String {
        var parts: [String] = []
        if totals.hasTotal {
            let low = WW.money(totals.low)
            let high = WW.money(totals.high)
            let range = low == high ? low : "between \(low) and \(high)"
            parts.append("Estimated value: \(range)")
        } else {
            parts.append("No total yet")
        }
        parts.append(countLine.replacingOccurrences(of: " · ", with: ", "))
        if totals.hasTotal && totals.uncounted > 0 {
            parts.append(CollectionTotalCard.uncountedSentence(totals.uncounted))
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Tiles (04 §7, 05 §2.20)

enum TileSelection {
    case unselected
    case selected
}

/// Square photo, name (2 lines) and a level-aware price line: the range
/// for A/B, the caveat word for C ("Wide range" / "Unsure match" / "Rough
/// guide"), "No price" for D. Money wraps after the en dash and never
/// truncates. At accessibility sizes the tile becomes a row.
struct ItemTile: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let item: SavedCollectible
    let compact: Bool
    /// In Recent scans: mark the ones already in the collection.
    let showsSavedState: Bool
    /// Select mode / Add Items: the selection circle (nil = no circle).
    let selection: TileSelection?
    /// Add Items: "In {other folder}" under the title.
    let folderNote: String?

    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: SavedCollectible, compact: Bool = false, showsSavedState: Bool = false,
         selection: TileSelection? = nil, folderNote: String? = nil) {
        self.item = item
        self.compact = compact
        self.showsSavedState = showsSavedState
        self.selection = selection
        self.folderNote = folderNote
    }

    private var isAX: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isSelected: Bool { selection == .selected }
    private var showsSavedBadge: Bool { showsSavedState && item.isInCollection }

    var body: some View {
        content
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(selectedTraits)
            .accessibilityHint(hintText)
    }

    private var hintText: String {
        selection == nil ? "" : "Double-tap to select"
    }

    @ViewBuilder
    private var content: some View {
        if isAX && compact {
            WWListRow(
                thumbnail: collectionStore.thumbnail(for: item.id),
                title: item.title,
                subtitle: folderNote,
                accessory: AnyView(ItemPriceLine(item: item, compact: false))
            )
        } else if isAX {
            axRow
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : WW.Space.xs) {
            photo(side: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .wwFont(compact ? WWTextRole.footnote : WWTextRole.subhead, weight: .semibold)
                    .foregroundStyle(WW.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let folderNote {
                    folderNoteText(folderNote)
                }
                ItemPriceLine(item: item, compact: compact)
            }
        }
    }

    private var axRow: some View {
        HStack(alignment: .top, spacing: WW.Space.sm) {
            photo(side: WW.Size.thumbAX)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .wwFont(.headline)
                    .foregroundStyle(WW.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let folderNote {
                    folderNoteText(folderNote)
                }
                ItemPriceLine(item: item, compact: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func folderNoteText(_ note: String) -> some View {
        Label(note, systemImage: "folder")
            .labelStyle(WWInlineIconLabelStyle(spacing: 4))
            .wwFont(.footnote)
            .foregroundStyle(WW.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The square photo (side nil = fill the column width).
    private func photo(side: CGFloat?) -> some View {
        let radius: CGFloat = side == nil ? WW.Radius.tile : WW.Radius.control
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side, height: side)
            .overlay { thumbnail }
            .background(WW.photoBackdrop)
            .clipShape(shape)
            .overlay { selectionBorder(shape) }
            .overlay { contrastStroke(shape) }
            .scaleEffect(isSelected && !reduceMotion ? 0.96 : 1)
            .overlay(alignment: .topTrailing) { savedBadge }
            .overlay(alignment: .topLeading) { selectionCircle }
            .wwAnimation(.standard, value: isSelected)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb = collectionStore.thumbnail(for: item.id) {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFill()
        } else {
            PhotoPlaceholder()
        }
    }

    @ViewBuilder
    private func selectionBorder(_ shape: RoundedRectangle) -> some View {
        if isSelected {
            shape.strokeBorder(WW.accent, lineWidth: WW.Stroke.tileSelected)
        }
    }

    @ViewBuilder
    private func contrastStroke(_ shape: RoundedRectangle) -> some View {
        if contrast == .increased && !isSelected {
            shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
        }
    }

    @ViewBuilder
    private var savedBadge: some View {
        if showsSavedBadge {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(WW.scrim, in: Circle())
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    private var circleTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.scale(scale: 0.6).combined(with: .opacity)
    }

    @ViewBuilder
    private var selectionCircle: some View {
        if let selection {
            ZStack {
                Circle()
                    .fill(selection == .selected ? WW.accentFill : WW.scrim)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                if selection == .selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: WW.Size.selectionCircle, height: WW.Size.selectionCircle)
            .padding(WW.Space.xs)
            .transition(circleTransition)
            .accessibilityHidden(true)
        }
    }

    private var selectedTraits: AccessibilityTraits {
        isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits()
    }

    /// "{title}, {between low and high | rough guide: {word} | no price}{, in your collection}" (05 §2.20).
    private var spokenLabel: String {
        var parts: [String] = [item.title, ItemPriceLine.spoken(for: item.assessment)]
        if let folderNote { parts.append(folderNote) }
        if showsSavedBadge { parts.append("in your collection") }
        return parts.joined(separator: ", ")
    }
}

/// The level-aware price line used by tiles and Recent Scans rows (04 §4.4).
private struct ItemPriceLine: View {
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let item: SavedCollectible
    let compact: Bool

    var body: some View {
        let assessment = item.assessment
        switch assessment.level {
        case .strong, .fair:
            ValueRangeText(
                lowUSD: assessment.lowUSD,
                highUSD: assessment.highUSD,
                role: compact ? .priceCompact : .priceSmall
            )
        case .rough:
            roughWord(assessment)
        case .noPrice:
            Text("No price")
                .wwFont(compact ? WWTextRole.footnote : WWTextRole.subhead)
                .foregroundStyle(WW.secondaryText)
        }
    }

    @ViewBuilder
    private func roughWord(_ assessment: ValueAssessment) -> some View {
        if compact {
            Label(assessment.roughWord, systemImage: assessment.roughGlyph)
                .labelStyle(WWInlineIconLabelStyle(spacing: 4))
                .wwFont(.footnote, weight: .semibold)
                .foregroundStyle(WW.caution)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            CaveatFlag.roughGuide(assessment.roughWord, glyph: assessment.roughGlyph)
        }
    }

    /// The price part of a tile's VoiceOver label.
    static func spoken(for assessment: ValueAssessment) -> String {
        switch assessment.level {
        case .strong, .fair:
            let low = WW.money(assessment.lowUSD)
            let high = WW.money(assessment.highUSD)
            return low == high ? low : "between \(low) and \(high)"
        case .rough:
            let word = assessment.roughWord
            return word == "Rough guide" ? "rough guide" : "rough guide: \(word)"
        case .noPrice:
            return "no price"
        }
    }
}

// MARK: - Folder row (05 §2.21)

/// Mosaic, name, "{n} items", the counted total and "{u} not counted".
struct FolderRow: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let folder: CollectibleSet

    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.colorSchemeContrast) private var contrast

    init(folder: CollectibleSet) {
        self.folder = folder
    }

    var body: some View {
        let items = collectionStore.items(in: folder)
        let totals = CollectionStore.totals(for: items)
        let shape = RoundedRectangle(cornerRadius: WW.Radius.tile, style: .continuous)
        HStack(alignment: .center, spacing: WW.Space.sm) {
            CollectionFolderMosaic(thumbnails: items.prefix(4).map { collectionStore.thumbnail(for: $0.id) })
            details(items: items, totals: totals)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WW.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(WW.Space.sm)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(WW.surface, in: shape)
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(WW.separator, lineWidth: WW.Stroke.hc)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(itemCount: items.count, totals: totals))
    }

    private func details(items: [SavedCollectible], totals: CollectionStore.Totals) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(folder.name)
                .wwFont(.headline)
                .foregroundStyle(WW.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(itemCountText(items.count))
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
            if totals.hasTotal {
                ValueRangeText(lowUSD: totals.low, highUSD: totals.high, role: .priceSmall)
                    .padding(.top, 2)
                if totals.uncounted > 0 {
                    Text("\(totals.uncounted) not counted")
                        .wwFont(.footnote)
                        .foregroundStyle(WW.secondaryText)
                }
            } else if !items.isEmpty {
                Text("No total yet")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemCountText(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// "{name}, {n} items, {total or 'no total yet'}{, u not counted}".
    private func spoken(itemCount: Int, totals: CollectionStore.Totals) -> String {
        var parts: [String] = [folder.name, itemCountText(itemCount)]
        if totals.hasTotal {
            let low = WW.money(totals.low)
            let high = WW.money(totals.high)
            parts.append(low == high ? low : "between \(low) and \(high)")
            if totals.uncounted > 0 { parts.append("\(totals.uncounted) not counted") }
        } else if itemCount > 0 {
            parts.append("no total yet")
        }
        return parts.joined(separator: ", ")
    }
}

/// 64 pt, r 10, 2 × 2 thumbnails with 1 pt `separator` gaps; empty cells `fill`.
private struct CollectionFolderMosaic: View {
    let thumbnails: [UIImage?]

    private let cellSide: CGFloat = 31.5

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                cell(0)
                cell(1)
            }
            HStack(spacing: 1) {
                cell(2)
                cell(3)
            }
        }
        .frame(width: 64, height: 64)
        .background(WW.separator)
        .clipShape(RoundedRectangle(cornerRadius: WW.Radius.control, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if index < thumbnails.count, let image = thumbnails[index] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cellSide, height: cellSide)
                .clipped()
        } else {
            ZStack {
                WW.surface
                WW.fill
            }
            .frame(width: cellSide, height: cellSide)
        }
    }
}

// MARK: - Folder detail (04 §6.8, 05 §3.9)

struct FolderDetailView: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    @AppStorage("ww.collectionSort") private var sort: CollectionView.SortOrder = .newest
    let folderID: UUID
    /// The host shows "Folder deleted…" after the pop.
    let onFolderDeleted: () -> Void

    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var showMoveNewFolder = false
    @State private var moveFolderName = ""
    /// Unused in a folder (Remove from Folder has no dialog); SelectionBar needs a binding.
    @State private var confirmRemove = false
    @State private var showAddItems = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDuplicateName = false
    @State private var confirmDelete = false
    @State private var toast: WWToastModel?

    init(folderID: UUID, onFolderDeleted: @escaping () -> Void = {}) {
        self.folderID = folderID
        self.onFolderDeleted = onFolderDeleted
    }

    private var folder: CollectibleSet? {
        collectionStore.sets.first { $0.id == folderID }
    }

    private var folderItems: [SavedCollectible] {
        guard let folder else { return [] }
        return CollectionView.sorted(collectionStore.items(in: folder), by: sort)
    }

    private var selectedIDs: [UUID] {
        folderItems.filter { selection.contains($0.id) }.map(\.id)
    }

    private var allSelected: Bool {
        let items = folderItems
        return !items.isEmpty && items.allSatisfy { selection.contains($0.id) }
    }

    private var margin: CGFloat { WW.margin(for: dynamicTypeSize) }

    private var standardAnimation: Animation? {
        WW.Motion.animation(.standard, reduceMotion: reduceMotion)
    }

    private var titleText: String {
        if isSelecting { return "\(selectedIDs.count) Selected" }
        return folder?.name ?? "Folder"
    }

    private var selectAllTitle: String {
        allSelected ? "Deselect All" : "Select All"
    }

    var body: some View {
        scroll
            .background(WW.background)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
            .navigationBarBackButtonHidden(isSelecting)
            .toolbar { toolbarContent }
            .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
            .wwToast($toast)
            .onChange(of: folderItems.isEmpty) { _, isEmpty in
                if isEmpty { exitSelectMode() }
            }
            .sheet(isPresented: $showAddItems) {
                AddItemsSheet(folderID: folderID, onAdded: showAddedToast)
                    .environmentObject(collectionStore)
            }
    }

    private var scroll: some View {
        ScrollView {
            content
                .padding(.horizontal, margin)
                .padding(.bottom, WW.Space.xl)
                .alert("A folder with that name already exists.", isPresented: $showDuplicateName) {
                    Button("OK", role: .cancel) {}
                }
        }
        .contentMargins(.bottom, WW.Space.xl, for: .scrollContent)
    }

    @ViewBuilder
    private var content: some View {
        if let folder {
            let items = folderItems
            if items.isEmpty {
                emptyState(folder)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    CollectionTotalCard(items: items, style: .folder)
                        .padding(.top, WW.Space.xxs)
                    CollectionItemGrid(
                        items: items,
                        isSelecting: isSelecting,
                        selection: selection,
                        arriving: [],
                        onToggle: toggle
                    )
                    .padding(.top, WW.Space.md)
                }
            }
        } else {
            WWEmptyState(
                glyph: "folder",
                title: "This folder was deleted",
                message: "Its items are still in your collection."
            )
        }
    }

    /// F1 (07 §3): "Add items", or "Take a photo" when the collection is empty.
    @ViewBuilder
    private func emptyState(_ folder: CollectibleSet) -> some View {
        if collectionStore.items.isEmpty {
            WWEmptyState(
                glyph: "folder",
                title: "Nothing in \(folder.name) yet",
                message: "Scan something, then choose \(folder.name) when you save it.",
                actionTitle: "Take a photo",
                actionImage: "camera",
                action: { router.startScan(.camera) }
            )
        } else {
            WWEmptyState(
                glyph: "folder",
                title: "Nothing in \(folder.name) yet",
                message: "Add items from your collection. They stay in Items too.",
                actionTitle: "Add items",
                actionImage: "plus",
                action: { showAddItems = true }
            )
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(selectAllTitle) {
                    toggleSelectAll()
                }
                .buttonStyle(.wwBarText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { exitSelectMode() }
                    .buttonStyle(.wwBarTextProminent)
                    .fontWeight(.semibold)
            }
            SelectionBar(
                count: selectedIDs.count,
                context: .folder(folderID),
                folders: collectionStore.sets,
                showNewFolder: $showMoveNewFolder,
                newFolderName: $moveFolderName,
                confirmRemove: $confirmRemove,
                onMove: move(to:),
                onCreateAndMove: createFolderAndMove,
                onRemove: removeSelectedFromFolder
            )
        }
        if !isSelecting && folder != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddItems = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add items")
            }
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                showAddItems = true
            } label: {
                Label("Add Items…", systemImage: "plus")
            }
            Button {
                enterSelectMode()
            } label: {
                Label("Select Items", systemImage: "checkmark.circle")
            }
            .disabled(folderItems.isEmpty)
            Button {
                renameText = folder?.name ?? ""
                showRename = true
            } label: {
                Label("Rename Folder…", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Folder options")
        }
        .alert("Rename Folder", isPresented: $showRename) {
            TextField("Folder name", text: $renameText)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this folder?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Folder", role: .destructive) { deleteFolder() }
            Button("Cancel", role: WW.dialogCancelRole) {}
        } message: {
            Text("Its items stay in your collection.")
        }
    }

    // MARK: Actions

    private func enterSelectMode() {
        withAnimation(standardAnimation) {
            selection = []
            isSelecting = true
        }
    }

    private func exitSelectMode() {
        guard isSelecting || !selection.isEmpty else { return }
        withAnimation(standardAnimation) {
            isSelecting = false
            selection = []
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(standardAnimation) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        }
        Haptics.selection()
    }

    private func toggleSelectAll() {
        let ids = Set(folderItems.map(\.id))
        withAnimation(standardAnimation) {
            if allSelected {
                selection = []
            } else {
                selection = ids
            }
        }
        Haptics.selection()
    }

    private func move(to destination: UUID?) {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        var result: WWToastModel? = nil
        withAnimation(standardAnimation) {
            result = CollectionSelectionActions.move(ids, to: destination, store: collectionStore)
        }
        exitSelectMode()
        if let result { toast = result }
    }

    private func createFolderAndMove() {
        let ids = selectedIDs
        let name = moveFolderName
        moveFolderName = ""
        guard !ids.isEmpty else { return }
        var outcome: CollectionSelectionActions.Outcome = .failed(nil)
        withAnimation(standardAnimation) {
            outcome = CollectionSelectionActions.createFolderAndMove(ids, name: name, store: collectionStore)
        }
        switch outcome {
        case .done(let model):
            exitSelectMode()
            toast = model
        case .failed(let model):
            if let model { toast = model }
        }
    }

    private func removeSelectedFromFolder() {
        let ids = selectedIDs
        guard !ids.isEmpty, let folder else { return }
        var result: WWToastModel? = nil
        withAnimation(standardAnimation) {
            result = CollectionSelectionActions.removeFromFolder(ids, folder: folder, store: collectionStore)
        }
        exitSelectMode()
        if let result { toast = result }
    }

    private func rename() {
        let result = collectionStore.renameSet(id: folderID, to: renameText)
        if result == .duplicateName {
            // The rename alert is still closing; show the second one after it.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                showDuplicateName = true
            }
        }
    }

    private func deleteFolder() {
        let id = folderID
        let notify = onFolderDeleted
        dismiss()
        collectionStore.removeSet(id: id)
        notify()
    }

    private func showAddedToast(_ count: Int) {
        guard count > 0, let folder else { return }
        Haptics.notify(.success)
        toast = WWToastModel(message: count == 1 ? "Added to \(folder.name)" : "Added \(count) items to \(folder.name)")
    }
}

// MARK: - Add Items sheet (04 §5.4, §6.6, 05 §3.7)

/// Collection items that aren't in this folder yet; items in another folder
/// say "In {other}" and move here. Large sheet: Cancel / Add ({n}).
struct AddItemsSheet: View {
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let folderID: UUID
    let onAdded: (Int) -> Void

    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selection: Set<UUID> = []

    init(folderID: UUID, onAdded: @escaping (Int) -> Void = { _ in }) {
        self.folderID = folderID
        self.onAdded = onAdded
    }

    private var folder: CollectibleSet? {
        collectionStore.sets.first { $0.id == folderID }
    }

    private var candidates: [SavedCollectible] {
        guard let folder else { return [] }
        let here = Set(folder.itemIDs)
        return collectionStore.items
            .filter { !here.contains($0.id) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    private var chosenIDs: [UUID] {
        candidates.filter { selection.contains($0.id) }.map(\.id)
    }

    private var addTitle: String {
        let count = chosenIDs.count
        return count == 0 ? "Add" : "Add (\(count))"
    }

    private var anyInOtherFolder: Bool {
        candidates.contains { collectionStore.setContaining(itemID: $0.id) != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                sheetContent
                    .padding(.horizontal, WW.margin(for: dynamicTypeSize))
                    .padding(.bottom, WW.Space.xl)
            }
            .wwSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.wwBarText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addTitle) { add() }
                        .buttonStyle(.wwBarTextProminent)
                        .fontWeight(.semibold)
                        .disabled(chosenIDs.isEmpty)
                }
            }
        }
        .tint(WW.text)
        .presentationDetents([.large])
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            WWSheetHeader(title: "Add to \(folder?.name ?? "this folder")")
                .padding(.top, WW.Space.xs)
            if candidates.isEmpty {
                WWEmptyState(
                    glyph: "checkmark.circle",
                    title: "Nothing left to add",
                    message: "Everything in your collection is already here.",
                    style: .inline
                )
                .padding(.top, WW.Space.xl)
            } else {
                CollectionItemGrid(
                    items: candidates,
                    isSelecting: true,
                    selection: selection,
                    arriving: [],
                    folderNote: otherFolderNote,
                    onToggle: toggle
                )
                .padding(.top, WW.Space.xl)
                if anyInOtherFolder {
                    Text("Items in another folder move here.")
                        .wwFont(.footnote)
                        .foregroundStyle(WW.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, WW.Space.md)
                }
            }
        }
    }

    private func otherFolderNote(_ item: SavedCollectible) -> String? {
        guard let other = collectionStore.setContaining(itemID: item.id), other.id != folderID else { return nil }
        return "In \(other.name)"
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        Haptics.selection()
    }

    private func add() {
        let ids = chosenIDs
        guard !ids.isEmpty else { return }
        collectionStore.assignItems(ids, toSetID: folderID)
        let callback = onAdded
        dismiss()
        callback(ids.count)
    }
}

// MARK: - Item detail (04 §6.5, 05 §3.6)

/// A stored scan (in the collection or only in Recent scans), shown with the
/// same `ResultView` as a fresh result (`.stored` context). The result view
/// owns its menu, bar and record mutations; this host passes navigation only
/// and pops when the scan is deleted.
struct ItemDetailView: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let itemID: UUID

    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var creditManager: CreditManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Loaded once per item, not on every redraw (each load reads and decodes
    /// the photos from disk).
    @State private var photos: [UIImage] = []

    init(itemID: UUID) {
        self.itemID = itemID
    }

    var body: some View {
        Group {
            if let item = collectionStore.record(id: itemID) {
                ResultView(model: model(for: item), context: context(for: item))
            } else {
                deletedState
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: itemID) {
            photos = loadPhotos()
        }
    }

    /// RS-removed (05 §3.6).
    private var deletedState: some View {
        ScrollView {
            WWEmptyState(
                glyph: "trash",
                title: "This scan was deleted",
                message: "It's no longer in Recent scans or your collection."
            )
            .padding(.horizontal, WW.margin(for: dynamicTypeSize))
        }
        .background(WW.background)
    }

    private func context(for item: SavedCollectible) -> ResultContext {
        let id = item.id
        let rescan = router.rescan
        let openSettings = router.openSettings
        let pop = dismiss
        let appRouter = router
        let unlock: (() -> Void)? = creditManager.isPro ? nil : {
            appRouter.paywall = .listings
        }
        return ResultContext(
            origin: .stored,
            recordID: id,
            onRescan: { mode in rescan(id, mode) },
            onUnlock: unlock,
            onDeleted: { pop() },
            onOpenSettings: { openSettings() }
        )
    }

    private func model(for item: SavedCollectible) -> ResultModel {
        // The thumbnail is cached, so the header isn't empty while loading.
        let shown = photos.isEmpty ? [collectionStore.thumbnail(for: item.id)].compactMap { $0 } : photos
        return ResultModel(
            saved: item,
            photos: shown,
            history: collectionStore.histories[item.id],
            historyLocked: !creditManager.isPro
        )
    }

    private func loadPhotos() -> [UIImage] {
        guard let item = collectionStore.record(id: itemID) else { return [] }
        var loaded: [UIImage] = []
        if let image = collectionStore.image(for: item.id) {
            loaded.append(image)
        } else if let thumb = collectionStore.thumbnail(for: item.id) {
            loaded.append(thumb)
        }
        if item.hasSecondImage == true, let back = collectionStore.secondImage(for: item.id) {
            loaded.append(back)
        }
        return loaded
    }
}

// MARK: - Save to collection (transition)

/// Adds a stored scan to the collection, asking for a folder when there are
/// any (06 §4.6 copy, with New Folder…). Shows "Saved" / "Saved to {folder}"
/// once it's in. Kept for ContentView's current result screen; WP2's
/// `ResultActionBar` replaces it.
struct SaveToCollectionButton: View {
    let itemID: UUID
    let height: CGFloat

    @EnvironmentObject private var collectionStore: CollectionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var choosingFolder = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    init(itemID: UUID, height: CGFloat = 54) {
        self.itemID = itemID
        self.height = height
    }

    private var isSaved: Bool {
        collectionStore.record(id: itemID)?.isInCollection ?? false
    }

    private var savedTitle: String {
        if let folder = collectionStore.setContaining(itemID: itemID) {
            return "Saved to \(folder.name)"
        }
        return "Saved"
    }

    var body: some View {
        Button {
            if collectionStore.sets.isEmpty {
                save(to: nil)
            } else {
                choosingFolder = true
            }
        } label: {
            Label(isSaved ? savedTitle : "Save to collection",
                  systemImage: isSaved ? "checkmark" : "plus")
        }
        .buttonStyle(WWPrimaryButtonStyle(size: height < 48 ? .compact : .large))
        .disabled(isSaved)
        .confirmationDialog("Save to a folder?", isPresented: $choosingFolder, titleVisibility: .visible) {
            ForEach(collectionStore.sets) { folder in
                Button(folder.name) { save(to: folder.id) }
            }
            Button("New Folder…") { askForNewFolder() }
            Button("No Folder") { save(to: nil) }
            Button("Cancel", role: WW.dialogCancelRole) {}
        } message: {
            Text("It stays in Items either way.")
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Coins, cards, vases…", text: $newFolderName)
            Button("Create and Save") { createAndSave() }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
    }

    private func askForNewFolder() {
        newFolderName = ""
        // Let the dialog finish closing before the alert opens.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            showNewFolder = true
        }
    }

    private func createAndSave() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        if let id = collectionStore.createSetReturningID(named: name) {
            save(to: id)
        } else if let existing = collectionStore.sets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            save(to: existing.id)
        } else {
            save(to: nil)
        }
    }

    private func save(to folderID: UUID?) {
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            collectionStore.saveToCollection(id: itemID, folderID: folderID)
        }
        Haptics.notify(.success)
        let folderName = folderID.flatMap { id in collectionStore.sets.first(where: { $0.id == id })?.name }
        let announcement = folderName.map { "Saved to \($0)" } ?? "Saved to your collection"
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

// MARK: - Recent scans (04 §5.4, 05 §3.10, 07 §3 RC1)

struct RecentScansRoute: Hashable {}

/// Every scan, newest first, saved or not. Unsaved ones can be saved
/// (swipe right, long-press, or open them) or deleted; saved ones can be
/// hidden from this list and stay in the collection.
struct RecentScansView: View {
    @EnvironmentObject private var collectionStore: CollectionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirmClear = false
    @State private var pendingDelete: UUID?
    @State private var toast: WWToastModel?

    init() {}

    var body: some View {
        let scans = collectionStore.recentScans
        Group {
            if scans.isEmpty {
                emptyState
            } else {
                list(scans)
            }
        }
        .background(WW.background)
        .navigationTitle("Recent Scans")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu(isEmpty: scans.isEmpty)
            }
        }
        .wwToast($toast)
    }

    /// RC1, with 06 §4.5's corrected copy (unsaved scans beyond 50 are pruned).
    private var emptyState: some View {
        ScrollView {
            WWEmptyState(
                glyph: "clock.arrow.circlepath",
                title: "No recent scans",
                message: "Everything you scan lands here, so you can save it later. We keep your last \(CollectionStore.unsavedScanLimit) unsaved scans.",
                actionTitle: "Take a photo",
                actionImage: "camera",
                action: takePhoto
            )
            .padding(.horizontal, WW.margin(for: dynamicTypeSize))
            .padding(.bottom, WW.Space.xl)
        }
        .contentMargins(.bottom, WW.Space.xl, for: .scrollContent)
    }

    private func list(_ scans: [SavedCollectible]) -> some View {
        List {
            Section {
                ForEach(scans) { item in
                    row(item)
                }
            } footer: {
                Text("Only the last \(CollectionStore.unsavedScanLimit) unsaved scans are kept.")
                    .wwFont(.footnote)
                    .foregroundStyle(WW.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: SavedCollectible) -> some View {
        NavigationLink(value: item.id) {
            RecentScanRow(item: item)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: WW.Space.md))
        .listRowBackground(WW.surface)
        .swipeActions(edge: .leading) {
            if !item.isInCollection {
                Button {
                    save(item)
                } label: {
                    Label("Save", systemImage: "plus")
                }
                .tint(WW.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.isInCollection {
                Button {
                    hide(item)
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
                .tint(WW.secondaryText)
            } else {
                // Not `role: .destructive`: that animates the row away before
                // the confirmation is answered.
                Button {
                    pendingDelete = item.id
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(WW.danger)
            }
        }
        .contextMenu {
            RecentScanMenu(
                item: item,
                onDelete: { pendingDelete = item.id },
                onHide: { hide(item) }
            )
        }
        .confirmationDialog("Delete this scan?", isPresented: deleteBinding(for: item.id), titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive) { delete(item.id) }
            Button("Cancel", role: WW.dialogCancelRole) {}
        } message: {
            Text("It's removed from Recent scans. This can't be undone.")
        }
    }

    private func optionsMenu(isEmpty: Bool) -> some View {
        Menu {
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label("Clear Recent Scans", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Recent scans options")
        }
        .disabled(isEmpty)
        .confirmationDialog("Clear recent scans?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Recent Scans", role: .destructive) {
                withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
                    collectionStore.clearRecents()
                }
            }
            Button("Cancel", role: WW.dialogCancelRole) {}
        } message: {
            Text("Unsaved scans and their photos are deleted. Items in your collection stay.")
        }
    }

    private func deleteBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { pendingDelete == id },
            set: { isPresented in
                if !isPresented && pendingDelete == id { pendingDelete = nil }
            }
        )
    }

    private func takePhoto() {
        let start = router.startScan
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            start(.camera)
        }
    }

    private func save(_ item: SavedCollectible) {
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            collectionStore.saveToCollection(id: item.id)
        }
        Haptics.notify(.success)
        UIAccessibility.post(notification: .announcement, argument: "Saved to your collection")
    }

    private func hide(_ item: SavedCollectible) {
        let snapshot = collectionStore.membershipSnapshot(for: [item.id])
        withAnimation(WW.Motion.animation(.standard, reduceMotion: reduceMotion)) {
            collectionStore.removeFromRecents(id: item.id)
        }
        let store = collectionStore
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
}

/// Thumbnail, title, level-aware price line + "2 hours ago"; a check for
/// items already in the collection (05 §3.10).
private struct RecentScanRow: View {
    /// Redraws prices when Settings → Currency changes.
    @AppStorage(DisplayCurrency.codeKey) private var displayCurrency = ""
    let item: SavedCollectible

    @EnvironmentObject private var collectionStore: CollectionStore

    var body: some View {
        WWListRow(
            thumbnail: collectionStore.thumbnail(for: item.id),
            title: item.title,
            accessory: AnyView(detailLines),
            trailing: item.isInCollection ? AnyView(savedMark) : nil
        )
    }

    private var detailLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            ItemPriceLine(item: item, compact: false)
            Text(item.savedAt, format: .relative(presentation: .named))
                .wwFont(.subhead)
                .foregroundStyle(WW.secondaryText)
        }
    }

    private var savedMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(WW.secondaryText)
            .accessibilityLabel("In your collection")
    }
}

/// Long-press actions for a recent scan (Home recents and Recent Scans).
/// Unsaved: Save to Collection · Delete Scan. Saved: Hide from Recent Scans.
/// Hosts pass `onDelete` (which must confirm, 06 §4.6) and `onHide` (which
/// posts the Undo toast). Without `onDelete` there is no Delete Scan item, so
/// a host can never delete a scan silently; without `onHide`, Hide runs
/// directly (it is not destructive: the item stays in the collection).
struct RecentScanMenu: View {
    let item: SavedCollectible
    let onDelete: (() -> Void)?
    let onHide: (() -> Void)?

    @EnvironmentObject private var collectionStore: CollectionStore

    init(item: SavedCollectible, onDelete: (() -> Void)? = nil, onHide: (() -> Void)? = nil) {
        self.item = item
        self.onDelete = onDelete
        self.onHide = onHide
    }

    var body: some View {
        if item.isInCollection {
            Button {
                if let onHide {
                    onHide()
                } else {
                    collectionStore.removeFromRecents(id: item.id)
                }
            } label: {
                Label("Hide from Recent Scans", systemImage: "eye.slash")
            }
        } else {
            Button {
                collectionStore.saveToCollection(id: item.id)
                Haptics.notify(.success)
            } label: {
                Label("Save to Collection", systemImage: "plus")
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Scan", systemImage: "trash")
                }
            }
        }
    }
}
