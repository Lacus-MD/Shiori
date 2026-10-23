import SwiftUI

/// The main window: places on the left, the selected one on the right.
struct PlacesWindow: View {
    static let id = "places"

    @Environment(PlaceLibrary.self) private var library
    @State private var selection: Selection? = nil
    @State private var confirmingRemoval: Place?

    enum Selection: Hashable {
        case place(UUID)
        case setup
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Sidebar Places") {
                    ForEach(library.places) { place in
                        HStack(spacing: 8) {
                            PlaceIcon(symbol: place.symbol, tint: place.tint, size: 22)
                            Text(place.name).lineLimit(1)
                            Spacer(minLength: 2)
                            PlaceStateBadge(state: library.state(of: place))
                        }
                        .tag(Selection.place(place.id))
                        .contextMenu {
                            Button("Open Folder") { FinderBridge.open(place.url) }
                            Button("Remove from Sidebar", role: .destructive) { confirmingRemoval = place }
                        }
                    }
                    .onMove { library.move(from: $0, to: $1) }
                }
                Section {
                    Label("Setup", systemImage: "checklist")
                        .badge(library.pendingSetupCount)
                        .tag(Selection.setup)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .dropDestination(for: URL.self) { urls, _ in
                let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                for url in folders { selection = .place(library.add(folder: url).id) }
                return !folders.isEmpty
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0) {
                    Button {
                        if let url = FolderPicker.choose() { selection = .place(library.add(folder: url).id) }
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .help("Add a folder")
                    Button {
                        if case .place(let id) = selection { confirmingRemoval = library.place(withID: id) }
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(selectedPlace == nil)
                    .help("Remove the selected place")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        } detail: {
            switch selection {
            case .place(let id):
                if let place = library.place(withID: id) {
                    PlaceEditor(saved: place)
                        .id(place.id)
                } else {
                    EmptyPlacesView(selection: $selection)
                }
            case .setup:
                SetupView()
            case nil:
                EmptyPlacesView(selection: $selection)
            }
        }
        .onAppear(perform: takeRequestedSelection)
        .onChange(of: library.requestedPage) { takeRequestedSelection() }
        .confirmationDialog(
            Text("Remove “\(confirmingRemoval?.name ?? "")” from the Finder sidebar?"),
            isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } }),
            presenting: confirmingRemoval
        ) { place in
            Button("Remove", role: .destructive) {
                library.remove(place)
                if selection == .place(place.id) { selection = nil }
            }
        } message: { _ in
            Text("The folder itself and everything in it stay where they are.")
        }
    }

    private var selectedPlace: Place? {
        if case .place(let id) = selection { library.place(withID: id) } else { nil }
    }

    private func takeRequestedSelection() {
        guard let page = library.requestedPage else {
            if selection == nil, let first = library.places.first { selection = .place(first.id) }
            return
        }
        selection = page
        library.requestedPage = nil
    }
}

/// Shown before there is anything to edit, with one-click suggestions for
/// mounted network shares.
private struct EmptyPlacesView: View {
    @Environment(PlaceLibrary.self) private var library
    @Binding var selection: PlacesWindow.Selection?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Make the Finder sidebar yours")
                .font(.title2.weight(.semibold))
            Text("Pick a folder or a network share, give it a name and an icon, and Shiori puts it in the Finder sidebar — no alias arrow, no generic folder.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button("Add Folder…") {
                if let url = FolderPicker.choose() { selection = .place(library.add(folder: url).id) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            let suggestions = NetworkShares.mounted().filter { url in
                !library.places.contains { $0.path == url.path(percentEncoded: false) }
            }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mounted network shares")
                        .font(.headline)
                    ForEach(suggestions, id: \.self) { url in
                        HStack {
                            PlaceIcon(symbol: Place.suggestedSymbol(for: url), tint: .blue, size: 24)
                            Text(FileManager.default.displayName(atPath: url.path(percentEncoded: false)))
                            Spacer()
                            Button("Add") { selection = .place(library.add(folder: url).id) }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: 360)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum NetworkShares {
    static func mounted() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { (try? $0.resourceValues(forKeys: Set(keys)).volumeIsLocal) == false }
    }
}
