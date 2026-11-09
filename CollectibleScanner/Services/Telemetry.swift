import Foundation
import OSLog

/// Minimal, privacy-safe product funnel.
///
/// Deliberately contains no third-party SDK: everything goes to `OSLog`, which
/// shows up in Console.app and in a sysdiagnose, and costs nothing. When a real
/// backend is wired up (Sentry, Crashlytics, PostHog…), implement `forward` —
/// it is the single call site, so nothing else in the app has to change.
///
/// Rules for anything added here: **no photos, no item titles, no user
/// identifiers, no prices.** Counts, categories and failure reasons only. That
/// keeps the App Privacy questionnaire answer "we collect no analytics data"
/// honest, and keeps this out of the privacy manifest.
enum Telemetry {

    enum Event {
        case scanStarted(hasSecondImage: Bool, hasOCR: Bool, hasBarcode: Bool)
        case scanSucceeded(category: String, source: Source, comparableCount: Int)
        case scanFailed(reason: String)
        case paywallShown
        case purchaseStarted(productID: String)
        case purchaseCompleted(productID: String)
        case purchaseFailed(reason: String)
        case accountDeleted(appleRevoked: Bool)
        /// Guideline 5.1.2(i) consent. Worth a funnel line of its own: the
        /// decline rate is the single number that says whether the gate copy is
        /// working or scaring people off.
        case aiConsentSet(granted: Bool)
        case configPlaceholdersPresent

        enum Source: String {
            case cloud
            case onDevice
        }

        var name: String {
            switch self {
            case .scanStarted: return "scan_started"
            case .scanSucceeded: return "scan_succeeded"
            case .scanFailed: return "scan_failed"
            case .paywallShown: return "paywall_shown"
            case .purchaseStarted: return "purchase_started"
            case .purchaseCompleted: return "purchase_completed"
            case .purchaseFailed: return "purchase_failed"
            case .accountDeleted: return "account_deleted"
            case .aiConsentSet: return "ai_consent_set"
            case .configPlaceholdersPresent: return "config_placeholders_present"
            }
        }

        var properties: [String: String] {
            switch self {
            case let .scanStarted(hasSecondImage, hasOCR, hasBarcode):
                return [
                    "second_image": String(hasSecondImage),
                    "ocr": String(hasOCR),
                    "barcode": String(hasBarcode),
                ]
            case let .scanSucceeded(category, source, comparableCount):
                return [
                    "category": category,
                    "source": source.rawValue,
                    "comparables": String(comparableCount),
                ]
            case let .scanFailed(reason):
                return ["reason": reason]
            case let .purchaseStarted(productID), let .purchaseCompleted(productID):
                return ["product": productID]
            case let .purchaseFailed(reason):
                return ["reason": reason]
            case let .accountDeleted(appleRevoked):
                return ["apple_revoked": String(appleRevoked)]
            case let .aiConsentSet(granted):
                return ["granted": String(granted)]
            case .paywallShown, .configPlaceholdersPresent:
                return [:]
            }
        }

        var isFailure: Bool {
            switch self {
            case .scanFailed, .purchaseFailed, .configPlaceholdersPresent: return true
            default: return false
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CollectibleScanner",
        category: "telemetry"
    )

    static func log(_ event: Event) {
        let description = event.properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        // Public: these values are non-identifying by construction (see the rules
        // above), so leaving them readable in the log is the whole point.
        if event.isFailure {
            logger.error("\(event.name, privacy: .public) \(description, privacy: .public)")
        } else {
            logger.info("\(event.name, privacy: .public) \(description, privacy: .public)")
        }

        forward(event)
    }

    /// Hook for a crash/analytics backend. Intentionally empty.
    ///
    /// To add Sentry: add the SPM package, call `SentrySDK.start` from
    /// `CollectibleScannerApp.init`, then here:
    ///     SentrySDK.addBreadcrumb(...)  // or captureMessage for failures
    /// Adding an SDK changes the App Privacy answers and may need a privacy
    /// manifest entry — check before shipping it.
    private static func forward(_ event: Event) {}
}
