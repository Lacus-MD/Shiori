import SwiftUI

/// Everything macOS has to allow, as a checklist. Each step shows whether it
/// is done and has a button that leads to the right prompt or pane; the
/// status updates on its own.
struct SetupView: View {
    @Environment(PlaceLibrary.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                if library.places.isEmpty {
                    Text("Add a place first; each one then appears here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.places) { place in
                    let waiting = library.state(of: place) == .needsEnabling
                    SetupStep(
                        done: library.state(of: place) == .ready,
                        title: Text(place.name),
                        detail: waiting ? Text("Click Enable at the top of the Finder window that opens.") : nil
                    ) {
                        if waiting {
                            Button("Enable in Finder") { Task { await library.showSidebarEntry(of: place) } }
                        }
                    }
                }
            } header: {
                Text("Places in the Sidebar")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("macOS asks once for every new place. The same switches are in System Settings › General › Login Items & Extensions.")
                    Spacer()
                    Button("Open System Settings") { Permissions.openFileProviderSettings() }
                        .controlSize(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Clicking a place jumps straight to the real folder", isOn: $library.jumpToTarget)
                if library.jumpToTarget {
                    SetupStep(
                        done: library.canWatchFinder,
                        title: Text("Notice clicks in the sidebar"),
                        detail: library.canWatchFinder ? nil : Text("Turn on Shiori under Privacy & Security › Device Control and Data Access.")
                    ) {
                        Button("Allow…") { Permissions.requestFinderWatching() }
                    }
                    SetupStep(
                        done: library.finderAutomation == .granted,
                        title: Text("Move the Finder window"),
                        detail: library.finderAutomation == .denied
                            ? Text("Turned off. Turn on Finder under Shiori in Privacy & Security › Automation.") : nil
                    ) {
                        if library.finderAutomation == .denied {
                            Button("Open System Settings") { Permissions.openAutomationSettings() }
                        } else {
                            Button("Allow…") { Task { await library.askToControlFinder() } }
                        }
                    }
                }
            } header: {
                Text("Sidebar Clicks")
            } footer: {
                Text("Optional. The Finder window moves on to the real folder or share, so you work there as usual. Without it, a place shows the folder’s items as links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open Shiori at login", isOn: Binding(
                    get: { _ = library.loginItemRevision; return library.startsAtLogin },
                    set: { library.startsAtLogin = $0 }))
                if let error = library.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restart Finder")
                        Text("Finder shows new names and icons after it starts again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restart") {
                        FinderBridge.relaunch()
                        library.finderNeedsRelaunch = false
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("The places stay in the sidebar while Shiori is closed. It only needs to run to change them and for the jump.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .onAppear { library.checkSetup() }
    }
}

private struct SetupStep<Actions: View>: View {
    let done: Bool
    let title: Text
    let detail: Text?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                title
                if let detail {
                    detail.font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !done { actions() }
        }
        .animation(.snappy, value: done)
    }
}
