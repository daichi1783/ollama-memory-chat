// ContentView.swift
// Memoria for iPhone - Main Content View
// モデル未ロード時は読み込み画面、ロード済みならチャット画面を表示

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @StateObject private var llmService = LLMService.shared
    @StateObject private var chatService = ChatService()
    /// システムカラースキームの監視（Follow System Theme用）
    @Environment(\.colorScheme) private var colorScheme
    /// モデルが一度でもreadyになったかを追跡（NavigationStack破棄を防止）
    @State private var hasLoadedOnce = false
    /// NavigationStackのパス（@Stateで管理することでSwiftUIの最も信頼性の高いバインディングを使用）
    @State private var navigationPath = NavigationPath()

    var body: some View {
        // NavigationStackを常にZStackの底レイヤーとして保持する
        // → if/else 分岐による NavigationStack の破棄・再生成がナビゲーション破壊の原因だったため廃止
        ZStack {
            // NavigationStack は常に生きている（モデル読み込み中も）
            mainSplitView

            // モデル未ロード時はオーバーレイで隠す（NavigationStackは壊さない）
            if !hasLoadedOnce {
                Group {
                    switch llmService.state {
                    case .notLoaded, .downloading, .loading:
                        ModelLoadingView()
                    case .error(let message):
                        ErrorView(message: message) {
                            Task { await llmService.loadModel() }
                        }
                    default:
                        // ready/generating になったら即座にhasLoadedOnce = true → このオーバーレイ消える
                        Color.clear
                    }
                }
                .ignoresSafeArea()
                .zIndex(10)
            }

            // モデルロード後のエラーはバナーで通知
            if hasLoadedOnce, case .error(let message) = llmService.state {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(theme.colors.peach)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(theme.colors.text)
                            .lineLimit(2)
                        Spacer()
                        Button(loc["reload"]) {
                            Task { await llmService.loadModel() }
                        }
                        .font(.caption.bold())
                        .foregroundColor(theme.colors.blue)
                    }
                    .padding(12)
                    .background(theme.colors.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .zIndex(5)
            }
        }
        .onAppear {
            // アプリ起動時にシステムテーマを即時反映
            theme.applySystemColorScheme(colorScheme)
        }
        .onChange(of: colorScheme) { _, newScheme in
            // システムのダーク/ライト切り替えをThemeManagerに伝達
            theme.applySystemColorScheme(newScheme)
        }
        .task {
            if llmService.state == .notLoaded {
                await llmService.loadModel(type: .gemma3_1b)
            }
        }
        .onChange(of: llmService.state) { _, newState in
            if case .ready = newState {
                hasLoadedOnce = true
            } else if case .generating = newState {
                hasLoadedOnce = true
            }
        }
    }

    // MARK: - NavigationStack（データ駆動ナビゲーション）

    private var mainSplitView: some View {
        // navigationPathをContentViewの@Stateとして管理する
        // → NavigationLink(value:)がネイティブにパスを操作できる最も信頼性の高い方法
        NavigationStack(path: $navigationPath) {
            SessionListView()
                .environmentObject(chatService)
                .environmentObject(llmService)
                .navigationTitle(loc["app_name"])
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(theme.colors.surface0, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // セッションID（Int64）で画面遷移を管理
                .navigationDestination(for: Int64.self) { sessionId in
                    ChatView()
                        .environmentObject(chatService)
                        .environmentObject(llmService)
                        .environmentObject(theme)
                        .environmentObject(loc)
                }
        }
        .tint(theme.colors.blue)
        // createNewSession() / selectSession() が pendingNavigationId をセットしたら即ナビゲーション
        // NOTE: append() ではなく「パスを丸ごと置き換え」にすることで
        //       スタック蓄積バグ（同一 ChatView が複数 push されて Back を何度も押す必要がある）を防止
        .onChange(of: chatService.pendingNavigationId) { _, newId in
            if let id = newId {
                var newPath = NavigationPath()
                newPath.append(id)
                navigationPath = newPath
                // シグナルをリセット（重複ナビゲーション防止）
                chatService.pendingNavigationId = nil
            }
        }
    }

}

// MARK: - Model Loading View（モデル読み込み画面）

struct ModelLoadingView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @StateObject private var llmService = LLMService.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // ロゴ（Orbital風）
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [theme.colors.blue, theme.colors.mauve],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(15))

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [theme.colors.mauve, theme.colors.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-30))

                Circle()
                    .fill(theme.colors.blue)
                    .frame(width: 12, height: 12)
            }

            Text(loc["app_name"])
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(theme.colors.text)

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.blue))
                    .scaleEffect(1.2)

                Text(loc["model_loading"])
                    .font(.subheadline)
                    .foregroundColor(theme.colors.subtext0)

                Text(loc["first_download_wifi"])
                    .font(.caption)
                    .foregroundColor(theme.colors.overlay0)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.base)
    }
}

// MARK: - Error View

struct ErrorView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(theme.colors.red)

            Text(loc["error_occurred"])
                .font(.title2.bold())
                .foregroundColor(theme.colors.text)

            Text(message)
                .font(.body)
                .foregroundColor(theme.colors.subtext0)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onRetry) {
                Label(loc["retry"], systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(theme.colors.base)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(theme.colors.blue)
                    .cornerRadius(12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.base)
    }
}

// MARK: - Color Extension (Catppuccin Hex Support)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationService.shared)
}
