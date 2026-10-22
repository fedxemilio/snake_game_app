import Combine

/// Lets ContentView (SwiftUI) react to events signaled from inside
/// GameScene (SpriteKit) via plain closures rather than anything
/// SwiftUI-aware.
final class GameSessionState: ObservableObject {
    @Published var isGameOver = false
    @Published var isLevelComplete = false
    @Published var score = 0
    /// The snake's remaining lives, or nil in modes where it only has one.
    @Published var lives: Int?
    /// Mine fruit progress and mines ready to drop, or nil in modes without mine
    /// fruit.
    @Published var mineSupply: GameManager.MineSupply?
    /// The boss's name and lives, or nil when this run has no boss.
    @Published var boss: GameManager.BossStatus?
    /// Adventure: the stage just cleared, while its victory screen shows.
    @Published var clearedStage: Int?
    /// Adventure: the leg of the ascent the voyage chart is showing, while it shows.
    @Published var voyage: Voyage?
}
