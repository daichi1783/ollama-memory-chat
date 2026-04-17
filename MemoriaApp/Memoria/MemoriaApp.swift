// MemoriaApp.swift
// Memoria for iPhone - App Entry Point

import SwiftUI
import Combine

@main
struct MemoriaApp: App {
    // Services shared across the entire app
    @StateObject private var databaseService = DatabaseService.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var localization = LocalizationService.shared

    // Launch screen state
    @State private var showLaunchScreen = true

    // Onboarding state (初回起動時のみ表示)
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingCompleted")

    // App lifecycle
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(databaseService)
                    .environmentObject(themeManager)
                    .environmentObject(localization)
                    .preferredColorScheme(
                        themeManager.useSystemTheme
                            ? nil
                            : (themeManager.currentTheme == .dark ? .dark : .light)
                    )
                    .opacity(showLaunchScreen ? 0 : 1)

                if showLaunchScreen {
                    LaunchScreenView()
                        .transition(.opacity)
                        .ignoresSafeArea()
                }

                // 初回起動時のみオンボーディング（免責事項）を表示
                if showOnboarding && !showLaunchScreen {
                    OnboardingView {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showOnboarding = false
                        }
                    }
                    .environmentObject(themeManager)
                    .transition(.opacity)
                    .ignoresSafeArea()
                    .zIndex(10)
                }
            }
            .onAppear {
                // Keep launch screen for at least 1.5s, then fade out
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showLaunchScreen = false
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    // MARK: - App Lifecycle

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            break
        case .inactive:
            break
        case .background:
            // Persist any pending data when going to background
            break
        @unknown default:
            break
        }
    }
}
