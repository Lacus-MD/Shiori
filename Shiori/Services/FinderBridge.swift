import AppKit

/// The few things Shiori asks of Finder itself.
@MainActor
enum FinderBridge {
    /// Points the frontmost Finder window at `url`. The first time, macOS asks
    /// the user to let Shiori control Finder.
    static func retargetFrontWindow(to url: URL) {
        let path = url.path(percentEncoded: false)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                set target of Finder window 1 to (POSIX file "\(path)" as alias)
            else
                open (POSIX file "\(path)" as alias)
            end if
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { open(url) }
    }

    /// The folder the frontmost Finder window shows.
    static func frontWindowPath() -> String? {
        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            return POSIX path of (target of Finder window 1 as alias)
        end tell
        """
        var error: NSDictionary?
        let path = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        return path?.isEmpty == false ? path : nil
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Finder keeps sidebar names and glyphs until it starts again.
    static func relaunch() {
        // launchd starts Finder again on its own, like `killall Finder`.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").forEach { $0.forceTerminate() }
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty else { return }
            if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: finder, configuration: configuration)
            }
        }
    }
}
