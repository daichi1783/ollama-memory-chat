// ChatView.swift
// Memoria for iPhone - Main Chat Interface
// ThemeManager対応 / iMessage-style Bubbles / Markdown / Haptics / Animations
// テキスト部分選択: .textSelection(.enabled) 使用（.contextMenu 不使用）

import SwiftUI
import UIKit
import Speech
import AVFoundation
import Combine

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var llmService: LLMService
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @StateObject private var voiceService = VoiceInputService.shared
    @ObservedObject private var cloudService = CloudLLMService.shared
    @State private var inputText = ""
    @State private var showCommandSuggestions = false
    @State private var sendButtonScale: CGFloat = 1.0
    @State private var showVoicePermissionAlert = false
    @State private var showVoiceLanguagePicker = false
    @State private var micPulse = false
    @FocusState private var isInputFocused: Bool
    @State private var showModelPicker = false
    @State private var showCommandManagement = false
    @State private var userCommands: [UserCommand] = []
    /// ナビゲーションバーに表示するセッションタイトル
    @State private var sessionTitle: String = ""
    private let db = DatabaseService.shared

    // Placeholder animation
    @State private var placeholderIndex = 0
    @State private var placeholderOpacity: Double = 1.0
    @State private var placeholderTimer: Timer?

    private func placeholderTexts() -> [String] {
        [loc["placeholder_message"], loc["placeholder_command"], loc["placeholder_ask"]]
    }

    var body: some View {
        VStack(spacing: 0) {
            // ⑧ オフラインバナー: クラウドモデル使用中かつオフライン時のみ表示
            if llmService.currentModelType.isCloud && !cloudService.isNetworkAvailable {
                offlineBanner
            }

            messageList

            // ⑩ 録音中バナー
            if voiceService.state == .listening {
                recordingBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showCommandSuggestions {
                commandSuggestions
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            inputArea
        }
        .background(theme.colors.base)
        .navigationTitle(sessionTitle.isEmpty ? loc["app_name"] : sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.mantle, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            // 左上: コマンド管理ショートカット
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showCommandManagement = true
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(theme.colors.blue)
                }
            }
            // 右上: モデル切り替えバッジ
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showModelPicker = true
                } label: {
                    modelStatusBadge
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            QuickModelPickerView()
                .environmentObject(theme)
                .environmentObject(llmService)
                .environmentObject(loc)
        }
        .sheet(isPresented: $showCommandManagement, onDismiss: loadUserCommands) {
            NavigationStack {
                UserCommandManagementView()
                    .environmentObject(theme)
                    .environmentObject(loc)
            }
            .preferredColorScheme(theme.preferredColorScheme)
        }
        // ③ APIキー未設定時の設定画面誘導シート
        .sheet(item: $chatService.needsAPIKeySetupFor) { provider in
            APIKeySetupView(provider: provider)
                .environmentObject(theme)
                .environmentObject(loc)
        }
        .onAppear {
            startPlaceholderRotation()
            loadUserCommands()
            loadSessionTitle()
        }
        // セッション切り替え時にタイトルを更新
        .onChange(of: chatService.currentSessionId) { _, _ in
            loadSessionTitle()
        }
        // 自動タイトル設定（最初のメッセージ送信後）に追従
        .onChange(of: chatService.messages.count) { _, _ in
            loadSessionTitle()
        }
        .onDisappear {
            placeholderTimer?.invalidate()
            placeholderTimer = nil
        }
        .onChange(of: voiceService.transcribedText) { _, newText in
            if !newText.isEmpty {
                inputText = newText
            }
        }
        .onChange(of: voiceService.state) { _, newState in
            if newState == .idle && !inputText.isEmpty {
                isInputFocused = true
            }
        }
        .alert(loc["voice_permission_title"], isPresented: $showVoicePermissionAlert) {
            Button(loc["open_settings"]) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(loc["cancel"], role: .cancel) {}
        } message: {
            Text(loc["voice_permission_msg"])
        }
    }

    // ⑧ オフラインバナー
    private var offlineBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text(loc["offline_cloud_banner"])
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(theme.colors.red.opacity(0.85))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: cloudService.isNetworkAvailable)
    }

    // ⑩ 録音中バナー
    private var recordingBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(micPulse ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: micPulse)
            Text(loc["recording_label"])
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.colors.text)
            Spacer()
            Text(loc["tap_to_stop"])
                .font(.system(size: 11))
                .foregroundColor(theme.colors.subtext0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.colors.surface1)
        .overlay(
            Rectangle()
                .fill(Color.red.opacity(0.4))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Session Title

    private func loadSessionTitle() {
        guard let sessionId = chatService.currentSessionId else {
            sessionTitle = ""
            return
        }
        if let session = try? db.getSession(id: sessionId) {
            sessionTitle = session.title
        }
    }

    // MARK: - Placeholder Rotation

    private func loadUserCommands() {
        userCommands = (try? db.getAllUserCommands()) ?? []
    }

    private func startPlaceholderRotation() {
        let texts = placeholderTexts()
        // タイマーを @State に保存し、onDisappear で確実に無効化する（リーク防止）
        placeholderTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                placeholderOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                placeholderIndex = (placeholderIndex + 1) % texts.count
                withAnimation(.easeInOut(duration: 0.4)) {
                    placeholderOpacity = 1
                }
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if chatService.messages.isEmpty {
                        emptyState
                    }

                    ForEach(chatService.messages) { message in
                        MessageBubbleView(
                            message: message,
                            highlightKeyword: chatService.highlightKeyword
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            // 通常の末尾スクロール: 新規メッセージ追加時（送受信中）
            .onChange(of: chatService.messages.count) { _, _ in
                guard chatService.highlightKeyword == nil || chatService.highlightKeyword!.isEmpty else { return }
                if let lastMessage = chatService.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            // ストリーミング中の末尾追従
            .onChange(of: chatService.messages.last?.content) { _, _ in
                if let lastMessage = chatService.messages.last, lastMessage.isStreaming {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            // 検索キーワードスクロール: セッションが切り替わった時にキーワード一致位置へ移動
            // NOTE: messages.count ではなく currentSessionId を使う理由:
            //       同じ件数のセッション間を移動した場合 count の onChange が発火しないため
            .onChange(of: chatService.currentSessionId) { _, _ in
                guard let keyword = chatService.highlightKeyword, !keyword.isEmpty else { return }
                // loadSession は同期処理なのでここに来た時点でmessagesは更新済み
                // ただしSwiftUIのレンダリング完了を待つため少し遅延させる
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if let match = chatService.messages.first(where: {
                        $0.content.localizedCaseInsensitiveContains(keyword)
                    }) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            proxy.scrollTo(match.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 80)

            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [theme.colors.blue, theme.colors.mauve],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.colors.blue, theme.colors.mauve],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }

            Text(loc["chat_start"])
                .font(.title3.weight(.semibold))
                .foregroundColor(theme.colors.text)

            Text(loc["chat_empty_sub"])
                .font(.subheadline)
                .foregroundColor(theme.colors.subtext0.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.colors.surface1.opacity(0.5))
                .frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 8) {
                voiceMicButton

                // コマンド呼び出しボタン
                commandTriggerButton

                ZStack(alignment: .leading) {
                    let texts = placeholderTexts()
                    if inputText.isEmpty {
                        Text(texts[placeholderIndex])
                            .font(.body)
                            .foregroundColor(theme.colors.subtext0.opacity(0.5))
                            .opacity(placeholderOpacity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $inputText, axis: .vertical)
                        .lineLimit(1...6)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(theme.colors.text)
                        .focused($isInputFocused)
                        .onChange(of: inputText) { _, newValue in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCommandSuggestions = newValue.hasPrefix("/") && !newValue.contains(" ")
                            }
                        }
                }
                .background(theme.colors.surface0)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    if chatService.isGenerating {
                        // BUG-4修正: 停止ボタンで LLMService.stopGeneration() を呼ぶ
                        llmService.stopGeneration()
                    } else {
                        sendMessage()
                    }
                } label: {
                    Image(systemName: chatService.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(
                            canSend
                            ? theme.colors.blue
                            : theme.colors.subtext0.opacity(0.25)
                        )
                        .scaleEffect(sendButtonScale)
                }
                .disabled(!canSend)
                .sensoryFeedback(.impact(weight: .medium), trigger: chatService.messages.count)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.colors.mantle)
        }
    }

    // MARK: - Voice Mic Button

    private var voiceMicButton: some View {
        Button {
            Task {
                let speechAuth = SFSpeechRecognizer.authorizationStatus()
                let micAuth = AVAudioApplication.shared.recordPermission

                if speechAuth == .denied || micAuth == .denied {
                    showVoicePermissionAlert = true
                    return
                }

                // 録音中なら即停止、アイドル時は言語選択シートを表示
                if voiceService.state == .listening {
                    voiceService.stopListening()
                } else {
                    showVoiceLanguagePicker = true
                }

                if case .error = voiceService.state {
                    showVoicePermissionAlert = true
                }
            }
        } label: {
            ZStack {
                if voiceService.state == .listening {
                    Circle()
                        .fill(theme.colors.red.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .scaleEffect(micPulse ? 1.4 : 1.0)
                        .opacity(micPulse ? 0.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: micPulse
                        )

                    Circle()
                        .fill(theme.colors.red)
                        .frame(width: 36, height: 36)
                }

                Group {
                    switch voiceService.state {
                    case .idle, .requesting:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(theme.colors.subtext0)
                    case .listening:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    case .processing:
                        ProgressView()
                            .tint(theme.colors.subtext0)
                            .scaleEffect(0.8)
                    case .error:
                        Image(systemName: "mic.slash")
                            .font(.system(size: 20))
                            .foregroundColor(theme.colors.red)
                    }
                }
            }
            .frame(width: 36, height: 36)
        }
        .onChange(of: voiceService.state) { _, newState in
            micPulse = newState == .listening
        }
        .sensoryFeedback(.impact(weight: .light), trigger: voiceService.state == .listening)
        .confirmationDialog("音声入力の言語を選択", isPresented: $showVoiceLanguagePicker, titleVisibility: .visible) {
            Button("🇯🇵 日本語") {
                Task {
                    voiceService.setLanguage(Locale(identifier: "ja-JP"))
                    await voiceService.startListening()
                }
            }
            Button("🇺🇸 English") {
                Task {
                    voiceService.setLanguage(Locale(identifier: "en-US"))
                    await voiceService.startListening()
                }
            }
            Button("🇪🇸 Español") {
                Task {
                    voiceService.setLanguage(Locale(identifier: "es-ES"))
                    await voiceService.startListening()
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // MARK: - Command Trigger Button（コマンドパネルを開くボタン）

    private var commandTriggerButton: some View {
        Button {
            // "/" をセットしてコマンドパネルを表示
            if inputText.isEmpty || inputText == "/" {
                withAnimation(.easeInOut(duration: 0.2)) {
                    inputText = "/"
                    showCommandSuggestions = true
                }
                isInputFocused = true
            } else {
                // 既に何か入力中なら先頭に "/" を付加してパネルを開く
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCommandSuggestions.toggle()
                }
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(showCommandSuggestions
                          ? theme.colors.blue.opacity(0.18)
                          : theme.colors.surface0)
                    .frame(width: 36, height: 36)

                Text("/")
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundColor(showCommandSuggestions
                                     ? theme.colors.blue
                                     : theme.colors.subtext0)
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isGenerating
    }

    // MARK: - Command Suggestions

    private var commandSuggestions: some View {
        let builtIn: [(String, String, String)] = [
            ("/help",     "questionmark.circle",     loc["cmd_help_desc"]),
            ("/english",  "globe.americas",          loc["cmd_english_desc"]),
            ("/japanese", "globe.asia.australia",    loc["cmd_japanese_desc"]),
            ("/spanish",  "globe.europe.africa",     loc["cmd_spanish_desc"]),
            ("/cal",      "checkmark.circle",        loc["cmd_cal_desc"]),
            ("/grammar",  "character.book.closed",   loc["cmd_grammar_desc"]),
            ("/remember", "brain.head.profile",      loc["cmd_remember_desc"]),
            ("/memory",   "list.bullet.rectangle",   loc["cmd_memory_desc"]),
            ("/clear",    "sparkles",                loc["cmd_clear_desc"]),
        ]
        // ユーザー定義コマンドを結合
        let userDefined: [(String, String, String)] = userCommands.map { cmd in
            ("/\(cmd.name)", "terminal", cmd.commandDescription)
        }
        let commands = builtIn + userDefined

        let filtered = commands.filter { cmd, _, _ in
            inputText.isEmpty || cmd.hasPrefix(inputText.lowercased())
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filtered, id: \.0) { cmd, icon, desc in
                    Button {
                        inputText = cmd + " "
                        showCommandSuggestions = false
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .foregroundColor(theme.colors.mauve)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(cmd)
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                    .foregroundColor(theme.colors.lavender)
                                Text(desc)
                                    .font(.caption2)
                                    .foregroundColor(theme.colors.subtext0)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(theme.colors.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: theme.colors.crust.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                }

                // カスタムコマンド追加ショートカット
                Button {
                    showCommandSuggestions = false
                    showCommandManagement = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundColor(theme.colors.blue)
                        Text("コマンドを追加")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(theme.colors.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.colors.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.colors.blue.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(theme.colors.mantle)
    }

    // MARK: - Model Status Badge（タップでクイック切り替えシートを開く）
    // ⑦ クラウド/ローカルを視覚的に区別し、プロバイダー名を簡潔に表示

    private var modelStatusBadge: some View {
        let isCloud = llmService.currentModelType.isCloud
        let badgeColor = isCloud ? theme.colors.mauve : theme.colors.green

        return HStack(spacing: 5) {
            // ローカル/クラウドアイコン
            Image(systemName: isCloud ? "cloud.fill" : "iphone")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(badgeColor)

            // 状態インジケーター (生成中はアニメーション)
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
                .shadow(color: stateColor.opacity(0.7), radius: 3)

            Text(llmService.currentModelType.displayName)
                .font(.caption2.weight(.medium))
                .foregroundColor(theme.colors.subtext0)

            // 「変更可能」を示すシェブロン
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(theme.colors.overlay0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(badgeColor.opacity(0.08))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.25), lineWidth: 0.8)
        )
    }

    private var stateColor: Color {
        switch llmService.state {
        case .ready:      return theme.colors.green
        case .generating: return theme.colors.peach
        case .loading:    return theme.colors.yellow
        default:          return theme.colors.overlay0
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText
        inputText = ""
        showCommandSuggestions = false

        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            sendButtonScale = 0.8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                sendButtonScale = 1.0
            }
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        Task {
            await chatService.sendMessage(text)
        }
    }
}

// MARK: - Message Bubble View
// ★ .contextMenu を使わない → .textSelection(.enabled) が正しく動作する

struct MessageBubbleView: View {
    @EnvironmentObject var theme: ThemeManager
    let message: ChatMessage
    /// 検索ハイライト用キーワード（一致するバブルに強調リングを表示）
    var highlightKeyword: String? = nil

    private var isUser: Bool { message.role == "user" }

    /// このメッセージが検索キーワードに一致するか
    private var isKeywordMatch: Bool {
        guard let kw = highlightKeyword, !kw.isEmpty else { return false }
        return message.content.localizedCaseInsensitiveContains(kw)
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 6) {
                if isUser { Spacer(minLength: 48) }

                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    // BUG-1修正: .clipShape(BubbleShape) → .cornerRadius(18)
                    // BubbleShape はカスタム Shape で clipShape するとテキスト選択ハンドルが
                    // クリッピング境界に遮断されてロングプレスが機能しなかった。
                    // 標準の cornerRadius に変えることで .textSelection(.enabled) が正常動作する。
                    //
                    // BUG-5修正 (グレードット): content が空 かつ ストリーミング中でない場合、
                    // bubbleContent は高さ0だが padding+background で 28×20 の灰色楕円が出現する。
                    // content が空の時は背景ごと非表示にして、TypingIndicator のみ残す。
                    if !message.content.isEmpty {
                        bubbleContent
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isUser ? theme.colors.mauve : theme.colors.surface0)
                            .cornerRadius(18)
                            .shadow(color: theme.colors.crust.opacity(0.2), radius: 2, x: 0, y: 1)
                            // 検索キーワード一致バブルに強調リングを表示
                            // allowsHitTesting(false): タッチをテキスト選択に通すためオーバーレイはヒットテスト無効化
                            .overlay(
                                Group {
                                    if isKeywordMatch {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(Color.yellow.opacity(0.85), lineWidth: 2.5)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .allowsHitTesting(false)
                            )
                    }

                    // Typing indicator
                    if message.isStreaming && message.content.isEmpty {
                        TypingIndicatorView()
                            .padding(.leading, 4)
                    }
                }

                if !isUser { Spacer(minLength: 48) }
            }

            // Timestamp（常時表示）
            HStack {
                if isUser { Spacer() }
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(theme.colors.subtext0.opacity(0.4))
                    .padding(.horizontal, 16)
                if !isUser { Spacer() }
            }
        }
    }

    // MARK: - Bubble Content

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            // ユーザーメッセージ: UITextView ラッパーで部分選択を確実に実装
            // SwiftUI の Text.textSelection だと全文選択になる場合があるため UITextView を使用
            SelectableTextView(
                text: message.content,
                textColor: UIColor(theme.colors.base),
                font: UIFont.preferredFont(forTextStyle: .body)
            )
        } else {
            // AIメッセージ: Markdown対応 + 部分選択可能
            // NOTE: .textSelection(.enabled) をここ（VStackコンテナ）に付けると
            //       全ブロックが1ユニットとして扱われ全文コピーになる。
            //       MarkdownTextView 内部の各 Text に個別に付けることで
            //       段落単位の部分選択が可能になる。
            MarkdownTextView(
                text: message.content,
                textColor: theme.colors.text,
                codeBackgroundColor: theme.colors.surface1
            )
        }
    }
}

// MARK: - Markdown Text View（SwiftUI Text ベース）

struct MarkdownTextView: View {
    let text: String
    let textColor: Color
    let codeBackgroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .codeBlock(let code, _):
                    codeBlockView(code)
                case .text(let content):
                    // NOTE: VStackコンテナではなく各Textに個別付与することで段落単位の部分選択が可能
                    Text(buildAttributedString(content))
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Code Block

    @ViewBuilder
    private func codeBlockView(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(hex: "a6e3a1"))
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "11111b"))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Attributed String Builder

    private func buildAttributedString(_ input: String) -> AttributedString {
        var result = AttributedString()
        var remaining = input

        while !remaining.isEmpty {
            if let codeMatch = remaining.firstMatch(of: /`([^`]+)`/) {
                let beforeRange = remaining.startIndex..<codeMatch.range.lowerBound
                let before = String(remaining[beforeRange])
                if !before.isEmpty {
                    result.append(parseFormattedText(before))
                }
                var codeAttr = AttributedString(String(codeMatch.1))
                codeAttr.font = .system(.body, design: .monospaced)
                codeAttr.foregroundColor = Color(hex: "a6e3a1")
                codeAttr.backgroundColor = Color(hex: "11111b")
                result.append(codeAttr)
                remaining = String(remaining[codeMatch.range.upperBound...])
            } else {
                result.append(parseFormattedText(remaining))
                break
            }
        }

        return result
    }

    private func parseFormattedText(_ input: String) -> AttributedString {
        var result = AttributedString()
        var remaining = input

        while !remaining.isEmpty {
            if let boldMatch = remaining.firstMatch(of: /\*\*(.+?)\*\*/) {
                let beforeRange = remaining.startIndex..<boldMatch.range.lowerBound
                let before = String(remaining[beforeRange])
                if !before.isEmpty {
                    result.append(parseItalic(before))
                }
                var boldAttr = AttributedString(String(boldMatch.1))
                boldAttr.font = .body.bold()
                boldAttr.foregroundColor = textColor
                result.append(boldAttr)
                remaining = String(remaining[boldMatch.range.upperBound...])
            } else if let italicMatch = remaining.firstMatch(of: /\*(.+?)\*/) {
                let beforeRange = remaining.startIndex..<italicMatch.range.lowerBound
                let before = String(remaining[beforeRange])
                if !before.isEmpty {
                    var plainAttr = AttributedString(before)
                    plainAttr.foregroundColor = textColor
                    result.append(plainAttr)
                }
                var italicAttr = AttributedString(String(italicMatch.1))
                italicAttr.font = .body.italic()
                italicAttr.foregroundColor = textColor
                result.append(italicAttr)
                remaining = String(remaining[italicMatch.range.upperBound...])
            } else {
                var plainAttr = AttributedString(remaining)
                plainAttr.foregroundColor = textColor
                result.append(plainAttr)
                break
            }
        }

        return result
    }

    private func parseItalic(_ input: String) -> AttributedString {
        var result = AttributedString()
        var remaining = input

        while !remaining.isEmpty {
            if let italicMatch = remaining.firstMatch(of: /\*(.+?)\*/) {
                let beforeRange = remaining.startIndex..<italicMatch.range.lowerBound
                let before = String(remaining[beforeRange])
                if !before.isEmpty {
                    var plainAttr = AttributedString(before)
                    plainAttr.foregroundColor = textColor
                    result.append(plainAttr)
                }
                var italicAttr = AttributedString(String(italicMatch.1))
                italicAttr.font = .body.italic()
                italicAttr.foregroundColor = textColor
                result.append(italicAttr)
                remaining = String(remaining[italicMatch.range.upperBound...])
            } else {
                var plainAttr = AttributedString(remaining)
                plainAttr.foregroundColor = textColor
                result.append(plainAttr)
                break
            }
        }

        return result
    }

    // MARK: - Block Parser

    private enum TextBlock {
        case text(String)
        case codeBlock(String, String?)
    }

    private func parseBlocks(_ input: String) -> [TextBlock] {
        var blocks: [TextBlock] = []
        var remaining = input

        while !remaining.isEmpty {
            if let codeBlockMatch = remaining.firstMatch(of: /```(\w*)\n?([\s\S]*?)```/) {
                let beforeRange = remaining.startIndex..<codeBlockMatch.range.lowerBound
                let before = String(remaining[beforeRange])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(before))
                }

                let lang = String(codeBlockMatch.1)
                let code = String(codeBlockMatch.2).trimmingCharacters(in: .newlines)
                blocks.append(.codeBlock(code, lang.isEmpty ? nil : lang))
                remaining = String(remaining[codeBlockMatch.range.upperBound...])
            } else {
                if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(remaining))
                }
                break
            }
        }

        if blocks.isEmpty && !input.isEmpty {
            blocks.append(.text(input))
        }

        return blocks
    }
}

// MARK: - Bubble Shape (iMessage-style asymmetric corners)

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let largeRadius: CGFloat = 18
        let smallRadius: CGFloat = 6

        let topLeading: CGFloat = largeRadius
        let topTrailing: CGFloat = largeRadius
        let bottomLeading: CGFloat = isUser ? largeRadius : smallRadius
        let bottomTrailing: CGFloat = isUser ? smallRadius : largeRadius

        return Path { path in
            path.move(to: CGPoint(x: rect.minX + topLeading, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topTrailing),
                radius: topTrailing
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomTrailing))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX - bottomTrailing, y: rect.maxY),
                radius: bottomTrailing
            )
            path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeading),
                radius: bottomLeading
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeading))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX + topLeading, y: rect.minY),
                radius: topLeading
            )
        }
    }
}

// MARK: - Selectable Text View（UITextView ラッパー）
// SwiftUI の Text.textSelection(.enabled) はコンテナ全体が選択単位になる制約がある。
// UITextView(isEditable: false, isSelectable: true) を使うことで
// 長押し → 単語選択 → ドラッグで範囲調整 という標準 iOS テキスト選択が確実に機能する。

struct SelectableTextView: UIViewRepresentable {
    let text: String
    let textColor: UIColor
    let font: UIFont

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false          // SwiftUI が intrinsicContentSize でサイズ決定
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        // 文字選択ハイライトを白にして、どのバブル背景色でも見えるようにする
        tv.tintColor = UIColor.white.withAlphaComponent(0.8)
        // 横方向は親の幅に合わせる（圧縮耐性を下げて縮小を許可）
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // テキスト・スタイルが変わった時だけ更新（不要な再描画を防ぐ）
        if tv.text != text {
            tv.text = text
        }
        tv.textColor = textColor
        tv.font = font
    }

    /// SwiftUI レイアウトエンジンに正確な高さを伝える
    /// これがないと UITextView の高さが 0 や過剰になる場合がある
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fitsSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitsSize.height)
    }
}

// MARK: - Typing Indicator (3 animated dots)

struct TypingIndicatorView: View {
    @EnvironmentObject var theme: ThemeManager
    @State private var dotOffsets: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(theme.colors.subtext0.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .offset(y: dotOffsets[index])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.colors.surface0)
        .clipShape(BubbleShape(isUser: false))
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotOffsets[i] = -6
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChatView()
        .environmentObject(ChatService())
        .environmentObject(LLMService.shared)
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationService.shared)
}
