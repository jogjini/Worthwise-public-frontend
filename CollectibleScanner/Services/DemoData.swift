#if DEBUG
import UIKit

/// App Store screenshot mode, for the UI tests in `CollectibleScannerUITests`.
///
/// Active only in Debug builds and only with the `-UITestDemoData` launch
/// argument. The data lives in Preview Assets, which Xcode leaves out of
/// archives, so none of it can reach the App Store build.
///
/// What it does:
/// - the collection is a throwaway copy, seeded from real scans
///   (`DemoScans` data asset: server responses from the production pipeline,
///   with the date they were made);
/// - the plan shows as Pro, without asking RevenueCat or the server;
/// - a scan returns a stored scan instead of calling the server, after
///   `-UITestScanDelay` seconds (default 2): the one whose image is named by
///   `-UITestScanItem` (e.g. `DemoJug`), else the first;
/// - `-UITestOpenScan` opens the scan flow on that scan's photo at launch.
enum DemoData {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-UITestDemoData")
    static var opensScan: Bool { isActive && ProcessInfo.processInfo.arguments.contains("-UITestOpenScan") }

    struct Entry {
        let name: String
        let image: UIImage?
        let condition: ConditionGrade
        let profile: CollectibleProfile
        let estimate: ValueEstimate
    }

    /// Stored scans, newest first.
    static let entries: [Entry] = {
        guard let data = NSDataAsset(name: "DemoScans")?.data,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            assertionFailure("DemoScans data asset missing or malformed")
            return []
        }
        return list.compactMap { entry in
            guard let response = entry["response"],
                  let json = try? JSONSerialization.data(withJSONObject: response),
                  let profile = try? JSONDecoder().decode(CollectibleProfile.self, from: json),
                  let estimate = try? JSONDecoder().decode(ValueEstimate.self, from: json) else {
                assertionFailure("DemoScans entry doesn't decode: \(entry["image"] ?? "?")")
                return nil
            }
            let name = entry["image"] as? String ?? ""
            return Entry(
                name: name,
                image: UIImage(named: name),
                condition: ConditionGrade(rawValue: entry["condition"] as? String ?? "") ?? .good,
                profile: profile,
                estimate: estimate
            )
        }
    }()

    /// An empty folder for the demo collection, so real data is never touched.
    static func freshDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DemoCollection", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    static func seed(_ store: CollectionStore) {
        // Oldest first: each add goes to the top, so the first entry ends up newest.
        for entry in entries.reversed() {
            store.add(profile: entry.profile, estimate: entry.estimate, condition: entry.condition, image: entry.image)
        }
    }

    /// The stored scan a demo scan returns.
    static var scanEntry: Entry? {
        let name = UserDefaults.standard.string(forKey: "UITestScanItem")
        return entries.first { $0.name == name } ?? entries.first
    }

    static func analysisResult() async throws -> APIAnalyzer.AnalysisResult {
        guard let entry = scanEntry else { throw APIAnalyzer.APIError.decodingFailed }
        // Launch arguments arrive as strings; double(forKey:) converts them.
        let defaults = UserDefaults.standard
        let delay = defaults.object(forKey: "UITestScanDelay") == nil ? 2 : defaults.double(forKey: "UITestScanDelay")
        try await Task.sleep(for: .seconds(delay))
        return APIAnalyzer.AnalysisResult(profile: entry.profile, estimate: entry.estimate, meta: nil)
    }
}
#endif
