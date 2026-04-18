// ModelManagementView.swift
// Memoria for iPhone - Phase 6: ローカル + クラウドモデル統合管理画面

import SwiftUI
import Network

// MARK: - ModelManagementView

struct ModelManagementView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var loc: LocalizationService

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
                    sectionHeader(title: loc["local_models"], icon: "iphone", subtitle: loc["local_models_sub"])
                    localModelsSection

                    // クラウドモデルセクション
                    sectionHeader(title: loc["cloud_models"], icon: "cloud", subtitle: loc["cloud_models_sub"])
                    cloudModelsSection

                    // 下部情報
                    bottomInfoSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(theme.colors.base.ignoresSafeArea())
            .navigationTitle(loc["model_mgmt_title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.mantle, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                loc["unload_confirm_title"],
                isPresented: $showUnloadConfirm,
                titleVisibility: .visible
            ) {
                Button(loc["unload_confirm_action"], role: .destructive) {
                    llmService.unloadModel()
                }
                Button(loc["cancel"], role: .cancel) {}
            } message: {
                Text(loc["unload_confirm_msg"])
            }
            .sheet(item: $apiKeySetupProvider) { provider in
                APIKeySetupView(provider: provider)
                    .environmentObject(theme)
                    .environmentObject(loc)
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
            Text(loc["current_model_header"])
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
                statusPill(text: loc["in_use"], color: theme.colors.green, icon: "checkmark.circle.fill")
            case .downloading(let progress):
                Text(llmService.currentModelType.displayName)
                    .font(.headline).foregroundColor(theme.colors.text)
                statusPill(text: "DL \(Int(progress * 100))%", color: theme.colors.peach, icon: "arrow.down.circle")
            case .loading:
                Text(llmService.currentModelType.displayName)
                    .font(.headline).foregroundColor(theme.colors.text)
                statusPill(text: loc["state_loading"], color: theme.colors.yellow, icon: "hourglass")
            case .notLoaded:
                Text(loc["not_selected"])
                    .font(.headline).foregroundColor(theme.colors.subtext0)
                statusPill(text: loc["state_not_loaded"], color: theme.colors.overlay0, icon: "minus.circle")
            case .error(let msg):
                Text(loc["error_occurred"])
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
                Text(loc["offline_warning_title"])
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.colors.yellow)
                Text(loc["offline_warning_sub"])
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
        let memStatus = LLMService.memoryStatus(for: model)
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
                        .foregroundColor(theme.colors.text)
                    Text(model.descriptionText)
                        .font(.caption)
                        .foregroundColor(theme.colors.subtext1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    // ファイルサイズバッジ
                    Text(model.fileSize)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.colors.mauve)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(theme.colors.mauve.opacity(0.12))
                        .clipShape(Capsule())

                    // メモリ状態バッジ（3段階）or βバッジ
                    memoryStatusBadge(memStatus, for: model)
                }
            }

            // メモリ注意警告（tightのみ表示）
            if memStatus == .tight {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(theme.colors.peach)
                    Text(loc["mem_tight_warning"])
                        .font(.caption2)
                        .foregroundColor(theme.colors.subtext0)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(theme.colors.peach.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // ダウンロード進捗
            if isDownloading, let progress = llmService.downloadProgress {
                downloadProgressView(progress: progress)
            }

            // アクションエリア（全機種でダウンロード・使用可能）
            HStack {
                if isActive {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(theme.colors.green)
                        Text(loc["in_use"]).font(.subheadline.bold()).foregroundColor(theme.colors.green)
                    }
                    Spacer()
                    Button { showUnloadConfirm = true } label: {
                        Label(loc["unload_btn"], systemImage: "stop.circle")
                            .font(.caption.bold())
                            .foregroundColor(theme.colors.red)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(theme.colors.red.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .disabled(isInteractionDisabled)
                } else if isDownloading {
                    HStack(spacing: 6) {
                        ProgressView().tint(theme.colors.peach)
                        Text(loc["downloading"]).font(.subheadline).foregroundColor(theme.colors.peach)
                    }
                    Spacer()
                } else if isSwitchingThis {
                    HStack(spacing: 6) {
                        ProgressView().tint(theme.colors.blue)
                        Text(loc["switching"]).font(.subheadline).foregroundColor(theme.colors.blue)
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
    }

    /// メモリ状態バッジ（βモデルは "β" バッジを表示、それ以外は3段階）
    private func memoryStatusBadge(_ status: LLMService.MemoryStatus, for model: ModelType) -> some View {
        if model.isBeta {
            return AnyView(
                HStack(spacing: 3) {
                    Image(systemName: "flask.fill").font(.system(size: 8))
                    Text(loc["badge_beta"]).font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(theme.colors.yellow)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.colors.yellow.opacity(0.12))
                .clipShape(Capsule())
            )
        }
        let (icon, label, color): (String, String, Color) = {
            switch status {
            case .optimal: return ("checkmark.seal.fill", loc["mem_optimal"], theme.colors.green)
            case .usable:  return ("seal",                loc["mem_usable"],  theme.colors.yellow)
            case .tight:   return ("exclamationmark.triangle.fill", loc["mem_tight"], theme.colors.peach)
            }
        }()
        return AnyView(
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 8))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
        )
    }

    // MARK: - Cloud Models Section

    // MARK: - Web Search Info Banner

    private var webSearchInfoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(theme.colors.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(loc["web_search_banner_title"])
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.colors.text)
                Text(loc["web_search_banner_body"])
                    .font(.caption)
                    .foregroundColor(theme.colors.subtext0)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    webSearchSupportTag(label: "Gemini", supported: true)
                    webSearchSupportTag(label: "Claude", supported: true)
                    webSearchSupportTag(label: "OpenAI", supported: false)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.colors.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.colors.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func webSearchSupportTag(label: String, supported: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: supported ? "checkmark" : "xmark")
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(supported ? theme.colors.green : theme.colors.overlay0)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background((supported ? theme.colors.green : theme.colors.overlay0).opacity(0.12))
        .clipShape(Capsule())
    }

    private var cloudModelsSection: some View {
        VStack(spacing: 12) {
            // Web検索対応状況バナー
            webSearchInfoBanner

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
                        Text(loc["api_key_not_set"])
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
                        Text(hasKey ? loc["api_key_change"] : loc["api_key_setup"])
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

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(canUse ? theme.colors.text : theme.colors.subtext0)
                Text(model.descriptionText)
                    .font(.caption)
                    .foregroundColor(theme.colors.subtext1)
                // Web検索対応バッジ
                if model.supportsWebSearch {
                    HStack(spacing: 3) {
                        Image(systemName: "globe")
                            .font(.system(size: 8, weight: .semibold))
                        Text(loc["web_search_badge"])
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(theme.colors.blue)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(theme.colors.blue.opacity(0.10))
                    .clipShape(Capsule())
                }
            }

            Spacer()

            // 使用中 or ボタン
            if isActive {
                statusPill(text: loc["in_use"], color: accentColor, icon: "checkmark.circle.fill")
            } else if isSwitchingThis {
                ProgressView().tint(accentColor).scaleEffect(0.8)
            } else if !hasKey {
                Text(loc["key_required"])
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.colors.yellow)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.colors.yellow.opacity(0.1))
                    .clipShape(Capsule())
            } else if !isOnline {
                Text(loc["offline"])
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.colors.overlay0)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.colors.overlay0.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Button { switchToModel(model) } label: {
                    Text(loc["use_btn"])
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
            infoRow(icon: "wifi", text: loc["info_wifi"])
            infoRow(icon: "key.shield", text: loc["info_keychain"])
            infoRow(icon: "memorychip", text: String(format: loc["device_memory"], String(format: "%.1f", totalGB)))
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

    private func isModelFileDownloaded(_ model: ModelType) -> Bool {
        guard !model.ggufFilename.isEmpty else { return false }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return FileManager.default.fileExists(atPath: docs.appendingPathComponent(model.ggufFilename).path)
    }

    private func localActionLabel(_ model: ModelType) -> String {
        switch llmService.state {
        case .ready, .generating, .paused: return loc["switch_btn"]
        default:
            return isModelFileDownloaded(model) ? loc["use_model"] : loc["download_btn"]
        }
    }

    private func localActionIcon(_ model: ModelType) -> String {
        switch llmService.state {
        case .ready, .generating, .paused: return "arrow.triangle.2.circlepath"
        default:
            return isModelFileDownloaded(model) ? "play.circle.fill" : "arrow.down.circle"
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
        .environmentObject(LocalizationService.shared)
}
