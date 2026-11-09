import Foundation
import RevenueCat
import SwiftUI

// MARK: - Plan Manager
//
// Free: 3 scans, value range only. Pro (weekly / monthly / yearly subscription,
// RevenueCat entitlement "pro"): up to 250 scans a month (60 a week on the
// weekly plan) and the listings behind every estimate.
//
// Two sources of truth, on purpose:
//  - RevenueCat's CustomerInfo on the device flips the UI to Pro the instant a
//    purchase or restore completes, even before the server hears about it.
//  - The server (/api/credits) owns the counters: free scans left, Pro scans
//    used this period. It also enforces everything; the app only displays.
//
// The class keeps its old name so the environment object wiring across the app
// did not have to change.

/// What a purchase ended with (04 §5.5, §11.4). Ask to Buy (pending) and real
/// failures are thrown as RevenueCat errors; the paywall maps them to copy.
enum PurchaseOutcome: Equatable {
    /// Pro is active (on the device or on our server).
    case pro
    /// The user closed the App Store sheet. Nothing to show.
    case cancelled
    /// The store took the payment but no "pro" entitlement is active yet
    /// (e.g. a product-to-entitlement mapping problem). The paywall shows a
    /// message and puts Restore first.
    case noEntitlement
}

@MainActor
final class CreditManager: ObservableObject {
    enum Plan: String {
        case free, pro
    }

    /// Must match the entitlement identifier in RevenueCat and RC_PRO_ENTITLEMENT on the server.
    static let proEntitlementID = "pro"

    @Published private(set) var plan: Plan = .free
    /// Free scans left (free plan). Kept under its old name for existing views.
    @Published private(set) var credits: Int = 0
    /// Pro: scans used / allowed in the current period (nil until the server answers).
    @Published private(set) var scansUsed: Int?
    @Published private(set) var scanLimit: Int?
    @Published private(set) var periodEndsAt: Date?
    /// Pro product the user is on, e.g. "pro_yearly" (from RevenueCat).
    @Published private(set) var activeProductID: String?
    /// When the current Pro period ends or renews.
    @Published private(set) var proExpiresAt: Date?
    @Published private(set) var willRenew = true
    /// The Pro entitlement is in its free trial (RevenueCat `periodType == .trial`),
    /// so `proExpiresAt` is the day the trial ends.
    @Published private(set) var isInTrial = false
    @Published private(set) var isLoading = true
    /// The server has reported the free-scan count at least once on this
    /// install (persisted). Until then `credits` is a default, not a count:
    /// an offline first launch must not read as "out of free scans".
    @Published private(set) var hasServerCount = false

    var isPro: Bool { plan == .pro }
    var freeScansLeft: Int { credits }

    /// Free scans a new install starts with (copy only; the server counts).
    static let freeScanAllowance = 3

    /// Free, and the server really says 0 free scans left. An unknown count
    /// (first credit check failed) is never 0: the server decides at scan time.
    var isOutOfFreeScans: Bool {
        !isPro && hasServerCount && !isLoading && credits == 0
    }

    /// Pro users can always try: the server answers with a clear message when
    /// the fair-use cap is reached. Free users need a free scan left, or an
    /// unknown count (the server's 402 still catches a real 0).
    var canScan: Bool { isPro || credits > 0 || !hasServerCount }

    /// Pro scans left in this period, when known.
    var proScansLeft: Int? {
        guard let scansUsed, let scanLimit else { return nil }
        return max(scanLimit - scansUsed, 0)
    }

    var appUserID: String {
        Purchases.shared.appUserID
    }

    // MARK: - UserDefaults keys

    private static let cachedCreditsKey = "cached_credits"
    private static let cachedPlanKey = "cached_plan"
    private static let hasServerCountKey = "cached_credits_from_server"

    private var customerInfoTask: Task<Void, Never>?
    /// What RevenueCat on this device says, so a slow server cache can't demote a fresh subscriber.
    private var deviceSaysPro = false

    // MARK: - Lifecycle

    func start() async {
        #if DEBUG
        if DemoData.isActive {
            plan = .pro
            scansUsed = 12
            scanLimit = 250
            hasServerCount = true
            isLoading = false
            return
        }
        #endif
        // Cached values first, for an instant UI.
        credits = UserDefaults.standard.integer(forKey: Self.cachedCreditsKey)
        plan = Plan(rawValue: UserDefaults.standard.string(forKey: Self.cachedPlanKey) ?? "") ?? .free
        hasServerCount = UserDefaults.standard.bool(forKey: Self.hasServerCountKey)

        listenForCustomerInfo()
        if let info = try? await Purchases.shared.customerInfo() {
            apply(info)
        }
        await refresh()

        isLoading = false
    }

    /// Every change RevenueCat sees (purchase, renewal, expiry, restore, another
    /// device) arrives here.
    private func listenForCustomerInfo() {
        guard customerInfoTask == nil else { return }
        customerInfoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self else { return }
                let wasPro = self.deviceSaysPro
                self.apply(info)
                // Became Pro (or stopped being Pro) on the device: re-read the
                // server so the counters match, bypassing its cache.
                if wasPro != self.deviceSaysPro {
                    await self.refresh(fresh: true)
                }
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[Self.proEntitlementID]
        deviceSaysPro = entitlement?.isActive == true
        if deviceSaysPro {
            plan = .pro
            activeProductID = entitlement?.productIdentifier
            proExpiresAt = entitlement?.expirationDate
            willRenew = entitlement?.willRenew ?? true
            isInTrial = entitlement?.periodType == .trial
        } else {
            activeProductID = nil
            proExpiresAt = nil
            isInTrial = false
            if plan == .pro { plan = .free }
        }
        persist()
    }

    /// Re-fetch plan and counters from the server (foreground, after a scan).
    /// `fresh` skips the server's 10-minute subscription cache — use it right
    /// after a purchase or restore.
    func refresh(fresh: Bool = false) async {
        #if DEBUG
        if DemoData.isActive { return }
        #endif
        do {
            let status = try await APIAnalyzer.fetchAccessStatus(appUserID: appUserID, refresh: fresh)
            apply(status)
            #if DEBUG
            print("[Plan] Server: plan=\(status.plan ?? "?") free=\(status.freeScansLeft ?? -1) used=\(status.scansUsed ?? -1)/\(status.scanLimit ?? -1)")
            #endif
        } catch {
            #if DEBUG
            print("[Plan] Refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func apply(_ meta: APIAnalyzer.MetaResponse) {
        let serverSaysPro = meta.plan == "pro"
        // The device can know about a purchase before the server does, never the reverse.
        plan = (serverSaysPro || deviceSaysPro) ? .pro : .free
        if serverSaysPro {
            scansUsed = meta.scansUsed
            scanLimit = meta.scanLimit
            periodEndsAt = meta.periodEndsAt.flatMap(APIAnalyzer.parseDate)
        } else if !deviceSaysPro {
            scansUsed = nil
            scanLimit = nil
            periodEndsAt = nil
        }
        if let free = meta.freeScansLeft ?? (serverSaysPro ? nil : meta.creditsRemaining) {
            credits = max(free, 0)
            hasServerCount = true
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(credits, forKey: Self.cachedCreditsKey)
        UserDefaults.standard.set(plan.rawValue, forKey: Self.cachedPlanKey)
        UserDefaults.standard.set(hasServerCount, forKey: Self.hasServerCountKey)
    }

    // MARK: - Scan counting

    /// Fallback when a response carried no plan metadata.
    func recordScan() {
        if isPro {
            if let used = scansUsed { scansUsed = used + 1 }
        } else {
            credits = max(credits - 1, 0)
        }
        persist()
    }

    /// Sync from the `_meta` block returned by /api/analyze (and by a 402).
    func sync(_ meta: APIAnalyzer.MetaResponse?) {
        guard let meta else {
            recordScan()
            return
        }
        apply(meta)
    }

    /// Drop cached state after account deletion.
    func resetLocal() {
        credits = 0
        plan = .free
        scansUsed = nil
        scanLimit = nil
        periodEndsAt = nil
        activeProductID = nil
        proExpiresAt = nil
        isInTrial = false
        deviceSaysPro = false
        hasServerCount = false
        UserDefaults.standard.removeObject(forKey: Self.cachedCreditsKey)
        UserDefaults.standard.removeObject(forKey: Self.cachedPlanKey)
        UserDefaults.standard.removeObject(forKey: Self.hasServerCountKey)
    }

    // MARK: - Purchases

    /// The packages to offer: the current offering's weekly, monthly and annual.
    nonisolated static func proPackages(from offerings: Offerings?) -> [Package] {
        guard let offering = offerings?.current else { return [] }
        let order: [PackageType] = [.annual, .monthly, .weekly]
        let typed = order.compactMap { type in offering.availablePackages.first { $0.packageType == type } }
        if !typed.isEmpty { return typed }
        // Custom package identifiers: fall back to everything with a subscription period.
        return offering.availablePackages.filter { $0.storeProduct.subscriptionPeriod != nil }
    }

    /// Buy a Pro subscription (04 §5.5). Every way it can end is an outcome
    /// the paywall shows; nothing is silent any more.
    /// - `.cancelled`: the user closed the App Store sheet (RevenueCat reports
    ///   this either as `userCancelled` or as `purchaseCancelledError`).
    /// - `.pro`: Pro is active on the device, or our server already says Pro.
    /// - `.noEntitlement`: paid, but no active "pro" entitlement yet.
    /// Throws for Ask to Buy (`ErrorCode.paymentPendingError`) and real failures.
    func purchase(package: Package) async throws -> PurchaseOutcome {
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            apply(result.customerInfo)
        } catch let error as RevenueCat.ErrorCode where error == .purchaseCancelledError {
            return .cancelled
        }
        await refresh(fresh: true)
        // `isPro` = device or server (the server can know first via the webhook).
        return isPro ? .pro : .noEntitlement
    }

    /// Restore an existing subscription (new phone, reinstall). Returns true when Pro.
    @discardableResult
    func restorePurchases() async throws -> Bool {
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        await refresh(fresh: true)
        return deviceSaysPro
    }
}
