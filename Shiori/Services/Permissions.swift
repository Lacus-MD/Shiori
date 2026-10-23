import AppKit
import ApplicationServices

/// The macOS consents Shiori's optional jump needs, and the File Provider
/// switch every place needs once. Each one has a button that leads straight
/// to the right prompt or pane.
enum Permissions {
    // MARK: Accessibility — noticing sidebar clicks

    static var canWatchFinder: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt, which lists Shiori in Privacy & Security and
    /// offers to open it, and opens the pane as well.
    @MainActor
    static func requestFinderWatching() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacyPane("Privacy_Accessibility")
    }

    // MARK: Automation — moving the Finder window

    enum Automation: Sendable {
        case granted, notAsked, denied
    }

    /// With `ask`, macOS shows its "Shiori wants to control Finder" prompt if
    /// the user has not answered yet. Blocks while the prompt is up, so it
    /// runs off the main thread.
    static func finderAutomation(ask: Bool) async -> Automation {
        await Task.detached {
            if ask, NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty {
                return .notAsked
            }
            var target = AEAddressDesc()
            let bundleID = "com.apple.finder"
            let created = bundleID.withCString { AECreateDesc(typeApplicationBundleID, $0, bundleID.utf8.count, &target) }
            guard created == noErr else { return .notAsked }
            defer { AEDisposeDesc(&target) }
            switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask) {
            case noErr: return .granted
            case OSStatus(errAEEventNotPermitted): return .denied
            default: return .notAsked
            }
        }.value
    }

    @MainActor
    static func openAutomationSettings() {
        openPrivacyPane("Privacy_Automation")
    }

    // MARK: File Provider — one switch per place

    /// Login Items & Extensions, where every place is listed under File
    /// Providers (macOS 26 and later).
    @MainActor
    static func openFileProviderSettings() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    @MainActor
    private static func openPrivacyPane(_ anchor: String) {
        open("x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    @MainActor
    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
