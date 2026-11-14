import SwiftUI

/// The panel size chosen in the menu.
enum PanelSize: String, CaseIterable {
    case small, full

    var title: String { self == .small ? "80%" : "100%" }
    var scale: CGFloat { self == .small ? 0.8 : 1 }
}

/// Panel metrics: one layout, uniformly scaled. Shared with the panel controller (sizing,
/// hover hit-testing).
struct PanelLayout: Equatable {
    var scale: CGFloat = 1

    var width: CGFloat { (300 * scale).rounded() }
    var header: CGFloat { (34 * scale).rounded() }
    var row: CGFloat { (44 * scale).rounded() }
    var padding: CGFloat { (6 * scale).rounded() }

    func height(rows: Int) -> CGFloat { header + CGFloat(rows) * row + padding }
}

struct PanelView: View {
    @ObservedObject var model: DraftModel

    var body: some View {
        let layout = model.layout
        VStack(spacing: 0) {
            header.frame(height: layout.header)
            ForEach(model.rows) { row in
                RowView(row: row, layout: layout, hovered: model.hovered == row.id)
                    .frame(height: layout.row)
            }
            Spacer(minLength: 0)
        }
        .frame(width: layout.width)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let pack = model.pack {
                Text("Pack \(pack.pack) · Pick \(pack.pick)").fontWeight(.semibold)
                if let note = model.ratingsNote {
                    Text(note).foregroundStyle(.orange).lineLimit(1)
                }
                Spacer()
                if let mean = model.setMean {
                    Text([model.groupLabel, "avg \(percent(mean))"].compactMap { $0 }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                Text("GIH WR").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11 * model.layout.scale))
        .lineLimit(1)
        .padding(.horizontal, 10 * model.layout.scale)
    }
}

private struct RowView: View {
    let row: Row
    let layout: PanelLayout
    let hovered: Bool

    var body: some View {
        let scale = layout.scale
        HStack(spacing: 8 * scale) {
            Rectangle().fill(rarityColor).frame(width: 3)
            Thumbnail(url: row.rating?.url)
                .frame(width: (52 * scale).rounded(), height: (38 * scale).rounded())
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(row.rating?.name ?? "Card \(row.cardId)")
                    .font(.system(size: 12.5 * scale, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4 * scale) {
                    ForEach(Array(row.rating?.color ?? ""), id: \.self) { pip in
                        Circle().fill(pipColor(pip)).frame(width: 8 * scale, height: 8 * scale)
                            .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 0.5))
                    }
                    Text(typeLine).font(.system(size: 10 * scale)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            Text(row.rating?.ever_drawn_win_rate.map(percent) ?? "–")
                .font(.system(size: 15 * scale, weight: .bold).monospacedDigit())
                .foregroundStyle(gradeColor)
                .fixedSize()
                .padding(.trailing, 10 * scale)
        }
        .background(hovered ? Color.white.opacity(0.08) : .clear)
    }

    private var typeLine: String {
        guard let type = row.rating?.types?.first else { return "" }
        return type.components(separatedBy: " - ").first ?? type
    }

    private var rarityColor: Color {
        switch row.rating?.rarity {
        case "mythic": return Color(red: 0.93, green: 0.42, blue: 0.16)
        case "rare": return Color(red: 0.85, green: 0.70, blue: 0.32)
        case "uncommon": return Color(red: 0.62, green: 0.72, blue: 0.80)
        default: return Color.white.opacity(0.18)
        }
    }

    /// Tint by distance from the set's mean GIH WR.
    private var gradeColor: Color {
        guard let z = row.z else { return .secondary }
        if z >= 1.25 { return Color(red: 0.35, green: 0.90, blue: 0.50) }
        if z >= 0.4 { return Color(red: 0.62, green: 0.86, blue: 0.56) }
        if z >= -0.4 { return Color.white.opacity(0.9) }
        if z >= -1.25 { return Color(red: 0.95, green: 0.70, blue: 0.45) }
        return Color(red: 0.95, green: 0.45, blue: 0.42)
    }

    private func pipColor(_ pip: Character) -> Color {
        switch pip {
        case "W": return Color(red: 0.97, green: 0.94, blue: 0.80)
        case "U": return Color(red: 0.25, green: 0.56, blue: 0.90)
        case "B": return Color(red: 0.42, green: 0.36, blue: 0.46)
        case "R": return Color(red: 0.88, green: 0.30, blue: 0.24)
        case "G": return Color(red: 0.25, green: 0.66, blue: 0.38)
        default: return .gray
        }
    }
}

private struct Thumbnail: View {
    let url: String?
    @State private var art: CGImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let art {
                Image(decorative: art, scale: 1).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .task(id: url) {
            art = nil
            if let url { art = await CardImages.shared.load(url)?.art }
        }
    }
}

func percent(_ rate: Double) -> String { String(format: "%.1f%%", rate * 100) }
