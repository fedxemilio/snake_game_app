import SwiftUI

/// The start screen: living deep water (`LivingSea`), the floating title, a mode
/// picker, and the "Dive in" orb. The pieces live in `StartMenu/`. Debug builds
/// also get a zen mode toggle at the bottom, for testing.
///
/// Tapping the orb plays a short dive (the menu rushes toward the viewer and the
/// water goes black) before `onPlay` hands off to the game.
struct StartView: View {
    @Binding var mode: GameMode
    @Binding var isZen: Bool
    let onPlay: () -> Void

    @State private var hasAppeared = false
    @State private var isDiving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diveDuration = 0.7

    var body: some View {
        ZStack {
            ZStack {
                LivingSea()

                VStack(spacing: 0) {
                    Spacer(minLength: 16)

                    FloatingTitle()
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared || reduceMotion ? 0 : 30)
                        .blur(radius: hasAppeared || reduceMotion ? 0 : 12)
                        .animation(.easeOut(duration: 2), value: hasAppeared)

                    Spacer(minLength: 16)

                    modePicker
                        // Above the orb's glow, which spills up behind it.
                        .zIndex(1)

                    Spacer().frame(height: 60)

                    diveButton

                    Spacer(minLength: 16)
                    Spacer(minLength: 16)
                }

                #if DEBUG
                zenToggle
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
                #endif
            }
            .scaleEffect(isDiving ? 1.4 : 1)
            .blur(radius: isDiving ? 8 : 0)

            Color("Abyss")
                .ignoresSafeArea()
                .opacity(isDiving ? 1 : 0)
                .allowsHitTesting(false)
        }
        .statusBarHidden()
        .onAppear { hasAppeared = true }
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: isZen)
        .sensoryFeedback(.impact(weight: .heavy), trigger: isDiving)
    }

    // MARK: Mode

    /// One pill: the mode's name and tagline, and a dot per mode. Tapping cycles to
    /// the next mode.
    private var modePicker: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                mode = mode.next
            }
        } label: {
            VStack(spacing: 6) {
                Text(mode.title)
                    .font(.custom("Cinzel", size: 21).weight(.semibold))
                    .foregroundStyle(Color("Foam"))
                    .shadow(color: Color("Foam").opacity(0.35), radius: 8)
                    .id(mode)
                    .transition(Self.modeSwap)

                Text(mode.tagline)
                    .font(.custom("Work Sans", size: 13))
                    .foregroundStyle(Color("Foam").opacity(0.55))
                    .id(mode)
                    .transition(.opacity)

                HStack(spacing: 8) {
                    ForEach(GameMode.allCases, id: \.self) { option in
                        let isCurrent = option == mode
                        Circle()
                            .fill(isCurrent ? Color("BioluminescentGlow") : Color("Foam").opacity(0.22))
                            .frame(width: 6, height: 6)
                            .shadow(color: Color("BioluminescentGlow").opacity(isCurrent ? 0.9 : 0), radius: 4)
                    }
                }
                .padding(.top, 2)
            }
            // Fixed, so the pill doesn't resize as the names change.
            .frame(width: 230)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(Color("Abyss").opacity(0.55))
                    .overlay(Capsule().strokeBorder(Color("BoardBorder"), lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 1.4).delay(0.7), value: hasAppeared)
        .accessibilityLabel("Mode")
        .accessibilityValue(mode.title)
        .accessibilityHint("Switches to the next mode")
    }

    /// The new name drifts in from the right as the old one drifts off left. A short
    /// slide rather than a full push, so nothing has to be clipped to the pill.
    private static let modeSwap = AnyTransition.asymmetric(
        insertion: .offset(x: 28).combined(with: .opacity),
        removal: .offset(x: -28).combined(with: .opacity)
    )

    // MARK: Zen

    /// Zen mode on or off: a small pill that glows teal when it's on.
    private var zenToggle: some View {
        let glow = Color("BioluminescentGlow")
        return Button {
            isZen.toggle()
        } label: {
            Label("ZEN", systemImage: isZen ? "leaf.fill" : "leaf")
                .font(.custom("Work Sans", size: 12).weight(.semibold))
                .tracking(2)
                .foregroundStyle(isZen ? glow : Color("Foam").opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Color("Abyss").opacity(0.55))
                        .overlay(Capsule().strokeBorder(isZen ? glow.opacity(0.7) : Color("BoardBorder"), lineWidth: 1))
                }
                .shadow(color: glow.opacity(isZen ? 0.5 : 0), radius: 6)
        }
        .buttonStyle(.plain)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 1.4).delay(1.2), value: hasAppeared)
        .accessibilityLabel("Zen mode")
        .accessibilityValue(isZen ? "On" : "Off")
        .accessibilityHint("Nothing can hurt the snake, and Adventure can start at any stage")
    }

    // MARK: Dive

    private var diveButton: some View {
        Button(action: dive) {
            Text("DIVE IN")
                .font(.custom("Cinzel", size: 22).weight(.semibold))
                .tracking(3)
        }
        .buttonStyle(DiveButtonStyle())
        .disabled(isDiving)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.8)
        .animation(.easeOut(duration: 1.6).delay(1), value: hasAppeared)
        .accessibilityLabel("Dive in")
        .accessibilityHint("Starts the game")
    }

    private func dive() {
        guard !isDiving else { return }
        guard !reduceMotion else {
            onPlay()
            return
        }

        withAnimation(.easeIn(duration: Self.diveDuration)) {
            isDiving = true
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.diveDuration))
            onPlay()
        }
    }
}

#Preview {
    StartView(mode: .constant(.freePlay), isZen: .constant(false), onPlay: {})
}
