import AppKit
import Observation

/// Follows copies into the places' folders. Finder publishes a Progress for
/// every file it copies (the same one that draws the pie on the file's
/// icon); Shiori subscribes to each place's folder and adds them up.
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

    private var subscriptions: [UUID: (path: String, token: Any)] = [:]
    private var running: [UUID: [ObjectIdentifier: Progress]] = [:]
    private var names: [UUID: String] = [:]
    private var ticker: Task<Void, Never>?

    /// Subscribes to new places' folders and drops removed ones.
    func watch(_ places: [Place]) {
        let wanted = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        for (id, subscription) in subscriptions where wanted[id]?.path != subscription.path {
            Progress.removeSubscriber(subscription.token)
            subscriptions[id] = nil
            running[id] = nil
        }
        for place in places {
            names[place.id] = place.name
            guard subscriptions[place.id] == nil else { continue }
            let id = place.id
            let token = Progress.addSubscriber(forFileURL: place.url) { [weak self] progress in
                let box = Box(progress: progress)
                Task { @MainActor in self?.started(box.progress, in: id) }
                return {
                    Task { @MainActor in self?.finished(box.progress, in: id) }
                }
            }
            subscriptions[place.id] = (place.path, token)
        }
        update()
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
