/// CaseIterable so the start screen's toggle can cycle through modes
/// without needing to know how many exist or their order.
enum GameMode: CaseIterable, Equatable {
    case freePlay
    case levels
    case adventure

    var label: String {
        switch self {
        case .freePlay: return "mode: free-play"
        case .levels: return "mode: levels"
        case .adventure: return "mode: adventure"
        }
    }

    var next: GameMode {
        let all = GameMode.allCases
        let index = (all.firstIndex(of: self)! + 1) % all.count
        return all[index]
    }
}
