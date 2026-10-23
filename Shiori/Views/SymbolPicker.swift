import SwiftUI

/// A searchable grid of SF Symbols that read well at sidebar size. Any other
/// symbol can be used by typing its exact name.
struct SymbolPicker: View {
    @Binding var selection: String
    let tint: PlaceTint
    @State private var search = ""

    private static let groups: [(title: LocalizedStringResource, symbols: [String])] = [
        ("Folders & Drives", [
            "folder.fill", "folder.badge.person.crop", "tray.full.fill", "archivebox.fill", "shippingbox.fill",
            "externaldrive.fill", "externaldrive.connected.to.line.below.fill", "internaldrive.fill", "server.rack",
            "opticaldiscdrive.fill", "cloud.fill", "network", "icloud.and.arrow.down.fill", "arrow.down.circle.fill",
        ]),
        ("Media", [
            "film", "film.stack", "tv", "play.rectangle.fill", "popcorn.fill", "music.note", "music.note.list",
            "headphones", "photo.on.rectangle", "photo.stack", "camera.fill", "video.fill", "mic.fill", "gamecontroller.fill",
        ]),
        ("Work", [
            "hammer.fill", "wrench.and.screwdriver.fill", "terminal.fill", "chevron.left.forwardslash.chevron.right", "cpu",
            "briefcase.fill", "doc.text.fill", "books.vertical.fill", "book.closed.fill", "graduationcap.fill",
            "pencil.and.ruler.fill", "paintbrush.pointed.fill", "paintpalette.fill", "chart.bar.fill", "building.columns.fill",
        ]),
        ("Health", [
            "cross.case.fill", "stethoscope", "heart.text.square.fill", "waveform.path.ecg", "brain.head.profile",
            "pills.fill", "bandage.fill", "lungs.fill", "syringe.fill", "medical.thermometer.fill",
        ]),
        ("Life", [
            "house.fill", "person.fill", "person.2.fill", "figure.2.and.child.holdinghands", "heart.fill", "star.fill",
            "gift.fill", "cart.fill", "creditcard.fill", "banknote.fill", "airplane", "car.fill", "map.fill",
            "globe.europe.africa.fill", "calendar", "clock.fill",
        ]),
        ("Nature", [
            "leaf.fill", "tree.fill", "sun.max.fill", "moon.stars.fill", "snowflake", "flame.fill", "drop.fill",
            "pawprint.fill", "fish.fill", "bird.fill", "camera.macro", "mountain.2.fill",
        ]),
        ("Symbols", [
            "bookmark.fill", "tag.fill", "flag.fill", "bolt.fill", "lock.fill", "key.fill", "sparkles", "wand.and.stars",
            "lightbulb.fill", "puzzlepiece.fill", "atom", "cube.fill", "square.stack.3d.up.fill", "seal.fill",
        ]),
    ]

    private static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search symbols, or type any SF Symbol name", text: $search)
                    .lineLimit(1)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(7)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))

            if query.isEmpty {
                ForEach(Self.groups, id: \.symbols) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        grid(group.symbols)
                    }
                }
            } else {
                let matches = Self.groups.flatMap(\.symbols).filter { $0.contains(query) }
                let exact = Self.exists(query) && !matches.contains(query) ? [query] : []
                if matches.isEmpty && exact.isEmpty {
                    Text("No symbol named “\(search)”. The SF Symbols app lists every name.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    grid(exact + matches)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func grid(_ symbols: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 44), spacing: 6)], spacing: 6) {
            ForEach(symbols.filter(Self.exists), id: \.self) { symbol in
                let selected = symbol == selection
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 16))
                        .frame(width: 38, height: 34)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(selected ? AnyShapeStyle(tint.color.gradient) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                    in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(symbol)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
