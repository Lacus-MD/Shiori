import SwiftUI

/// A place's glyph on a soft tinted tile.
struct PlaceIcon: View {
    let symbol: String
    let tint: PlaceTint
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.color.gradient, in: .rect(cornerRadius: size * 0.28))
    }
}

struct PlaceStateBadge: View {
    let state: PlaceState

    var body: some View {
        switch state {
        case .working:
            ProgressView().controlSize(.small)
        case .needsEnabling:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .help("Waiting to be enabled in Finder")
        case .failed(let message):
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(message)
        case .ready, .unknown:
            EmptyView()
        }
    }
}

@MainActor
enum FolderPicker {
    static func choose(startingAt directory: URL? = nil) -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose a folder or a mounted network share for the Finder sidebar.")
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
}
