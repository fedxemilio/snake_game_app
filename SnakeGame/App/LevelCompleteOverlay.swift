import SwiftUI

/// Mostly transparent so the frozen board stays visible underneath --
/// tapping anywhere begins the next level. A floating carved "LEVEL
/// CLEARED" in the start menu's style, over a light veil of murk.
struct LevelCompleteOverlay: View {
    let onContinue: () -> Void

    @State private var isCaptionBright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let title = [
        FloatingTitle.Line(text: "LEVEL", fontSize: 28, tracking: 16, centerY: 0.26),
        FloatingTitle.Line(text: "CLEARED", fontSize: 54, tracking: 4, centerY: 0.66),
    ]

    var body: some View {
        ZStack {
            Color("Abyss").opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onContinue)
                .accessibilityLabel("Begin next level")
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 4) {
                FloatingTitle(lines: Self.title, height: 140)

                Text("tap to dive deeper")
                    .font(.custom("Work Sans", size: 15))
                    .foregroundStyle(Color("Foam").opacity(isCaptionBright ? 0.85 : 0.45))
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else {
                isCaptionBright = true
                return
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever()) {
                isCaptionBright = true
            }
        }
    }
}

#Preview {
    ZStack {
        SeaBackground()
        LevelCompleteOverlay(onContinue: {})
    }
}
