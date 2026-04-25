// SettingsView.swift
// Memoria for iPhone - Settings Screen
// Phase 3: テーマ切り替え、モデル情報、記憶管理、言語設定、アプリ情報

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var llmService = LLMService.shared
    @StateObject private var db = DatabaseService.shared

    // Local state
    @State private var globalMemoryCount: Int = 0
    @State private var sessionCount: Int = 0
    @State private var showDeleteMemoryAlert = false
    @State private var commandCount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                modelSection
                memorySection
                commandSection
                languageSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.base)
            .navigationTitle(loc["settings"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surface0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.currentTheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc["done"]) {
                        dismiss()
                    }
                    .foregroundColor(theme.colors.blue)
                }
            }
            .onAppear {
                loadCounts()
            }
            .onChange(of: colorScheme) { _, newScheme in
                theme.applySystemColorScheme(newScheme)
            }
            .alert(loc["delete_memory_title"], isPresented: $showDeleteMemoryAlert) {
                Button(loc["delete"], role: .destructive) {
                    deleteAllGlobalMemories()
                }
                Button(loc["cancel"], role: .cancel) {}
            } message: {
                Text(loc["delete_memory_msg"])
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    // MARK: - 外観 (Appearance)

    private var appearanceSection: some View {
        Section {
            // System theme toggle
            Toggle(isOn: Binding(
                get: { theme.useSystemTheme },
                set: { newValue in
                    theme.useSystemTheme = newValue
                    if newValue {
                        theme.applySystemColorScheme(colorScheme)
                    }
                }
            )) {
                Label {
                    Text(loc["follow_system_theme"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "iphone")
                        .foregroundColor(theme.colors.blue)
                }
            }
            .tint(theme.colors.blue)
            .listRowBackground(theme.colors.surface0)

            // Theme picker
            Picker(selection: Binding(
                get: { theme.currentTheme },
                set: { newTheme in
                    theme.currentTheme = newTheme
                }
            )) {
                ForEach(AppTheme.allCases) { appTheme in
                    Text(loc[appTheme == .dark ? "theme_dark" : "theme_light"])
                        .tag(appTheme)
                }
            } label: {
                Label {
                    Text(loc["theme_label"])
                        .foregroundColor(theme.useSystemTheme ? theme.colors.overlay0 : theme.colors.text)
                } icon: {
                    Image(systemName: theme.currentTheme == .dark ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(theme.useSystemTheme ? theme.colors.overlay0 : theme.colors.mauve)
                }
            }
            .disabled(theme.useSystemTheme)
            .listRowBackground(theme.colors.surface0)

            // Color preview strip
            colorPreviewStrip
                .listRowBackground(theme.colors.surface0)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            sectionHeader(loc["section_appearance"])
        }
    }

    private var colorPreviewStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc["color_palette"])
                .font(.caption)
                .foregroundColor(theme.colors.subtext0)

            HStack(spacing: 4) {
                colorSwatch(theme.colors.red)
                colorSwatch(theme.colors.peach)
                colorSwatch(theme.colors.yellow)
                colorSwatch(theme.colors.green)
                colorSwatch(theme.colors.teal)
                colorSwatch(theme.colors.sky)
                colorSwatch(theme.colors.sapphire)
                colorSwatch(theme.colors.blue)
                colorSwatch(theme.colors.lavender)
                colorSwatch(theme.colors.mauve)
                colorSwatch(theme.colors.pink)
                colorSwatch(theme.colors.flamingo)
                colorSwatch(theme.colors.rosewater)
            }
        }
    }

    private func colorSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
    }

    // MARK: - モデル (Model)

    private var modelSection: some View {
        Section {
            // Current model name + size
            HStack {
                Label {
                    Text(loc["model_label"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "cpu")
                        .foregroundColor(theme.colors.teal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(llmService.currentModelType.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.colors.subtext1)
                    Text(llmService.currentModelType.isLocal
                         ? llmService.currentModelType.fileSize
                         : loc[llmService.currentModelType.fileSize])
                        .font(.caption)
                        .foregroundColor(theme.colors.overlay0)
                }
            }
            .listRowBackground(theme.colors.surface0)

            // Memory usage
            HStack {
                Label {
                    Text(loc["memory_usage"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "memorychip")
                        .foregroundColor(theme.colors.yellow)
                }
                Spacer()
                Text(String(format: "%.0f MB", llmService.memoryUsageMB))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(memoryUsageColor)
            }
            .listRowBackground(theme.colors.surface0)

            // Change model button → ModelManagementView（ローカル+クラウド統合）
            NavigationLink {
                ModelManagementView()
                    .environmentObject(theme)
                    .environmentObject(llmService)
                    .environmentObject(loc)
            } label: {
                Label {
                    Text(loc["change_model"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(theme.colors.blue)
                }
            }
            .listRowBackground(theme.colors.surface0)
        } header: {
            sectionHeader(loc["section_model"])
        }
    }

    private var memoryUsageColor: Color {
        if llmService.memoryUsageMB > 1000 {
            return theme.colors.red
        } else if llmService.memoryUsageMB > 500 {
            return theme.colors.yellow
        } else {
            return theme.colors.green
        }
    }

    // MARK: - 記憶 (Memory)

    private var memorySection: some View {
        Section {
            // Global memory → NavigationLink で一覧画面へ
            NavigationLink {
                GlobalMemoryManagementView()
                    .environmentObject(theme)
                    .environmentObject(loc)
            } label: {
                HStack {
                    Label {
                        Text(loc["global_memory_label"])
                            .foregroundColor(theme.colors.text)
                    } icon: {
                        Image(systemName: "brain")
                            .foregroundColor(theme.colors.mauve)
                    }
                    Spacer()
                    Text("\(globalMemoryCount) \(loc["mem_count_unit"])")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.colors.subtext1)
                }
            }
            .listRowBackground(theme.colors.surface0)

            // Session count
            HStack {
                Label {
                    Text(loc["session_count_label"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundColor(theme.colors.sapphire)
                }
                Spacer()
                Text("\(sessionCount) \(loc["mem_count_unit"])")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.colors.subtext1)
            }
            .listRowBackground(theme.colors.surface0)

            // Delete all global memories
            Button {
                showDeleteMemoryAlert = true
            } label: {
                Label {
                    Text(loc["clear_global_memory"])
                        .foregroundColor(theme.colors.red)
                } icon: {
                    Image(systemName: "trash")
                        .foregroundColor(theme.colors.red)
                }
            }
            .disabled(globalMemoryCount == 0)
            .opacity(globalMemoryCount == 0 ? 0.5 : 1.0)
            .listRowBackground(theme.colors.surface0)
        } header: {
            sectionHeader(loc["section_memory"])
        }
    }

    // MARK: - カスタムコマンド (Custom Commands)

    private var commandSection: some View {
        Section {
            NavigationLink {
                UserCommandManagementView()
                    .environmentObject(theme)
                    .environmentObject(loc)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.colors.blue)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.colors.blue.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc["cmd_settings_row"])
                            .foregroundColor(theme.colors.text)
                        Text(loc["cmd_settings_sub"])
                            .font(.caption)
                            .foregroundColor(theme.colors.subtext0)
                    }

                    Spacer()

                    if commandCount > 0 {
                        Text(String(format: loc["cmd_count_fmt"], commandCount))
                            .font(.caption2.weight(.medium))
                            .foregroundColor(theme.colors.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(theme.colors.blue.opacity(0.12))
                            )
                    }
                }
            }
            .listRowBackground(theme.colors.surface0)
        } header: {
            sectionHeader(loc["section_commands"])
        }
    }

    // MARK: - 言語 (Language)

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { loc.currentLanguage },
                set: { loc.currentLanguage = $0 }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            } label: {
                Label {
                    Text(loc["app_language"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "globe")
                        .foregroundColor(theme.colors.sky)
                }
            }
            .listRowBackground(theme.colors.surface0)
        } header: {
            sectionHeader(loc["section_language"])
        }
    }

    // MARK: - アプリ情報 (About)

    @State private var showDisclaimerSheet = false

    private var aboutSection: some View {
        Section {
            // App version
            HStack {
                Label {
                    Text(loc["version_label"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(theme.colors.blue)
                }
                Spacer()
                Text("1.0.0")
                    .font(.subheadline)
                    .foregroundColor(theme.colors.subtext0)
            }
            .listRowBackground(theme.colors.surface0)

            // Powered by Gemma (帰属表示)
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc["inference_engine"])
                            .foregroundColor(theme.colors.text)
                        Text("Powered by Gemma (Google DeepMind)")
                            .font(.caption)
                            .foregroundColor(theme.colors.subtext0)
                    }
                } icon: {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(theme.colors.peach)
                }
            }
            .listRowBackground(theme.colors.surface0)

            // Offline badge
            HStack {
                Label {
                    Text(loc["fully_offline_label"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(theme.colors.green)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(theme.colors.green)
            }
            .listRowBackground(theme.colors.surface0)

            // 免責事項
            Button {
                showDisclaimerSheet = true
            } label: {
                Label {
                    Text(loc["disclaimer_label"])
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(theme.colors.yellow)
                }
            }
            .listRowBackground(theme.colors.surface0)
            .sheet(isPresented: $showDisclaimerSheet) {
                disclaimerSheet
                    .environmentObject(theme)
                    .environmentObject(loc)
            }

        } header: {
            sectionHeader(loc["section_about"])
        }
    }

    private var disclaimerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    disclaimerItem(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: theme.colors.yellow,
                        title: loc["disclaimer_ai_title"],
                        body: loc["disclaimer_ai_body"]
                    )
                    disclaimerItem(
                        icon: "cpu",
                        iconColor: theme.colors.teal,
                        title: loc["disclaimer_model_title"],
                        body: loc["disclaimer_model_body"]
                    )
                    disclaimerItem(
                        icon: "lock.shield",
                        iconColor: theme.colors.green,
                        title: loc["disclaimer_privacy_title"],
                        body: loc["disclaimer_privacy_body"]
                    )
                    disclaimerItem(
                        icon: "doc.text",
                        iconColor: theme.colors.blue,
                        title: loc["disclaimer_oss_title"],
                        body: loc["disclaimer_oss_body"]
                    )

                    Text(loc["last_updated"])
                        .font(.caption)
                        .foregroundColor(theme.colors.overlay0)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(theme.colors.base)
            .navigationTitle(loc["disclaimer_nav_title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surface0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc["close"]) { showDisclaimerSheet = false }
                        .foregroundColor(theme.colors.blue)
                }
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private func disclaimerItem(icon: String, iconColor: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.colors.text)
            }
            Text(body)
                .font(.footnote)
                .foregroundColor(theme.colors.subtext0)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.surface0)
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(theme.colors.subtext0)
            .textCase(nil)
    }

    private func loadCounts() {
        do {
            let memories = try db.getAllGlobalMemories()
            globalMemoryCount = memories.count
            let sessions = try db.getAllSessions()
            sessionCount = sessions.count
            let commands = try db.getAllUserCommands()
            commandCount = commands.count
        } catch {
            globalMemoryCount = 0
            sessionCount = 0
            commandCount = 0
        }
    }

    private func deleteAllGlobalMemories() {
        do {
            let memories = try db.getAllGlobalMemories()
            for memory in memories {
                if let id = memory.id {
                    try db.deleteGlobalMemory(id: id)
                }
            }
            globalMemoryCount = 0
        } catch {
            // Silently handle — error logging is handled by DatabaseService
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationService.shared)
}
