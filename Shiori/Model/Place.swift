import SwiftUI

/// One entry the user wants in the Finder sidebar.
struct Place: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var path: String
    var symbol: String
    var tint: PlaceTint = .blue
    /// Set when the folder is on a network share, so Shiori can connect it.
    var remount: Remount?

    struct Remount: Codable, Hashable, Sendable {
        /// The share's `smb://` (or `afp://`, `nfs://`) URL, without a password.
        var url: String
        /// Where the share was mounted when the place was set up.
        var volumePath: String
    }

    /// Bundle identifiers must not start a component with a digit.
    var bundleID: String { "hu.lacus.shiori.place.p" + id.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
    var domainID: String { id.uuidString }

    var url: URL { URL(filePath: path, directoryHint: .isDirectory) }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: path) }

    /// The folder's path if its share was mounted at `mountpoint`.
    func path(onShareMountedAt mountpoint: String) -> String {
        guard let remount else { return path }
        let volume = Self.trimmed(remount.volumePath)
        guard path == volume || path.hasPrefix(volume + "/") else { return path }
        return Self.trimmed(mountpoint) + path.dropFirst(volume.count)
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// A place for a folder the user just picked, with a name and an icon
    /// guessed from what the folder looks like.
    init(folder url: URL) {
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        name = FileManager.default.displayName(atPath: path)
        self.path = path
        symbol = Self.suggestedSymbol(for: url)
        remount = NetworkMounter.remount(for: url)
    }

    init(name: String, path: String, symbol: String, tint: PlaceTint = .blue) {
        self.name = name
        self.path = path
        self.symbol = symbol
        self.tint = tint
    }

    static func suggestedSymbol(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        let hints: [(words: [String], symbol: String)] = [
            (["film", "movie", "mozi", "video", "videó"], "film"),
            (["zene", "music", "audio"], "music.note"),
            (["fotó", "foto", "photo", "kép", "pictures"], "photo.on.rectangle"),
            (["app", "code", "dev", "projekt", "project", "src"], "hammer.fill"),
            (["műtét", "mutet", "orvos", "medical", "health", "egészség"], "cross.case.fill"),
            (["könyv", "book", "doc", "dokumentum"], "books.vertical.fill"),
            (["letölt", "download"], "arrow.down.circle.fill"),
            (["backup", "mentés", "archív", "archive"], "archivebox.fill"),
        ]
        if let hint = hints.first(where: { $0.words.contains { name.contains($0) } }) { return hint.symbol }
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .isVolumeKey])
        if values?.volumeIsLocal == false { return "externaldrive.connected.to.line.below.fill" }
        if values?.isVolume == true { return "externaldrive.fill" }
        return "folder.fill"
    }
}

/// The tint of a place in Shiori's own menu and window. The Finder sidebar
/// draws every glyph in its own monochrome style.
enum PlaceTint: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .teal: "Teal"
        case .graphite: "Graphite"
        }
    }
}

/// Where a place stands with the system.
enum PlaceState: Equatable, Sendable {
    case unknown
    case working
    /// In the sidebar, but macOS waits for the user to allow it once.
    case needsEnabling
    case ready
    case failed(String)
}
