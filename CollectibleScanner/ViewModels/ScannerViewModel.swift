import Foundation
import ImageIO
import SwiftUI
import UIKit

// MARK: - Scan failure

/// Why a scan didn't produce a result (04 §6.2, 05 §2.33). A failure is never
/// turned into a guess: the flow goes back to Review, keeps the photos, and
/// the Review bar shows `ScanFailureCard`.
enum ScanFailure: Equatable {
    /// No connection (any `NSURLErrorDomain` error).
    case offline
    /// The server answered with an error, or the answer couldn't be read.
    case server
    /// Pro fair-use cap reached for this period.
    case proLimit(limit: Int?, resetsAt: Date?)
    /// Photo analysis is off and the photo has no text or barcode to read.
    case nothingToRead

    var title: String {
        switch self {
        case .offline:
            return "No connection"
        case .server:
            return "Something went wrong on our side"
        case .proLimit(let limit, _):
            if let limit {
                return "You've used all \(limit) Pro scans for this period"
            }
            return "You've used all your Pro scans for this period"
        case .nothingToRead:
            return "Nothing to read on this photo"
        }
    }

    var message: String {
        switch self {
        case .offline:
            return "Your photos are kept and no scan was used. Try again when you have signal."
        case .server:
            return "Your photos are still here and no scan was used."
        case .proLimit(_, let resetsAt):
            if let resetsAt {
                return "More scans on \(ScanFailure.shortDate(resetsAt))."
            }
            return "More scans when your plan period renews."
        case .nothingToRead:
            return "With photo analysis off, we can only read text and barcodes, and this photo has none."
        }
    }

    /// SF Symbol for the card (05 §2.33).
    var glyph: String {
        switch self {
        case .offline: return "wifi.slash"
        case .server: return "exclamationmark.icloud"
        case .proLimit: return "hourglass"
        case .nothingToRead: return "text.viewfinder"
        }
    }

    /// The Review bar's primary relabels to "Try again" (05 D10).
    var canRetry: Bool {
        switch self {
        case .offline, .server: return true
        case .proLimit, .nothingToRead: return false
        }
    }

    /// "Nov 1": the day a Pro period renews.
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - View model

@MainActor
final class ScannerViewModel: ObservableObject {
    static let userInfoCharacterLimit = 320

    /// Where a scan is (04 §3.3 SC1/SC2). Drives the real first step on
    /// Scanning and whether Cancel needs the "Stop this scan?" dialog.
    enum ScanStage: Equatable {
        case idle
        /// On-device reading (Vision). Nothing has left the phone.
        case reading
        /// The photo was sent; waiting for the server's answer.
        case waitingForServer
    }

    /// The photos as they'll be analysed and saved (cropped, if the user cropped).
    @Published var selectedImage: UIImage?
    @Published var secondaryImage: UIImage?

    enum PhotoSide { case front, back }

    /// Uncropped photos, so a crop can be widened again later.
    private(set) var frontOriginal: UIImage?
    private(set) var backOriginal: UIImage?
    /// The current crop of each photo, as a fraction of the original (0...1).
    @Published private(set) var frontCrop: CGRect?
    @Published private(set) var backCrop: CGRect?
    /// The grade sent to the server. "Not sure" sends `.good` (04 §1).
    @Published var condition: ConditionGrade = .good
    /// false = "Not sure": `.good` is sent, and the record is stored as "not set".
    @Published var conditionIsSet = false
    @Published var isScanning = false
    @Published private(set) var stage: ScanStage = .idle
    /// When the current scan started (Scanning's long-wait copy).
    @Published private(set) var scanStartedAt: Date?
    /// The last scan's failure, shown in the Review bar. Never a guess.
    @Published var failure: ScanFailure?
    @Published var profile: CollectibleProfile?
    @Published var estimate: ValueEstimate?
    @Published private(set) var userProvidedInfo = ""
    @Published var showPaywall = false
    /// True when the result on screen came from the on-device pipeline because
    /// the user declined AI analysis. With consent on, network and server
    /// errors no longer fall back to on-device (04 §11.4): they set `failure`.
    @Published private(set) var lastScanWasLocalByChoice = false
    /// Whether the last scan used a scan, from the counters before and after
    /// (04 §10 S4). nil = unknown. On-device scans never charge.
    @Published private(set) var lastScanCharged: Bool?

    /// The stored record of the result on screen (every finished scan is kept
    /// in Recent scans), so "Save to collection" can add that same record.
    @Published private(set) var resultRecordID: UUID?
    /// Set when this flow re-checks a saved record (`router.rescan`): the
    /// result offers "Replace saved item" (04 RS-replace).
    @Published private(set) var replacingRecordID: UUID?

    weak var creditManager: CreditManager?
    weak var collectionStore: CollectionStore?

    private let scanner = VisionScanner()
    private let analyzer = CollectibleAnalyzer()
    private let estimator = ValueEstimator()
    private let apiAnalyzer = APIAnalyzer()
    private let settings: AppSettings

    private var scanTask: Task<Void, Never>?

    /// `?? .shared` rather than a `= .shared` default argument: a default
    /// argument is evaluated in the caller's context, which is nonisolated, and
    /// Swift 6 rejects reaching a main-actor-isolated singleton from there.
    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
    }

    // MARK: Derived

    /// Kept for older call sites: the failure as one sentence.
    var scanError: String? {
        guard let failure else { return nil }
        return "\(failure.title). \(failure.message)"
    }

    var userProvidedInfoCount: Int {
        userProvidedInfo.count
    }

    var trimmedUserProvidedInfo: String? {
        let trimmed = userProvidedInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canAddSecondImage: Bool {
        selectedImage != nil
    }

    /// Review has edits worth confirming before Cancel throws them away
    /// (04 R3): a crop, a back photo, a chosen condition or details.
    var isDirty: Bool {
        frontCrop != nil
            || backCrop != nil
            || secondaryImage != nil
            || conditionIsSet
            || trimmedUserProvidedInfo != nil
    }

    // MARK: Photos

    /// Start a new item: clears photos, crops, condition, details, result and
    /// any failure. (`replaceFrontImage` keeps everything but the front photo.)
    func setImage(_ image: UIImage?) {
        scanTask?.cancel()
        scanTask = nil
        clearFrontPhoto(image)
        secondaryImage = nil
        backOriginal = nil
        backCrop = nil
        condition = .good
        conditionIsSet = false
        userProvidedInfo = ""
        replacingRecordID = nil
        clearResult()
    }

    func setSecondaryImage(_ image: UIImage?) {
        let small = image.map { ImageDownsampler.downsample($0) }
        secondaryImage = small
        backOriginal = small
        backCrop = nil
    }

    /// Retake the front photo without losing the back photo (or its crop),
    /// the condition or the details.
    func replaceFrontImage(_ image: UIImage) {
        scanTask?.cancel()
        scanTask = nil
        clearFrontPhoto(image)
        clearResult()
    }

    func originalImage(for side: PhotoSide) -> UIImage? {
        side == .front ? frontOriginal : backOriginal
    }

    func crop(for side: PhotoSide) -> CGRect? {
        side == .front ? frontCrop : backCrop
    }

    /// Crop a photo to `rect` (a fraction of the original), or undo the crop
    /// with nil. Always cuts from the original, never from an earlier crop.
    func applyCrop(_ rect: CGRect?, to side: PhotoSide) {
        guard let original = originalImage(for: side) else { return }
        let cropped = rect.map { ImageDownsampler.crop(original, to: $0) } ?? original
        switch side {
        case .front:
            selectedImage = cropped
            frontCrop = rect
        case .back:
            secondaryImage = cropped
            backCrop = rect
        }
    }

    /// Seed the flow from a stored record (`router.rescan`, 04 §11.3): its
    /// photos, condition and notes. A saved record is replaced by the new
    /// result when the user chooses "Replace saved item".
    func load(record: SavedCollectible, photos: [UIImage]) {
        setImage(photos.first)
        if photos.count > 1 {
            setSecondaryImage(photos[1])
        }
        condition = record.condition
        conditionIsSet = record.isConditionSet
        userProvidedInfo = String((record.userProvidedInfo ?? "").prefix(Self.userInfoCharacterLimit))
        replacingRecordID = record.isInCollection ? record.id : nil
    }

    // MARK: Flow

    /// Stop a scan in progress and go back to the review step, keeping the photos.
    /// (A cloud scan the server already started may still count there.)
    func cancelScan() {
        let wasSent = stage == .waitingForServer
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        stage = .idle
        scanStartedAt = nil
        if wasSent, let creditManager {
            // Read-only: keep the plan pill honest if the server counted it.
            Task { await creditManager.refresh() }
        }
    }

    /// Back to the review step to improve the photos or details and scan again.
    /// The scan already made stays in Recent scans.
    func backToReview() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        stage = .idle
        scanStartedAt = nil
        failure = nil
        profile = nil
        estimate = nil
        resultRecordID = nil
    }

    /// Close the whole scan flow.
    func reset() {
        setImage(nil)
    }

    func updateCondition(_ value: ConditionGrade) {
        condition = value
        // Only re-run the offline heuristic for offline results. Never overwrite a
        // cloud (market/AI) estimate — that would drop the real listings and the
        // server-side valuation. Re-scanning applies the new condition properly.
        guard let profile, estimate?.basis == .offlineEstimate else { return }
        estimate = estimator.estimate(for: profile, condition: value)
    }

    func updateUserProvidedInfo(_ value: String) {
        userProvidedInfo = String(value.prefix(Self.userInfoCharacterLimit))
    }

    /// "Not the right item?": put the user's hint in front of the details.
    func applyHint(_ hint: String) {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = trimmedUserProvidedInfo.map { " \($0)" } ?? ""
        updateUserProvidedInfo("It is: \(trimmed).\(existing)")
    }

    // MARK: Scan

    func scan() {
        guard let image = selectedImage else { return }

        // App Store Guideline 5.1.2(i): a photograph is personal data and this
        // app sends it to Google and OpenAI, so nothing leaves the device until
        // the user has said yes. Declining is not a dead end — the on-device
        // pipeline still runs — but it is a far weaker result, so it also costs
        // no credit.
        guard settings.aiConsentGranted else {
            runOnDeviceScan(image: image)
            return
        }

        // Check credits before starting
        if let cm = creditManager, !cm.canScan {
            showPaywall = true
            return
        }

        scanTask?.cancel()

        lastScanWasLocalByChoice = false
        lastScanCharged = nil
        beginScan()
        ReviewPrompter.shared.scanStarted()

        let userInfo = trimmedUserProvidedInfo
        let currentCondition = condition
        let appUserID = creditManager?.appUserID
        let isPro = creditManager?.isPro ?? false
        let before = chargeSnapshot()

        var images = [image]
        if let secondary = secondaryImage {
            images.append(secondary)
        }

        scanTask = Task {
            // On-device Vision runs on EVERY scan, not just offline. Its OCR
            // reads a card's set name and collector number far more reliably
            // than a vision model reads them back out of a JPEG, and those two
            // fields make the price lookup hit the right printing.
            var payload: ScanPayload?
            do {
                payload = try await scanner.scan(image: image)
            } catch {
                // No text and no barcode is a perfectly normal outcome (a loose
                // figurine, a coin). With consent on, the server does the rest.
                payload = nil
            }
            guard !Task.isCancelled else { return }

            #if DEBUG
            print("[Scan] Vision: \(payload?.textLines.count ?? 0) text lines, \(payload?.barcodes.count ?? 0) barcodes")
            #endif

            Telemetry.log(.scanStarted(
                hasSecondImage: images.count > 1,
                hasOCR: !(payload?.textLines.isEmpty ?? true),
                hasBarcode: !(payload?.barcodes.isEmpty ?? true)
            ))

            // Step 1 ("Reading the photo") is really done: the photo is sent.
            self.stage = .waitingForServer

            do {
                #if DEBUG
                print("[Scan] Attempting API analysis via \(APIAnalyzer.baseURL) (images: \(images.count))...")
                #endif
                let result = try await apiAnalyzer.analyze(
                    images: images,
                    userInfo: userInfo,
                    condition: currentCondition,
                    appUserID: appUserID,
                    ocrText: payload?.textLines ?? [],
                    barcode: payload?.barcodes.first,
                    includeDeviceCheck: !isPro
                )
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("[Scan] API success — title: \(result.profile.title), category: \(result.profile.probableCategory.rawValue)")
                #endif
                self.profile = result.profile
                self.estimate = result.estimate
                self.settings.recordScanBasis(result.estimate.basis)
                // No success haptic here: the result reveal plays it (06 §3.1).

                Telemetry.log(.scanSucceeded(
                    category: result.profile.probableCategory.rawValue,
                    source: .cloud,
                    comparableCount: result.estimate.comparables.count
                ))

                // Sync plan and counters from the server (it already counted the scan).
                self.creditManager?.sync(result.meta)
                self.lastScanCharged = self.charged(since: before)
                self.recordResult(condition: currentCondition)
                self.finishScan(failure: nil)
            } catch APIAnalyzer.APIError.noCreditsRemaining {
                guard !Task.isCancelled else { return }
                await self.creditManager?.refresh()
                guard !Task.isCancelled else { return }
                self.finishScan(failure: nil)
                // A sales screen never arrives with a buzz (06 §3.2).
                self.showPaywall = true
            } catch let apiError as APIAnalyzer.APIError {
                guard !Task.isCancelled else { return }
                if case .scanLimitReached(let limit, let resetsAt) = apiError {
                    // Pro fair-use cap: say so plainly. Not a paywall.
                    self.finishScan(failure: .proLimit(limit: limit, resetsAt: resetsAt))
                    Haptics.notify(.warning)
                    return
                }
                #if DEBUG
                print("[Scan] API failed: \(apiError.localizedDescription)")
                #endif
                Telemetry.log(.scanFailed(reason: Self.failureReason(for: apiError)))
                // 04 §11.4: with consent on, never fall back to an on-device guess.
                self.finishScan(failure: Self.failure(for: apiError))
                Haptics.notify(.error)
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("[Scan] API failed: \(error.localizedDescription)")
                #endif
                Telemetry.log(.scanFailed(reason: Self.failureReason(for: error)))
                self.finishScan(failure: Self.failure(for: error))
                Haptics.notify(.error)
            }
        }
    }

    /// The pipeline for someone who declined AI analysis: on-device Vision only.
    ///
    /// Deliberately does not touch credits. A local result is OCR plus a
    /// heuristic price band — nowhere near what a cloud scan produces — and
    /// charging for it would be charging for the weak version of the product.
    private func runOnDeviceScan(image: UIImage) {
        scanTask?.cancel()

        lastScanWasLocalByChoice = true
        lastScanCharged = false
        beginScan()
        ReviewPrompter.shared.scanStarted()

        let userInfo = trimmedUserProvidedInfo
        let currentCondition = condition

        scanTask = Task {
            do {
                let payload = try await scanner.scan(image: image)
                guard !Task.isCancelled else { return }

                let profile = analyzer.analyze(payload, supplementalInfo: userInfo)
                let estimate = estimator.estimate(for: profile, condition: currentCondition)
                self.profile = profile
                self.estimate = estimate
                self.recordResult(condition: currentCondition)
                self.settings.recordScanBasis(estimate.basis)
                Telemetry.log(.scanSucceeded(
                    category: profile.probableCategory.rawValue,
                    source: .onDevice,
                    comparableCount: 0
                ))
                self.finishScan(failure: nil)
            } catch {
                guard !Task.isCancelled else { return }
                // No text and no barcode means the on-device pipeline has
                // nothing at all to work with.
                self.finishScan(failure: .nothingToRead)
                Haptics.notify(.error)
                Telemetry.log(.scanFailed(reason: "on_device_no_signals"))
            }
        }
    }

    private func beginScan() {
        isScanning = true
        stage = .reading
        scanStartedAt = Date()
        failure = nil
        profile = nil
        estimate = nil
        resultRecordID = nil
    }

    private func finishScan(failure newFailure: ScanFailure?) {
        failure = newFailure
        isScanning = false
        stage = .idle
        scanStartedAt = nil
    }

    private func clearFrontPhoto(_ image: UIImage?) {
        let small = image.map { ImageDownsampler.downsample($0) }
        selectedImage = small
        frontOriginal = small
        frontCrop = nil
    }

    private func clearResult() {
        isScanning = false
        stage = .idle
        scanStartedAt = nil
        failure = nil
        profile = nil
        estimate = nil
        resultRecordID = nil
        lastScanWasLocalByChoice = false
        lastScanCharged = nil
    }

    /// Keep the result in Recent scans, with both photos, so it isn't lost if
    /// the user closes the result without saving.
    private func recordResult(condition: ConditionGrade) {
        guard let profile, let estimate, let collectionStore else { return }
        ReviewPrompter.shared.recordResult(profile: profile, estimate: estimate)
        let id = collectionStore.recordScan(
            profile: profile,
            estimate: estimate,
            condition: condition,
            image: selectedImage,
            secondImage: secondaryImage
        )
        resultRecordID = id
        if !conditionIsSet {
            // "Not sure" is stored as `.good` + not set (04 §1, WP3 API §11.4).
            let notes = collectionStore.record(id: id)?.userProvidedInfo ?? ""
            collectionStore.updateDetails(id: id, condition: condition, conditionSet: false, notes: notes)
        }
    }

    // MARK: Charge (04 §10 S4: counters before and after)

    private struct ChargeSnapshot {
        let isPro: Bool
        let freeLeft: Int
        /// The free count before the scan came from the server (H-2).
        let freeKnown: Bool
        let proUsed: Int?
    }

    private func chargeSnapshot() -> ChargeSnapshot? {
        guard let cm = creditManager else { return nil }
        return ChargeSnapshot(isPro: cm.isPro, freeLeft: cm.freeScansLeft, freeKnown: cm.hasServerCount, proUsed: cm.scansUsed)
    }

    private func charged(since before: ChargeSnapshot?) -> Bool? {
        guard let before, let cm = creditManager else { return nil }
        guard before.isPro == cm.isPro else { return nil }
        if cm.isPro {
            guard let was = before.proUsed, let now = cm.scansUsed else { return nil }
            return now > was
        }
        // An unknown count before the scan can't be compared: say nothing.
        guard before.freeKnown, cm.hasServerCount else { return nil }
        return cm.freeScansLeft < before.freeLeft
    }

    // MARK: Errors

    /// No connection vs. a server problem (04 §6.2).
    private static func failure(for error: Error) -> ScanFailure {
        (error as NSError).domain == NSURLErrorDomain ? .offline : .server
    }

    /// Coarse, non-identifying failure bucket for the funnel.
    private static func failureReason(for error: Error) -> String {
        switch error {
        case APIAnalyzer.APIError.invalidResponse(let code): return "http_\(code)"
        case APIAnalyzer.APIError.decodingFailed: return "decode"
        case APIAnalyzer.APIError.compressionFailed: return "compression"
        case APIAnalyzer.APIError.invalidURL: return "bad_url"
        default: return (error as NSError).domain == NSURLErrorDomain ? "network" : "other"
        }
    }
}

// MARK: - Photo size

/// Keeps photos at a size the app can hold in memory.
///
/// A library photo can be 24 to 48 megapixels: 100 to 190 MB once decoded, and
/// the scan flow holds two of them while showing them full screen. Nothing
/// needs that much: the server analyses 1536 px, and on-device text reading is
/// just as good at this size.
enum ImageDownsampler {
    nonisolated static let maxPixel: CGFloat = 2400

    /// Decode straight from file data at the target size, without ever
    /// decoding the full-resolution bitmap. Applies the EXIF orientation.
    nonisolated static func image(from data: Data, maxPixel: CGFloat = maxPixel) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data).map { downsample($0, maxPixel: maxPixel) }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data).map { downsample($0, maxPixel: maxPixel) }
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// Cut out `normalized` (a fraction of the image, 0...1 on each axis).
    /// Drawing through the renderer also bakes in the image's orientation.
    nonisolated static func crop(_ image: UIImage, to normalized: CGRect) -> UIImage {
        let size = image.size
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clamped = normalized.intersection(unit)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return image }
        let rect = CGRect(
            x: (clamped.minX * size.width).rounded(),
            y: (clamped.minY * size.height).rounded(),
            width: max(1, (clamped.width * size.width).rounded()),
            height: max(1, (clamped.height * size.height).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
    }

    /// Redraw an in-memory image at no more than `maxPixel` on its long side,
    /// at 1x scale. Returns the image unchanged when it is already small enough.
    nonisolated static func downsample(_ image: UIImage, maxPixel: CGFloat = maxPixel) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxPixel else { return image }
        let ratio = maxPixel / longest
        let target = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
