import Combine

/// Lets ContentView (SwiftUI) react to game-over, which is signaled from
/// inside GameScene (SpriteKit) via a plain closure rather than anything
/// SwiftUI-aware.
final class GameSessionState: ObservableObject {
    @Published var isGameOver = false
}
