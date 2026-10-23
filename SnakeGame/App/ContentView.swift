import SwiftUI
import SpriteKit

struct ContentView: View {
    let mode: GameMode
    /// Zen mode (for testing): nothing costs a life, and Adventure's opening chart
    /// lets any stop be picked to start at.
    let isZen: Bool
    let onExitToHome: () -> Void

    @StateObject private var session = GameSessionState()
    /// False for the first moments on screen: the game opens on the black the
    /// menu's dive ended on, which then clears to reveal the board.
    @State private var hasArrived = false
    /// True while the screen is faded to black between Adventure stages, so the
    /// old stage never visibly turns into the new one.
    @State private var isBetweenStages = false
    private let scene: GameScene

    init(mode: GameMode, isZen: Bool = false, onExitToHome: @escaping () -> Void) {
        self.mode = mode
        self.isZen = isZen
        self.onExitToHome = onExitToHome
        let scene = GameScene(mode: mode, isZen: isZen)
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
                // In zen mode the hearts never change, so a badge says why.
                if isZen {
                    ZenHUD()
                } else if let lives = session.lives {
                    LivesHUD(lives: lives)
                }
                if let supply = session.mineSupply {
                    MineHUD(supply: supply)
                }
            }
            // Up in the corner beside the Dynamic Island, clear of the board.
            .padding(.leading, 16)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // Game over shows the score itself, big; the chart has no room for it.
            .opacity(isHUDHidden ? 0 : 1)

            if let boss = session.boss {
                BossHUD(status: boss)
                    // The other top corner, mirroring the score.
                    .padding(.trailing, 16)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(isHUDHidden ? 0 : 1)
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

            if let cleared = session.clearedStage {
                VictoryOverlay(stage: AdventureStage.all[cleared]) {
                    session.clearedStage = nil
                    session.voyage = Voyage(from: cleared, to: cleared + 1)
                }
                .transition(.opacity)
            }

            if let voyage = session.voyage {
                VoyageChart(
                    voyage: voyage,
                    onSetOff: { setOff(on: voyage) },
                    onRestart: {
                        session.voyage = nil
                        scene.startNewGame()
                    },
                    onSurface: onExitToHome,
                    // Zen mode: at the start of a run, any stop can be picked.
                    onPickStage: isZen && voyage.from == nil ? { index in
                        session.voyage = Voyage(from: nil, to: index)
                        scene.chooseStartingStage(index)
                    } : nil
                )
                .transition(.opacity)
            }

            Color("Abyss")
                .ignoresSafeArea()
                .opacity(hasArrived && !isBetweenStages ? 0 : 1)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.4), value: session.isGameOver)
        .animation(.easeInOut(duration: 0.3), value: session.isLevelComplete)
        .animation(.easeInOut(duration: 0.5), value: session.clearedStage)
        .animation(.easeInOut(duration: 0.5), value: session.voyage)
        .onAppear {
            scene.onScoreChanged = { score in
                session.score = score
            }
            scene.onBossChanged = { status in
                session.boss = status
            }
            scene.onStageCleared = { stage in
                session.clearedStage = stage
            }
            scene.onLivesChanged = { lives in
                session.lives = lives
            }
            scene.onMineSupplyChanged = { supply in
                session.mineSupply = supply
            }
            scene.onGameOver = {
                session.isGameOver = true
            }
            scene.onLevelComplete = {
                session.isLevelComplete = true
            }
            // Adventure opens on the chart, showing where the ascent begins; the
            // board waits behind it (`releaseStart()`).
            if mode == .adventure {
                session.voyage = Voyage(from: nil, to: 0)
            }
            withAnimation(.easeOut(duration: 0.7)) {
                hasArrived = true
            }
        }
    }
}

extension ContentView {
    /// Score, lives and boss pills give way to anything full-screen.
    private var isHUDHidden: Bool {
        session.isGameOver || session.voyage != nil || session.clearedStage != nil
    }

    /// Leaving the voyage chart for the stage it arrived at: at the start of a
    /// run the board is already there, waiting. Between stages the screen fades
    /// to black, the next stage is laid out, and it fades back in.
    private func setOff(on voyage: Voyage) {
        guard voyage.from != nil else {
            session.voyage = nil
            scene.releaseStart()
            return
        }
        withAnimation(.easeIn(duration: 0.45)) {
            isBetweenStages = true
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            session.voyage = nil
            scene.beginNextStage()
            withAnimation(.easeOut(duration: 0.8)) {
                isBetweenStages = false
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

/// Zen mode's stand-in for the hearts: a teal leaf and "ZEN", under the score.
private struct ZenHUD: View {
    var body: some View {
        Label("ZEN", systemImage: "leaf.fill")
            .font(.custom("Work Sans", size: 11).weight(.semibold))
            .tracking(2)
            .foregroundStyle(Color("BioluminescentGlow"))
            .shadow(color: Color("BioluminescentGlow").opacity(0.6), radius: 4)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color("Abyss").opacity(0.6))
                    .overlay(Capsule().strokeBorder(Color("BoardBorder"), lineWidth: 1))
            }
            .accessibilityLabel("Zen mode: nothing costs a life")
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

/// Mine fruit eaten toward the next mine (a pip each), and mines ready to drop.
/// With one ready, the label turns into a glowing "TAP" and the count shows,
/// pulsing, so it's clear a tap will do something.
private struct MineHUD: View {
    let supply: GameManager.MineSupply

    @State private var isPulsing = false

    private static let crimson = Color(red: 1.0, green: 0.3, blue: 0.4)

    var body: some View {
        let isReady = supply.ready > 0
        HStack(spacing: 7) {
            Text(isReady ? "TAP" : "MINES")
                .font(.custom("Work Sans", size: 11).weight(.semibold))
                .tracking(2)
                .foregroundStyle(isReady ? Self.crimson : Color("Foam").opacity(0.6))
                .shadow(color: Self.crimson.opacity(isReady ? 0.9 : 0), radius: 5)

            HStack(spacing: 4) {
                ForEach(0..<GameManager.MineSupply.fruitPerMine, id: \.self) { index in
                    let isFilled = index < supply.progress
                    Circle()
                        .fill(isFilled ? Self.crimson : .clear)
                        .overlay(Circle().strokeBorder(Self.crimson.opacity(isFilled ? 0 : 0.5), lineWidth: 1))
                        .frame(width: 8, height: 8)
                        .shadow(color: Self.crimson.opacity(isFilled ? 0.7 : 0), radius: 3)
                }
            }

            if isReady {
                Text("×\(supply.ready)")
                    .font(.custom("Cinzel", size: 15).weight(.semibold))
                    .foregroundStyle(Self.crimson)
                    .shadow(color: Self.crimson, radius: isPulsing ? 8 : 3)
            }
        }
        .animation(.spring(duration: 0.35), value: supply)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color("Abyss").opacity(0.6))
                .overlay(Capsule().strokeBorder(isReady ? Self.crimson.opacity(isPulsing ? 0.8 : 0.35) : Color("BoardBorder"), lineWidth: 1))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                isPulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mines")
        .accessibilityValue("\(supply.ready) ready, \(supply.progress) of \(GameManager.MineSupply.fruitPerMine) mine fruit toward the next")
        .accessibilityHint(isReady ? "Tap the screen to drop one" : "")
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

/// The boss's name and remaining lives: one glowing red pip per life, hollow once
/// lost, in a pill matching `ScoreHUD`.
private struct BossHUD: View {
    let status: GameManager.BossStatus

    private var lives: Int { status.lives }

    private static let pipColor = Color(red: 1.0, green: 0.3, blue: 0.3)

    var body: some View {
        HStack(spacing: 8) {
            Text(status.name)
                .font(.custom("Work Sans", size: 11).weight(.semibold))
                .tracking(2)
                .foregroundStyle(Color("Foam").opacity(0.6))

            HStack(spacing: 5) {
                ForEach(0..<status.maxLives, id: \.self) { index in
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
        .accessibilityLabel(status.name.capitalized)
        .accessibilityValue(lives == 0 ? "Defeated" : "\(lives) of \(status.maxLives) lives left")
    }
}

#Preview {
    ContentView(mode: .freePlay, onExitToHome: {})
}
