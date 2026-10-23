import SwiftUI

@main
struct ShioriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(delegate.library)
        } label: {
            MenuBarLabel()
                .environment(delegate.library)
        }
        .menuBarExtraStyle(.window)

        Window("Shiori", id: PlacesWindow.id) {
            PlacesWindow()
                .environment(delegate.library)
        }
        .defaultSize(width: 860, height: 620)
        .windowToolbarStyle(.unified)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = PlaceLibrary()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // For checks from the shell: `-ShioriAddFolder <path>` adds a place,
        // `-ShioriEditFirst "Name|symbol"` changes the first one,
        // `-ShioriShowSetup YES` opens the setup page.
        if let path = UserDefaults.standard.string(forKey: "ShioriAddFolder") {
            library.requestedPage = .place(library.add(folder: URL(filePath: path, directoryHint: .isDirectory)).id)
        }
        if let edit = UserDefaults.standard.string(forKey: "ShioriEditFirst")?.split(separator: "|"), edit.count == 2,
           var place = library.places.first {
            place.name = String(edit[0])
            place.symbol = String(edit[1])
            library.update(place)
        }
        if UserDefaults.standard.bool(forKey: "ShioriShowSetup") {
            library.requestedPage = .setup
        }
        #endif
    }
}

/// Always alive while Shiori runs, so it can open the window when something
/// asks to show a place.
private struct MenuBarLabel: View {
    @Environment(PlaceLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "bookmark.fill")
            .onChange(of: library.requestedPage) { _, page in
                guard page != nil else { return }
                openWindow(id: PlacesWindow.id)
                NSApp.activate()
            }
    }
}
