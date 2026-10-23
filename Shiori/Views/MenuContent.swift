import SwiftUI

/// The menu bar window: every place one click away, plus the way in.
struct MenuContent: View {
    @Environment(PlaceLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Shiori")
                    .font(.headline)
                Spacer()
                Button {
                    showWindow()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Open Shiori")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if library.places.isEmpty {
                Text("Add a folder or a network share, give it a name and an icon, and it appears in the Finder sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(library.places) { place in
                        MenuPlaceRow(place: place, state: library.state(of: place))
                    }
                }
                .padding(.horizontal, 6)
            }

            Divider().padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 2) {
                if library.pendingSetupCount > 0 {
                    MenuActionRow(title: "Finish Setup (\(library.pendingSetupCount))…", symbol: "checklist", tint: .orange) {
                        library.requestedPage = .setup
                    }
                }
                MenuActionRow(title: "Add Folder…", symbol: "plus") {
                    if let url = FolderPicker.choose() {
                        library.requestedPage = .place(library.add(folder: url).id)
                    }
                }
                if library.finderNeedsRelaunch {
                    MenuActionRow(title: "Restart Finder to Show Changes", symbol: "arrow.clockwise") {
                        FinderBridge.relaunch()
                        library.finderNeedsRelaunch = false
                    }
                }
                MenuActionRow(title: "Edit Places…", symbol: "slider.horizontal.3") { showWindow() }
                MenuActionRow(title: "Quit Shiori", symbol: "power") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 300)
    }

    private func showWindow() {
        openWindow(id: PlacesWindow.id)
        NSApp.activate()
    }
}

private struct MenuPlaceRow: View {
    let place: Place
    let state: PlaceState
    @State private var hovering = false

    var body: some View {
        Button {
            FinderBridge.open(place.url)
        } label: {
            HStack(spacing: 10) {
                PlaceIcon(symbol: place.symbol, tint: place.tint, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name)
                        .lineLimit(1)
                    Text(place.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                PlaceStateBadge(state: state)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(place.path)
    }
}

private struct MenuActionRow: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(tint ?? .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(.rect)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
