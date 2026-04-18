// ThemeManager.swift
// Memoria for iPhone - Centralized Catppuccin Theme System
// Phase 3: Mocha (Dark) & Latte (Light) テーマ切り替え対応

import SwiftUI
import Combine

// MARK: - AppTheme Enum

enum AppTheme: String, CaseIterable, Identifiable {
    case dark = "dark"
    case light = "light"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "ダーク (Mocha)"
        case .light: return "ライト (Latte)"
        }
    }

    var colorSchemeValue: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - ThemeColors

struct ThemeColors: Sendable {
    // Backgrounds
    let base: Color
    let mantle: Color
    let crust: Color

    // Surfaces (card/bubble backgrounds)
    let surface0: Color
    let surface1: Color
    let surface2: Color

    // Overlays (borders, separators)
    let overlay0: Color
    let overlay1: Color
    let overlay2: Color

    // Text
    let text: Color
    let subtext0: Color
    let subtext1: Color

    // Accent colors
    let blue: Color
    let mauve: Color
    let pink: Color
    let red: Color
    let green: Color
    let yellow: Color
    let peach: Color
    let teal: Color
    let sky: Color
    let lavender: Color
    let flamingo: Color
    let rosewater: Color
    let sapphire: Color
}

// MARK: - Catppuccin Palette Definitions

extension ThemeColors {

    /// Catppuccin Mocha (Dark)
    static let mocha = ThemeColors(
        base: Color(hex: "1e1e2e"),
        mantle: Color(hex: "181825"),
        crust: Color(hex: "11111b"),
        surface0: Color(hex: "313244"),
        surface1: Color(hex: "45475a"),
        surface2: Color(hex: "585b70"),
        overlay0: Color(hex: "6c7086"),
        overlay1: Color(hex: "7f849c"),
        overlay2: Color(hex: "9399b2"),
        text: Color(hex: "cdd6f4"),
        subtext0: Color(hex: "a6adc8"),
        subtext1: Color(hex: "bac2de"),
        blue: Color(hex: "89b4fa"),
        mauve: Color(hex: "cba6f7"),
        pink: Color(hex: "f5c2e7"),
        red: Color(hex: "f38ba8"),
        green: Color(hex: "a6e3a1"),
        yellow: Color(hex: "f9e2af"),
        peach: Color(hex: "fab387"),
        teal: Color(hex: "94e2d5"),
        sky: Color(hex: "89dcfe"),
        lavender: Color(hex: "b4befe"),
        flamingo: Color(hex: "f2cdcd"),
        rosewater: Color(hex: "f5e0dc"),
        sapphire: Color(hex: "74c7ec")
    )

    /// Catppuccin Latte (Light)
    static let latte = ThemeColors(
        base: Color(hex: "eff1f5"),
        mantle: Color(hex: "e6e9ef"),
        crust: Color(hex: "dce0e8"),
        surface0: Color(hex: "ccd0da"),
        surface1: Color(hex: "bcc0cc"),
        surface2: Color(hex: "acb0be"),
        overlay0: Color(hex: "9ca0b0"),
        overlay1: Color(hex: "8c8fa1"),
        overlay2: Color(hex: "7c7f93"),
        text: Color(hex: "4c4f69"),
        subtext0: Color(hex: "6c6f85"),
        subtext1: Color(hex: "5c5f77"),
        blue: Color(hex: "1e66f5"),
        mauve: Color(hex: "8839ef"),
        pink: Color(hex: "ea76cb"),
        red: Color(hex: "d20f39"),
        green: Color(hex: "40a02b"),
        yellow: Color(hex: "df8e1d"),
        peach: Color(hex: "fe640b"),
        teal: Color(hex: "179299"),
        sky: Color(hex: "04a5e5"),
        lavender: Color(hex: "7287fd"),
        flamingo: Color(hex: "dd7878"),
        rosewater: Color(hex: "dc8a78"),
        sapphire: Color(hex: "209fb5")
    )

    /// Returns the palette for a given theme
    static func forTheme(_ theme: AppTheme) -> ThemeColors {
        switch theme {
        case .dark: return .mocha
        case .light: return .latte
        }
    }
}

// MARK: - ThemeManager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    // MARK: - Published Properties

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.selectedThemeKey)
        }
    }

    @Published var useSystemTheme: Bool {
        didSet {
            UserDefaults.standard.set(useSystemTheme, forKey: Self.useSystemThemeKey)
        }
    }

    // MARK: - Computed Colors

    /// The current theme's color palette. Views should use this to access all colors.
    var colors: ThemeColors {
        ThemeColors.forTheme(currentTheme)
    }

    // MARK: - UserDefaults Keys

    private static let selectedThemeKey = "selectedTheme"
    private static let useSystemThemeKey = "useSystemTheme"

    // MARK: - Init

    private init() {
        // Restore persisted preferences
        let savedUseSystem = UserDefaults.standard.object(forKey: Self.useSystemThemeKey) as? Bool ?? true
        let savedThemeRaw = UserDefaults.standard.string(forKey: Self.selectedThemeKey) ?? AppTheme.dark.rawValue
        let savedTheme = AppTheme(rawValue: savedThemeRaw) ?? .dark

        self.useSystemTheme = savedUseSystem
        self.currentTheme = savedTheme
    }

    // MARK: - Theme Control

    /// Toggle between dark and light manually
    func toggleTheme() {
        currentTheme = (currentTheme == .dark) ? .light : .dark
    }

    /// Update theme based on system color scheme. Call this from a view that
    /// has access to `@Environment(\.colorScheme)`.
    func applySystemColorScheme(_ colorScheme: ColorScheme) {
        guard useSystemTheme else { return }
        let newTheme: AppTheme = (colorScheme == .dark) ? .dark : .light
        if currentTheme != newTheme {
            currentTheme = newTheme
        }
    }

    /// The `ColorScheme` override to apply to the app's root view.
    /// Returns `nil` when following the system, otherwise forces the selected scheme.
    var preferredColorScheme: ColorScheme? {
        useSystemTheme ? nil : currentTheme.colorSchemeValue
    }
}
