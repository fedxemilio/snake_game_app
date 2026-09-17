import Combine

/// Lets ContentView (SwiftUI) react to events signaled from inside
/// GameScene (SpriteKit) via plain closures rather than anything
/// SwiftUI-aware.
final class GameSessionState: ObservableObject {
    @Published var isGameOver = false
    @Published var isLevelComplete = false
}
