import FileProvider
import Foundation

// A generated place app. Shiori runs it to manage the one File Provider domain
// its extension serves:
//   (no argument)  add or update the domain
//   --remove       remove the domain
//   --status       print a PlaceStatus as JSON
//   --signal       ask the system to list the root again
guard let config = PlaceConfig.current else {
    FileHandle.standardError.write(Data("This is Shiori's template; Shiori configures a copy per place.\n".utf8))
    exit(2)
}

let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(config.id), displayName: config.name)
let arguments = CommandLine.arguments.dropFirst()

@MainActor func status() async throws -> PlaceStatus {
    let registered = try await NSFileProviderManager.domains().first { $0.identifier == domain.identifier }
    guard let registered else { return PlaceStatus(registered: false, enabled: false) }
    let root = try? await NSFileProviderManager(for: registered)?.getUserVisibleURL(for: .rootContainer)
    return PlaceStatus(registered: true, enabled: registered.userEnabled, rootPath: root?.path(percentEncoded: false))
}

Task {
    do {
        switch arguments.first {
        case "--remove":
            try await NSFileProviderManager.remove(domain)
        case "--status":
            let data = try JSONEncoder().encode(try await status())
            FileHandle.standardOutput.write(data)
        case "--signal":
            let manager = NSFileProviderManager(for: domain)
            try await manager?.signalEnumerator(for: .rootContainer)
            try await manager?.signalEnumerator(for: .workingSet)
        default:
            try await NSFileProviderManager.add(domain)
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}
dispatchMain()
