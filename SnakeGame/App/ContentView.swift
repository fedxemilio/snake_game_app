import SwiftUI
import SpriteKit

struct ContentView: View {
    let onExitToHome: () -> Void

    @StateObject private var session = GameSessionState()
    /// False for the first moments on screen: the game opens on the black the
    /// menu's dive ended on, which then clears to reveal the board.
    @State private var hasArrived = false
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

            ScoreHUD(score: session.score)
                // Up in the corner beside the Dynamic Island, clear of the board.
                .padding(.leading, 16)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                // Game over shows the score itself, big.
                .opacity(session.isGameOver ? 0 : 1)

            if session.isGameOver {
                GameOverOverlay(
                    score: session.score,
                    onPlayAgain: {
                        session.isGameOver = false
                        scene.startNewGame()
                    },
                    onGoHome: onExitToHome
                )
                .transition(.opacity)
            }

            if session.isLevelComplete {
                LevelCompleteOverlay(
                    onContinue: {
                        session.isLevelComplete = false
                        scene.beginNextLevel()
                    }
                )
                .transition(.opacity)
            }

            Color("Abyss")
                .ignoresSafeArea()
                .opacity(hasArrived ? 0 : 1)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.4), value: session.isGameOver)
        .animation(.easeInOut(duration: 0.3), value: session.isLevelComplete)
        .onAppear {
            scene.onScoreChanged = { score in
                session.score = score
            }
            scene.onGameOver = {
                session.isGameOver = true
            }
            scene.onLevelComplete = {
                session.isLevelComplete = true
            }
            withAnimation(.easeOut(duration: 0.7)) {
                hasArrived = true
            }
        }
    }
}

/// The running score, in a pill matching the start menu's mode picker.
private struct ScoreHUD: View {
    let score: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("SCORE")
                .font(.custom("Work Sans", size: 11).weight(.semibold))
                .tracking(2)
                .foregroundStyle(Color("Foam").opacity(0.6))

            Text("\(score)")
                .font(.custom("Cinzel", size: 22).weight(.semibold))
                .foregroundStyle(Color("Foam"))
                .shadow(color: Color("Foam").opacity(0.45), radius: 8)
                .contentTransition(.numericText(value: Double(score)))
                .animation(.spring(duration: 0.3), value: score)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color("Abyss").opacity(0.6))
                .overlay(Capsule().strokeBorder(Color("BoardBorder"), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView(mode: .freePlay, onExitToHome: {})
}
