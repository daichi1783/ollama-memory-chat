// ChatService.swift
// Memoria for iPhone - Chat Orchestration Service
// LLMServiceとDatabaseServiceを繋ぎ、記憶圧縮・コマンド処理を統合
// Phase 2: ユーザー定義コマンド、プロンプトインジェクション対策、セッション管理強化

import Foundation
import Combine
import SwiftUI
import os.log

/// チャットメッセージのUI表示用モデル
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: String        // "user" or "assistant"
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    init(role: String, content: String, isStreaming: Bool = false) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
    }

    // DBモデルからの変換
    init(from message: Message) {
        self.id = "\(message.id ?? 0)"
        self.role = message.role
        self.content = message.content
        self.timestamp = message.createdAt
        self.isStreaming = false
    }
}

@MainActor
class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    /// ContentViewのNavigationStackを駆動するためのシグナル
    /// 値がセットされると ContentView がパスに追加してナビゲーションする
    @Published var pendingNavigationId: Int64? = nil
    /// セッション一覧でキーワード検索して遷移した際の検索ワード（ChatViewでスクロール・ハイライト用）
    @Published var highlightKeyword: String? = nil
    @Published var currentSessionId: Int64? {
        didSet {
            // セッション切り替え時に下書きを復元
            restoreDraft()
        }
    }
    @Published var sessions: [SessionPreview] = []
    @Published var messageCountWarning: String?
    /// APIキー未設定でクラウドモデルを使おうとした場合に設定画面をポップアップするためのプロバイダー
    @Published var needsAPIKeySetupFor: APIProvider? = nil

    /// 入力中の下書きテキスト（UserDefaultsで永続化、アプリ終了しても残る）
    @Published var draftText: String = "" {
        didSet {
            saveDraft()
        }
    }

    /// セッションあたりの最大メッセージ数（超えると警告）
    private let maxMessagesPerSession = 500

    private let db = DatabaseService.shared
    private let llm = LLMService.shared
    private let logger = Logger(subsystem: "com.memoria.app", category: "Chat")

    // デフォルトシステムプロンプト
    private let baseSystemPrompt = """
    あなたはMemoriaというAIアシスタントです。
    ユーザーとの会話を記憶し、親切で丁寧に応答してください。
    必ずユーザーが使用した言語で、回答は一度だけ出力してください。
    括弧やカッコ内での繰り返し・翻訳は絶対にしないでください。
    簡潔で分かりやすい回答を心がけてください。
    """

    // 組み込みコマンド一覧（ユーザー定義と区別）
    private let builtinCommands: Set<String> = [
        "help", "clear", "remember", "memory",
        "english", "japanese", "spanish", "cal", "grammar",
        "commands", "addcommand", "deletecommand"
    ]

    // MARK: - Session Management

    /// 新しいセッションを作成し、ContentViewへナビゲーションシグナルを送る
    func createNewSession() {
        // 古いセッションの生成が新セッションに漏れ込まないよう isGenerating を確実にリセット
        isGenerating = false
        do {
            let session = try db.createSession()
            currentSessionId = session.id
            messages = []
            refreshSessions()
            // pendingNavigationId の変更を次のランループに遅延させる
            // → refreshSessions() 等の @Published 変更バッチが SwiftUI に処理された後、
            //   独立したサイクルで onChange が確実に発火するようにする
            if let id = session.id {
                Task { @MainActor in
                    self.pendingNavigationId = id
                }
            }
        } catch {
            logger.error("Failed to create session: \(error.localizedDescription)")
        }
    }

    /// セッションを選択してナビゲーション（ButtonタップからのUI起点）
    /// loadSession + pendingNavigationId セットを一括で行う
    func selectSession(id: Int64) {
        loadSession(id: id)
        pendingNavigationId = id
    }

    /// 既存セッションを読み込む
    func loadSession(id: Int64) {
        currentSessionId = id
        do {
            let dbMessages = try db.getMessages(sessionId: id)
            messages = dbMessages.map { ChatMessage(from: $0) }
        } catch {
            logger.error("Failed to load session: \(error.localizedDescription)")
        }
    }

    /// セッション一覧をリフレッシュ
    func refreshSessions() {
        do {
            sessions = try db.getSessionsWithPreview()
        } catch {
            logger.error("Failed to refresh sessions: \(error.localizedDescription)")
            sessions = []
        }
    }

    /// セッション一覧をバックグラウンドでリフレッシュ
    func refreshSessionsAsync() async {
        do {
            let previews = try await db.getSessionsWithPreviewAsync()
            self.sessions = previews
        } catch {
            logger.error("Failed to refresh sessions async: \(error.localizedDescription)")
        }
    }

    /// セッションを削除
    func deleteSession(id: Int64) {
        do {
            try db.deleteSession(id: id)
            // 現在のセッションが削除された場合はクリア
            if currentSessionId == id {
                currentSessionId = nil
                messages = []
            }
            refreshSessions()
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription)")
        }
    }

    /// セッション検索
    func searchSessions(query: String) -> [Session] {
        do {
            return try db.searchSessions(query: query)
        } catch {
            logger.error("Session search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Draft Persistence（下書き保存）

    /// 下書きをUserDefaultsに保存
    private func saveDraft() {
        guard let sessionId = currentSessionId else { return }
        let key = "draftText_\(sessionId)"
        if draftText.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(draftText, forKey: key)
        }
    }

    /// 現在のセッションの下書きをUserDefaultsから復元
    private func restoreDraft() {
        guard let sessionId = currentSessionId else {
            draftText = ""
            return
        }
        let key = "draftText_\(sessionId)"
        draftText = UserDefaults.standard.string(forKey: key) ?? ""
    }

    /// 下書きをクリア（送信完了時に呼ぶ）
    private func clearDraft() {
        draftText = ""
    }

    // MARK: - Export Chat History

    /// セッションの全メッセージをテキスト形式でエクスポート
    func exportSessionAsText(sessionId: Int64) throws -> String {
        let session = try db.getSession(id: sessionId)
        let dbMessages = try db.getMessages(sessionId: sessionId)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "ja_JP")

        var lines: [String] = []
        lines.append("=== Memoria チャット履歴 ===")
        lines.append("セッション: \(session.title)")
        lines.append("作成日: \(dateFormatter.string(from: session.createdAt))")
        lines.append("メッセージ数: \(dbMessages.count)")
        lines.append("=============================")
        lines.append("")

        for message in dbMessages {
            let roleLabel = message.role == "user" ? "あなた" : "AI"
            let timestamp = dateFormatter.string(from: message.createdAt)
            lines.append("[\(timestamp)] \(roleLabel):")
            lines.append(message.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Model Output Cleaning

    /// Gemma が「回答 (回答)」と繰り返し出力するパターンを除去するポストプロセス
    /// 例: "こんにちは (こんにちは)" → "こんにちは"
    static func cleanModelOutput(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 末尾の括弧ブロックを最大5回繰り返し除去（入れ子・連続パターン対応）
        // 10文字以上の内容を持つ末尾 (...) を除去
        guard let parenPattern = try? NSRegularExpression(
            pattern: "\\s*\\([^()]{10,}\\)\\s*$", options: []
        ) else { return text }

        for _ in 0..<5 {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = parenPattern.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range, in: text) else { break }
            let candidate = String(text[..<swiftRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { break }
            text = candidate
        }

        return text
    }

    // MARK: - Prompt Injection Sanitization
    // Mac版 command_manager.py の sanitize_prompt_input() を移植

    /// プロンプトインジェクション対策: 危険なパターンを除去
    static func sanitizePromptInput(_ input: String) -> String {
        var sanitized = input

        // プロンプトインジェクションパターン（正規表現）
        let injectionPatterns: [(pattern: String, options: NSRegularExpression.Options)] = [
            ("ignore\\s+.*instruction", [.caseInsensitive]),
            ("system\\s+prompt", [.caseInsensitive]),
            ("you\\s+are\\s+now", [.caseInsensitive]),
            ("forget\\s+.*previous", [.caseInsensitive]),
            ("disregard\\s+.*above", [.caseInsensitive]),
            ("override\\s+.*system", [.caseInsensitive]),
            ("act\\s+as\\s+if", [.caseInsensitive]),
            ("pretend\\s+you\\s+are", [.caseInsensitive]),
            ("new\\s+instructions?:", [.caseInsensitive]),
            ("\\[SYSTEM\\]", [.caseInsensitive]),
            ("\\[INST\\]", [.caseInsensitive]),
            ("<\\|im_start\\|>", []),
            ("<\\|im_end\\|>", []),
        ]

        for entry in injectionPatterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: entry.options) else {
                continue
            }
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: range, withTemplate: "")
        }

        // 連続空白を単一スペースに正規化
        sanitized = sanitized.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Send Message

    /// メッセージを送信してAIの応答を取得
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // ③ クラウドモデルでAPIキー未設定の場合、送信前に設定画面を誘導
        if llm.currentModelType.isCloud,
           let provider = llm.currentModelType.cloudProvider,
           !KeychainService.shared.hasAPIKey(for: provider) {
            needsAPIKeySetupFor = provider
            return
        }

        // セッションがなければ作成
        if currentSessionId == nil {
            createNewSession()
        }
        guard let sessionId = currentSessionId else { return }

        // メッセージ数上限チェック
        do {
            let currentCount = try db.getMessageCount(sessionId: sessionId)
            if currentCount >= maxMessagesPerSession {
                messageCountWarning = "このセッションは\(maxMessagesPerSession)件を超えました。新しいセッションの作成をおすすめします。"
                logger.info("Session \(sessionId) exceeded \(self.maxMessagesPerSession) messages")
            } else {
                messageCountWarning = nil
            }
        } catch {
            logger.error("Failed to check message count: \(error.localizedDescription)")
        }

        // 下書きをクリア（送信成功）
        clearDraft()

        // コマンド判定
        if trimmed.hasPrefix("/") {
            await handleCommand(trimmed, sessionId: sessionId)
            return
        }

        // サニタイズ（通常メッセージもインジェクション除去）
        let sanitizedInput = Self.sanitizePromptInput(trimmed)

        // ユーザーメッセージをDBに保存 & UI追加
        do {
            _ = try db.addMessage(role: "user", content: sanitizedInput, sessionId: sessionId)
        } catch {
            logger.error("Failed to save user message: \(error.localizedDescription)")
        }
        messages.append(ChatMessage(role: "user", content: sanitizedInput))

        // AI応答をストリーミング生成
        await generateResponse(for: sanitizedInput, sessionId: sessionId)

        // セッション一覧を更新
        refreshSessions()
    }

    /// AI応答を生成（ストリーミング）
    /// - overrideSystemPrompt: nilの場合はbaseSystemPrompt+記憶を使用。指定した場合はそのまま使用（記憶注入なし）
    /// - initialContent: ストリーミング開始前にバブルに表示するプレフィックス文字列（例: 分析対象テキストの表示）
    private func generateResponse(for input: String, sessionId: Int64, overrideSystemPrompt: String? = nil, initialContent: String = "") async {
        isGenerating = true

        // ★ defer で確実に isGenerating = false にする（例外・早期リターン時も安全）
        defer { isGenerating = false }

        // システムプロンプトに記憶を注入
        let systemPrompt: String
        if let override = overrideSystemPrompt {
            systemPrompt = override
        } else {
            do {
                systemPrompt = try db.buildSystemPrompt(
                    basePrompt: baseSystemPrompt,
                    sessionId: sessionId
                )
            } catch {
                systemPrompt = baseSystemPrompt
            }
        }

        // ストリーミング用の仮メッセージを追加（initialContentがあれば先頭に表示）
        let placeholderMessage = ChatMessage(role: "assistant", content: initialContent, isStreaming: true)
        messages.append(placeholderMessage)
        let streamIndex = messages.count - 1

        // BUG-4修正: LLM.swift が内部で history を蓄積するため、毎回明示的に渡して制御する。
        // 現在の messages 末尾 2 件 = [今回のユーザー入力, AIプレースホルダー] は除外し、
        // それ以前の有効なメッセージのみを「会話履歴」として渡す。
        // 履歴は最大6件（3往復）に絞りトークンオーバーフローを防ぐ
        let historyMessages = messages.dropLast(2)
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(6)
            .map { (role: $0.role, content: $0.content) }

        // LLMで生成
        let fullResponse = await llm.generate(
            prompt: input,
            systemPrompt: systemPrompt,
            conversationHistory: historyMessages
        ) { [weak self] token in
            Task { @MainActor in
                guard let self = self, streamIndex < self.messages.count else { return }
                self.messages[streamIndex].content += token
            }
        }

        // BUG-5修正: onToken は Task { @MainActor in } でキューされるため、
        // generate() 完了直後にメインアクターに溜まった未実行タスクを先にドレインする。
        // これにより messages[streamIndex].content に全トークンが反映された状態で読める。
        await Task.yield()

        // ストリーミング完了
        if streamIndex < messages.count {
            messages[streamIndex].isStreaming = false
            // 空の応答の場合はエラーメッセージに置換
            if messages[streamIndex].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[streamIndex].content = fullResponse.isEmpty
                    ? "[応答を生成できませんでした]"
                    : fullResponse
            }
            // Gemma の二重出力クリーニング（括弧内繰り返しを除去）
            messages[streamIndex].content = Self.cleanModelOutput(messages[streamIndex].content)
        }

        // AI応答をDBに保存
        // 優先度: in-memory (onToken 積み上げ済み) > fullResponse (LLMService戻り値) > フォールバック
        let inMemoryContent = streamIndex < messages.count ? messages[streamIndex].content : ""
        let contentToSave: String
        if !inMemoryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentToSave = inMemoryContent
        } else if !fullResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentToSave = fullResponse
        } else {
            contentToSave = "[応答なし]"
        }
        do {
            _ = try db.addMessage(role: "assistant", content: contentToSave, sessionId: sessionId)
        } catch {
            logger.error("Failed to save assistant message: \(error.localizedDescription)")
        }

        // 記憶圧縮チェック
        await checkAndCompress(sessionId: sessionId)

        // セッションタイトルを最初のメッセージから自動設定
        await autoSetSessionTitle(sessionId: sessionId, firstMessage: input)
    }

    // MARK: - Memory Compression（記憶圧縮）

    private func checkAndCompress(sessionId: Int64) async {
        do {
            guard try db.shouldCompress(sessionId: sessionId) else { return }

            let recentMessages = try db.getRecentMessages(sessionId: sessionId, count: 30)
            let messageCount = try db.getMessageCount(sessionId: sessionId)
            let previousSummary = try db.getLatestSummary(sessionId: sessionId)

            // 会話をフォーマット
            let conversation = recentMessages.map { msg in
                let roleLabel = msg.role == "user" ? "ユーザー" : "AI"
                return "\(roleLabel): \(msg.content)"
            }.joined(separator: "\n")

            // 圧縮プロンプト（Mac版と同じ）
            var compressionPrompt = "以下の会話の重要な情報を200文字以内の箇条書きで要約してください。"
            if let prev = previousSummary {
                compressionPrompt += "\n\n前回の要約:\n\(prev.summary)"
            }
            compressionPrompt += "\n\n会話:\n\(conversation)"

            // LLMで要約生成
            var summary = ""
            await llm.generate(prompt: compressionPrompt) { token in
                summary += token
            }

            // サマリーをDBに保存
            if !summary.isEmpty {
                try db.saveSummary(
                    summary: summary,
                    messageCount: messageCount,
                    sessionId: sessionId
                )
                logger.info("Memory compressed for session \(sessionId)")
            }
        } catch {
            logger.error("Compression failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Auto Session Title

    private func autoSetSessionTitle(sessionId: Int64, firstMessage: String) async {
        do {
            let msgCount = try db.getMessageCount(sessionId: sessionId)
            guard msgCount <= 2 else { return }

            let session = try db.getSession(id: sessionId)
            guard session.title == "新しい会話" else { return }

            // 最初のメッセージの先頭30文字をタイトルに
            let title = String(firstMessage.prefix(30))
            try db.updateSessionTitle(session, title: title)
            refreshSessions()
        } catch {
            logger.error("Auto title failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Command Handling（スラッシュコマンド）

    private func handleCommand(_ input: String, sessionId: Int64) async {
        let parts = input.split(separator: " ", maxSplits: 1)
        let command = String(parts[0]).lowercased().replacingOccurrences(of: "/", with: "")
        let rawBody = parts.count > 1 ? String(parts[1]) : ""
        let body = Self.sanitizePromptInput(rawBody)

        // 組み込みコマンドの判定
        if builtinCommands.contains(command) {
            await handleBuiltinCommand(command, body: body, rawInput: input, sessionId: sessionId)
            return
        }

        // ユーザー定義コマンドの判定
        await handleUserDefinedCommand(command, body: body, rawInput: input, sessionId: sessionId)
    }

    /// ユーザーメッセージをDBに保存してUIにも追加するヘルパー
    private func persistAndAppendUser(_ content: String, sessionId: Int64) {
        do {
            _ = try db.addMessage(role: "user", content: content, sessionId: sessionId)
        } catch {
            logger.error("Failed to persist user message: \(error.localizedDescription)")
        }
        messages.append(ChatMessage(role: "user", content: content))
    }

    /// アシスタントメッセージをDBに保存してUIにも追加するヘルパー
    private func persistAndAppendAssistant(_ content: String, sessionId: Int64) {
        do {
            _ = try db.addMessage(role: "assistant", content: content, sessionId: sessionId)
        } catch {
            logger.error("Failed to persist assistant message: \(error.localizedDescription)")
        }
        messages.append(ChatMessage(role: "assistant", content: content))
    }

    /// 組み込みコマンドの処理
    private func handleBuiltinCommand(_ command: String, body: String, rawInput: String, sessionId: Int64) async {
        switch command {
        case "help":
            var helpText = """
            利用可能なコマンド:
            /english [テキスト] -- 英語ネイティブの英語に変換
            /japanese [テキスト] -- 日本語ネイティブの日本語に変換
            /spanish [テキスト] -- スペイン語ネイティブのスペイン語に変換
            /cal [テキスト] -- 言語を自動判定して校正（日本語・英語・スペイン語）
            /grammar [テキスト] -- 翻訳・代替表現・文法解説を表示
            /remember [内容] -- グローバルメモリに保存
            /memory -- 記憶サマリー表示
            /clear -- セッションリセット
            /commands -- ユーザー定義コマンド一覧
            /addcommand [名前] [説明] [テンプレート] -- コマンド追加
            /deletecommand [名前] -- コマンド削除
            /help -- このヘルプを表示
            """
            // ユーザー定義コマンドも表示
            do {
                let userCmds = try db.getAllUserCommands()
                if !userCmds.isEmpty {
                    helpText += "\n\nユーザー定義コマンド:"
                    for cmd in userCmds {
                        helpText += "\n/\(cmd.name) -- \(cmd.commandDescription)"
                    }
                }
            } catch {
                logger.error("Failed to load user commands for help: \(error.localizedDescription)")
            }
            persistAndAppendAssistant(helpText, sessionId: sessionId)

        case "clear":
            createNewSession()
            // clear は新セッション作成のため保存不要（新セッションIDが変わる）
            messages.append(ChatMessage(role: "assistant", content: "新しい会話を始めました。"))

        case "remember":
            guard !body.isEmpty else {
                persistAndAppendAssistant("記憶する内容を入力してください。\n例: /remember 私の名前はDaichiです", sessionId: sessionId)
                return
            }
            do {
                try db.addGlobalMemory(content: body)
                persistAndAppendUser(rawInput, sessionId: sessionId)
                persistAndAppendAssistant("記憶しました: \(body)", sessionId: sessionId)
            } catch {
                persistAndAppendAssistant("記憶の保存に失敗しました。", sessionId: sessionId)
            }

        case "memory":
            do {
                let memories = try db.getAllGlobalMemories()
                if memories.isEmpty {
                    persistAndAppendAssistant("グローバルメモリは空です。\n/remember で記憶を追加できます。", sessionId: sessionId)
                } else {
                    let list = memories.enumerated().map { "\($0.offset + 1). \($0.element.content)" }.joined(separator: "\n")
                    persistAndAppendAssistant("グローバルメモリ:\n\(list)", sessionId: sessionId)
                }
            } catch {
                persistAndAppendAssistant("メモリの読み込みに失敗しました。", sessionId: sessionId)
            }

        case "english":
            let prompt = "You are a native English speaker. Rewrite the following text exactly as a native English speaker would write it — not as a translation. Use natural English idioms, phrasing, and rhythm. Output only the rewritten text.\n\nText: \(body)"
            persistAndAppendUser(rawInput, sessionId: sessionId)
            await generateResponse(for: prompt, sessionId: sessionId)

        case "japanese":
            let prompt = "あなたは日本語のネイティブスピーカーです。以下のテキストを、日本語ネイティブが最初から書いたかのように自然な日本語で書き直してください。翻訳調にならず、日本語として完全に自然な表現・言い回しを使ってください。書き直したテキストのみを出力してください。\n\nテキスト: \(body)"
            persistAndAppendUser(rawInput, sessionId: sessionId)
            await generateResponse(for: prompt, sessionId: sessionId)

        case "spanish":
            let prompt = "Eres un hablante nativo de español. Reescribe el siguiente texto como lo escribiría un nativo desde cero, no como una traducción. Usa expresiones, giros y ritmo naturales del español. Devuelve solo el texto reescrito.\n\nTexto: \(body)"
            persistAndAppendUser(rawInput, sessionId: sessionId)
            await generateResponse(for: prompt, sessionId: sessionId)

        case "cal":
            let prompt = "以下のテキストの言語（日本語・英語・スペイン語）を自動判定し、そのネイティブスピーカーとして校正してください。誤字・脱字・文法ミス・不自然な表現を修正し、修正箇所とその理由を入力と同じ言語で説明してください。\n\nテキスト: \(body)"
            persistAndAppendUser(rawInput, sessionId: sessionId)
            await generateResponse(for: prompt, sessionId: sessionId)

        case "grammar":
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                persistAndAppendAssistant("💡 使い方: /grammar [分析したいテキスト]\n例: /grammar She don't know nothing about it.", sessionId: sessionId)
                return
            }
            let appLang = LocalizationService.shared.currentLanguage
            let grammarPrompt: String
            switch appLang {
            case .japanese:
                grammarPrompt = """
                語学分析の例:
                テキスト: She don't know nothing about it.
                翻訳: 彼女はそれについて何も知りません。
                推奨される代替表現:
                • She doesn't know anything about it.
                • She has no knowledge of it.
                • She knows nothing about it.
                文法的な解説: "don't"は三人称単数の主語"She"には使えず"doesn't"が正しい。"don't know nothing"は二重否定のため"don't know anything"を使う。

                ---
                テキスト: \(body)
                翻訳:
                推奨される代替表現:
                •
                •
                •
                文法的な解説:
                """
            case .english:
                grammarPrompt = """
                Language analysis example:
                Text: She don't know nothing about it.
                Translation: She doesn't know anything about it.
                Recommended alternatives:
                • She doesn't know anything about it.
                • She has no knowledge of it.
                • She knows nothing about it.
                Grammar notes: "don't" is wrong with "She" — use "doesn't". "Don't know nothing" is a double negative; use "don't know anything".

                ---
                Text: \(body)
                Translation:
                Recommended alternatives:
                •
                •
                •
                Grammar notes:
                """
            case .spanish:
                grammarPrompt = """
                Ejemplo de análisis:
                Texto: She don't know nothing about it.
                Traducción: Ella no sabe nada al respecto.
                Expresiones alternativas recomendadas:
                • She doesn't know anything about it.
                • She has no knowledge of it.
                • She knows nothing about it.
                Explicación gramatical: "don't" es incorrecto con "She" — usar "doesn't". "Don't know nothing" es doble negación; usar "don't know anything".

                ---
                Texto: \(body)
                Traducción:
                Expresiones alternativas recomendadas:
                •
                •
                •
                Explicación gramatical:
                """
            }
            // grammar専用システムプロンプト:
            // デフォルトの「簡潔に」指示を除外し、全セクション出力を強制する
            let grammarSystemPrompt = "あなたは語学教師です。与えられたテンプレートの空欄をすべて埋めて出力してください。省略せずにすべてのセクションを完成させてください。"
            // レスポンスバブルの先頭に入力テキストを表示
            let textHeader = "📝 \(body)\n\n"
            persistAndAppendUser(rawInput, sessionId: sessionId)
            await generateResponse(for: grammarPrompt, sessionId: sessionId, overrideSystemPrompt: grammarSystemPrompt, initialContent: textHeader)

        case "commands":
            do {
                let userCmds = try db.getAllUserCommands()
                if userCmds.isEmpty {
                    persistAndAppendAssistant("ユーザー定義コマンドはまだありません。\n/addcommand で追加できます。", sessionId: sessionId)
                } else {
                    var text = "ユーザー定義コマンド:\n"
                    for cmd in userCmds {
                        text += "\n/\(cmd.name) -- \(cmd.commandDescription)\n  テンプレート: \(cmd.promptTemplate.prefix(60))..."
                    }
                    persistAndAppendAssistant(text, sessionId: sessionId)
                }
            } catch {
                persistAndAppendAssistant("コマンド一覧の取得に失敗しました。", sessionId: sessionId)
            }

        case "addcommand":
            await handleAddCommand(body: body)

        case "deletecommand":
            await handleDeleteCommand(body: body)

        default:
            break
        }
    }

    /// ユーザー定義コマンドの実行
    private func handleUserDefinedCommand(_ command: String, body: String, rawInput: String, sessionId: Int64) async {
        do {
            guard let userCommand = try db.getUserCommand(name: command) else {
                persistAndAppendAssistant("不明なコマンド: /\(command)\n/help でコマンド一覧を確認できます。", sessionId: sessionId)
                return
            }

            let template = userCommand.promptTemplate

            // {input}/{text} プレースホルダーを含むテンプレートで body が空の場合は案内を表示
            let hasInputPlaceholder = template.contains("{input}") ||
                                      template.contains("{text}") ||
                                      template.contains("{{input}}") ||
                                      template.contains("{{text}}")

            if hasInputPlaceholder && body.isEmpty {
                let hint = """
                **「/\(command)」の使い方**
                テキストをコマンドの後ろに続けて入力してください。

                例: `/\(command) ここに対象テキストを入力`

                テンプレート: \(template.prefix(80))\(template.count > 80 ? "…" : "")
                """
                messages.append(ChatMessage(role: "assistant", content: hint))
                return
            }

            // テンプレート展開: {input} をユーザー入力に置換
            let expandedPrompt = template
                .replacingOccurrences(of: "{input}", with: body)
                .replacingOccurrences(of: "{text}", with: body)
                .replacingOccurrences(of: "{{input}}", with: body)
                .replacingOccurrences(of: "{{text}}", with: body)

            persistAndAppendUser(rawInput, sessionId: sessionId)
            await generateResponse(for: expandedPrompt, sessionId: sessionId)
        } catch {
            logger.error("User command execution failed: \(error.localizedDescription)")
            persistAndAppendAssistant("コマンドの実行に失敗しました: \(error.localizedDescription)", sessionId: sessionId)
        }
    }

    /// /addcommand の処理
    /// 書式: /addcommand [名前] | [説明] | [プロンプトテンプレート]
    private func handleAddCommand(body: String) async {
        let components = body.split(separator: "|", maxSplits: 2).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard components.count >= 3,
              !components[0].isEmpty,
              !components[1].isEmpty,
              !components[2].isEmpty else {
            messages.append(ChatMessage(role: "assistant", content: """
            コマンドの追加書式:
            /addcommand 名前 | 説明 | プロンプトテンプレート

            例:
            /addcommand summarize | テキストを要約 | 以下のテキストを3行以内で要約してください: {input}

            テンプレート内で {input} がユーザー入力に置換されます。
            """))
            return
        }

        do {
            let cmd = try db.addUserCommand(
                name: components[0],
                description: components[1],
                promptTemplate: components[2]
            )
            messages.append(ChatMessage(role: "assistant", content: "コマンド /\(cmd.name) を追加しました。\n説明: \(cmd.commandDescription)"))
        } catch let error as DatabaseError {
            messages.append(ChatMessage(role: "assistant", content: "コマンド追加に失敗: \(error.localizedDescription)"))
        } catch {
            messages.append(ChatMessage(role: "assistant", content: "コマンド追加に失敗しました。"))
        }
    }

    /// /deletecommand の処理
    private func handleDeleteCommand(body: String) async {
        let name = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            messages.append(ChatMessage(role: "assistant", content: "削除するコマンド名を指定してください。\n例: /deletecommand summarize"))
            return
        }

        do {
            guard let cmd = try db.getUserCommand(name: name) else {
                messages.append(ChatMessage(role: "assistant", content: "コマンド /\(name) は見つかりませんでした。"))
                return
            }
            guard let cmdId = cmd.id else {
                messages.append(ChatMessage(role: "assistant", content: "コマンドの削除に失敗しました。"))
                return
            }
            try db.deleteUserCommand(id: cmdId)
            messages.append(ChatMessage(role: "assistant", content: "コマンド /\(cmd.name) を削除しました。"))
        } catch {
            messages.append(ChatMessage(role: "assistant", content: "コマンドの削除に失敗しました: \(error.localizedDescription)"))
        }
    }
}
