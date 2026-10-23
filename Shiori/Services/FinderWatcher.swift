import AppKit
import ApplicationServices

/// Makes a click on a place in the Finder sidebar land in the real folder.
///
/// Finder tells nobody when it shows a File Provider folder (Finder Sync
/// extensions get no callbacks there), so Shiori watches Finder's window
/// titles through Accessibility. When the front window's title is a place's
/// name, one Apple Event asks Finder what the window shows; if it is the
/// place's sidebar folder, the window moves on to the real one.
@MainActor
final class FinderWatcher {
    /// The sidebar folder (File Provider root) and real folder of each place.
    var places: () -> [(name: String, root: String, target: URL)] = { [] }

    private var observer: AXObserver?
    private var finderPID: pid_t = 0
    private var pending: Task<Void, Never>?
    private var launchObservation: (any NSObjectProtocol)?
    /// What the front window showed when Shiori last looked, and the places
    /// the user went back to from their real folder (Back must not be undone).
    private var lastShown: String?
    private var wentBack: Set<String> = []
    /// The real folder Shiori just sent a window to, and the place to
    /// highlight in the sidebar once it is there.
    private var arriving: (target: String, name: String)?

    var isRunning: Bool { observer != nil }

    func start() {
        guard launchObservation == nil else { return }
        // Finder gets a new process whenever it restarts.
        launchObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.finder" else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
        attach()
    }

    func stop() {
        if let launchObservation { NSWorkspace.shared.notificationCenter.removeObserver(launchObservation) }
        launchObservation = nil
        detach()
    }

    /// Call again once Accessibility access was granted.
    func attach() {
        guard launchObservation != nil, Permissions.canWatchFinder,
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return }
        if observer != nil, finder.processIdentifier == finderPID { return }
        detach()
        finderPID = finder.processIdentifier

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FinderWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.windowChanged() }
        }
        guard AXObserverCreate(finderPID, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(finderPID)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXTitleChangedNotification, kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
            AXObserverAddNotification(created, app, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        finderPID = 0
    }

    private func windowChanged() {
        // Titles change in bursts while Finder navigates; look once it settles.
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            jumpIfNeeded()
        }
    }

    private func jumpIfNeeded() {
        let places = places()
        // Ask Finder for the folder only when the title could be a place or
        // its real folder; every other window is none of Shiori's business.
        let titles = Set(places.flatMap { [$0.name, FileManager.default.displayName(atPath: $0.target.path(percentEncoded: false))] })
        guard let title = frontWindowTitle(), titles.contains(title), let path = FinderBridge.frontWindowPath() else {
            lastShown = nil
            wentBack.removeAll()
            return
        }
        let shown = Self.normalized(path)
        guard let place = places.first(where: { Self.normalized($0.root) == shown }) else {
            wentBack.removeAll()
            lastShown = shown
            if let arriving, arriving.target == shown {
                selectSidebarRow(named: arriving.name)
                self.arriving = nil
            }
            return
        }
        let target = Self.normalized(place.target.path(percentEncoded: false))
        if wentBack.contains(shown) { return }
        if lastShown == target {
            // From the real folder to its place: that was Back.
            wentBack.insert(shown)
            lastShown = shown
            return
        }
        FinderBridge.retargetFrontWindow(to: place.target)
        lastShown = target
        // Finder drops the sidebar highlight when the window leaves the
        // place's own folder; put it back once the window has arrived (its
        // title changes then). A place named like its folder keeps the same
        // title, so try after a moment as well.
        arriving = (target, place.name)
        Task {
            for delay in [400, 1000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let arriving, arriving.target == target else { return }
                selectSidebarRow(named: arriving.name)
            }
            if arriving?.target == target { arriving = nil }
        }
    }

    /// Highlights a place in the front window's sidebar without navigating.
    /// Sections are the outline's level-0 rows; when a favorite has the same
    /// name, the later section (Locations) wins.
    private func selectSidebarRow(named name: String) {
        guard let window = focusedWindow(), let outline = Self.first(in: window, role: kAXOutlineRole) else { return }
        var section = -1
        var matches: [(section: Int, row: AXUIElement)] = []
        for row in Self.value(outline, kAXRowsAttribute) as? [AXUIElement] ?? [] {
            let level = Self.value(row, kAXDisclosureLevelAttribute) as? Int ?? 1
            if level == 0 { section += 1; continue }
            if Self.rowText(row) == name { matches.append((section, row)) }
        }
        let row = matches.count > 1 ? matches.first { $0.section > 0 }?.row : matches.first?.row
        if let row { AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) }
    }

    private static func rowText(_ row: AXUIElement) -> String? {
        let cells = value(row, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for cell in cells {
            for child in value(cell, kAXChildrenAttribute) as? [AXUIElement] ?? []
            where value(child, kAXRoleAttribute) as? String == kAXStaticTextRole {
                return value(child, kAXValueAttribute) as? String
            }
        }
        return nil
    }

    private static func first(in element: AXUIElement, role: String, depth: Int = 0) -> AXUIElement? {
        if value(element, kAXRoleAttribute) as? String == role { return element }
        guard depth < 8 else { return nil }
        for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let found = first(in: child, role: role, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private func focusedWindow() -> AXUIElement? {
        guard let window = Self.value(AXUIElementCreateApplication(finderPID), kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }

    private func frontWindowTitle() -> String? {
        focusedWindow().flatMap { Self.value($0, kAXTitleAttribute) as? String }
    }

    static func normalized(_ path: String) -> String {
        var path = (path as NSString).standardizingPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
