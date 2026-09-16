import SwiftUI

struct StartView: View {
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.14)
                .ignoresSafeArea()

            VStack(spacing: 56) {
                Text("Sea Snake")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Button(action: onPlay) {
                    Text("Play")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 160, height: 160)
                        .background(Circle().fill(Color.green))
                }
                .buttonStyle(.plain)
            }
        }
        .statusBarHidden()
    }
}

#Preview {
    StartView(onPlay: {})
}
