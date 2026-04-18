// LaunchScreenView.swift
// Memoria for iPhone - Animated Launch Screen

import SwiftUI
import Combine

struct LaunchScreenView: View {
    @State private var isAnimating = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var glowPulse = false
    @State private var outerRotation: Double = 0
    @State private var middleRotation: Double = 0
    @State private var innerRotation: Double = 0

    // MARK: - Catppuccin Mocha Colors (hardcoded — no ThemeManager dependency)
    private let base = Color(red: 0x1e / 255.0, green: 0x1e / 255.0, blue: 0x2e / 255.0)
    private let blue = Color(red: 0x89 / 255.0, green: 0xb4 / 255.0, blue: 0xfa / 255.0)
    private let mauve = Color(red: 0xcb / 255.0, green: 0xa6 / 255.0, blue: 0xf7 / 255.0)
    private let pink = Color(red: 0xf5 / 255.0, green: 0xc2 / 255.0, blue: 0xe7 / 255.0)
    private let text = Color(red: 0xcd / 255.0, green: 0xd6 / 255.0, blue: 0xf4 / 255.0)
    private let subtext0 = Color(red: 0xa6 / 255.0, green: 0xad / 255.0, blue: 0xc8 / 255.0)

    var body: some View {
        ZStack {
            // Background
            base.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Orbital logo animation
                ZStack {
                    // Outer ring — slow rotation
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [pink.opacity(0.6), mauve.opacity(0.3), pink.opacity(0.6)]),
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(outerRotation))

                    // Middle ring — medium rotation, opposite direction
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [mauve.opacity(0.7), blue.opacity(0.3), mauve.opacity(0.7)]),
                                center: .center
                            ),
                            lineWidth: 2.0
                        )
                        .frame(width: 82, height: 82)
                        .rotationEffect(.degrees(middleRotation))

                    // Inner ring — fast rotation
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [blue.opacity(0.8), pink.opacity(0.3), blue.opacity(0.8)]),
                                center: .center
                            ),
                            lineWidth: 1.8
                        )
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(innerRotation))

                    // Glowing center dot
                    Circle()
                        .fill(blue)
                        .frame(width: 14, height: 14)
                        .shadow(color: blue.opacity(glowPulse ? 0.9 : 0.3), radius: glowPulse ? 18 : 8)
                        .scaleEffect(glowPulse ? 1.15 : 1.0)
                }
                .frame(height: 130)

                // Title
                VStack(spacing: 10) {
                    Text("Memoria")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(text)
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 12)

                    // Subtitle
                    Text("Your Offline AI Assistant")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(subtext0)
                        .opacity(showSubtitle ? 1 : 0)
                        .offset(y: showSubtitle ? 0 : 8)
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Animation Orchestration

    private func startAnimations() {
        // Continuous orbital rotations
        withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
            outerRotation = 360
        }
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            middleRotation = -360
        }
        withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
            innerRotation = 360
        }

        // Glow pulse
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            glowPulse = true
        }

        // Title fade-in after 0.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                showTitle = true
            }
        }

        // Subtitle fade-in after 0.8s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                showSubtitle = true
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
