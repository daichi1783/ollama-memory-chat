// ModelManagementView.swift
// Memoria for iPhone - Phase 6: ローカル + クラウドモデル統合管理画面

import SwiftUI
import Network

// MARK: - ModelManagementView

struct ModelManagementView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var llmService: LLMService

    @State private var isSwitching = false
    @State private var switchTargetModel: ModelType?
    @State private var showUnloadConfirm = false
    @State private var apiKeySetupProvider: APIProvider? = nil
    @State private var isOnline = true

    private var isInteractionDisabled: Bool {
        switch llmService.state {
        case .downloading, .loading: return true
        default: return isSwitching
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 現在のモデルステータスヘッダー
                    headerSection

                    // オフライン警告
                    if !isOnline {
                        offlineWarningBanner
                    }

                    // ローカルモデルセクション
                    sectionHeader(title: "ローカルモデル", icon: "iphone", subtitle: "オフライン動作・プライバシー保護")
                    localModelsSection

                    // クラウドモデルセクション
                    sectionHeader(title: "クラウドモデル", icon: "cloud", subtitle: "高性能・要インターネット接続")
                    cloudModelsSection

                    // 下部情報
                    bottomInfoSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(theme.colors.base.ignoresSafeArea())
            .navigationTitle("モデル管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.mantle, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "モデルをアンロードしますか？",
                isPresented: $showUnloadConfirm,
                titleVisibility: .visible
            ) {
                Button("アンロード", role: .destructive) {
                    llmService.unloadModel()
                }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(item: $apiKeySetupProvider) { provider in
                APIKeySetupView(provider: provider)
                    .environmentObject(theme)
            }
            .task {
                await monitorNetworkPath()
            }
        }
    }

    // MARK: - Network Monitoring

    private func monitorNetworkPath() async {
        let monitor = NWPathMonitor()
        let stream = AsyncStream<Bool> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "com.memoria.netmonitor"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
        for await online in stream {
            isOnline = online
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 16) {
            memoryGauge
            currentModelInfo
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.colors.surface0)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private var memoryGauge: some View {
        let usage = llmService.memoryUsageMB
        let totalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
        let fraction = min(usage / totalMB, 1.0)
        let gaugeColor = fraction < 0.6
            ? theme.colors.green
            : (fraction < 0.85 ? theme.colors.yellow : theme.colors.red)

        return ZStack {
            Circle().stroke(theme.colors.surface1, lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Image(systemName: "memorychip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(gaugeColor)
                Text("\(Int(usage))MB")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.colors.text)
            }
        }
        .frame(width: 66, height: 66)
    }

    private var currentModelInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("現在のモデル")
                .font(.caption)
                .foregroundColor(theme.colors.subtext1)

            switch llmService.state {
            case .ready, .generating, .paused:
                HStack(spacing: 6) {
                    Text(llmService.currentModelType.displayName)
                        .font(.headline)
                        .foregroundColor(theme.colors.text)
                        .lineLimit(1)
                }
                statusPill(text: "使用中", color: theme.colors.green, icon: "checkmark.circle.fill")
            case .downloading(let progress):
                Text(llmService.currentModelType.displayName)
                    .font(.headline).foregroundColor(theme.colors.text)
                statusPill(text: "DL \(Int(progress * 100))%", color: theme.colors.peach, icon: "arrow.down.circle")
            case .loading:
                Text(llmService.currentModelType.displayName)
                    .font(.headline).foregroundColor(theme.colors.text)
                statusPill(text: "読み込み中...", color: theme.colors.yellow, icon: "hourglass")
            case .notLoaded:
                Text("未選択")
                    .font(.headline).foregroundColor(theme.colors.subtext0)
                statusPill(text: "未ロード", color: theme.colors.overlay0, icon: "minus.circle")
            case .error(let msg):
                Text("エラー")
                    .font(.headline).foregroundColor(theme.colors.red)
                Text(msg).font(.caption2).foregroundColor(theme.colors.red).lineLimit(2)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.colors.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(theme.colors.text)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(theme.colors.subtext0)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Offline Warning

    private var offlineWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundColor(theme.colors.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("オフライン")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.colors.yellow)
                Text("クラウドモデルにはインターネット接続が必要です")
                    .font(.caption)
                    .foregroundColor(theme.colors.subtext0)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.colors.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Local Models Section

    private var localModelsSection: some View {
        VStack(spacing: 12) {
            ForEach(LLMService.availableLocalModels, id: \.self) { model in
                localModelCard(for: model)
            }
        }
    }

    @ViewBuilder
    private func localModelCard(for model: ModelType) -> some View {
        let isActive = isModelActive(model)
        let hasMemory = LLMService.hasEnoughMemory(for: model)
        let isDownloading = isModelDownloading(model)
        let isSwitchingThis = isSwitching && switchTargetModel == model

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                // モデルアイコン
                ZStack {
                    Circle()
                        .fill(isActive ? theme.colors.green.opacity(0.15) : theme.colors.surface1)
                        .frame(width: 40, height: 40)
                    Image(systemName: model.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isActive ? theme.colors.green : theme.colors.blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(hasMemory ? theme.colors.text : theme.colors.subtext0)
                    Text(model.descriptionText)
                        .font(.caption)
                        .foregroundColor(theme.colors.subtext1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.fileSize)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.colors.mauve)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(theme.colors.mauve.opacity(0.12))
                        .clipShape(Capsule())

                    HStack(spacing: 3) {
                        Image(systemName: hasMemory ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .font(.system(size: 8))
                        Text(hasMemory ? "対応" : "非対応")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(hasMemory ? theme.colors.green : theme.colors.red)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((hasMemory ? theme.colors.green : theme.colors.red).opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // ダウンロード進捗
            if isDownloading, let progress = llmService.downloadProgress {
                downloadProgressView(progress: progress)
            }

            // アクションエリア
            HStack {
                if isActive {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(theme.colors.green)
                        Text("使用中").font(.subheadline.bold()).foregroundColor(theme.colors.green)
                    }
                    Spacer()
                    Button { showUnloadConfirm = true } label: {
                        Label("アンロード", systemImage: "eject.fill")
                            .font(.caption.bold())
                            .foregroundColor(theme.colors.red)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(theme.colors.red.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .disabled(isInteractionDisabled)
                } else if !hasMemory {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(theme.colors.overlay0)
                        Text("メモリ不足").font(.subheadline.bold()).foregroundColor(theme.colors.overlay0)
                    }
                    Spacer()
                } else if isDownloading {
                    HStack(spacing: 6) {
                        ProgressView().tint(theme.colors.peach)
                        Text("ダウンロード中...").font(.subheadline).foregroundColor(theme.colors.peach)
                    }
                    Spacer()
                } else if isSwitchingThis {
                    HStack(spacing: 6) {
                        ProgressView().tint(theme.colors.blue)
                        Text("切替中...").font(.subheadline).foregroundColor(theme.colors.blue)
                    }
                    Spacer()
                } else {
                    Spacer()
                    Button { switchToModel(model) } label: {
                        Label(localActionLabel(model), systemImage: localActionIcon(model))
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(theme.colors.blue)
                            .clipShape(Capsule())
                    }
                    .disabled(isInteractionDisabled)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? theme.colors.green.opacity(0.06) : theme.colors.surface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? theme.colors.green.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)
        .opacity(hasMemory ? 1.0 : 0.55)
    }

    // MARK: - Cloud Models Section

    private var cloudModelsSection: some View {
        VStack(spacing: 12) {
            // Geminiグループ
            cloudProviderGroup(
                provider: .gemini,
                models: LLMService.availableCloudModels.filter { $0.cloudProvider == .gemini },
                accentColor: theme.colors.blue
            )
            // Claudeグループ
            cloudProviderGroup(
                provider: .claude,
                models: LLMService.availableCloudModels.filter { $0.cloudProvider == .claude },
                accentColor: theme.colors.mauve
            )
            // OpenAIグループ
            cloudProviderGroup(
                provider: .openai,
                models: LLMService.availableCloudModels.filter { $0.cloudProvider == .openai },
                accentColor: theme.colors.teal
            )
        }
    }

    @ViewBuilder
    private func cloudProviderGroup(provider: APIProvider, models: [ModelType], accentColor: Color) -> some View {
        let hasKey = KeychainService.shared.hasAPIKey(for: provider)
        let masked = KeychainService.shared.maskedKey(for: provider)

        VStack(alignment: .leading, spacing: 0) {
            // プロバイダーヘッダー行
            HStack(spacing: 10) {
                Image(systemName: provider.displayIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 28, height: 28)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.colors.text)
                    if let masked = masked {
                        Text(masked)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(theme.colors.subtext0)
                    } else {
                        Text("APIキー未設定")
                            .font(.caption)
                            .foregroundColor(theme.colors.yellow)
                    }
                }

                Spacer()

                // APIキー設定ボタン
                Button {
                    apiKeySetupProvider = provider
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasKey ? "key.fill" : "key")
                            .font(.system(size: 11))
                        Text(hasKey ? "変更" : "設定")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(hasKey ? accentColor : theme.colors.yellow)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background((hasKey ? accentColor : theme.colors.yellow).opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            Divider()
                .background(theme.colors.surface1)
                .padding(.horizontal, 14)

            // モデルカード（プロバイダー内）
            VStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element) { index, model in
                    cloudModelRow(model: model, provider: provider, hasKey: hasKey, accentColor: accentColor)
                    if index < models.count - 1 {
                        Divider()
                            .background(theme.colors.surface1)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.colors.surface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(hasKey ? 0.2 : 0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)
        .opacity((!isOnline && hasKey) ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func cloudModelRow(model: ModelType, provider: APIProvider, hasKey: Bool, accentColor: Color) -> some View {
        let isActive = isModelActive(model)
        let isSwitchingThis = isSwitching && switchTargetModel == model
        let canUse = hasKey && isOnline

        HStack(spacing: 12) {
            // モデルアイコン
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? accentColor.opacity(0.15) : theme.colors.surface1)
                    .frame(width: 34, height: 34)
                Image(systemName: model.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isActive ? accentColor : theme.colors.subtext0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(canUse ? theme.colors.text : theme.colors.subtext0)
                Text(model.descriptionText)
                    .font(.caption)
                    .foregroundColor(theme.colors.subtext1)
            }

            Spacer()

            // 使用中 or ボタン
            if isActive {
                statusPill(text: "使用中", color: accentColor, icon: "checkmark.circle.fill")
            } else if isSwitchingThis {
                ProgressView().tint(accentColor).scaleEffect(0.8)
            } else if !hasKey {
                Text("要設定")
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.colors.yellow)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.colors.yellow.opacity(0.1))
                    .clipShape(Capsule())
            } else if !isOnline {
                Text("オフライン")
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.colors.overlay0)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.colors.overlay0.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Button { switchToModel(model) } label: {
                    Text("使用")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(accentColor)
                        .clipShape(Capsule())
                }
                .disabled(isInteractionDisabled)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(isActive ? accentColor.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if canUse && !isActive && !isInteractionDisabled {
                switchToModel(model)
            }
        }
    }

    // MARK: - Bottom Info Section

    private var bottomInfoSection: some View {
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

        return VStack(spacing: 10) {
            infoRow(icon: "wifi", text: "ローカルモデルは初回のみWi-Fiでダウンロードが必要です")
            infoRow(icon: "key.shield", text: "APIキーはiPhone内のKeychainに暗号化保存されます")
            infoRow(icon: "memorychip", text: "このデバイスのメモリ: \(String(format: "%.1f", totalGB)) GB")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.colors.mantle)
        )
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(theme.colors.subtext0)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(theme.colors.subtext0)
            Spacer()
        }
    }

    // MARK: - Shared Components

    private func statusPill(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func downloadProgressView(progress: DownloadProgress) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.colors.surface1)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.colors.peach)
                        .frame(width: geo.size.width * progress.progress)
                        .animation(.easeInOut(duration: 0.3), value: progress.progress)
                }
            }
            .frame(height: 5)
            HStack {
                Text(progress.percentString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.colors.peach)
                Spacer()
                if let sizeStr = progress.sizeString {
                    Text(sizeStr)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.colors.subtext0)
                }
            }
        }
    }

    // MARK: - Helpers

    private func isModelActive(_ model: ModelType) -> Bool {
        switch llmService.state {
        case .ready, .generating, .paused:
            return llmService.currentModelType == model
        default:
            return false
        }
    }

    private func isModelDownloading(_ model: ModelType) -> Bool {
        if case .downloading = llmService.state, llmService.currentModelType == model { return true }
        return false
    }

    private func localActionLabel(_ model: ModelType) -> String {
        switch llmService.state {
        case .ready, .generating, .paused: return "切り替え"
        default: return "ダウンロード"
        }
    }

    private func localActionIcon(_ model: ModelType) -> String {
        switch llmService.state {
        case .ready, .generating, .paused: return "arrow.triangle.2.circlepath"
        default: return "arrow.down.circle"
        }
    }

    private func switchToModel(_ model: ModelType) {
        isSwitching = true
        switchTargetModel = model
        Task {
            await llmService.switchModel(to: model)
            isSwitching = false
            switchTargetModel = nil
        }
    }
}

// MARK: - APIProvider: Identifiable (for .sheet(item:))

extension APIProvider: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Preview

#Preview {
    ModelManagementView()
        .environmentObject(LLMService.shared)
        .environmentObject(ThemeManager.shared)
}
