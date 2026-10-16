import Foundation

@main
enum ReceiverStoreEnvironmentTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func rejects(_ message: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(message) }
            catch { checks += 1 }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Library/Containers/com.chekusu.sofatap.receiver/Data", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let paths = try ReceiverStoreDirectories(containerHome: home, applicationSupport: support, caches: cache)
        let resolvedHome = home.resolvingSymlinksInPath()
        check(paths.data.path == resolvedHome.appendingPathComponent("Library/Application Support/Sofatap").path,
              "private profile is inside the parent container")
        check(paths.bundleCache.path == resolvedHome.appendingPathComponent("Library/Caches/Sofatap/dotnet-bundle").path,
              "bundle extraction is private container cache")
        let environment = paths.helperEnvironment(inherited: [
            "PATH": "/usr/bin", "DOTNET_BUNDLE_EXTRACT_BASE_DIR": "/outside/website-cache",
        ])
        check(environment["DOTNET_BUNDLE_EXTRACT_BASE_DIR"] == paths.bundleCache.path,
              "an inherited outside extraction directory is always replaced")
        check(environment["PATH"] == "/usr/bin", "unrelated process environment is preserved")
        rejects("non-sandbox store launch must fail closed") {
            _ = try ReceiverStoreDirectories(containerHome: root, applicationSupport: support, caches: cache)
        }
        rejects("cannot use another app container") {
            _ = try ReceiverStoreDirectories(containerHome: root.appendingPathComponent("Library/Containers/another.app/Data"),
                                             applicationSupport: support, caches: cache)
        }
        for outside in [root.appendingPathComponent("Library/Application Support"),
                        home.appendingPathComponent("../website-profile"),
                        URL(fileURLWithPath: home.path + "-sibling/Library/Caches")] {
            rejects("credential profile cannot escape the app container") {
                _ = try ReceiverStoreDirectories(containerHome: home, applicationSupport: outside, caches: cache)
            }
            rejects("bundle extraction cannot escape the app container") {
                _ = try ReceiverStoreDirectories(containerHome: home, applicationSupport: support, caches: outside)
            }
        }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: support.appendingPathComponent("Sofatap"),
                                                   withDestinationURL: outside)
        rejects("an existing credential-directory symlink cannot escape the container") {
            _ = try ReceiverStoreDirectories(containerHome: home, applicationSupport: support, caches: cache)
        }
        print("PASS: \(checks) store-container checks (temporary paths only; no receiver, permission prompt or input)")
    }
}
