import Foundation
import NetFS

/// Connects network shares that a place lives on, so a click on a place
/// whose share is not mounted still lands in the right folder.
enum NetworkMounter {
    enum Failure: LocalizedError {
        case mount(Int32)

        var errorDescription: String? {
            switch self {
            case let .mount(code): String(localized: "Could not connect to the share (error \(code)).")
            }
        }
    }

    /// How to bring back the share a folder is on; `nil` for local folders.
    static func remount(for url: URL) -> Place.Remount? {
        let keys: Set<URLResourceKey> = [.volumeURLForRemountingKey, .volumeURLKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let remount = values.volumeURLForRemounting, let volume = values.volume else { return nil }
        return Place.Remount(url: remount.absoluteString, volumePath: volume.path(percentEncoded: false))
    }

    /// Mounts the share and returns where it landed. macOS shows its own
    /// sign-in window if the Keychain has no password for it.
    static func mount(_ remount: Place.Remount) async throws -> String {
        guard let url = URL(string: remount.url) else { throw Failure.mount(-1) }
        let options = NSMutableDictionary()
        options[kNAUIOptionKey] = kNAUIOptionAllowUI
        return try await withCheckedThrowingContinuation { continuation in
            var request: AsyncRequestID?
            let started = NetFSMountURLAsync(url as CFURL, nil, nil, nil, options, nil, &request, .main) { status, _, mountpoints in
                // EEXIST: someone mounted it meanwhile, which is just as good.
                if status == 0 || status == EEXIST,
                   let mountpoint = (mountpoints as? [String])?.first ?? (status == EEXIST ? remount.volumePath : nil) {
                    continuation.resume(returning: mountpoint)
                } else {
                    continuation.resume(throwing: Failure.mount(status))
                }
            }
            if started != 0 { continuation.resume(throwing: Failure.mount(started)) }
        }
    }
}
