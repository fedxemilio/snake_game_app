import SwiftUI

/// Mostly transparent so the frozen board stays visible underneath --
/// tapping anywhere begins the next level.
struct LevelCompleteOverlay: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onContinue)

            VStack(spacing: 10) {
                Text("Level Complete!")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)

                Text("tap to begin next level")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 4)
            }
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    LevelCompleteOverlay(onContinue: {})
}
