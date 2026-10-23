import AppKit
import Observation

/// Follows copies into the places' folders. Finder publishes a Progress for
/// every file it copies (the same one that draws the pie on the file's
/// icon). A subscription only sees items directly inside one folder, so
/// Shiori subscribes to each place's folder and its subfolders two levels
/// deep, and adds the copies up per place.
@MainActor
@Observable
final class CopyMonitor {
    /// Copies going on right now, per place.
    struct Activity: Identifiable, Equatable {
        var id: UUID
        var name: String
        var fraction: Double
        var files: Int
    }

    private(set) var activities: [Activity] = []

    /// All copies together, `nil` while nothing is being copied.
    var overallFraction: Double? {
        activities.isEmpty ? nil : activities.map(\.fraction).reduce(0, +) / Double(activities.count)
    }

    /// Progress objects are not Sendable; Finder's arrive on a background
    /// queue and are only read on the main actor afterwards.
    private struct Box: @unchecked Sendable { let progress: Progress }

    /// One subscription per watched folder, keyed by its path.
    private var subscriptions: [String: (place: UUID, token: Any)] = [:]
    private var running: [UUID: [ObjectIdentifier: Progress]] = [:]
    private var names: [UUID: String] = [:]
    private var ticker: Task<Void, Never>?
    private var places: [Place] = []
    private var rescan: Task<Void, Never>?

    nonisolated private static let depth = 2
    /// Enough for a NAS share's genres and titles, without holding
    /// thousands of subscriptions.
    nonisolated private static let folderLimit = 400

    /// Watches the places' folders; the subfolders are listed again every
    /// few minutes, since new ones appear without Shiori noticing.
    func watch(_ places: [Place]) {
        self.places = places
        for place in places { names[place.id] = place.name }
        rescan?.cancel()
        rescan = Task {
            while !Task.isCancelled {
                await resubscribe()
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    private func resubscribe() async {
        let roots = places.map { ($0.id, $0.path) }
        // Listing a network share takes a while; not on the main actor.
        let wanted = await Task.detached(priority: .utility) {
            var folders: [String: UUID] = [:]
            for (id, root) in roots { for folder in Self.folders(in: root) { folders[folder] = folders[folder] ?? id } }
            return folders
        }.value
        guard !Task.isCancelled else { return }
        for (path, subscription) in subscriptions where wanted[path] != subscription.place {
            Progress.removeSubscriber(subscription.token)
            subscriptions[path] = nil
        }
        let ids = Set(places.map(\.id))
        for id in running.keys where !ids.contains(id) { running[id] = nil }
        for (path, id) in wanted where subscriptions[path] == nil {
            let token = Progress.addSubscriber(forFileURL: URL(filePath: path, directoryHint: .isDirectory)) { [weak self] progress in
                let box = Box(progress: progress)
                Task { @MainActor in self?.started(box.progress, in: id) }
                return {
                    Task { @MainActor in self?.finished(box.progress, in: id) }
                }
            }
            subscriptions[path] = (id, token)
        }
        update()
    }

    /// The folder and its visible subfolders down to `depth`, breadth first.
    nonisolated private static func folders(in root: String) -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root) else { return [] }
        var result = [root]
        var level = [root]
        for _ in 0..<depth {
            var next: [String] = []
            for folder in level {
                let url = URL(filePath: folder, directoryHint: .isDirectory)
                let children = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
                for child in children {
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    guard values?.isDirectory == true, values?.isPackage != true else { continue }
                    next.append(child.path(percentEncoded: false))
                    if result.count + next.count >= folderLimit { return result + next }
                }
            }
            result += next
            level = next
        }
        return result
    }

    private func started(_ progress: Progress, in place: UUID) {
        // Only copies and moves into the folder; not downloads or reads.
        if let kind = progress.fileOperationKind, kind != .copying, kind != .duplicating, kind != .receiving {
            return
        }
        running[place, default: [:]][ObjectIdentifier(progress)] = progress
        update()
        guard ticker == nil else { return }
        // Progress is observable through KVO only; a light tick while
        // something runs is simpler and stops on its own.
        ticker = Task {
            while !Task.isCancelled, !running.values.allSatisfy(\.isEmpty) {
                update()
                try? await Task.sleep(for: .milliseconds(250))
            }
            ticker = nil
            update()
        }
    }

    private func finished(_ progress: Progress, in place: UUID) {
        running[place]?[ObjectIdentifier(progress)] = nil
        update()
    }

    private func update() {
        activities = running.compactMap { id, progresses in
            let live = progresses.values.filter { !$0.isFinished && !$0.isCancelled }
            guard !live.isEmpty else { return nil }
            let total = live.reduce(Int64(0)) { $0 + max($1.totalUnitCount, 0) }
            let done = live.reduce(Int64(0)) { $0 + max($1.completedUnitCount, 0) }
            let fraction = total > 0 ? Double(done) / Double(total) : live.map(\.fractionCompleted).reduce(0, +) / Double(live.count)
            return Activity(id: id, name: names[id] ?? "", fraction: min(max(fraction, 0), 1), files: live.count)
        }
        .sorted { $0.name < $1.name }
    }
}

/// The menu bar icon while copying: a pie that fills up, drawn as a
/// template so it follows the menu bar's color.
enum ProgressPie {
    static func image(_ fraction: Double) -> NSImage {
        // Twenty-four steps are smooth enough and keep redraws rare.
        let step = (fraction * 24).rounded() / 24
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let circle = rect.insetBy(dx: 1.5, dy: 1.5)
            let outline = NSBezierPath(ovalIn: circle)
            outline.lineWidth = 1.5
            NSColor.black.setStroke()
            outline.stroke()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: circle.width / 2 - 1.5,
                            startAngle: 90, endAngle: 90 - 360 * step, clockwise: true)
            wedge.close()
            NSColor.black.setFill()
            wedge.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
