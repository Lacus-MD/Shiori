import FileProvider
import UniformTypeIdentifiers

/// The sidebar entry of one place.
///
/// The root lists the place's top-level items as symbolic links to the real
/// ones, so nothing is copied: opening a folder takes Finder to the real
/// location, opening a file opens the original. The root itself is
/// read-only. With the jump on, Shiori moves the Finder window from here to
/// the real folder right away (see FinderWatcher).
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    required init(domain: NSFileProviderDomain) {
        super.init()
    }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        let listing = PlaceListing.current()
        if identifier == .rootContainer {
            completionHandler(PlaceItem.root(listing), nil)
        } else if let item = listing?.item(identifier) {
            completionHandler(item, nil)
        } else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
        }
        return Progress()
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        // Every item is a folder or a symbolic link; there are no contents.
        completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
        return Progress()
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> any NSFileProviderEnumerator {
        guard containerItemIdentifier == .rootContainer || containerItemIdentifier == .workingSet else {
            throw NSFileProviderError(.noSuchItem)
        }
        return PlaceEnumerator()
    }

    // MARK: Writing (refused: the real folder is one click away)

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, [], false, NSFileProviderError(.cannotSynchronize))
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields,
                    contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        // Tags, last-used dates and the like stay in the local replica.
        let listing = PlaceListing.current()
        let current = item.itemIdentifier == .rootContainer ? PlaceItem.root(listing) : listing?.item(item.itemIdentifier)
        completionHandler(current, [], false, current == nil ? NSFileProviderError(.noSuchItem) : nil)
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping ((any Error)?) -> Void) -> Progress {
        completionHandler(NSFileProviderError(.deletionRejected))
        return Progress()
    }
}

/// The visible top-level items of the place's real folder, read on demand.
/// The extension's sandbox gets read access to exactly that folder.
struct PlaceListing {
    let config: PlaceConfig
    let names: [String]

    static func current() -> PlaceListing? {
        guard let config = PlaceConfig.current else { return nil }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: config.path)) ?? []
        return PlaceListing(config: config, names: names.filter { !$0.hasPrefix(".") }.sorted())
    }

    var items: [PlaceItem] {
        names.map { PlaceItem(name: $0, target: (config.path as NSString).appendingPathComponent($0)) }
    }

    func item(_ identifier: NSFileProviderItemIdentifier) -> PlaceItem? {
        items.first { $0.itemIdentifier == identifier }
    }

    /// Changes whenever the folder's top level or the target does.
    var anchor: NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(Data(([config.path] + names).joined(separator: "\n").utf8))
    }
}

final class PlaceItem: NSObject, NSFileProviderItem {
    private let name: String
    private let target: String?

    init(name: String, target: String?) {
        self.name = name
        self.target = target
    }

    static func root(_ listing: PlaceListing?) -> PlaceItem {
        PlaceItem(name: listing?.config.name ?? "Shiori", target: nil)
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        target.map { NSFileProviderItemIdentifier("link:\($0)") } ?? .rootContainer
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { name }
    var contentType: UTType { target == nil ? .folder : .symbolicLink }
    var symlinkTargetPath: String? { target }

    var capabilities: NSFileProviderItemCapabilities {
        target == nil ? [.allowsReading, .allowsContentEnumerating] : [.allowsReading]
    }

    var fileSystemFlags: NSFileProviderFileSystemFlags { [.userReadable, .userExecutable] }

    var itemVersion: NSFileProviderItemVersion {
        let version = Data((target ?? name).utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class PlaceEnumerator: NSObject, NSFileProviderEnumerator {
    func invalidate() {}

    func enumerateItems(for observer: any NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.didEnumerate(PlaceListing.current()?.items ?? [])
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: any NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        guard let listing = PlaceListing.current(), listing.anchor == syncAnchor else {
            // Something changed: the system lists the root again.
            observer.finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))
            return
        }
        observer.finishEnumeratingChanges(upTo: syncAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(PlaceListing.current()?.anchor)
    }
}
