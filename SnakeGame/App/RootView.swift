import SwiftUI

/// Switches between the start screen and the game itself. A fresh
/// `ContentView` (and so a fresh `GameScene` and `GameSessionState`) is
/// created each time the player returns to Play, so every run starts clean.
/// `mode` lives here rather than in either child, since it's chosen on the
/// start screen but consumed by the game.
struct RootView: View {
    @State private var isPlaying = false
    @State private var mode: GameMode = .freePlay

    var body: some View {
        if isPlaying {
            ContentView(mode: mode, onExitToHome: { isPlaying = false })
        } else {
            StartView(mode: $mode, onPlay: { isPlaying = true })
        }
    }
}

#Preview {
    RootView()
}
