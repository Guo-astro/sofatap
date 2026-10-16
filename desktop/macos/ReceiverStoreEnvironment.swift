import Foundation

/// Derive all writable helper paths in the signed parent's App Sandbox container.
/// The inherited helper must never fall back to the website receiver's profile or
/// a DOTNET_BUNDLE_EXTRACT_BASE_DIR inherited from the launching shell.
struct ReceiverStoreDirectories: Equatable {
    let data: URL
    let bundleCache: URL

    init(containerHome: URL, applicationSupport: URL, caches: URL) throws {
        let home = containerHome.standardizedFileURL.resolvingSymlinksInPath()
        guard home.lastPathComponent == "Data",
              home.deletingLastPathComponent().lastPathComponent == "com.chekusu.sofatap.receiver",
              home.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Containers" else {
            throw ReceiverStoreEnvironmentError.missingContainer
        }
        let support = applicationSupport.standardizedFileURL.resolvingSymlinksInPath()
        let cache = caches.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isDescendant(support, of: home), Self.isDescendant(cache, of: home) else {
            throw ReceiverStoreEnvironmentError.outsideContainer
        }
        data = support.appendingPathComponent("Sofatap", isDirectory: true)
        bundleCache = cache.appendingPathComponent("Sofatap/dotnet-bundle", isDirectory: true)
        // A pre-existing symlink inside the container must not redirect private
        // credentials or extracted executable files into the website profile.
        guard Self.isDescendant(data.resolvingSymlinksInPath(), of: home),
              Self.isDescendant(bundleCache.resolvingSymlinksInPath(), of: home) else {
            throw ReceiverStoreEnvironmentError.outsideContainer
        }
    }

    static func production(fileManager: FileManager = .default) throws -> Self {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: false)
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: false)
        let result = try Self(containerHome: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
                              applicationSupport: support, caches: caches)
        for directory in [result.data, result.bundleCache] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
        }
        return result
    }

    func helperEnvironment(inherited: [String: String]) -> [String: String] {
        var result = inherited
        result["DOTNET_BUNDLE_EXTRACT_BASE_DIR"] = bundleCache.path
        return result
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        url.path.hasPrefix(directory.path + "/")
    }
}

enum ReceiverStoreEnvironmentError: Error {
    case missingContainer, outsideContainer
}
