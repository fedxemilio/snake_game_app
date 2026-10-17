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
    /// The boss's remaining lives, or nil when this run has no boss.
    @Published var bossLives: Int?
}
