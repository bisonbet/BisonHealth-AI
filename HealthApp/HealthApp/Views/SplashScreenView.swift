import SwiftUI

struct SplashScreenView: View {
    @State private var isVisible = false
    @State private var isGlowActive = false

    var body: some View {
        ZStack {
            // Base background
            Color(red: 0.07, green: 0.07, blue: 0.07)
                .ignoresSafeArea()

            // Hero image with cinematic gradient overlay
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Image("BisonStartupHero")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(isVisible ? 1.0 : 0.0)

                    // Top and Bottom gradient overlays for contrast and smooth blending
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.07, blue: 0.07).opacity(0.85),
                            Color(red: 0.07, green: 0.07, blue: 0.07).opacity(0.2),
                            Color.clear,
                            Color(red: 0.07, green: 0.07, blue: 0.07).opacity(0.6),
                            Color(red: 0.07, green: 0.07, blue: 0.07).opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
            }
            .ignoresSafeArea()

            // Foreground Branding
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 12) {
                    // App Icon / Emblem
                    ZStack {
                        Circle()
                            .fill(BisonTheme.gold.opacity(0.15))
                            .frame(width: 84, height: 84)
                            .blur(radius: isGlowActive ? 12 : 6)

                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BisonTheme.gold, BisonTheme.hideBrown],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    // Main Title
                    Text("BisonHealth AI")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color(red: 0.95, green: 0.90, blue: 0.82)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)

                    // Subtitle
                    Text("Private • Intelligent • On-Device")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .tracking(2.5)
                        .textCase(.uppercase)
                        .foregroundColor(BisonTheme.gold)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                }
                .opacity(isVisible ? 1.0 : 0.0)

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = true
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
