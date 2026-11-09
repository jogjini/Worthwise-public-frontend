import Foundation
import UIKit
import ImageIO

@MainActor
final class CollectionStore: ObservableObject {
    enum SetCreationResult {
        case success
        case emptyName
        case duplicateName
    }

    /// What a bulk action changed, so a toast's Undo can put it back exactly
    /// (collection flag, Recent-scans flag, folder and position in it).
    /// Take it with `membershipSnapshot(for:)` before the change; apply it
    /// with `restore(_:)`.
    struct MembershipSnapshot {
        fileprivate struct Entry {
            let id: UUID
            let inCollection: Bool?
            let hiddenFromRecents: Bool?
            let setID: UUID?
            let setIndex: Int?
        }

        fileprivate let entries: [Entry]

        var isEmpty: Bool { entries.isEmpty }
    }

    /// Collection totals: A and B items only (04 §4.4). C and D are listed
    /// but not added up, because their ranges are rough or missing.
    struct Totals: Equatable {
        let low: Double
        let high: Double
        /// Items whose range is added up.
        let counted: Int
        /// Items left out of the sum ("{n} items aren't counted").
        let uncounted: Int

        var midpoint: Double { (low + high) / 2 }
        var hasTotal: Bool { counted > 0 }
    }

    private struct PersistedState: Codable {
        let items: [SavedCollectible]
        let sets: [CollectibleSet]
    }

    // One-time migration helper: pulls embedded image bytes out of old JSON files.
    private struct MigrationItem: Decodable {
        let id: UUID
        let imageData: Data?
    }
    private struct MigrationState: Decodable {
        let items: [MigrationItem]
    }

    /// Every stored scan, newest first: collection items and unsaved scans.
    @Published private(set) var records: [SavedCollectible] = []
    @Published private(set) var sets: [CollectibleSet] = []

    /// Items saved to the collection since a screen last showed them arriving
    /// (06 M16 / S3). Transient: never persisted. Screens that animate the
    /// arrival call `clearJustSaved(_:)` once they have shown it.
    @Published private(set) var justSaved: Set<UUID> = []

    /// The collection: scans the user saved.
    var items: [SavedCollectible] { records.filter(\.isInCollection) }

    /// Recent scans, newest first: everything scanned, saved or not, unless the
    /// user removed it from the list.
    var recentScans: [SavedCollectible] { records.filter(\.isInRecents) }

    /// Unsaved scans kept in history; older ones are deleted with their photos.
    static let unsavedScanLimit = 50

    /// Price histories for saved items (Pro), keyed by item id. Kept in memory:
    /// seeded from a scan's own history when it is saved, then refreshed from
    /// POST /api/prices when the collection opens.
    @Published private(set) var histories: [UUID: PriceHistory] = [:]
    private var lastHistoryRefresh: Date?
    private static let historyRefreshInterval: TimeInterval = 15 * 60

    // MARK: - Totals (04 §4.4: counted = level A or B)

    /// Collection items whose range is firm enough to add up (A and B).
    var countedItems: [SavedCollectible] { items.filter { $0.assessment.countsInTotal } }

    /// Collection items left out of the total (C and D).
    var uncountedCount: Int { Self.totals(for: items).uncounted }

    /// The collection total: counted items only.
    var totals: Totals { Self.totals(for: items) }

    /// Sum of the low ends of the counted items (A and B only).
    var totalEstimatedLow: Double { totals.low }
    /// Sum of the high ends of the counted items (A and B only).
    var totalEstimatedHigh: Double { totals.high }
    var totalEstimatedMidpoint: Double { totals.midpoint }
    var itemCount: Int { items.count }

    /// The collection in "Highest Value" order (04 §4.4): A and B by their
    /// best estimate (or midpoint), then C newest first, then D newest first.
    var sortedByValue: [SavedCollectible] { Self.sortByValue(items) }

    /// Totals for any list of items (a folder, a search result).
    nonisolated static func totals(for items: [SavedCollectible]) -> Totals {
        var low: Double = 0
        var high: Double = 0
        var counted = 0
        var uncounted = 0
        for item in items {
            let assessment = item.assessment
            if assessment.countsInTotal {
                low += assessment.lowUSD
                high += assessment.highUSD
                counted += 1
            } else {
                uncounted += 1
            }
        }
        return Totals(low: low, high: high, counted: counted, uncounted: uncounted)
    }

    /// "Highest Value" order for any list (04 §4.4). C and D never rise to
    /// the top: they follow every counted item, newest first.
    nonisolated static func sortByValue(_ items: [SavedCollectible]) -> [SavedCollectible] {
        let keyed: [ValueSortKey] = items.map { item in
            let assessment = item.assessment
            return ValueSortKey(item: item, level: assessment.level, value: assessment.sortValueUSD ?? 0)
        }
        let sorted: [ValueSortKey] = keyed.sorted { lhs, rhs in
            let lhsCounted: Bool = lhs.level >= .fair
            let rhsCounted: Bool = rhs.level >= .fair
            if lhsCounted != rhsCounted { return lhsCounted }
            if lhsCounted {
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.item.savedAt > rhs.item.savedAt
            }
            if lhs.level != rhs.level { return lhs.level > rhs.level }
            return lhs.item.savedAt > rhs.item.savedAt
        }
        return sorted.map { $0.item }
    }

    private struct ValueSortKey {
        let item: SavedCollectible
        let level: ValueLevel
        let value: Double
    }

    private let storageURL: URL
    private let imagesDirectory: URL
    private let imageCache = NSCache<NSString, UIImage>()

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        var directory = appSupport.appendingPathComponent("CollectibleScanner", isDirectory: true)
        #if DEBUG
        if DemoData.isActive { directory = DemoData.freshDirectory() }
        #endif
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        storageURL = directory.appendingPathComponent("collection.json")
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        imageCache.countLimit = 150

        load()
        #if DEBUG
        if DemoData.isActive { DemoData.seed(self) }
        #endif
    }

    // MARK: - Items

    /// Save straight to the collection.
    @discardableResult
    func add(profile: CollectibleProfile, estimate: ValueEstimate, condition: ConditionGrade, image: UIImage?, secondImage: UIImage? = nil) -> UUID {
        let id = store(profile: profile, estimate: estimate, condition: condition, image: image, secondImage: secondImage, inCollection: true)
        justSaved.insert(id)
        return id
    }

    /// Record a finished scan in Recent scans without adding it to the collection.
    @discardableResult
    func recordScan(profile: CollectibleProfile, estimate: ValueEstimate, condition: ConditionGrade, image: UIImage?, secondImage: UIImage? = nil) -> UUID {
        let id = store(profile: profile, estimate: estimate, condition: condition, image: image, secondImage: secondImage, inCollection: false)
        pruneUnsavedScans()
        return id
    }

    func record(id: UUID) -> SavedCollectible? {
        records.first { $0.id == id }
    }

    /// Add a scan from Recent scans to the collection, optionally into a folder.
    func saveToCollection(id: UUID, folderID: UUID? = nil) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let wasInCollection = records[index].isInCollection
        records[index].inCollection = true
        if !wasInCollection {
            justSaved.insert(id)
        }
        if let folderID {
            assignItem(id, toSetID: folderID)   // persists
        } else {
            persist()
        }
    }

    /// Take items out of the collection (04 §11.4). They never get deleted:
    /// each one goes back to Recent scans (even one hidden from there before)
    /// and leaves its folder. Pruning of old unsaved scans happens on the
    /// next scan, as before.
    func removeFromCollection<S: Sequence>(ids: S) where S.Element == UUID {
        var changed = false
        for id in ids {
            guard let index = records.firstIndex(where: { $0.id == id }) else { continue }
            records[index].inCollection = false
            records[index].hiddenFromRecents = false
            removeItemReferenceFromAllSets(itemID: id)
            justSaved.remove(id)
            changed = true
        }
        if changed {
            persist()
        }
    }

    /// One item: see `removeFromCollection(ids:)`. Never deletes.
    func removeFromCollection(id: UUID) {
        removeFromCollection(ids: [id])
    }

    /// Remove from Recent scans. A collection item only leaves the list; an
    /// unsaved scan is deleted along with its photos.
    func removeFromRecents(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        if records[index].isInCollection {
            records[index].hiddenFromRecents = true
            persist()
        } else {
            remove(id: id)
        }
    }

    /// Empty Recent scans. Collection items are kept.
    func clearRecents() {
        for scan in recentScans {
            removeFromRecents(id: scan.id)
        }
    }

    /// Edit Details (04 §5.3): condition, "Not sure", and the user's notes.
    /// "Not sure" is stored as `.good` with `conditionSet == false`. Empty
    /// notes are stored as nil.
    func updateDetails(id: UUID, condition: ConditionGrade, conditionSet: Bool, notes: String?) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].condition = conditionSet ? condition : .good
        records[index].conditionSet = conditionSet
        let trimmed = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].userProvidedInfo = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    /// Drop arrival marks once a screen has shown them (06 M16). nil = all.
    func clearJustSaved(_ ids: Set<UUID>? = nil) {
        if let ids {
            let remaining = justSaved.subtracting(ids)
            if remaining != justSaved { justSaved = remaining }
        } else if !justSaved.isEmpty {
            justSaved = []
        }
    }

    private func pruneUnsavedScans() {
        let unsaved = records.filter { !$0.isInCollection }
        guard unsaved.count > Self.unsavedScanLimit else { return }
        for old in unsaved.dropFirst(Self.unsavedScanLimit) {
            remove(id: old.id)
        }
    }

    private func store(profile: CollectibleProfile, estimate: ValueEstimate, condition: ConditionGrade, image: UIImage?, secondImage: UIImage?, inCollection: Bool) -> UUID {
        let saved = SavedCollectible(profile: profile, estimate: estimate, condition: condition, hasSecondImage: secondImage != nil, inCollection: inCollection)
        records.insert(saved, at: 0)
        if let history = estimate.history, history.isDrawable {
            histories[saved.id] = history
        }

        // Resize and encode off the main thread: this now runs on every scan,
        // right when the result appears.
        if let secondImage {
            let url = secondImageURL(for: saved.id)
            Task.detached(priority: .utility) {
                if let data = Self.downsampledJPEG(secondImage, maxDimension: 1400, quality: 0.7) {
                    try? data.write(to: url, options: [.atomic])
                }
            }
        }

        if let image {
            // Pre-warm the thumbnail for instant display (small, so main thread
            // is fine), then write the stored photo to disk in the background.
            if let thumb = Self.thumbnail(from: image, maxPixel: 220) {
                imageCache.setObject(thumb, forKey: saved.id.uuidString as NSString)
            }
            let url = imageURL(for: saved.id)
            Task.detached(priority: .utility) {
                if let data = Self.downsampledJPEG(image, maxDimension: 1400, quality: 0.7) {
                    try? data.write(to: url, options: [.atomic])
                }
            }
        }

        persist()
        return saved.id
    }

    // MARK: - Price history

    /// Ask the server for the price histories of saved items, which also tells
    /// it to keep re-pricing them daily. Pro only (the server checks too).
    /// At most every 15 minutes unless `force`.
    func refreshHistories(appUserID: String, force: Bool = false) async {
        if !force, let last = lastHistoryRefresh, Date().timeIntervalSince(last) < Self.historyRefreshInterval { return }
        let tracked: [(UUID, JSONValue)] = items.compactMap { item in
            guard let keys = item.priceKeys else { return nil }
            return (item.id, keys)
        }
        guard !tracked.isEmpty, !appUserID.isEmpty else { return }
        lastHistoryRefresh = Date()
        do {
            let fetched = try await APIAnalyzer.fetchPriceHistories(appUserID: appUserID, items: tracked)
            for (id, history) in fetched where history.isDrawable {
                histories[id] = history
            }
        } catch {
            // Try again next time the collection opens.
            lastHistoryRefresh = nil
            #if DEBUG
            print("[History] refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Delete a scan everywhere: collection, folders, Recent scans and photos.
    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        removeItemReferenceFromAllSets(itemID: id)
        justSaved.remove(id)
        imageCache.removeObject(forKey: id.uuidString as NSString)
        let url = imageURL(for: id)
        let secondURL = secondImageURL(for: id)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: secondURL)
        }
        persist()
    }

    // MARK: - Images

    /// Cached thumbnail for list display. Loads + downsamples from disk on first use.
    func thumbnail(for id: UUID) -> UIImage? {
        let key = id.uuidString as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let thumb = Self.thumbnail(fromFile: imageURL(for: id), maxPixel: 220) else { return nil }
        imageCache.setObject(thumb, forKey: key)
        return thumb
    }

    /// The stored photo for the item screen, decoded at no more than 1400 px.
    /// (Photos saved by earlier builds can be 4200 px; this keeps those from
    /// decoding at full size.)
    func image(for id: UUID) -> UIImage? {
        Self.thumbnail(fromFile: imageURL(for: id), maxPixel: 1400)
    }

    /// The second photo (back / base), when one was saved.
    func secondImage(for id: UUID) -> UIImage? {
        Self.thumbnail(fromFile: secondImageURL(for: id), maxPixel: 1400)
    }

    private func imageURL(for id: UUID) -> URL {
        imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func secondImageURL(for id: UUID) -> URL {
        imagesDirectory.appendingPathComponent("\(id.uuidString)-2.jpg")
    }

    // MARK: - Sets (folders)

    /// `.success` when `rawName` can name a folder: not empty, and no other
    /// folder (other than `excludingID`) has it, ignoring case.
    func validateSetName(_ rawName: String, excludingID: UUID? = nil) -> SetCreationResult {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .emptyName }
        let taken = sets.contains { set in
            set.id != excludingID && set.name.caseInsensitiveCompare(name) == .orderedSame
        }
        return taken ? .duplicateName : .success
    }

    @discardableResult
    func createSet(named rawName: String) -> SetCreationResult {
        let check = validateSetName(rawName)
        guard check == .success else { return check }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        sets.insert(CollectibleSet(name: name), at: 0)
        persist()
        return .success
    }

    /// "New Folder…" from a move menu (04 §5.4): creates the folder and
    /// returns its id, or nil when the name is empty or already taken
    /// (`validateSetName(_:)` says which).
    @discardableResult
    func createSetReturningID(named rawName: String) -> UUID? {
        guard validateSetName(rawName) == .success else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let set = CollectibleSet(name: name)
        sets.insert(set, at: 0)
        persist()
        return set.id
    }

    /// Rename Folder (04 §5.4). Duplicate names are refused (`.duplicateName`).
    /// A folder that no longer exists is a no-op (`.success`).
    @discardableResult
    func renameSet(id: UUID, to rawName: String) -> SetCreationResult {
        let check = validateSetName(rawName, excludingID: id)
        guard check == .success else { return check }
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return .success }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sets[index].name != name else { return .success }
        sets[index].name = name
        persist()
        return .success
    }

    /// Delete a folder. Its items stay in the collection.
    func removeSet(id: UUID) {
        sets.removeAll { $0.id == id }
        persist()
    }

    func assignItem(_ itemID: UUID, toSetID setID: UUID) {
        guard items.contains(where: { $0.id == itemID }) else {
            return
        }

        removeItemReferenceFromAllSets(itemID: itemID)

        guard let index = sets.firstIndex(where: { $0.id == setID }) else {
            persist()
            return
        }

        sets[index].itemIDs.append(itemID)
        persist()
    }

    /// Bulk move / Add Items (04 §5.4): every collection item in `ids` ends
    /// up in this folder (and leaves any other). Items already here keep
    /// their place; ids that aren't collection items are ignored.
    func assignItems<S: Sequence>(_ ids: S, toSetID setID: UUID) where S.Element == UUID {
        guard sets.contains(where: { $0.id == setID }) else { return }
        let collectionIDs = Set(items.map(\.id))
        var seen = Set<UUID>()
        var changed = false
        for id in ids {
            guard collectionIDs.contains(id), !seen.contains(id) else { continue }
            seen.insert(id)
            guard let target = sets.firstIndex(where: { $0.id == setID }) else { continue }
            if sets[target].itemIDs.contains(id) { continue }
            removeItemReferenceFromAllSets(itemID: id)
            if let index = sets.firstIndex(where: { $0.id == setID }) {
                sets[index].itemIDs.append(id)
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    /// Remove from Folder (04 §5.4): the items leave this folder only and
    /// stay in the collection.
    func removeItems<S: Sequence>(_ ids: S, fromSetID setID: UUID) where S.Element == UUID {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        let removing = Set(ids)
        guard !removing.isEmpty else { return }
        let before = sets[index].itemIDs.count
        sets[index].itemIDs.removeAll { removing.contains($0) }
        if sets[index].itemIDs.count != before {
            persist()
        }
    }

    func clearSetAssignment(for itemID: UUID) {
        removeItemReferenceFromAllSets(itemID: itemID)
        persist()
    }

    func setContaining(itemID: UUID) -> CollectibleSet? {
        sets.first(where: { $0.itemIDs.contains(itemID) })
    }

    func isItem(_ itemID: UUID, inSetID setID: UUID) -> Bool {
        sets.first(where: { $0.id == setID })?.itemIDs.contains(itemID) ?? false
    }

    func items(in set: CollectibleSet) -> [SavedCollectible] {
        let ids = Set(set.itemIDs)
        return items.filter { ids.contains($0.id) }
    }

    /// Folder totals: counted items only (A and B), plus how many were left out.
    func estimateTotals(in set: CollectibleSet) -> (low: Double, high: Double, midpoint: Double, counted: Int, uncounted: Int) {
        let totals = Self.totals(for: items(in: set))
        return (totals.low, totals.high, totals.midpoint, totals.counted, totals.uncounted)
    }

    // MARK: - Undo

    /// Records where each item is now (collection, Recent scans, folder and
    /// position). Take it before a move or remove; `restore(_:)` puts it back.
    func membershipSnapshot<S: Sequence>(for ids: S) -> MembershipSnapshot where S.Element == UUID {
        var entries: [MembershipSnapshot.Entry] = []
        var seen = Set<UUID>()
        for id in ids {
            guard !seen.contains(id), let existing = self.record(id: id) else { continue }
            seen.insert(id)
            var setID: UUID? = nil
            var setIndex: Int? = nil
            for set in sets {
                if let position = set.itemIDs.firstIndex(of: id) {
                    setID = set.id
                    setIndex = position
                    break
                }
            }
            entries.append(MembershipSnapshot.Entry(
                id: id,
                inCollection: existing.inCollection,
                hiddenFromRecents: existing.hiddenFromRecents,
                setID: setID,
                setIndex: setIndex
            ))
        }
        return MembershipSnapshot(entries: entries)
    }

    /// Undo: puts the snapshot's items back where they were. Items deleted
    /// in the meantime, and folders deleted in the meantime, are skipped.
    func restore(_ snapshot: MembershipSnapshot) {
        guard !snapshot.isEmpty else { return }
        var changed = false
        for entry in snapshot.entries {
            guard let index = records.firstIndex(where: { $0.id == entry.id }) else { continue }
            records[index].inCollection = entry.inCollection
            records[index].hiddenFromRecents = entry.hiddenFromRecents
            removeItemReferenceFromAllSets(itemID: entry.id)
            changed = true
        }
        // Lowest positions first, so later positions land where they were.
        let placed = snapshot.entries
            .filter { $0.setID != nil }
            .sorted { ($0.setIndex ?? 0) < ($1.setIndex ?? 0) }
        for entry in placed {
            guard let setID = entry.setID,
                  let setIndex = sets.firstIndex(where: { $0.id == setID }),
                  let existing = self.record(id: entry.id),
                  existing.isInCollection else { continue }
            let position = min(max(entry.setIndex ?? 0, 0), sets[setIndex].itemIDs.count)
            sets[setIndex].itemIDs.insert(entry.id, at: position)
            changed = true
        }
        if changed {
            persist()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            records = []
            sets = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1) One-time migration: pull any embedded image bytes out into files.
        var didMigrate = false
        if let legacy = try? decoder.decode(MigrationState.self, from: data) {
            for entry in legacy.items {
                guard let bytes = entry.imageData, !bytes.isEmpty else { continue }
                let url = imageURL(for: entry.id)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? bytes.write(to: url, options: [.atomic])
                }
                didMigrate = true
            }
        }

        // 2) Decode slim metadata (any legacy `imageData` key is ignored).
        // (`items` in the file holds every record; older files only had
        // collection items, which decode with `inCollection == nil`, i.e. saved.)
        if let state = try? decoder.decode(PersistedState.self, from: data) {
            records = state.items
            let collectionIDs = Set(state.items.filter(\.isInCollection).map(\.id))
            sets = normalizedSets(from: state.sets, validItemIDs: collectionIDs)
        } else if let legacyItems = try? decoder.decode([SavedCollectible].self, from: data) {
            records = legacyItems
            sets = []
        } else {
            records = []
            sets = []
        }

        // 3) If we extracted images, rewrite the file slim to drop the embedded bytes.
        if didMigrate {
            persist()
        }
    }

    private func persist() {
        // Metadata is now small (no image bytes): encode on-main, write off-main.
        guard let data = try? encodeState() else { return }
        let url = storageURL
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func encodeState() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(PersistedState(items: records, sets: sets))
    }

    // MARK: - Helpers

    private func removeItemReferenceFromAllSets(itemID: UUID) {
        for index in sets.indices {
            sets[index].itemIDs.removeAll { $0 == itemID }
        }
    }

    private func normalizedSets(from sets: [CollectibleSet], validItemIDs: Set<UUID>) -> [CollectibleSet] {
        sets.map { set in
            var normalized = set
            normalized.itemIDs = normalized.itemIDs.filter { validItemIDs.contains($0) }
            return normalized
        }
    }

    // MARK: - Image processing (pure)

    nonisolated private static func downsampledJPEG(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let resized = scaled(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    nonisolated private static func thumbnail(from image: UIImage, maxPixel: CGFloat) -> UIImage? {
        scaled(image, maxDimension: maxPixel)
    }

    nonisolated private static func scaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return image }
        let scale = min(maxDimension / longest, 1.0)
        guard scale < 1.0 else { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        // 1x, not the screen's 3x: `maxDimension` is meant in pixels. At 3x a
        // "1400 px" photo was really 4200 px (about 50 MB while being encoded).
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    nonisolated private static func thumbnail(fromFile url: URL, maxPixel: Int) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Export (04 §11.3 WP3)

    /// The collection as CSV, in the phone's locale and the display currency.
    func csvString() -> String {
        Self.csv(items: items, sets: sets, locale: Locale.current, currencyCode: DisplayCurrency.code)
    }

    /// Write the CSV to a temp file and return its URL (activity sheet,
    /// Settings › Export). Name: "Worthwise collection {yyyy-MM-dd}.csv".
    func exportCSVFile() -> URL? {
        Self.writeCSVFile(csvString(), date: Date())
    }

    /// Writes `csv` with a UTF-8 byte-order mark (so Excel reads accents and
    /// currency signs correctly) into a fresh temp folder. Safe off the main actor.
    nonisolated static func writeCSVFile(_ csv: String, date: Date) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(csvFileName(for: date))
            let body = "\u{FEFF}" + csv
            guard let data = body.data(using: .utf8) else { return nil }
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    /// "Worthwise collection 2026-10-14.csv" (06 §4.4).
    nonisolated static func csvFileName(for date: Date) -> String {
        "Worthwise collection \(csvDay(date)).csv"
    }

    /// The column separator for a locale: ";" where the decimal mark is a
    /// comma (fr-BE, de-DE, nl-BE…), else ",".
    nonisolated static func csvSeparator(for locale: Locale) -> String {
        (locale.decimalSeparator ?? ".") == "," ? ";" : ","
    }

    /// The CSV for `items` (pure, testable). Amounts are converted from USD
    /// to `currencyCode` (falls back to USD when no rate is known) and written
    /// with the locale's decimal mark, no grouping. Columns:
    /// Title, Category, Brand, Year, Set, Number, Condition, Folder,
    /// Estimate low (CUR), Estimate high (CUR), Best estimate (CUR),
    /// Value level, Evidence, Sold median (CUR), Sales, Prices checked, Notes.
    nonisolated static func csv(items: [SavedCollectible], sets: [CollectibleSet], locale: Locale, currencyCode: String) -> String {
        let separator = CollectionStore.csvSeparator(for: locale)
        let code = DisplayCurrency.fromUSD(1, to: currencyCode).code
        let digits = CollectionStore.csvFractionDigits(for: code)
        var folderNames: [UUID: String] = [:]
        for set in sets {
            for id in set.itemIDs where folderNames[id] == nil {
                folderNames[id] = set.name
            }
        }

        let header: [String] = [
            "Title", "Category", "Brand", "Year", "Set", "Number", "Condition", "Folder",
            "Estimate low (\(code))", "Estimate high (\(code))", "Best estimate (\(code))",
            "Value level", "Evidence", "Sold median (\(code))", "Sales", "Prices checked", "Notes",
        ]
        var rows: [String] = [header.map { CollectionStore.csvEscape($0, separator: separator) }.joined(separator: separator)]

        for item in items {
            let assessment = item.assessment
            func amount(_ usd: Double?) -> String {
                guard let usd, usd.isFinite else { return "" }
                let converted = DisplayCurrency.fromUSD(usd, to: currencyCode).amount
                return CollectionStore.csvNumber(converted, digits: digits, locale: locale)
            }

            var soldMedian = ""
            var sales = ""
            if let sold = item.sold, !sold.unavailable, sold.count > 0 {
                sales = String(sold.count)
                if let median = sold.median {
                    let soldCode = sold.currency.uppercased()
                    if soldCode == "USD" {
                        soldMedian = amount(median)
                    } else if soldCode == code {
                        soldMedian = CollectionStore.csvNumber(median, digits: digits, locale: locale)
                    }
                }
            }

            let condition = item.isConditionSet ? item.condition.label(for: item.probableCategory) : "Not set"
            let fields: [String] = [
                item.title,
                item.probableCategory.rawValue,
                item.brand ?? "",
                item.year.map { String($0) } ?? "",
                CollectionStore.csvAttribute(item, labels: ["set", "set name", "series"]) ?? "",
                CollectionStore.csvNumberField(item),
                condition,
                folderNames[item.id] ?? "",
                amount(assessment.lowUSD),
                amount(assessment.highUSD),
                amount(assessment.best?.amountUSD),
                assessment.level.csvLabel,
                assessment.evidence?.spoken ?? "",
                soldMedian,
                sales,
                CollectionStore.csvDay(item.savedAt),
                item.userProvidedInfo ?? "",
            ]
            rows.append(fields.map { CollectionStore.csvEscape($0, separator: separator) }.joined(separator: separator))
        }
        return rows.joined(separator: "\n")
    }

    /// RFC-4180 field escaping: quotes a field that holds the separator, a
    /// quote, or a line break, and doubles its quotes.
    nonisolated static func csvEscape(_ field: String, separator: String = ",") -> String {
        // Line breaks by scalar: Swift reads "\r\n" as one Character, which
        // contains("\n") and contains("\r") both miss.
        let needsQuotes = field.contains(separator)
            || field.contains("\"")
            || field.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
        if needsQuotes {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    /// A plain number in the locale's decimal mark, without grouping: 1234.5 →
    /// "1234.50" (en-US) / "1234,50" (fr-BE).
    nonisolated static func csvNumber(_ value: Double, digits: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// 2 for most currencies, 0 for JPY.
    nonisolated private static func csvFractionDigits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return max(0, min(formatter.maximumFractionDigits, 2))
    }

    /// "2026-10-14" (unambiguous in every spreadsheet locale).
    nonisolated private static func csvDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The first attribute whose label matches one of `labels` (case-insensitive).
    nonisolated private static func csvAttribute(_ item: SavedCollectible, labels: [String]) -> String? {
        guard let attributes = item.attributes else { return nil }
        for attribute in attributes {
            let label = attribute.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = attribute.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if labels.contains(label), !value.isEmpty { return value }
        }
        return nil
    }

    /// Model / card / catalogue number: the scan's number, else an attribute.
    nonisolated private static func csvNumberField(_ item: SavedCollectible) -> String {
        if let number = item.modelNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !number.isEmpty {
            return number
        }
        return csvAttribute(item, labels: ["number", "card number", "catalog number", "catalogue number", "no.", "ref.", "reference"]) ?? ""
    }
}
