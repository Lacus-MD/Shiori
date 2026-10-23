import Foundation

/// Turns a place into its own little app with a File Provider extension, so
/// Finder shows it in the sidebar with its own name and glyph.
///
/// The sidebar takes both from the extension bundle (its display name and
/// `CFBundleIcons › CFBundlePrimaryIcon › CFBundleSymbolName`), never from a
/// domain, so each place needs a bundle of its own. Shiori copies the template
/// it ships with, writes the place into the Info.plists, gives the extension
/// read access to exactly the place's folder, signs the copy for this Mac
/// (ad hoc) and registers it.
enum PlaceInstaller {
    static var placesDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Shiori/Places", directoryHint: .isDirectory)
    }

    /// Finder labels the sidebar entry with the place app's file name, so the
    /// bundle is called after the place, in a folder of its own.
    static func folderURL(for place: Place) -> URL {
        placesDirectory.appending(path: place.bundleID, directoryHint: .isDirectory)
    }

    static func bundleURL(for place: Place) -> URL {
        let name = place.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return folderURL(for: place).appending(path: "\(name).app", directoryHint: .isDirectory)
    }

    /// The bundle currently on disk, which still has the old name after a rename.
    static func installedBundle(for place: Place) -> URL? {
        let folder = folderURL(for: place)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.first { $0.hasSuffix(".app") }.map { folder.appending(path: $0, directoryHint: .isDirectory) }
    }

    private static var templateURL: URL? {
        Bundle.main.url(forResource: "PlaceTemplate", withExtension: "app")
    }

    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let extensionPath = "Contents/PlugIns/ShioriFileProvider.appex"
    private static let hostPath = "Contents/MacOS/ShioriPlaceHost"

    enum Failure: LocalizedError {
        case missingTemplate
        case command(String, String)

        var errorDescription: String? {
            switch self {
            case .missingTemplate: String(localized: "Shiori’s place template is missing. Reinstall Shiori.")
            case let .command(tool, output): String(localized: "\(tool) failed: \(output)")
            }
        }
    }

    /// Builds (or rebuilds) the place's bundle and adds its sidebar entry.
    /// An existing entry keeps its identity, so macOS keeps it enabled.
    static func install(_ place: Place) async throws -> PlaceStatus {
        guard let templateURL else { throw Failure.missingTemplate }
        let fileManager = FileManager.default
        let bundle = bundleURL(for: place)
        let staging = placesDirectory.appending(path: ".staging-\(place.bundleID).app")
        try fileManager.createDirectory(at: placesDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.copyItem(at: templateURL, to: staging)

        let appex = staging.appending(path: extensionPath)
        let version = String(Int(Date.now.timeIntervalSince1970))
        let config = PlaceConfig(id: place.domainID, name: place.name, path: place.path)
        try editInfo(at: staging.appending(path: "Contents/Info.plist")) { info in
            info["CFBundleIdentifier"] = place.bundleID
            info["CFBundleName"] = place.name
            info["CFBundleDisplayName"] = place.name
            info["CFBundleVersion"] = version
            info[PlaceConfig.infoKey] = config.infoValue
        }
        try editInfo(at: appex.appending(path: "Contents/Info.plist")) { info in
            info["CFBundleIdentifier"] = place.bundleID + ".file-provider"
            info["CFBundleName"] = place.name
            info["CFBundleDisplayName"] = place.name
            info["CFBundleVersion"] = version
            info["CFBundleIcons"] = ["CFBundlePrimaryIcon": ["CFBundleSymbolName": place.symbol]]
            info[PlaceConfig.infoKey] = config.infoValue
        }

        // The extension is sandboxed; it may read the place's folder and
        // nothing else.
        let folder = place.path.hasSuffix("/") ? place.path : place.path + "/"
        let entitlements: [String: Any] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.temporary-exception.files.absolute-path.read-only": [folder],
        ]
        let entitlementsURL = fileManager.temporaryDirectory.appending(path: "shiori-\(UUID().uuidString).plist")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: entitlementsURL)
        defer { try? fileManager.removeItem(at: entitlementsURL) }
        try await run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime",
                                            "--entitlements", entitlementsURL.path(percentEncoded: false),
                                            appex.path(percentEncoded: false)])
        try await run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", staging.path(percentEncoded: false)])

        if let old = installedBundle(for: place) {
            _ = try? await run(lsregister, ["-u", old.path(percentEncoded: false)])
            try fileManager.removeItem(at: old)
        }
        try fileManager.createDirectory(at: folderURL(for: place), withIntermediateDirectories: true)
        try fileManager.moveItem(at: staging, to: bundle)
        try await register(bundle)

        // The system needs a moment to see a freshly registered extension.
        var lastError: (any Error)?
        for attempt in 0..<8 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(500 * attempt)) }
            do {
                try await host(place, [])
                _ = try? await host(place, ["--signal"])
                return try await status(of: place)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? Failure.command("ShioriPlaceHost", "")
    }

    static func uninstall(_ place: Place) async {
        guard let bundle = installedBundle(for: place) else { return }
        await remove(bundle)
        try? FileManager.default.removeItem(at: folderURL(for: place))
    }

    private static func remove(_ bundle: URL) async {
        _ = try? await run(bundle.appending(path: hostPath).path(percentEncoded: false), ["--remove"])
        _ = try? await run("/usr/bin/pluginkit", ["-r", bundle.appending(path: extensionPath).path(percentEncoded: false)])
        _ = try? await run(lsregister, ["-u", bundle.path(percentEncoded: false)])
    }

    static func status(of place: Place) async throws -> PlaceStatus {
        guard installedBundle(for: place) != nil else { return PlaceStatus(registered: false, enabled: false) }
        let output = try await host(place, ["--status"])
        return try JSONDecoder().decode(PlaceStatus.self, from: Data(output.utf8))
    }

    /// Asks the system to list the place's root again.
    static func refresh(_ place: Place) async {
        _ = try? await host(place, ["--signal"])
    }

    /// Bundles in the places folder that no place owns any more.
    static func removeOrphans(keeping places: [Place]) async {
        let keep = Set(places.map(\.bundleID))
        let found = (try? FileManager.default.contentsOfDirectory(atPath: placesDirectory.path(percentEncoded: false))) ?? []
        for name in found where name.hasPrefix("hu.lacus.shiori.place.") && !keep.contains(name) {
            let folder = placesDirectory.appending(path: name, directoryHint: .isDirectory)
            let bundles = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            for bundle in bundles where bundle.hasSuffix(".app") {
                await remove(folder.appending(path: bundle, directoryHint: .isDirectory))
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: Helpers

    private static func register(_ bundle: URL) async throws {
        try await run(lsregister, ["-f", "-R", bundle.path(percentEncoded: false)])
        try await run("/usr/bin/pluginkit", ["-a", bundle.appending(path: extensionPath).path(percentEncoded: false)])
    }

    @discardableResult
    private static func host(_ place: Place, _ arguments: [String]) async throws -> String {
        guard let bundle = installedBundle(for: place) else { throw CocoaError(.fileNoSuchFile) }
        return try await run(bundle.appending(path: hostPath).path(percentEncoded: false), arguments)
    }

    private static func editInfo(at url: URL, _ edit: (inout [String: Any]) -> Void) throws {
        let data = try Data(contentsOf: url)
        guard var info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        edit(&info)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard status == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Failure.command(URL(filePath: tool).lastPathComponent, message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}
