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

            VStack(alignment: .leading, spacing: 6) {
                ScoreHUD(score: session.score)
                if let lives = session.lives {
                    LivesHUD(lives: lives)
                }
            }
            // Up in the corner beside the Dynamic Island, clear of the board.
            .padding(.leading, 16)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // Game over shows the score itself, big.
            .opacity(session.isGameOver ? 0 : 1)

            if let lives = session.bossLives {
                BossHUD(lives: lives)
                    // The other top corner, mirroring the score.
                    .padding(.trailing, 16)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(session.isGameOver ? 0 : 1)
            }

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
            scene.onBossLivesChanged = { lives in
                session.bossLives = lives
            }
            scene.onLivesChanged = { lives in
                session.lives = lives
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

/// The snake's lives as glowing teal hearts (teal for the snake, against the
/// kraken's red pips), in a small pill under the score: beside it, the pill would
/// run under the Dynamic Island.
private struct LivesHUD: View {
    let lives: Int

    /// Hearts drawn: the most the snake has had this run, so lost ones stay
    /// visible as empty outlines.
    @State private var slots = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<slots, id: \.self) { index in
                HeartIcon(isFull: index < lives)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(Color("Abyss").opacity(0.6))
                .overlay(Capsule().strokeBorder(Color("BoardBorder"), lineWidth: 1))
        }
        .onChange(of: lives, initial: true) { _, newValue in
            slots = max(slots, newValue)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lives")
        .accessibilityValue("\(lives) left")
    }
}

/// One of `LivesHUD`'s hearts. Losing it (or getting it back) is a moment: it
/// swells with a red flash, then settles into its new state.
private struct HeartIcon: View {
    let isFull: Bool

    private struct Pop {
        var scale: CGFloat = 1
        var flash: Double = 0
    }

    private static let teal = Color("BioluminescentGlow")
    private static let red = Color(red: 1.0, green: 0.3, blue: 0.3)

    var body: some View {
        // A local copy: the animator's closure can't reach the main-actor static.
        let red = Self.red
        Image(systemName: isFull ? "heart.fill" : "heart")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Self.teal.opacity(isFull ? 1 : 0.45))
            .shadow(color: Self.teal.opacity(isFull ? 0.8 : 0), radius: 4)
            .keyframeAnimator(initialValue: Pop(), trigger: isFull) { content, pop in
                content
                    .overlay {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(red)
                            .shadow(color: red, radius: 6)
                            .opacity(pop.flash)
                    }
                    .scaleEffect(pop.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.9, duration: 0.14)
                    SpringKeyframe(0.75, duration: 0.16)
                    SpringKeyframe(1, duration: 0.3)
                }
                KeyframeTrack(\.flash) {
                    LinearKeyframe(1, duration: 0.05)
                    LinearKeyframe(1, duration: 0.15)
                    LinearKeyframe(0, duration: 0.45)
                }
            }
    }
}

/// The boss's remaining lives: one glowing red pip per life, hollow once lost, in
/// a pill matching `ScoreHUD`.
private struct BossHUD: View {
    let lives: Int

    private static let pipColor = Color(red: 1.0, green: 0.3, blue: 0.3)

    var body: some View {
        HStack(spacing: 8) {
            Text("KRAKEN")
                .font(.custom("Work Sans", size: 11).weight(.semibold))
                .tracking(2)
                .foregroundStyle(Color("Foam").opacity(0.6))

            HStack(spacing: 5) {
                ForEach(0..<Kraken.maxLives, id: \.self) { index in
                    let isLeft = index < lives
                    Circle()
                        .fill(isLeft ? Self.pipColor : .clear)
                        .overlay(Circle().strokeBorder(Self.pipColor.opacity(isLeft ? 0 : 0.5), lineWidth: 1))
                        .frame(width: 10, height: 10)
                        .shadow(color: Self.pipColor.opacity(isLeft ? 0.8 : 0), radius: 5)
                }
            }
            .animation(.spring(duration: 0.4), value: lives)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(Color("Abyss").opacity(0.6))
                .overlay(Capsule().strokeBorder(Color("BoardBorder"), lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kraken")
        .accessibilityValue(lives == 0 ? "Defeated" : "\(lives) of \(Kraken.maxLives) lives left")
    }
}

#Preview {
    ContentView(mode: .freePlay, onExitToHome: {})
}
