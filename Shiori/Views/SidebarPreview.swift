import SwiftUI

/// A small likeness of the Finder sidebar, in light and dark, showing the
/// place the way Finder will.
struct SidebarPreview: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                mock.environment(\.colorScheme, .light)
                mock.environment(\.colorScheme, .dark)
            }
            Text("This is how Finder shows it: your name and icon under Locations, without an alias arrow.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var mock: some View {
        MockSidebar(place: place)
    }
}

private struct MockSidebar: View {
    let place: Place
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Locations")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
            row(symbol: "icloud", name: String(localized: "iCloud Drive"), selected: false)
            row(symbol: place.symbol, name: place.name.isEmpty ? " " : place.name, selected: true)
            row(symbol: "network", name: String(localized: "Network"), selected: false)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.95), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .animation(.snappy, value: place.symbol)
    }

    private func row(symbol: String, name: String, selected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(scheme == .dark ? Color(white: 0.62) : Color(white: 0.42))
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.primary.opacity(scheme == .dark ? 0.14 : 0.08) : .clear, in: .rect(cornerRadius: 7))
    }
}
