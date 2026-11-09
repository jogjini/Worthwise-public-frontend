import Foundation

/// Every value that changes between "works on my Mac" and "works on the App
/// Store" lives here, so shipping is one file to check rather than four.
///
/// ⚠️ Before archiving a Release build, `productionBaseURL` and
/// `revenueCatPublicKey` must be real. Both are placeholders on a fresh
/// checkout, and TestFlight uses the Release configuration — a build with
/// placeholders installs fine and then fails every scan and every purchase.
enum AppConfig {

    // MARK: - Backend

    /// Deployed proxy. Fill in after the first `vercel --prod`.
    /// Example: "https://collectible-proxy.vercel.app"
    private static let productionBaseURL = "https://collectible-proxy.vercel.app"

    #if DEBUG
    /// Debug builds use the live server too, so the app works away from home.
    /// Set to true to test server changes on your Mac first (`npm run serve`,
    /// same Wi-Fi as the phone).
    private static let useLocalServer = false
    private static let localServerURL = "http://192.168.1.10:3000"  // your Mac's LAN address
    static let apiBaseURL = useLocalServer ? localServerURL : productionBaseURL
    #else
    static let apiBaseURL = productionBaseURL
    #endif

    /// Hosted legal pages always point at production — a localhost link in a
    /// debug build would just fail to open on device.
    static var termsURL: URL { URL(string: "\(productionBaseURL)/terms.html")! }
    static var privacyURL: URL { URL(string: "\(productionBaseURL)/privacy.html")! }
    static var supportURL: URL { URL(string: "\(productionBaseURL)/support.html")! }

    // MARK: - App gate

    /// Sent as `X-App-Key` on every authenticated endpoint.
    ///
    /// This is a stopgap, not a secret: anyone can pull it out of the binary.
    /// It exists to stop drive-by `curl` abuse of the credit and analysis
    /// endpoints, which was otherwise free. The real fix is App Attest (v1.1).
    ///
    /// Must match `APP_SHARED_SECRET` on the (private) backend.
    ///
    /// Read from Info.plist, which gets it from the `APP_SHARED_SECRET` build
    /// setting in `Config/Secrets.xcconfig` (git-ignored). Empty on a fresh
    /// clone, which is fine for running the UI with demo data.
    static let appSharedSecret: String =
        (Bundle.main.object(forInfoDictionaryKey: "AppSharedSecret") as? String) ?? ""

    // MARK: - RevenueCat

    #if DEBUG
    static let revenueCatPublicKey = "test_TBfEqJEWmphCCZKjiYcShKirYph"
    #else
    /// RevenueCat dashboard → Project settings → API keys → App Store app.
    /// Public SDK key, prefix "appl_".
    static let revenueCatPublicKey = "appl_bYfHHHCkGYaGxaYTShjKVNuskRv"
    #endif

    // MARK: - Preflight

    /// True when a Release build still carries placeholder values.
    /// Surfaced as a loud debug assertion rather than a silent broken build.
    static var hasUnfilledPlaceholders: Bool {
        apiBaseURL.contains("REPLACE-WITH") || revenueCatPublicKey.contains("REPLACE_WITH")
    }
}
