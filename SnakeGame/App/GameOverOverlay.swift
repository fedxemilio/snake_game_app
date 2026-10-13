import SwiftUI

/// The end of a run, in the start menu's voice: the board sinks into the murk behind
/// a floating carved "GAME OVER", the final score glows in pale gold, and the menu's
/// orb (`DiveButtonStyle`) offers another dive. "Surface" goes back to the menu.
struct GameOverOverlay: View {
    let score: Int
    let onPlayAgain: () -> Void
    let onGoHome: () -> Void

    private static let title = [
        FloatingTitle.Line(text: "GAME", fontSize: 30, tracking: 18, centerY: 0.24),
        FloatingTitle.Line(text: "OVER", fontSize: 70, tracking: 8, centerY: 0.64),
    ]

    var body: some View {
        ZStack {
            // The frozen board stays faintly visible, darkest at the edges.
            RadialGradient(
                colors: [Color("Abyss").opacity(0.6), Color("Abyss").opacity(0.94)],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                FloatingTitle(lines: Self.title)

                VStack(spacing: 0) {
                    Text("SCORE")
                        .font(.custom("Work Sans", size: 12).weight(.semibold))
                        .tracking(3)
                        .foregroundStyle(Color("Foam").opacity(0.6))

                    Text("\(score)")
                        .font(.custom("Cinzel", size: 46).weight(.semibold))
                        .foregroundStyle(Color("PaleGold"))
                        .shadow(color: Color("PaleGold").opacity(0.5), radius: 12)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                Button(action: onPlayAgain) {
                    Text("DIVE\nAGAIN")
                        .font(.custom("Cinzel", size: 19).weight(.semibold))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(DiveButtonStyle(diameter: 132))
                .accessibilityLabel("Dive again")
                .accessibilityHint("Starts a new run")

                Button(action: onGoHome) {
                    Label("SURFACE", systemImage: "arrow.up")
                        .font(.custom("Cinzel", size: 15).weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(Color("Foam"))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(Color("Abyss").opacity(0.6))
                                .overlay(Capsule().strokeBorder(Color("BoardBorder"), lineWidth: 1))
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 56)
                .accessibilityLabel("Surface")
                .accessibilityHint("Returns to the main menu")

                Spacer()
            }
        }
    }
}

#Preview {
    ZStack {
        SeaBackground()
        GameOverOverlay(score: 12, onPlayAgain: {}, onGoHome: {})
    }
}
