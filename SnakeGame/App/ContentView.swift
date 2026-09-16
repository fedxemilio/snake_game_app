import SwiftUI
import SpriteKit

struct ContentView: View {
    let onExitToHome: () -> Void

    @StateObject private var session = GameSessionState()
    private let scene: GameScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .statusBarHidden()

            if session.isGameOver {
                GameOverOverlay(
                    onPlayAgain: {
                        session.isGameOver = false
                        scene.startNewGame()
                    },
                    onGoHome: onExitToHome
                )
            }
        }
        .onAppear {
            scene.onGameOver = {
                session.isGameOver = true
            }
        }
    }
}

#Preview {
    ContentView(onExitToHome: {})
}
