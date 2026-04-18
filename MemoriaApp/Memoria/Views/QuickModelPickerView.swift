// QuickModelPickerView.swift
// Memoria for iPhone - チャット画面から素早くモデルを切り替えるシート
// 会話を引き継いだままモデルを変更できる

import SwiftUI

// MARK: - QuickModelPickerView

struct QuickModelPickerView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss

    @State private var isSwitching = false
    @State private var switchingModel: ModelType?
    @State private var showFullManagement = false
    @State private var showAPIKeySetup: APIProvider? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // 現在のモデル表示
                    currentModelBanner

                    // ローカルモデル
                    modelSection(
                        title: loc["local_models"],
                        subtitle: loc["local_models_short_sub"],
                        icon: "iphone",
                        models: LLMService.availableLocalModels
                    )

                    // クラウドモデル（プロバイダーごと）
                    cloudSection(provider: .gemini,  accentColor: theme.colors.blue)
                    cloudSection(provider: .claude,  accentColor: theme.colors.mauve)
                    cloudSection(provider: .openai,  accentColor: theme.colors.teal)

                    // 詳細設定への導線
                    Button {
                        showFullManagement = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15))
                                .foregroundColor(theme.colors.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc["full_settings_label"])
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(theme.colors.text)
                                Text(loc["full_settings_sub"])
                                    .font(.caption2)
                                    .foregroundColor(theme.colors.subtext0)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(theme.colors.overlay0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.colors.surface0)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(theme.colors.blue.opacity(0.2), lineWidth: 1)
                        )
                    }

                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(theme.colors.base.ignoresSafeArea())
            .navigationTitle(loc["quick_model_title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.mantle, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc["done"]) { dismiss() }
                        .foregroundColor(theme.colors.blue)
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showFullManagement) {
                ModelManagementView()
                    .environmentObject(theme)
                    .environmentObject(llmService)
                    .environmentObject(loc)
            }
            .sheet(item: $showAPIKeySetup) { provider in
                APIKeySetupView(provider: provider)
                    .environmentObject(theme)
                    .environmentObject(loc)
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    // MARK: - 現在のモデルバナー

    private var currentModelBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.colors.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: llmService.currentModelType.iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(theme.colors.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(loc["current_model_active"])
                    .font(.caption)
                    .foregroundColor(theme.colors.subtext0)
                Text(llmService.currentModelType.displayName)
                    .font(.headline)
                    .foregroundColor(theme.colors.text)
            }

            Spacer()

            // 状態バッジ
            stateIndicator
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.surface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.colors.blue.opacity(0.25), lineWidth: 1.5)
        )
    }

    private var stateIndicator: some View {
        HStack(spacing: 5) {
            switch llmService.state {
            case .ready:
                Circle().fill(theme.colors.green).frame(width: 7, height: 7)
                Text(loc["in_use"]).font(.caption.weight(.medium)).foregroundColor(theme.colors.green)
            case .generating:
                Circle().fill(theme.colors.peach).frame(width: 7, height: 7)
                Text(loc["state_generating"]).font(.caption.weight(.medium)).foregroundColor(theme.colors.peach)
            case .loading:
                ProgressView().tint(theme.colors.yellow).scaleEffect(0.7)
                Text(loc["state_loading"]).font(.caption.weight(.medium)).foregroundColor(theme.colors.yellow)
            default:
                Circle().fill(theme.colors.overlay0).frame(width: 7, height: 7)
                Text(loc["state_idle"]).font(.caption.weight(.medium)).foregroundColor(theme.colors.overlay0)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.colors.surface1)
        .clipShape(Capsule())
    }

    // MARK: - ローカルモデルセクション

    private func modelSection(title: String, subtitle: String, icon: String, models: [ModelType]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title: title, subtitle: subtitle, icon: icon)

            VStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element) { index, model in
                    localModelRow(model)
                    if index < models.count - 1 {
                        Divider()
                            .padding(.horizontal, 14)
                            .background(theme.colors.surface1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.surface0)
            )
        }
    }

    // MARK: - クラウドセクション（プロバイダーごと）

    @ViewBuilder
    private func cloudSection(provider: APIProvider, accentColor: Color) -> some View {
        let models = LLMService.availableCloudModels.filter { $0.cloudProvider == provider }
        let hasKey = KeychainService.shared.hasAPIKey(for: provider)

        VStack(alignment: .leading, spacing: 8) {
            // プロバイダーヘッダー
            HStack(spacing: 8) {
                Image(systemName: provider.displayIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 26, height: 26)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(theme.colors.subtext0)
                    Text(hasKey ? loc["api_key_set"] : loc["api_key_not_set"])
                        .font(.caption2)
                        .foregroundColor(hasKey ? theme.colors.green : theme.colors.yellow)
                }

                Spacer()

                if !hasKey {
                    // APIキー設定ボタン（未設定の場合のみ表示）
                    Button {
                        showAPIKeySetup = provider
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10))
                            Text(loc["setup_api_key"])
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(theme.colors.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(theme.colors.yellow.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element) { index, model in
                    cloudModelRow(model: model, hasKey: hasKey, accentColor: accentColor)
                    if index < models.count - 1 {
                        Divider()
                            .padding(.horizontal, 14)
                            .background(theme.colors.surface1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.surface0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(hasKey ? accentColor.opacity(0.15) : Color.clear, lineWidth: 1)
            )
        }
    }

    // MARK: - ローカルモデル行

    @ViewBuilder
    private func localModelRow(_ model: ModelType) -> some View {
        let isActive = isModelActive(model)
        let isSwitchingThis = isSwitching && switchingModel == model
        let memStatus = LLMService.memoryStatus(for: model)

        HStack(spacing: 12) {
            // アイコン
            ZStack {
                Circle()
                    .fill(isActive ? theme.colors.green.opacity(0.15) : theme.colors.surface1)
                    .frame(width: 38, height: 38)
                Image(systemName: model.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isActive ? theme.colors.green : theme.colors.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.colors.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(model.fileSize)
                        .font(.caption2)
                        .foregroundColor(theme.colors.subtext0)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(theme.colors.overlay0)
                    memBadgeText(memStatus, for: model)
                }
            }

            Spacer()

            // 右側
            if isSwitchingThis {
                ProgressView().tint(theme.colors.green).scaleEffect(0.85)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(theme.colors.green)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.colors.overlay0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(isActive ? theme.colors.green.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isActive && !isSwitching else { return }
            switchTo(model)
        }
    }

    // MARK: - クラウドモデル行

    @ViewBuilder
    private func cloudModelRow(model: ModelType, hasKey: Bool, accentColor: Color) -> some View {
        let isActive = isModelActive(model)
        let isSwitchingThis = isSwitching && switchingModel == model
        let canUse = hasKey

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? accentColor.opacity(0.15) : theme.colors.surface1)
                    .frame(width: 36, height: 36)
                Image(systemName: model.iconName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isActive ? accentColor : (canUse ? theme.colors.subtext1 : theme.colors.overlay0))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(canUse ? theme.colors.text : theme.colors.overlay0)
                    .lineLimit(1)
                Text(model.descriptionText)
                    .font(.caption2)
                    .foregroundColor(theme.colors.subtext0)
            }

            Spacer()

            if isSwitchingThis {
                ProgressView().tint(accentColor).scaleEffect(0.85)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(accentColor)
            } else if !canUse {
                Text(loc["api_key_needed"])
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.colors.yellow)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(theme.colors.yellow.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.colors.overlay0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(isActive ? accentColor.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canUse && !isActive && !isSwitching else { return }
            switchTo(model)
        }
        .opacity(canUse ? 1.0 : 0.7)
    }

    // MARK: - Helpers

    private func sectionLabel(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.colors.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.colors.subtext0)
                    .textCase(nil)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(theme.colors.overlay0)
            }
        }
        .padding(.leading, 4)
    }

    private func memBadgeText(_ status: LLMService.MemoryStatus, for model: ModelType) -> some View {
        if model.isBeta {
            return Text(loc["badge_beta"])
                .font(.caption2.weight(.semibold))
                .foregroundColor(theme.colors.yellow)
        }
        let (text, color): (String, Color) = {
            switch status {
            case .optimal: return (loc["mem_optimal"], theme.colors.green)
            case .usable:  return (loc["mem_usable"],  theme.colors.yellow)
            case .tight:   return (loc["mem_tight"],   theme.colors.peach)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(color)
    }

    private func isModelActive(_ model: ModelType) -> Bool {
        switch llmService.state {
        case .ready, .generating, .paused:
            return llmService.currentModelType == model
        default:
            return false
        }
    }

    private func switchTo(_ model: ModelType) {
        isSwitching = true
        switchingModel = model
        Task {
            await llmService.switchModel(to: model)
            isSwitching = false
            switchingModel = nil
            // 切り替え成功したらシートを閉じる
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - Preview

#Preview {
    QuickModelPickerView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(LLMService.shared)
        .environmentObject(LocalizationService.shared)
}
