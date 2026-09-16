import SwiftUI

/// Switches between the start screen and the game itself. A fresh
/// `ContentView` (and so a fresh `GameScene`) is created each time the
/// player returns to Play, matching Sea Snake's game-over/restart flow
/// being purely in-scene rather than a navigation stack.
struct RootView: View {
    @State private var isPlaying = false

    var body: some View {
        if isPlaying {
            ContentView()
        } else {
            StartView(onPlay: { isPlaying = true })
        }
    }
}

#Preview {
    RootView()
}
