import SwiftUI

/// Switches between the start screen and the game itself. A fresh
/// `ContentView` (and so a fresh `GameScene` and `GameSessionState`) is
/// created each time the player returns to Play, so every run starts clean.
struct RootView: View {
    @State private var isPlaying = false

    var body: some View {
        if isPlaying {
            ContentView(onExitToHome: { isPlaying = false })
        } else {
            StartView(onPlay: { isPlaying = true })
        }
    }
}

#Preview {
    RootView()
}
