# Shiori

A small menu bar app that makes the Finder sidebar yours. Pick a folder or a mounted network share, give it a **name** and an **SF Symbol icon**, and it shows up in the Finder sidebar under *Locations* as its own entry. It has no alias arrow and no generic folder glyph.

*Shiori* (栞) is Japanese for *bookmark*, the ribbon that keeps your place in a book. The UI is in English with a full Hungarian translation (String Catalogs).

## How it works

Finder draws its own glyph only for **File Provider domains**. It takes the name and icon of that sidebar entry from the **extension bundle**, not from the domain:

- name: the extension's `CFBundleDisplayName`. With more than one domain per extension, Finder writes "Extension - Domain".
- icon: the extension's `CFBundleIcons › CFBundlePrimaryIcon › CFBundleSymbolName`. Any SF Symbol name works, as does a custom symbol in the extension's asset catalog.

To give every place its own name and icon, Shiori builds **one tiny bundle per place**:

1. It copies `PlaceTemplate.app` (embedded in Shiori's resources; a background-only app plus a File Provider extension).
2. It writes the place into both Info.plists: bundle IDs `hu.lacus.shiori.place.p<uuid>`, display name, symbol, and the target path under `ShioriPlace`.
3. It signs the copy ad hoc. The extension's sandbox gets a read-only exception for exactly the place's folder.
4. It registers the copy with LaunchServices and pluginkit, then runs it once. The place app calls `NSFileProviderManager.add(_:)` for its single domain.

The generated bundles live in `~/Library/Application Support/Shiori/Places/`. Removing a place removes its domain, unregisters the bundle and deletes it. A place's folder is never touched.

**What a click does.** The domain root lists the target's top-level items as **symbolic links** (`UTType.symbolicLink` + `symlinkTargetPath`). Nothing is copied or downloaded: opening a folder in there takes Finder to the real location, opening a file opens the original.

With **"Clicking a place jumps straight to the real folder"** on (Setup page), it is smoother still:

1. Shiori watches Finder's window titles through an Accessibility observer.
2. When the front window's title is a place's name, one Apple Event asks Finder what the window shows.
3. If it is the place's root, Shiori points the window at the real folder (`set target of Finder window 1`).
4. Shiori then re-selects the place's sidebar row (`AXSelected`), which highlights it without navigating.

Result: click *Filmek* and you are in `/Volumes/Filmek`, with *Filmek* still highlighted. Back from there returns to the place's own view instead of being undone.

### Copy progress in the menu bar

Finder publishes a `Progress` for every file it copies (the pie on the file's icon). Shiori subscribes to each place's folder with `Progress.addSubscriber(forFileURL:)`. While something is being copied into a place, the menu bar icon becomes a filling pie, and the menu lists *Copying to …* per place with a progress bar. Verified with a 3 GB cross-volume copy by Finder. Copies within one APFS volume are clones and finish at once. Only items directly inside the place's folder are seen, as the API publishes per file URL or directory.

### Setup inside the app

Everything macOS must allow is a checklist on the **Setup** page. The menu bar shows *Finish Setup (n)…* while something is missing. Each step has a button to the right prompt or pane, and the status updates on its own (polled every 3 s only while something is pending):

- **Every new place:** only without the jump. A place macOS has not enabled still sits in the sidebar, and the jump goes straight past its root, so with the jump working Shiori counts the place as done (verified with *Appok*). Without the jump, *Enable in Finder* opens the place, where Finder shows its *Enable* bar.
- **Jump (optional):**
  - *Notice clicks in the sidebar*: Accessibility. On macOS 27 the pane is called *Privacy & Security › Device Control and Data Access* (Hungarian: *Eszközvezérlés és adathozzáférés*).
  - *Move the Finder window*: Automation › Finder. It is asked up front with `AEDeterminePermissionToAutomateTarget`.

## Options evaluated

| Approach | Own icon in sidebar | Own name | Real folder semantics | Verdict |
|---|---|---|---|---|
| Favorites (folder, symlink, alias) | ✗ always the generic folder/drive template glyph | ✓ (symlink keeps its name) | ✓ | What the user has today. Custom folder icons and the macOS 26 folder symbol (`com.apple.icon.folder#S`) only appear inside Finder windows. |
| `LSSharedFileList` / `sfltool` | – | – | – | The legacy favorites API crashes on this macOS, and `sfltool` has no add-item. It could only add plain favorites anyway, with the same glyph. |
| Finder Sync (`FIFinderSync`) | ✗ | ✗ | – | The SDK headers offer badges, toolbar items and contextual menus, including one for the sidebar, but **no sidebar icon or entry API**. It was also tried as the jump trigger: verified that `beginObservingDirectory(at:)` fires for a normal folder but **never for a File Provider root**, so it was dropped for an Accessibility observer. |
| One File Provider extension, many domains | ✓ but one shared glyph | ✗ "Shiori - Filmek" | depends on content | Verified: both domains showed the same glyph with the prefix. |
| **One generated File Provider bundle per place** | **✓ any SF Symbol** | **✓ exactly the chosen name** | via symlinks + jump | **Chosen.** Verified on macOS 27.2 with ad hoc signed copies. |
| Replicated mirror of the share (full pass-through) | ✓ | ✓ | ✗ | Replicated providers materialise contents in their own store: opening a 20 GB film would first copy it locally. Writes have to be re-implemented, and tools like git or Xcode in `~/Appok` would work against a copy. No read-through/streaming API exists. The macOS 27 `NSFileProviderNamespacePolicy` only controls when folders are *enumerated*, not where content lives. Rejected. |
| FSKit pass-through volume | ? volume glyph | ✓ volume name | ✓ | FSKit (macOS 15.4+) could expose a user-space pass-through file system, but mounted volumes get the generic drive glyph in the sidebar, and writing a correct pass-through FS (locking, xattrs, SMB edge cases) is a big project. Not pursued. |
| macOS 26/27 SDK sidebar API | – | – | – | None found. `FileProvider.framework` has no per-domain icon, and the new macOS 26/27 additions are search, sync controls and namespace policy. |

### Trade-offs of the chosen approach

- **One-time enable per place.** New File Provider domains start disabled. A rename or an icon change keeps the same bundle and domain ID, so the place stays enabled (verified).
- **Sidebar glyphs are monochrome.** Finder renders the symbol as a template in its own gray. The color picker tints the place in Shiori's menu and window only.
- **Finder caches names and icons.** After a rename or an icon change, the sidebar updates once Finder restarts (verified; Shiori offers the button).
- **The name comes from the bundle's file name.** Finder labels the entry with the place app's file name, not `CFBundleDisplayName`, so each bundle is `Places/<bundle id>/<Name>.app`.
- **The root is read-only.** You cannot drop files into the place root itself; with the jump you are in the real folder anyway. Without the jump, the root items carry Finder's link badge (the sidebar entry itself has none).
- **Location in the sidebar.** Places appear under *Locations*, not *Favorites*. macOS gives File Providers no way to sit in Favorites.
- **The jump is a heuristic over UI state.** It relies on window titles and Apple Events, so it can be a beat late on a slow share. Clicking a place while its real folder is already open counts as "Back" and stays put.
- **Undocumented-but-stable tooling.** Registration uses `lsregister` and `pluginkit` from the base system, and the bundles are signed ad hoc (`codesign -s -`). A generated place app is a real (background-only) app bundle, so Spotlight may list it.

### Verified on this Mac (macOS 27.2, 2026-10-23)

- A local folder (`~/Shiori-teszt`) and the UniFi SMB share `/Volumes/Filmek`. Both appear under Locations with the chosen name and glyph, no prefix, no arrow.
- After enabling, the root lists links to the real items. With the jump on, a sidebar click lands in the real folder with the row still highlighted, and Back stays on the place.
- Rename "Shiori-teszt" → "Teszt Kalapács" with `hammer`: the place stays enabled, and the new name and glyph show after a Finder restart.

## Icon

`Shiori/Resources/ShioriIcon.icon` is an Icon Composer document: three sidebar rows in washi cream on an ink background, the middle one lit, and a vermilion bookmark ribbon (栞) hanging across it. `Design/make_icon.py` draws its layers (`--preview` writes `Design/icon-preview.png`). It also covers the dark and tinted appearances (glass in tinted). `actool` derives the flat renditions and `ShioriIcon.icns` from it.

## Building

```bash
xcodegen generate
xcodebuild -project Shiori.xcodeproj -scheme Shiori -configuration Debug -derivedDataPath build -allowProvisioningUpdates build
open build/Build/Products/Debug/Shiori.app
```

Swift 6 with strict concurrency, macOS 26+. Team `YGU3DVQ6S8`, automatic signing. The app is not sandboxed: it runs `codesign`, `lsregister` and `pluginkit`, observes Finder through Accessibility and sends it Apple Events.

Targets:

- `Shiori`: SwiftUI menu bar app (places one click away, *Finish Setup*) and window (places, editor with live sidebar preview, SF Symbol picker, Setup page).
- `ShioriPlaceHost` + `ShioriFileProvider`: the per-place template. It is copied, configured and re-signed at runtime; the build itself never registers a domain. Running the template directly does nothing.

Debug-only launch arguments for checks from the shell: `-ShioriAddFolder <path>`, `-ShioriEditFirst "Name|symbol"`, `-ShioriShowSetup YES`.

Accessibility and Automation consents belong to the signed app at its path. Move it to `/Applications` before relying on it day to day.
