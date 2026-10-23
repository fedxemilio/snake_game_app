import SwiftUI

/// A boss beaten: its name over a floating carved word for its fate ("SLAIN",
/// "SUNK"), a soft gold light welling up behind it, and an orb to swim on to the
/// voyage chart. Shown once the boss's own send-off (the kraken sinking, the moray
/// coming apart, the galleon foundering) has played.
struct VictoryOverlay: View {
    let stage: AdventureStage
    let onSwimOn: () -> Void

    @State private var isGlowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("Abyss").opacity(0.55)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color("PaleGold").opacity(isGlowing ? 0.28 : 0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadius: 10,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                FloatingTitle(lines: [
                    FloatingTitle.Line(text: stage.bossName, fontSize: 30, tracking: 16, centerY: 0.24),
                    FloatingTitle.Line(text: stage.victoryWord, fontSize: 72, tracking: 8, centerY: 0.64),
                ])

                Text(stage.victoryLine)
                    .font(.custom("Work Sans", size: 15))
                    .foregroundStyle(Color("Foam").opacity(0.75))
                    .padding(.top, 4)

                Spacer()

                Button(action: onSwimOn) {
                    Text("SWIM\nON")
                        .font(.custom("Cinzel", size: 19).weight(.semibold))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(DiveButtonStyle(diameter: 132))
                .accessibilityLabel("Swim on")
                .accessibilityHint("Shows the way to the next stage")

                Spacer()
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever()) {
                isGlowing = true
            }
        }
    }
}

#Preview {
    ZStack {
        SeaBackground()
        VictoryOverlay(stage: AdventureStage.krakensLair, onSwimOn: {})
    }
}
