import Foundation

struct Row: Identifiable {
    let id: Int  // position in the sorted list
    let cardId: Int
    let rating: CardRating?
    /// GIH WR distance from the set mean, in standard deviations.
    let z: Double?
}

@MainActor
final class DraftModel: ObservableObject {
    @Published private(set) var pack: Pack?
    @Published private(set) var rows: [Row] = []
    /// Format the ratings are for, when it differs from the draft's own.
    @Published private(set) var ratingsNote: String?
    /// The player group the shown ratings are for, when it isn't all players.
    @Published private(set) var groupLabel: String?
    /// When the most recently loaded ratings were fetched from 17Lands (kept after a draft ends).
    private(set) var ratingsUpdated: Date?
    /// Whose ratings to show; changing it redraws the current pack.
    var group = PlayerGroup(rawValue: UserDefaults.standard.string(forKey: "playerGroup") ?? "") ?? .all {
        didSet {
            guard group != oldValue else { return }
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in await self?.refresh() }
        }
    }
    /// The group the shown rows were loaded for.
    private var loadedGroup: PlayerGroup?
    @Published var hovered: Int?
    /// Set by the panel controller to fit the space beside Arena's pack grid.
    @Published var layout = PanelLayout()

    private var pending: Pack?
    private var refreshTask: Task<Void, Never>?

    func apply(_ event: DraftEvent) {
        switch event {
        case .pack(let p): pending = p
        case .pick(let pack, let pick):
            if pending?.pack == pack && pending?.pick == pick { pending = nil }
        case .draftComplete: pending = nil
        }
        // Coalesce bursts (the whole log is replayed at startup) into one refresh.
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard let target = pending else {
            pack = nil
            rows = []
            hovered = nil
            return
        }
        let group = self.group
        guard target != pack || group != loadedGroup else { return }
        var ratings: RatingSet?
        var note: String?
        if let (format, set) = target.formatAndSet {
            ratings = await RatingsStore.shared.load(set: set, format: format, group: group)
            guard !Task.isCancelled, pending == target, group == self.group else { return }
            note = ratings.flatMap { $0.format == format ? nil : "\($0.format) data" }
        }
        // The ratings table omits some cards (basic lands): look those up so they still show.
        let unrated = target.cardIds.filter { ratings?.byId[$0] == nil }
        let extras = unrated.isEmpty ? [:] : await RatingsStore.shared.lookup(ids: unrated)
        guard !Task.isCancelled, pending == target, group == self.group else { return }
        let sorted = target.cardIds
            .map { id -> (Int, CardRating?) in (id, ratings?.byId[id] ?? extras[id]) }
            .sorted { a, b in
                (a.1?.ever_drawn_win_rate ?? -1, b.1?.name ?? "") > (b.1?.ever_drawn_win_rate ?? -1, a.1?.name ?? "")
            }
        hovered = nil
        ratingsNote = note
        groupLabel = group.label
        if let updated = ratings?.updated { ratingsUpdated = updated }
        pack = target
        loadedGroup = group
        rows = sorted.enumerated().map { index, entry in
            let z = ratings.flatMap { r in entry.1?.ever_drawn_win_rate.map { ($0 - r.mean) / r.sd } }
            return Row(id: index, cardId: entry.0, rating: entry.1, z: z)
        }
    }
}
