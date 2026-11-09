import DeviceCheck
import Foundation
import Security
import UIKit

struct APIAnalyzer {
    /// Local dev server in DEBUG, deployed proxy in Release — see `AppConfig`.
    static let baseURL = AppConfig.apiBaseURL

    // 768px at q0.5 was small enough that the model was guessing at set names and
    // collector numbers it could not actually read. 1536px at q0.7 keeps a
    // two-image payload around 1 MB, well under the platform's ~4.5 MB body cap.
    private static let jpegCompression: CGFloat = 0.7
    private static let maxImageDimension: CGFloat = 1536
    private static let timeoutInterval: TimeInterval = 120
    // Reverse image search (Google Lens, eBay) gets its own smaller copy of the
    // main photo: Lens refuses uploads over 500 KB, and it matches on overall
    // look, not small print, so 1024px is plenty.
    private static let searchImageDimension: CGFloat = 1024
    private static let searchImageCompression: CGFloat = 0.6

    /// Builds a request with the headers every authenticated endpoint needs.
    private static func makeRequest(
        path: String,
        method: String,
        appUserID: String?,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.appSharedSecret, forHTTPHeaderField: "X-App-Key")
        if let appUserID, !appUserID.isEmpty {
            request.setValue(appUserID, forHTTPHeaderField: "X-RC-User-ID")
        }
        // Lets the server count the free scans per device, so reinstalling or
        // signing out doesn't hand out a fresh set.
        request.setValue(DeviceIdentity.installID, forHTTPHeaderField: "X-Device-ID")
        request.timeoutInterval = timeout
        return request
    }

    struct AnalysisResult {
        let profile: CollectibleProfile
        let estimate: ValueEstimate
        let meta: MetaResponse?
    }

    enum APIError: LocalizedError {
        case compressionFailed
        case invalidURL
        case invalidResponse(Int)
        case decodingFailed
        /// Free plan: the free scans are used up. Show the paywall.
        case noCreditsRemaining
        /// Pro: fair-use cap for this period reached. Not a paywall moment.
        case scanLimitReached(limit: Int?, resetsAt: Date?)

        var errorDescription: String? {
            switch self {
            case .compressionFailed:
                return "Failed to compress image for upload."
            case .invalidURL:
                return "Invalid API endpoint URL."
            case .invalidResponse(let code):
                return "Server returned status \(code)."
            case .decodingFailed:
                return "Could not parse the analysis response."
            case .noCreditsRemaining:
                return "You've used your free scans."
            case .scanLimitReached(let limit, let resetsAt):
                let count = limit.map { "all \($0) " } ?? "all your "
                if let resetsAt {
                    let when = resetsAt.formatted(date: .abbreviated, time: .omitted)
                    return "You've used \(count)Pro scans for this period. More on \(when)."
                }
                return "You've used \(count)Pro scans for this period."
            }
        }
    }

    /// Plan metadata: `_meta` on /api/analyze (and its 402), and the body of GET /api/credits.
    struct MetaResponse: Decodable {
        /// "free" or "pro". Nil from an older server.
        let plan: String?
        let freeScansLeft: Int?
        let scansUsed: Int?
        let scanLimit: Int?
        /// ISO 8601: when the Pro fair-use window resets.
        let periodEndsAt: String?
        // Older fields, still sent.
        let creditsRemaining: Int?
        let scansRemaining: Int?
    }

    private struct LimitResponse: Decodable {
        let reason: String?
        let meta: MetaResponse?

        enum CodingKeys: String, CodingKey {
            case reason
            case meta = "_meta"
        }
    }

    /// Exchange rates sent with each scan: units per 1 USD (ECB).
    private struct FXBlock: Decodable {
        let date: String?
        let perUSD: [String: Double]
    }

    private struct APIResponse: Decodable {
        let profile: CollectibleProfile
        let estimate: ValueEstimate
        let meta: MetaResponse?
        let fx: FXBlock?

        enum CodingKeys: String, CodingKey {
            case profile, estimate, fx
            case meta = "_meta"
        }

        init(from decoder: Decoder) throws {
            let rootContainer = try? decoder.container(keyedBy: CodingKeys.self)
            self.meta = try rootContainer?.decodeIfPresent(MetaResponse.self, forKey: .meta)
            if let block = try? rootContainer?.decodeIfPresent(FXBlock.self, forKey: .fx) {
                self.fx = block
            } else {
                self.fx = nil
            }

            // Try nested keys first, then fall back to flat top-level decode
            if let container = rootContainer,
               let profile = try? container.decode(CollectibleProfile.self, forKey: .profile),
               let estimate = try? container.decode(ValueEstimate.self, forKey: .estimate) {
                self.profile = profile
                self.estimate = estimate
            } else {
                // Flat JSON: both CollectibleProfile and ValueEstimate fields at root
                self.profile = try CollectibleProfile(from: decoder)
                self.estimate = try ValueEstimate(from: decoder)
            }
        }
    }

    func analyze(
        images: [UIImage],
        userInfo: String? = nil,
        condition: ConditionGrade? = nil,
        appUserID: String? = nil,
        ocrText: [String] = [],
        barcode: String? = nil,
        includeDeviceCheck: Bool = false
    ) async throws -> AnalysisResult {
        #if DEBUG
        if DemoData.isActive { return try await DemoData.analysisResult() }
        #endif
        var base64Images: [String] = []
        for img in images {
            let resized = downsample(img, maxDimension: Self.maxImageDimension)
            guard let jpegData = resized.jpegData(compressionQuality: Self.jpegCompression) else {
                throw APIError.compressionFailed
            }
            base64Images.append(jpegData.base64EncodedString())
        }

        var body: [String: Any] = ["images": base64Images]
        if let first = images.first,
           let searchData = downsample(first, maxDimension: Self.searchImageDimension)
               .jpegData(compressionQuality: Self.searchImageCompression) {
            body["searchImage"] = searchData.base64EncodedString()
        }
        if let userInfo, !userInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["userInfo"] = userInfo
        }
        if let condition {
            body["condition"] = condition.rawValue
        }
        // On-device Vision reads small print far more reliably than a vision model
        // reads it back out of a JPEG, so the transcript rides along with the photos.
        if !ocrText.isEmpty {
            body["ocrText"] = ocrText
        }
        if let barcode, !barcode.isEmpty {
            body["barcode"] = barcode
        }
        // Free plan: Apple's proof that this is a real iPhone, which the server
        // uses to stop free scans being claimed again after a reinstall.
        if includeDeviceCheck, let token = await DeviceIdentity.deviceCheckToken() {
            body["deviceCheckToken"] = token
            body["deviceCheckEnv"] = DeviceIdentity.deviceCheckEnvironment
        }

        var request = try Self.makeRequest(
            path: "/api/analyze",
            method: "POST",
            appUserID: appUserID,
            timeout: Self.timeoutInterval
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? -1
        #if DEBUG
        print("[API] Response status: \(statusCode), body size: \(data.count) bytes")
        #endif

        if statusCode == 402 {
            let limit = try? JSONDecoder().decode(LimitResponse.self, from: data)
            #if DEBUG
            print("[API] 402 — \(limit?.reason ?? "no scans left")")
            #endif
            if limit?.reason == "fair_use" {
                let resetsAt = limit?.meta?.periodEndsAt.flatMap(Self.parseDate)
                throw APIError.scanLimitReached(limit: limit?.meta?.scanLimit, resetsAt: resetsAt)
            }
            throw APIError.noCreditsRemaining
        }

        guard (200...299).contains(statusCode) else {
            #if DEBUG
            if let body = String(data: data, encoding: .utf8) {
                print("[API] Error body: \(body)")
            }
            #endif
            throw APIError.invalidResponse(statusCode)
        }

        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("[API] Response JSON: \(raw.prefix(500))")
        }
        #endif

        let decoder = JSONDecoder()

        do {
            let apiResponse = try decoder.decode(APIResponse.self, from: data)
            if let fx = apiResponse.fx {
                DisplayCurrency.store(perUSD: fx.perUSD, date: fx.date)
            }
            return AnalysisResult(profile: apiResponse.profile, estimate: apiResponse.estimate, meta: apiResponse.meta)
        } catch {
            #if DEBUG
            print("[API] Failed to decode response: \(error)")
            #endif
            throw APIError.decodingFailed
        }
    }

    // MARK: - Plan status

    /// The server writes ISO 8601 dates with milliseconds ("2026-11-01T00:00:00.000Z").
    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// Plan, free scans left and Pro usage. `refresh` skips the server's
    /// subscription cache (right after a purchase or restore).
    static func fetchAccessStatus(appUserID: String, refresh: Bool = false) async throws -> MetaResponse {
        let request = try makeRequest(
            path: refresh ? "/api/credits?refresh=1" : "/api/credits",
            method: "GET",
            appUserID: appUserID,
            timeout: 10
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            throw APIError.invalidResponse(http?.statusCode ?? -1)
        }

        return try JSONDecoder().decode(MetaResponse.self, from: data)
    }

    // MARK: - Auth Migration

    private struct MigrateResponse: Decodable {
        let migrated: Int
        let credits: Int
    }

    /// Migrate credits from an old anonymous user ID to a new Apple user ID.
    /// Price histories for saved items, by item id (Pro). Sending the keys also
    /// registers the items for the server's daily re-pricing.
    static func fetchPriceHistories(appUserID: String, items: [(UUID, JSONValue)]) async throws -> [UUID: PriceHistory] {
        struct Response: Decodable {
            let histories: [String: PriceHistory]?
            let locked: Bool?
        }
        var request = try makeRequest(path: "/api/prices", method: "POST", appUserID: appUserID, timeout: 30)
        let body: [String: Any] = [
            "items": items.prefix(200).map { item -> [String: Any] in
                ["id": item.0.uuidString, "keys": item.1.foundationValue]
            }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw APIError.invalidResponse(status) }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw APIError.decodingFailed
        }
        var out: [UUID: PriceHistory] = [:]
        for (key, history) in decoded.histories ?? [:] {
            if let id = UUID(uuidString: key) { out[id] = history }
        }
        return out
    }

    static func migrateCredits(fromUserID: String, toUserID: String) async throws -> Int {
        var request = try makeRequest(
            path: "/api/auth/migrate-credits",
            method: "POST",
            appUserID: toUserID,
            timeout: 10
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "oldUserID": fromUserID,
            "newUserID": toUserID,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            throw APIError.invalidResponse(http?.statusCode ?? -1)
        }

        let decoded = try JSONDecoder().decode(MigrateResponse.self, from: data)
        #if DEBUG
        print("[API] Migrated \(decoded.migrated) credits → new balance: \(decoded.credits)")
        #endif
        return decoded.credits
    }

    // MARK: - Account Deletion

    struct DeletionResult: Decodable {
        let deleted: Bool
        let creditsDeleted: Int?
        let revenueCatDeleted: Bool?
        let appleCredentialRevoked: Bool?
    }

    /// Erase everything the server holds for this user: credit balance,
    /// RevenueCat subscriber, and — when `appleAuthorizationCode` is supplied —
    /// the Sign in with Apple token.
    ///
    /// Apple requires token revocation for accounts created with Sign in with
    /// Apple (Guideline 5.1.1(v)), and revocation can only be done server-side,
    /// which is why the code is passed through instead of used on device.
    static func deleteAccount(
        appUserID: String,
        appleAuthorizationCode: String? = nil
    ) async throws -> DeletionResult {
        var request = try makeRequest(
            path: "/api/auth/delete-account",
            method: "POST",
            appUserID: appUserID,
            timeout: 20
        )

        var body: [String: Any] = [:]
        if let appleAuthorizationCode, !appleAuthorizationCode.isEmpty {
            body["appleAuthorizationCode"] = appleAuthorizationCode
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            throw APIError.invalidResponse(http?.statusCode ?? -1)
        }

        return try JSONDecoder().decode(DeletionResult.self, from: data)
    }

    private func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        guard scale < 1.0 else { return image }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        // Pin the renderer to 1x. The default is the device's screen scale (3x on
        // most iPhones), which would render maxDimension * 3 real pixels and blow
        // the request past the proxy's 4 MB body limit after base64 encoding.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Device identity

/// A random install ID kept in the Keychain.
///
/// iOS keeps Keychain items when the app is deleted, so a reinstall comes back
/// with the same ID (and the server knows its free scans are used). It is
/// random, not derived from the hardware, and `ThisDeviceOnly` keeps it out of
/// backups, so it never follows the user to a new phone. Not a security
/// boundary — App Attest / DeviceCheck is the stronger, later step.
enum DeviceIdentity {
    static let installID: String = loadOrCreate()

    /// Apple DeviceCheck token (base64), or nil on the simulator / when Apple
    /// can't issue one. Never throws: the scan goes ahead without it.
    static func deviceCheckToken() async -> String? {
        guard DCDevice.current.isSupported else { return nil }
        do {
            return try await DCDevice.current.generateToken().base64EncodedString()
        } catch {
            #if DEBUG
            print("[DeviceCheck] token failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Xcode debug builds are development-signed; their tokens are checked
    /// against Apple's development server. TestFlight and App Store: production.
    static var deviceCheckEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private static let service = "com.johan.collectiblescanner.device"
    private static let account = "install-id"

    private static func loadOrCreate() -> String {
        if let existing = load() { return existing }
        let fresh = UUID().uuidString
        save(fresh)
        // If saving failed, the next launch makes a new ID: no worse than before.
        return load() ?? fresh
    }

    private static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let id = String(data: data, encoding: .utf8),
              !id.isEmpty
        else { return nil }
        return id
    }

    private static func save(_ id: String) {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(id.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }
}

