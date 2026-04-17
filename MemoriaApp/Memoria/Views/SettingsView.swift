// SettingsView.swift
// Memoria for iPhone - Settings Screen
// Phase 3: テーマ切り替え、モデル情報、記憶管理、言語設定、アプリ情報

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var llmService = LLMService.shared
    @StateObject private var db = DatabaseService.shared

    // Local state
    @State private var globalMemoryCount: Int = 0
    @State private var sessionCount: Int = 0
    @State private var showDeleteMemoryAlert = false
    @State private var selectedLanguage: AppLanguage

    private static let languageKey = "appLanguage"

    init() {
        let savedLang = UserDefaults.standard.string(forKey: Self.languageKey) ?? "ja"
        _selectedLanguage = State(initialValue: AppLanguage(rawValue: savedLang) ?? .japanese)
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                modelSection
                memorySection
                languageSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.base)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surface0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.currentTheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
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
            .alert("グローバルメモリを全削除", isPresented: $showDeleteMemoryAlert) {
                Button("削除", role: .destructive) {
                    deleteAllGlobalMemories()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("すべてのグローバルメモリが削除されます。この操作は取り消せません。")
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
                    Text("システムテーマに従う")
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
                    Text(appTheme.displayName)
                        .tag(appTheme)
                }
            } label: {
                Label {
                    Text("テーマ")
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
            sectionHeader("外観")
        }
    }

    private var colorPreviewStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("カラーパレット")
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
                    Text("モデル")
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
                    Text(llmService.currentModelType.fileSize)
                        .font(.caption)
                        .foregroundColor(theme.colors.overlay0)
                }
            }
            .listRowBackground(theme.colors.surface0)

            // Memory usage
            HStack {
                Label {
                    Text("メモリ使用量")
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
            } label: {
                Label {
                    Text("モデルを変更")
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(theme.colors.blue)
                }
            }
            .listRowBackground(theme.colors.surface0)
        } header: {
            sectionHeader("モデル")
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
            // Global memory count
            HStack {
                Label {
                    Text("グローバルメモリ")
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "brain")
                        .foregroundColor(theme.colors.mauve)
                }
                Spacer()
                Text("\(globalMemoryCount) 件")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.colors.subtext1)
            }
            .listRowBackground(theme.colors.surface0)

            // Session count
            HStack {
                Label {
                    Text("セッション数")
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundColor(theme.colors.sapphire)
                }
                Spacer()
                Text("\(sessionCount) 件")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.colors.subtext1)
            }
            .listRowBackground(theme.colors.surface0)

            // Delete all global memories
            Button {
                showDeleteMemoryAlert = true
            } label: {
                Label {
                    Text("グローバルメモリを全削除")
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
            sectionHeader("記憶")
        }
    }

    // MARK: - 言語 (Language)

    private var languageSection: some View {
        Section {
            Picker(selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            } label: {
                Label {
                    Text("アプリの言語")
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "globe")
                        .foregroundColor(theme.colors.sky)
                }
            }
            .onChange(of: selectedLanguage) { _, newLang in
                UserDefaults.standard.set(newLang.rawValue, forKey: Self.languageKey)
            }
            .listRowBackground(theme.colors.surface0)
        } header: {
            sectionHeader("言語")
        }
    }

    // MARK: - アプリ情報 (About)

    @State private var showDisclaimerSheet = false

    private var aboutSection: some View {
        Section {
            // App version
            HStack {
                Label {
                    Text("バージョン")
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
                        Text("推論エンジン")
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
                    Text("完全オフライン対応")
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
                    Text("免責事項")
                        .foregroundColor(theme.colors.text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(theme.colors.yellow)
                }
            }
            .listRowBackground(theme.colors.surface0)
            .sheet(isPresented: $showDisclaimerSheet) {
                disclaimerSheet
            }

        } header: {
            sectionHeader("アプリ情報")
        }
    }

    private var disclaimerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    disclaimerItem(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: theme.colors.yellow,
                        title: "AIの回答精度について",
                        body: "Memoriaが生成する回答はAIモデルによる推測です。内容の正確性・完全性・適時性を一切保証しません。医療・法律・財務等の重要な判断には専門家へご相談ください。AIの回答を参考にした結果生じたいかなる損害についても開発者は責任を負いません。"
                    )
                    disclaimerItem(
                        icon: "cpu",
                        iconColor: theme.colors.teal,
                        title: "使用AIモデルの帰属",
                        body: "本アプリはGoogle DeepMindが開発したGemma（オープンウェイトモデル）を使用しています。GemmaはGoogle Gemma利用規約のもとで提供されています。モデルのダウンロードにはHuggingFaceの利用規約への同意が必要です。"
                    )
                    disclaimerItem(
                        icon: "lock.shield",
                        iconColor: theme.colors.green,
                        title: "プライバシー",
                        body: "会話データ・AIの記憶はすべてお使いのiPhone内にのみ保存されます。マイクは音声入力にのみ使用し、音声データは変換後即時廃棄されます。外部サーバーへのデータ送信は行いません（AIモデルの初回ダウンロードを除く）。"
                    )
                    disclaimerItem(
                        icon: "doc.text",
                        iconColor: theme.colors.blue,
                        title: "オープンソースライセンス",
                        body: "本アプリはLLM.swift（MIT）、GRDB.swift（MIT）、llama.cpp（MIT）、Catppuccin（MIT）を使用しています。各ライブラリの著作権はそれぞれの作者に帰属します。"
                    )

                    Text("最終更新: 2026年4月")
                        .font(.caption)
                        .foregroundColor(theme.colors.overlay0)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(theme.colors.base)
            .navigationTitle("免責事項")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surface0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { showDisclaimerSheet = false }
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
        } catch {
            globalMemoryCount = 0
            sessionCount = 0
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
}
