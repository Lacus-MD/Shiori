import SwiftUI

/// Name, folder, icon and tint of one place, with a live preview of the
/// Finder sidebar. Changes go to Finder when saved, since each save rebuilds
/// the place's sidebar entry.
struct PlaceEditor: View {
    @Environment(PlaceLibrary.self) private var library
    let saved: Place
    @State private var draft: Place

    init(saved: Place) {
        self.saved = saved
        _draft = State(initialValue: saved)
    }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool { draft != saved }

    var body: some View {
        Form {
            Section {
                SidebarPreview(place: draft)
            }

            Section("Name") {
                TextField("Name", text: $draft.name, prompt: Text("Name in the sidebar"))
                    .labelsHidden()
                    .onSubmit(save)
            }

            Section("Folder") {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: draft.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FileManager.default.displayName(atPath: draft.path))
                        Text(draft.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose…") {
                        if let url = FolderPicker.choose(startingAt: draft.url.deletingLastPathComponent()) {
                            draft.path = url.path(percentEncoded: false)
                        }
                    }
                }
                if !FileManager.default.fileExists(atPath: draft.path) {
                    Label("Not available right now. If it is a network share, connect to it first.", systemImage: "wifi.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                SymbolPicker(selection: $draft.symbol, tint: draft.tint)
            } header: {
                Text("Icon")
            }

            Section {
                TintPicker(selection: $draft.tint)
            } header: {
                Text("Color")
            } footer: {
                Text("Used in Shiori’s menu. Finder draws every sidebar icon in its own gray.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In Finder") {
                PlaceStatusView(place: saved)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(saved.name)
        .navigationSubtitle(saved.path)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Revert") { draft = saved }
                    .disabled(!hasChanges)
                Button("Save to Sidebar", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges || trimmedName.isEmpty)
                    .keyboardShortcut("s")
            }
        }
    }

    private func save() {
        guard hasChanges, !trimmedName.isEmpty else { return }
        draft.name = trimmedName
        library.update(draft)
    }
}

/// Where the place stands in Finder, and what to do about it.
private struct PlaceStatusView: View {
    @Environment(PlaceLibrary.self) private var library
    let place: Place

    var body: some View {
        let state = library.state(of: place)
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .ready:
                Label("In the Finder sidebar under Locations.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .needsEnabling:
                Label("In the sidebar and waiting for you. macOS asks once for every new place.", systemImage: "hand.tap.fill")
                    .foregroundStyle(.orange)
            case .working:
                Label("Updating the sidebar…", systemImage: "hourglass")
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            case .unknown:
                Label("Not in the sidebar yet.", systemImage: "circle.dashed")
            }
            HStack {
                if state == .needsEnabling {
                    Button("Enable in Finder") { Task { await library.showSidebarEntry(of: place) } }
                        .buttonStyle(.borderedProminent)
                } else if state == .ready {
                    Button("Show in Finder") { Task { await library.showSidebarEntry(of: place) } }
                }
                Button("Open Folder") { FinderBridge.open(place.url) }
                if case .failed = state {
                    Button("Try Again") { Task { await library.install(place) } }
                }
                if library.finderNeedsRelaunch {
                    Button("Restart Finder") {
                        FinderBridge.relaunch()
                        library.finderNeedsRelaunch = false
                    }
                    .help("Finder shows new names and icons after it starts again.")
                }
                Spacer()
                Button {
                    Task { await library.refreshStatus(of: place) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Check again")
            }
        }
    }
}

private struct TintPicker: View {
    @Binding var selection: PlaceTint

    var body: some View {
        HStack(spacing: 10) {
            ForEach(PlaceTint.allCases, id: \.self) { tint in
                Button {
                    selection = tint
                } label: {
                    Circle()
                        .fill(tint.color.gradient)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if tint == selection {
                                Circle().strokeBorder(.background, lineWidth: 2).padding(2)
                            }
                        }
                        .overlay { Circle().strokeBorder(tint == selection ? tint.color : .clear, lineWidth: 2).padding(-3) }
                }
                .buttonStyle(.plain)
                .help(Text(tint.title))
                .accessibilityLabel(Text(tint.title))
            }
        }
        .padding(.vertical, 4)
    }
}
