import SwiftUI

/// Switches between the start screen and the game itself. A fresh
/// `ContentView` (and so a fresh `GameScene` and `GameSessionState`) is
/// created each time the player returns to Play, so every run starts clean.
/// `mode` (and zen mode) live here rather than in either child, since they're
/// chosen on the start screen but consumed by the game.
struct RootView: View {
    @State private var isPlaying = false
    @State private var mode: GameMode = .freePlay
    /// Zen mode, for testing (the toggle only shows in Debug builds). Remembered
    /// between launches, so it stays on while you test.
    @AppStorage("isZenMode") private var isZen = false

    var body: some View {
        if isPlaying {
            ContentView(mode: mode, isZen: isZen, onExitToHome: { isPlaying = false })
        } else {
            StartView(mode: $mode, isZen: $isZen, onPlay: { isPlaying = true })
        }
    }
}

#Preview {
    RootView()
}
