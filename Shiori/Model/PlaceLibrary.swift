import FileProvider
import Observation
import ServiceManagement
import SwiftUI

/// The user's places, their state in the sidebar, and Shiori's settings.
@MainActor
@Observable
final class PlaceLibrary {
    private(set) var places: [Place] = []
    private(set) var states: [UUID: PlaceState] = [:]
    private(set) var roots: [UUID: String] = [:]

    /// Clicking a place in the sidebar jumps to the real folder (needs
    /// Accessibility access, and Shiori may control Finder).
    var jumpToTarget: Bool {
        didSet {
            UserDefaults.standard.set(jumpToTarget, forKey: "jumpToTarget")
            updateWatcher()
            checkSetup()
        }
    }

    private let watcher = FinderWatcher()

    /// Copies into the places' folders, for the menu bar pie.
    let copies = CopyMonitor()

    var startsAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                loginItemError = error.localizedDescription
            }
            loginItemRevision += 1
        }
    }

    private(set) var loginItemError: String?
    /// Bumped so views re-read `startsAtLogin`.
    private(set) var loginItemRevision = 0
    /// Names or glyphs changed since Finder last started.
    var finderNeedsRelaunch = false

    /// Asks the window to open on this page.
    var requestedPage: PlacesWindow.Selection?

    // MARK: Setup

    private(set) var canWatchFinder = Permissions.canWatchFinder
    private(set) var finderAutomation = Permissions.Automation.notAsked

    var placesWaitingToBeEnabled: [Place] { places.filter { state(of: $0) == .needsEnabling } }

    /// Steps the user still has to take in macOS for everything to work.
    var pendingSetupCount: Int {
        var count = placesWaitingToBeEnabled.count
        if jumpToTarget {
            if !canWatchFinder { count += 1 }
            if finderAutomation != .granted { count += 1 }
        }
        return count
    }

    private var setupMonitor: Task<Void, Never>?

    /// macOS announces none of these switches, so Shiori looks again every
    /// few seconds while something is still pending, and stops after.
    func checkSetup() {
        guard setupMonitor == nil else { return }
        setupMonitor = Task {
            repeat {
                await refreshSetup()
                if pendingSetupCount == 0 { break }
                try? await Task.sleep(for: .seconds(3))
            } while !Task.isCancelled
            setupMonitor = nil
        }
    }

    private func refreshSetup() async {
        let watching = Permissions.canWatchFinder
        if watching != canWatchFinder {
            canWatchFinder = watching
            updateWatcher()
        }
        if jumpToTarget { finderAutomation = await Permissions.finderAutomation(ask: false) }
        for place in placesWaitingToBeEnabled { await refreshStatus(of: place) }
    }

    func askToControlFinder() async {
        finderAutomation = await Permissions.finderAutomation(ask: true)
        if finderAutomation == .denied { Permissions.openAutomationSettings() }
        checkSetup()
    }

    private let storeURL = URL.applicationSupportDirectory.appending(path: "Shiori/places.json")

    init() {
        jumpToTarget = UserDefaults.standard.object(forKey: "jumpToTarget") as? Bool ?? false
        if let data = try? Data(contentsOf: storeURL), let saved = try? JSONDecoder().decode([Place].self, from: data) {
            places = saved
        }
        watcher.places = { [weak self] in
            guard let self else { return [] }
            return places.compactMap { place in roots[place.id].map { (place.id, place.name, $0, place.url) } }
        }
        watcher.resolve = { [weak self] id in
            guard let self, let place = place(withID: id) else { return nil }
            return await reachableURL(of: place)
        }
        updateWatcher()
        copies.watch(places)
        Task { await refreshAll() }
    }

    /// Starts or stops watching Finder; call again after Accessibility
    /// access was granted.
    func updateWatcher() {
        if jumpToTarget {
            watcher.start()
            watcher.attach()
        } else {
            watcher.stop()
        }
    }

    var isWatchingFinder: Bool { watcher.isRunning }

    /// A place macOS has not enabled still sits in the sidebar, and with the
    /// jump working a click goes straight past it to the real folder, so
    /// there is nothing left for the user to do.
    func state(of place: Place) -> PlaceState {
        let state = states[place.id] ?? .unknown
        return state == .needsEnabling && jumpWorks ? .ready : state
    }

    /// Clicks in the sidebar land in the real folder.
    var jumpWorks: Bool { jumpToTarget && canWatchFinder && finderAutomation == .granted }

    func place(withID id: UUID) -> Place? { places.first { $0.id == id } }

    // MARK: Editing

    /// Adds a place for a folder and puts it in the sidebar.
    @discardableResult
    func add(folder url: URL) -> Place {
        let place = Place(folder: url)
        if let existing = places.first(where: { $0.path == place.path }) { return existing }
        places.append(place)
        save()
        scheduleInstall(place)
        return place
    }

    /// Saves changes to a place and rebuilds its sidebar entry.
    func update(_ place: Place) {
        guard let index = places.firstIndex(where: { $0.id == place.id }), places[index] != place else { return }
        let old = places[index]
        places[index] = place
        save()
        if old.name != place.name || old.symbol != place.symbol || old.path != place.path {
            if states[place.id] == .ready || states[place.id] == .needsEnabling { finderNeedsRelaunch = true }
            scheduleInstall(place)
        }
    }

    func remove(_ place: Place) {
        places.removeAll { $0.id == place.id }
        states[place.id] = nil
        roots[place.id] = nil
        save()
        let pending = installs.removeValue(forKey: place.id)
        Task {
            await pending?.value
            await PlaceInstaller.uninstall(place)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        places.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: System state

    /// Installs run one after another per place, so quick edits never
    /// build the same bundle twice at once.
    private var installs: [UUID: Task<Void, Never>] = [:]

    private func scheduleInstall(_ place: Place) {
        states[place.id] = .working
        let previous = installs[place.id]
        installs[place.id] = Task {
            await previous?.value
            // A newer edit or a removal may have come in meanwhile.
            guard let current = self.place(withID: place.id) else { return }
            do {
                apply(try await PlaceInstaller.install(current), to: current)
                checkSetup()
            } catch {
                states[place.id] = .failed(error.localizedDescription)
            }
        }
    }

    func install(_ place: Place) async {
        scheduleInstall(place)
        await installs[place.id]?.value
    }

    // MARK: Network shares

    /// Why the last attempt to connect a place's share failed.
    private(set) var connectionErrors: [UUID: String] = [:]

    /// The place's folder, connecting its network share first if needed.
    func reachableURL(of place: Place) async -> URL? {
        if place.isAvailable { return place.url }
        guard let remount = place.remount else { return nil }
        do {
            let mountpoint = try await NetworkMounter.mount(remount)
            connectionErrors[place.id] = nil
            let path = place.path(onShareMountedAt: mountpoint)
            return FileManager.default.fileExists(atPath: path) ? URL(filePath: path, directoryHint: .isDirectory) : nil
        } catch {
            connectionErrors[place.id] = error.localizedDescription
            return nil
        }
    }

    /// Opens the place's folder in Finder, connecting its share if needed.
    func open(_ place: Place) {
        Task {
            if let url = await reachableURL(of: place) { FinderBridge.open(url) }
        }
    }

    /// Places added before Shiori remembered shares learn theirs while the
    /// share is mounted.
    private func rememberShares() {
        var changed = false
        for index in places.indices where places[index].remount == nil && places[index].isAvailable {
            if let remount = NetworkMounter.remount(for: places[index].url) {
                places[index].remount = remount
                changed = true
            }
        }
        if changed { save() }
    }

    func refreshAll() async {
        rememberShares()
        await PlaceInstaller.removeOrphans(keeping: places)
        defer { checkSetup() }
        for place in places where states[place.id] != .working {
            do {
                let status = try await PlaceInstaller.status(of: place)
                if status.registered {
                    apply(status, to: place)
                    await PlaceInstaller.refresh(place)
                } else {
                    await install(place)
                }
            } catch {
                await install(place)
            }
        }
    }

    func refreshStatus(of place: Place) async {
        if let status = try? await PlaceInstaller.status(of: place) { apply(status, to: place) }
    }

    private func apply(_ status: PlaceStatus, to place: Place) {
        states[place.id] = status.enabled ? .ready : (status.registered ? .needsEnabling : .unknown)
        if let root = status.rootPath { roots[place.id] = root }
    }

    /// Opens the place's sidebar entry in Finder, where macOS shows its
    /// "Enable" button the first time.
    func showSidebarEntry(of place: Place) async {
        if roots[place.id] == nil { await refreshStatus(of: place) }
        if let root = roots[place.id] {
            NSWorkspace.shared.open(URL(filePath: root, directoryHint: .isDirectory))
        }
    }

    // MARK: Storage

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(places).write(to: storeURL, options: .atomic)
        } catch {
            NSLog("Shiori: could not save places: \(error)")
        }
        copies.watch(places)
    }
}
