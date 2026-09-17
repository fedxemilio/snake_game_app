import SwiftUI
import SpriteKit

struct ContentView: View {
    let onExitToHome: () -> Void

    @StateObject private var session = GameSessionState()
    private let scene: GameScene

    init(mode: GameMode, onExitToHome: @escaping () -> Void) {
        self.onExitToHome = onExitToHome
        let scene = GameScene(mode: mode)
        scene.scaleMode = .resizeFill
        self.scene = scene
    }

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

            if session.isLevelComplete {
                LevelCompleteOverlay(
                    onContinue: {
                        session.isLevelComplete = false
                        scene.beginNextLevel()
                    }
                )
            }
        }
        .onAppear {
            scene.onGameOver = {
                session.isGameOver = true
            }
            scene.onLevelComplete = {
                session.isLevelComplete = true
            }
        }
    }
}

#Preview {
    ContentView(mode: .freePlay, onExitToHome: {})
}
