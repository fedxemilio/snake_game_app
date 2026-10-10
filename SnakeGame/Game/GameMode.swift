/// CaseIterable so the start screen's toggle can cycle through modes
/// without needing to know how many exist or their order.
enum GameMode: CaseIterable, Equatable {
    case freePlay
    case levels
    case adventure

    var title: String {
        switch self {
        case .freePlay: return "Free Play"
        case .levels: return "Levels"
        case .adventure: return "Adventure"
        }
    }

    /// One line under the title on the start screen.
    var tagline: String {
        switch self {
        case .freePlay: return "Open water, no end"
        case .levels: return "Three walled reefs to clear"
        case .adventure: return "A sea wider than the screen"
        }
    }

    var next: GameMode {
        let all = GameMode.allCases
        let index = (all.firstIndex(of: self)! + 1) % all.count
        return all[index]
    }
}
