import SwiftUI

struct GameOverOverlay: View {
    let onPlayAgain: () -> Void
    let onGoHome: () -> Void

    var body: some View {
        ZStack {
            Color.white.opacity(0.94)
                .ignoresSafeArea()

            VStack {
                Text("GAME OVER")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.top, 72)

                Spacer()

                VStack(spacing: 28) {
                    GlowButton(title: "Play Again", color: .green, diameter: 140, action: onPlayAgain)
                    GlowButton(title: "Home", color: .red, diameter: 84, action: onGoHome)
                }

                Spacer()
                Spacer()
            }
        }
    }
}

private struct GlowButton: View {
    let title: String
    let color: Color
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: diameter * 0.16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(color))
                .shadow(color: color, radius: 12)
                .shadow(color: color.opacity(0.7), radius: 24)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    GameOverOverlay(onPlayAgain: {}, onGoHome: {})
}
