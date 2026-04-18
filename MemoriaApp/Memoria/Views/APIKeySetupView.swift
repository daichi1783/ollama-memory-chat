// APIKeySetupView.swift
// Memoria for iPhone - API Key Setup Sheet
// Phase 6: クラウドAI APIキー貼り付け入力シート

import SwiftUI

struct APIKeySetupView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss

    let provider: APIProvider

    @State private var apiKeyInput: String = ""
    @State private var showKey: Bool = false
    @State private var saveResult: SaveResult? = nil
    @State private var showDeleteAlert = false

    enum SaveResult {
        case success
        case invalidFormat
        case deleted
    }

    private var existingMasked: String? {
        KeychainService.shared.maskedKey(for: provider)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // ── ヘッダー ──────────────────────────────────
                    providerHeader

                    // ── 現在の設定状態 ─────────────────────────────
                    if let masked = existingMasked {
                        currentKeyCard(masked: masked)
                    }

                    // ── APIキー入力 ────────────────────────────────
                    inputSection

                    // ── 取得ガイド ─────────────────────────────────
                    getKeyGuide

                    // ── 免責 ──────────────────────────────────────
                    disclaimerNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(theme.colors.base)
            // ⑨ ローカライズ対応: "OpenAI API Key Setup" 等の形式
            .navigationTitle("\(provider.displayName) \(loc["api_key_setup_nav_title"])")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surface0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc["done"]) { dismiss() }
                        .foregroundColor(theme.colors.blue)
                }
            }
            .alert(loc["delete_memory_title"], isPresented: $showDeleteAlert) {
                Button(loc["delete"], role: .destructive) {
                    KeychainService.shared.deleteAPIKey(for: provider)
                    apiKeyInput = ""
                    saveResult = .deleted
                }
                Button(loc["cancel"], role: .cancel) {}
            } message: {
                Text("\(provider.displayName) \(loc["api_key_setup_nav_title"])")
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    // MARK: - Provider Header

    private var providerHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: provider.displayIcon)
                .font(.system(size: 40))
                .foregroundColor(providerColor)
                .padding(16)
                .background(
                    Circle()
                        .fill(providerColor.opacity(0.1))
                )

            VStack(spacing: 4) {
                Text(provider.displayName)
                    .font(.title2.bold())
                    .foregroundColor(theme.colors.text)
                Text(loc["api_key_keychain_note"])
                    .font(.caption)
                    .foregroundColor(theme.colors.subtext0)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Current Key Card

    private func currentKeyCard(masked: String) -> some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(theme.colors.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc["api_key_already_set"])
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.colors.green)
                Text(masked)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(theme.colors.subtext0)
            }
            Spacer()
            Button {
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(theme.colors.red)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.colors.green.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingMasked != nil ? "APIキーを更新する" : "APIキーを入力")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.colors.text)

            // テキストフィールド
            HStack(spacing: 12) {
                Group {
                    if showKey {
                        TextField("APIキーを貼り付け...", text: $apiKeyInput)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("APIキーを貼り付け...", text: $apiKeyInput)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .foregroundColor(theme.colors.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                // 表示/非表示トグル
                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .foregroundColor(theme.colors.overlay0)
                }

                // クリップボードから貼り付けボタン
                Button {
                    if let clip = UIPasteboard.general.string {
                        apiKeyInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(theme.colors.blue)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.surface0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.colors.surface1, lineWidth: 1)
                    )
            )

            // 形式チェック表示
            if !apiKeyInput.isEmpty {
                keyValidationRow
            }

            // 保存結果フィードバック
            if let result = saveResult {
                saveResultBanner(result)
            }

            // 保存ボタン
            Button {
                saveKey()
            } label: {
                Text("保存する")
                    .font(.body.weight(.semibold))
                    .foregroundColor(theme.colors.base)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canSave ? providerColor : theme.colors.surface1)
                    )
            }
            .disabled(!canSave)
            .animation(.easeInOut(duration: 0.2), value: canSave)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.colors.surface0)
        )
    }

    private var keyValidationRow: some View {
        HStack(spacing: 6) {
            let isValid = provider.isValidKey(apiKeyInput)
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(isValid ? theme.colors.green : theme.colors.yellow)
                .font(.caption)
            Text(isValid
                 ? "正しい形式のAPIキーです"
                 : "形式が異なります（\(provider.keyPrefix)... で始まる必要があります）")
                .font(.caption)
                .foregroundColor(isValid ? theme.colors.green : theme.colors.yellow)
        }
    }

    private func saveResultBanner(_ result: SaveResult) -> some View {
        HStack(spacing: 8) {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundColor(theme.colors.green)
                Text("APIキーを保存しました").foregroundColor(theme.colors.green)
            case .invalidFormat:
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(theme.colors.yellow)
                Text("APIキーの形式が正しくありません").foregroundColor(theme.colors.yellow)
            case .deleted:
                Image(systemName: "trash.fill").foregroundColor(theme.colors.red)
                Text("APIキーを削除しました").foregroundColor(theme.colors.red)
            }
        }
        .font(.caption.weight(.medium))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(result == .success ? theme.colors.green.opacity(0.1) :
                      result == .deleted ? theme.colors.red.opacity(0.1) :
                      theme.colors.yellow.opacity(0.1))
        )
    }

    // MARK: - Get Key Guide

    private var getKeyGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APIキーの取得方法")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.colors.text)

            VStack(alignment: .leading, spacing: 8) {
                guideStep(number: "1", text: "下のリンクから\(provider.displayName)の公式サイトを開く")
                guideStep(number: "2", text: "アカウントを作成またはサインイン")
                guideStep(number: "3", text: "APIキーを発行してコピー")
                guideStep(number: "4", text: "このページに戻って貼り付け")
            }

            // リンクボタン
            Link(destination: URL(string: provider.keyObtainURL)!) {
                HStack {
                    Image(systemName: "safari")
                    Text("\(provider.displayName) でAPIキーを取得")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(providerColor)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(providerColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(providerColor.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // 料金メモ
            costNote
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.colors.surface0)
        )
    }

    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundColor(providerColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(providerColor.opacity(0.15)))
            Text(text)
                .font(.caption)
                .foregroundColor(theme.colors.subtext0)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var costNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "creditcard")
                .font(.caption)
                .foregroundColor(theme.colors.peach)
            Text(providerCostNote)
                .font(.caption)
                .foregroundColor(theme.colors.subtext0)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.colors.peach.opacity(0.08))
        )
    }

    // MARK: - Disclaimer

    private var disclaimerNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.caption)
                .foregroundColor(theme.colors.green)
            Text("APIキーはiPhoneのKeychain（セキュアストレージ）に保存されます。Memoriaのサーバーには一切送信されません。クラウドAIの利用料金はご自身のAPIアカウントに課金されます。")
                .font(.caption)
                .foregroundColor(theme.colors.subtext0)
                .lineSpacing(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.surface0)
        )
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && apiKeyInput.count >= 20
    }

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // 形式チェック（警告のみ、保存は許可）
        if KeychainService.shared.setAPIKey(trimmed, for: provider) {
            saveResult = .success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } else {
            saveResult = .invalidFormat
        }
    }

    private var providerColor: Color {
        switch provider {
        case .gemini: return theme.colors.blue
        case .claude: return theme.colors.mauve
        case .openai: return theme.colors.teal
        }
    }

    private var providerCostNote: String {
        switch provider {
        case .gemini:
            return "Gemini 2.0 Flash は無料枠あり（1日あたり最大1,500リクエスト）。超過分は従量課金。"
        case .claude:
            return "Claude Haiku は最安値モデル。1Mトークンあたり約$0.25。プリペイド制。"
        case .openai:
            return "GPT-4o mini は最安値モデル。1Mトークンあたり約$0.15。プリペイド制。"
        }
    }
}

// MARK: - Preview

#Preview {
    APIKeySetupView(provider: .gemini)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationService.shared)
}
