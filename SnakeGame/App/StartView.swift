import SwiftUI

struct StartView: View {
    @Binding var mode: GameMode
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            SeaBackground()

            VStack(spacing: 32) {
                Text("Sea Snake")
                    .font(.custom("Cinzel", size: 46).weight(.semibold))
                    .foregroundStyle(Color("Foam"))
                    .shadow(color: Color("Foam").opacity(0.45), radius: 14)
                    .shadow(color: Color("PaleGold").opacity(0.2), radius: 26)

                Button(action: { mode = mode.next }) {
                    Text(mode.label)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button(action: onPlay) {
                    Text("Play")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 160, height: 160)
                        .background(Circle().fill(Color.green))
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
        }
        .statusBarHidden()
    }
}

#Preview {
    StartView(mode: .constant(.freePlay), onPlay: {})
}
