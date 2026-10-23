import Foundation

/// What a generated place bundle serves. Shiori writes it into the Info.plist
/// of both the place app and its File Provider extension under `ShioriPlace`.
struct PlaceConfig: Sendable {
    var id: String
    var name: String
    var path: String

    static let infoKey = "ShioriPlace"

    static var current: PlaceConfig? {
        guard let dict = Bundle.main.object(forInfoDictionaryKey: infoKey) as? [String: String],
              let id = dict["id"], let name = dict["name"], let path = dict["path"] else { return nil }
        return PlaceConfig(id: id, name: name, path: path)
    }

    var infoValue: [String: String] { ["id": id, "name": name, "path": path] }
}

/// What a place app reports for `--status`.
struct PlaceStatus: Codable, Sendable, Equatable {
    var registered: Bool
    var enabled: Bool
    var rootPath: String?
}
