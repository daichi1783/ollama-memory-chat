// LLMService.swift
// Memoria for iPhone - LLM Inference Service
// LLM.swift を使って Gemma 3 1B をオンデバイスで推論
// Phase 2: メモリ監視、ダウンロード進捗改善、推論キャンセル、バックグラウンド状態保存

import Foundation
import UIKit
import LLM
import Combine
import os.log

/// LLMの状態
enum LLMState: Equatable {
    case notLoaded
    case downloading(progress: Double)
    case loading
    case ready
    case generating
    case paused              // バックグラウンド移行時の一時停止
    case error(String)

    static func == (lhs: LLMState, rhs: LLMState) -> Bool {
        switch (lhs, rhs) {
        case (.notLoaded, .notLoaded): return true
        case (.loading, .loading): return true
        case (.ready, .ready): return true
        case (.generating, .generating): return true
        case (.paused, .paused): return true
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .generating, .loading, .downloading: return true
        default: return false
        }
    }
}

/// モデル種別
enum ModelType: String, CaseIterable {
    // ── ローカルモデル ──────────────────────────────────
    case gemma3_1b   = "gemma3_1b"
    case gemma4_e2b  = "gemma4_e2b"
    // ── クラウドモデル: Gemini ───────────────────────────
    case gemini2Flash = "gemini_2_flash"
    case gemini15Pro  = "gemini_1_5_pro"
    // ── クラウドモデル: Claude ───────────────────────────
    case claudeHaiku  = "claude_haiku"
    case claudeSonnet = "claude_sonnet"
    // ── クラウドモデル: OpenAI ───────────────────────────
    case gpt4oMini    = "gpt_4o_mini"
    case gpt4o        = "gpt_4o"

    // MARK: - ローカル / クラウド 判定

    var isLocal: Bool {
        switch self {
        case .gemma3_1b, .gemma4_e2b: return true
        default: return false
        }
    }

    var isCloud: Bool { !isLocal }

    /// クラウドモデルの場合の APIProvider
    var cloudProvider: APIProvider? {
        switch self {
        case .gemini2Flash, .gemini15Pro: return .gemini
        case .claudeHaiku, .claudeSonnet: return .claude
        case .gpt4oMini, .gpt4o:          return .openai
        default: return nil
        }
    }

    /// クラウドAPIに渡すモデル識別子
    var cloudModelID: String {
        switch self {
        case .gemini2Flash: return "gemini-2.0-flash"
        case .gemini15Pro:  return "gemini-1.5-pro"
        case .claudeHaiku:  return "claude-haiku-4-5-20251001"
        case .claudeSonnet: return "claude-sonnet-4-6"
        case .gpt4oMini:    return "gpt-4o-mini"
        case .gpt4o:        return "gpt-4o"
        default:            return rawValue
        }
    }

    // MARK: - 表示情報

    var displayName: String {
        switch self {
        case .gemma3_1b:   return "Gemma 3 1B"
        case .gemma4_e2b:  return "Gemma 4 E2B"
        case .gemini2Flash: return "Gemini 2.0 Flash"
        case .gemini15Pro:  return "Gemini 1.5 Pro"
        case .claudeHaiku:  return "Claude Haiku"
        case .claudeSonnet: return "Claude Sonnet"
        case .gpt4oMini:    return "GPT-4o mini"
        case .gpt4o:        return "GPT-4o"
        }
    }

    var fileSize: String {
        switch self {
        case .gemma3_1b:   return "~600MB"
        case .gemma4_e2b:  return "~1.3GB"
        default:           return "クラウド"
        }
    }

    var descriptionText: String {
        switch self {
        case .gemma3_1b:    return "全端末対応・完全オフライン"
        case .gemma4_e2b:   return "iPhone 16以降・高性能"
        case .gemini2Flash: return "高速・無料枠あり"
        case .gemini15Pro:  return "高精度・長文対応"
        case .claudeHaiku:  return "高速・低コスト"
        case .claudeSonnet: return "バランス型・高精度"
        case .gpt4oMini:    return "低コスト・高速"
        case .gpt4o:        return "最高精度"
        }
    }

    var iconName: String {
        switch self {
        case .gemma3_1b, .gemma4_e2b: return "iphone"
        case .gemini2Flash, .gemini15Pro: return "sparkles"
        case .claudeHaiku, .claudeSonnet: return "wand.and.stars"
        case .gpt4oMini, .gpt4o: return "brain.head.profile"
        }
    }

    // MARK: - ローカルモデル専用プロパティ

    var huggingFaceRepo: String {
        switch self {
        case .gemma3_1b: return "unsloth/gemma-3-1b-it-GGUF"
        case .gemma4_e2b: return "unsloth/gemma-4-E2B-it-GGUF"
        default: return ""
        }
    }

    var directDownloadURL: URL {
        switch self {
        case .gemma3_1b:
            return URL(string: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf")!
        case .gemma4_e2b:
            return URL(string: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!
        default:
            return URL(string: "https://example.com")!
        }
    }

    var ggufFilename: String {
        switch self {
        case .gemma3_1b: return "gemma-3-1b-it-Q4_K_M.gguf"
        case .gemma4_e2b: return "gemma-4-E2B-it-Q4_K_M.gguf"
        default: return ""
        }
    }

    var requiresHighMemory: Bool {
        switch self {
        case .gemma4_e2b: return true
        default: return false
        }
    }

    var estimatedMemoryUsage: UInt64 {
        switch self {
        case .gemma3_1b: return 800 * 1024 * 1024
        case .gemma4_e2b: return 1_600 * 1024 * 1024
        default: return 0
        }
    }
}

/// ダウンロード進捗の詳細情報
struct DownloadProgress {
    let progress: Double          // 0.0 - 1.0
    let estimatedTotalBytes: UInt64?
    let downloadedBytes: UInt64?

    var percentString: String {
        "\(Int(progress * 100))%"
    }

    var sizeString: String? {
        guard let downloaded = downloadedBytes, let total = estimatedTotalBytes, total > 0 else {
            return nil
        }
        let downloadedMB = Double(downloaded) / (1024 * 1024)
        let totalMB = Double(total) / (1024 * 1024)
        return String(format: "%.0fMB / %.0fMB", downloadedMB, totalMB)
    }
}

@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    @Published var state: LLMState = .notLoaded
    @Published var currentModelType: ModelType = .gemma3_1b
    @Published var downloadProgress: DownloadProgress?
    @Published var memoryUsageMB: Double = 0
    @Published var tokensPerSecond: Double = 0

    private var llm: LLM?
    private var outputObservation: AnyCancellable?
    private var generationCancelled = false
    private var generationTimedOut = false
    private var memoryMonitorTimer: Timer?
    private var generationTimeoutTimer: Timer?
    private var stateBeforeBackground: LLMState?
    private let logger = Logger(subsystem: "com.memoria.app", category: "LLM")

    /// 生成中のタスク参照（キャンセル用） BUG-4修正
    /// Task<Void, Never> のラッパーとして保持（cancel() 呼び出し専用）
    private var currentGenerationTask: Task<Void, Never>?

    /// タイムアウト: トークンが一切生成されないまま何秒経過したらキャンセルするか
    private let generationTimeoutSeconds: TimeInterval = 90

    // デフォルトシステムプロンプト
    let defaultSystemPrompt = """
    あなたはMemoriaというAIアシスタントです。
    ユーザーとの会話を記憶し、親切で丁寧に応答してください。
    必ずユーザーが使用した言語で、回答は一度だけ出力してください。
    括弧やカッコ内での繰り返し・翻訳は絶対にしないでください。
    簡潔で分かりやすい回答を心がけてください。
    """

    /// Gemma 3 用テンプレートを生成（システムプロンプト付き）
    /// Gemma 3 は <start_of_turn>system ... <end_of_turn> 形式でシステムプロンプトを受け付ける
    /// BUG-2修正: 旧実装は system プロンプトを <start_of_turn>user でラップしていたが、
    ///            これは Gemma 3 の学習フォーマットと一致せず、stop token が正常に機能しなかった
    private func gemmaTemplate(systemPrompt: String? = nil) -> Template {
        Template(
            system: ("<start_of_turn>system\n", "<end_of_turn>\n"),
            user: ("<start_of_turn>user\n", "<end_of_turn>\n"),
            bot: ("<start_of_turn>model\n", "<end_of_turn>\n"),
            stopSequence: "<end_of_turn>",
            systemPrompt: systemPrompt
        )
    }

    private init() {
        setupLifecycleObservers()
    }

    deinit {
        memoryMonitorTimer?.invalidate()
    }

    // MARK: - Device Capability Check

    static var supportsLargeModel: Bool {
        ProcessInfo.processInfo.physicalMemory >= 6 * 1024 * 1024 * 1024
    }

    /// ローカルモデル一覧（デバイスメモリに応じて変動）
    static var availableLocalModels: [ModelType] {
        if supportsLargeModel {
            return [.gemma3_1b, .gemma4_e2b]
        } else {
            return [.gemma3_1b]
        }
    }

    /// クラウドモデル一覧（常に全モデルを表示、APIキー未設定は設定を促す）
    static let availableCloudModels: [ModelType] = [
        .gemini2Flash, .gemini15Pro,
        .claudeHaiku, .claudeSonnet,
        .gpt4oMini, .gpt4o
    ]

    /// 全モデル一覧（ローカル + クラウド）
    static var availableModels: [ModelType] {
        availableLocalModels + availableCloudModels
    }

    /// モデルファイルがキャッシュ済みかチェック（ダウンロード不要か判定）
    static func isModelCached(_ type: ModelType) -> Bool {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localURL = documentsDir.appendingPathComponent(type.ggufFilename)
        return FileManager.default.fileExists(atPath: localURL.path)
    }

    /// 現在のアプリメモリ使用量（MB）
    static var currentMemoryUsageMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }

    /// デバイスの利用可能メモリが十分かチェック
    static func hasEnoughMemory(for modelType: ModelType) -> Bool {
        let available = ProcessInfo.processInfo.physicalMemory
        let required = modelType.estimatedMemoryUsage
        // 推定メモリ使用量の1.5倍以上の物理メモリがあればOK
        return available >= UInt64(Double(required) * 1.5)
    }

    // MARK: - Lifecycle Observers（バックグラウンド対応）

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleEnterForeground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleMemoryWarning()
            }
        }
    }

    private func handleEnterBackground() {
        logger.info("App entering background, state: \(String(describing: self.state))")
        if state == .generating {
            // 推論中にバックグラウンドへ移行: キャンセルして状態を保存
            stateBeforeBackground = .generating
            stopGeneration()
        } else if state == .ready {
            stateBeforeBackground = .ready
        }
        stopMemoryMonitor()
    }

    private func handleEnterForeground() {
        logger.info("App entering foreground")
        if stateBeforeBackground == .ready && llm != nil {
            state = .ready
            startMemoryMonitor()
        }
        stateBeforeBackground = nil
    }

    private func handleMemoryWarning() {
        logger.warning("Memory warning received! Current usage: \(Self.currentMemoryUsageMB)MB")
        if state == .generating {
            stopGeneration()
        }
        // メモリ圧迫時はモデルをアンロード
        if state != .notLoaded {
            logger.warning("Unloading model due to memory pressure")
            unloadModel()
            state = .error("メモリ不足のためモデルをアンロードしました。再度読み込んでください。")
        }
    }

    // MARK: - Memory Monitor

    private func startMemoryMonitor() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.memoryUsageMB = Self.currentMemoryUsageMB
            }
        }
        // 初回即時更新
        memoryUsageMB = Self.currentMemoryUsageMB
    }

    private func stopMemoryMonitor() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
    }

    // MARK: - Model Loading

    /// モデルファイルのローカル保存先URL
    private func localModelURL(for type: ModelType) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent(type.ggufFilename)
    }

    func loadModel(type: ModelType = .gemma3_1b) async {
        guard state != .loading && state != .generating else { return }

        // メモリチェック
        guard Self.hasEnoughMemory(for: type) else {
            state = .error("\(type.displayName) を読み込むにはメモリが不足しています")
            return
        }

        // 既存モデルがあればアンロード
        if llm != nil {
            unloadModel()
        }

        state = .loading
        currentModelType = type
        downloadProgress = nil

        let localURL = localModelURL(for: type)

        do {
            // Step 1: ローカルにGGUFファイルが無ければダウンロード
            if !FileManager.default.fileExists(atPath: localURL.path) {
                logger.info("Model not cached, downloading from: \(type.directDownloadURL.absoluteString)")
                try await downloadModelFile(from: type.directDownloadURL, to: localURL)
            } else {
                logger.info("Model already cached at: \(localURL.path)")
                state = .downloading(progress: 1.0)
            }

            // Step 2: ローカルファイルからモデルを読み込み
            state = .loading
            logger.info("Loading model from local file...")

            let model = LLM(
                from: localURL,
                template: gemmaTemplate(systemPrompt: defaultSystemPrompt),
                maxTokenCount: 4096
            )

            if let model = model {
                self.llm = model
                state = .ready
                startMemoryMonitor()
                UserDefaults.standard.set(true, forKey: "modelCached_\(type.rawValue)")
                logger.info("Model loaded successfully: \(type.displayName)")
            } else {
                state = .error("モデルファイルの読み込みに失敗しました。ファイルが破損している可能性があります。")
                logger.error("LLM init returned nil for \(type.displayName)")
                // 破損ファイルを削除して次回再ダウンロードさせる
                try? FileManager.default.removeItem(at: localURL)
            }
        } catch {
            state = .error("モデルのダウンロードに失敗しました: \(error.localizedDescription)")
            logger.error("Model load error: \(error)")
            // 不完全なファイルを削除
            try? FileManager.default.removeItem(at: localURL)
        }

        downloadProgress = nil
    }

    // MARK: - Direct Download（HuggingFace直接ダウンロード）

    /// URLSessionでGGUFファイルを直接ダウンロード（進捗表示付き）
    private func downloadModelFile(from remoteURL: URL, to localURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: remoteURL) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: URLError(.cannotCreateFile))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    continuation.resume(throwing: URLError(.badServerResponse, userInfo: [
                        NSLocalizedDescriptionKey: "サーバーエラー (HTTP \(statusCode))"
                    ]))
                    return
                }
                do {
                    // 既存ファイルがあれば削除
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        try FileManager.default.removeItem(at: localURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: localURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // 進捗監視
            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.state = .downloading(progress: fraction)
                    self.downloadProgress = DownloadProgress(
                        progress: fraction,
                        estimatedTotalBytes: task.countOfBytesExpectedToReceive > 0 ? UInt64(task.countOfBytesExpectedToReceive) : nil,
                        downloadedBytes: UInt64(task.countOfBytesReceived)
                    )
                }
            }

            task.resume()

            // observationをタスク完了まで保持（解放防止）
            _ = observation
        }
    }

    // MARK: - Text Generation（ストリーミング）

    // BUG-2 全面改修:
    // 旧実装の問題点:
    //   1) タイムアウトはフラグをセットするだけで、for-await がブロック中は検査不能
    //   2) [weak self] の ?? true により、まれに self が nil 扱いされループ即断
    //   3) Gemma テンプレートが <start_of_turn>user でシステムプロンプトを包んでいた（上記修正済み）
    //
    // 新実装:
    //   - Task { ... } でラップし .cancel() で確実に for-await ループを打ち切る
    //   - タイムアウトは別 Task.sleep で実装し、時間切れで generationTask.cancel()
    //   - stopGeneration() も generationTask.cancel() を呼ぶ（BUG-4修正）

    @discardableResult
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        onToken: @escaping (String) -> Void
    ) async -> String {

        // ── クラウドモデルの場合は CloudLLMService にルーティング ──
        if currentModelType.isCloud {
            return await generateCloud(
                prompt: prompt,
                systemPrompt: systemPrompt ?? defaultSystemPrompt,
                conversationHistory: conversationHistory,
                onToken: onToken
            )
        }

        // .generating 状態でスタックしている場合は強制リカバリー
        if state == .generating {
            logger.warning("[generate] .generating でスタック検出 — 前のタスクをキャンセルしてリカバリー")
            currentGenerationTask?.cancel()
            currentGenerationTask = nil
            state = .ready
        }

        guard let llm = llm, state == .ready else {
            logger.error("[generate] モデル未ロード / 状態不正: \(String(describing: self.state))")
            return "[エラー] モデルが読み込まれていません"
        }

        // BUG-4修正: llm.history の蓄積問題を防ぐため、毎回クリアして渡された履歴から再構築する。
        // LLM.swift は respond() 呼び出しごとに history に (.user, input), (.bot, output) を追記するため、
        // 明示的にリセットしなければ2回目以降のプロンプトが肥大化し、モデルが応答を生成できなくなる。
        llm.history.removeAll()
        let validHistory = conversationHistory.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for msg in validHistory {
            switch msg.role {
            case "user":      llm.history.append((role: .user, content: msg.content))
            case "assistant": llm.history.append((role: .bot,  content: msg.content))
            default: break
            }
        }

        state = .generating
        generationCancelled = false
        generationTimedOut = false
        tokensPerSecond = 0

        // システムプロンプト更新
        if let sp = systemPrompt {
            llm.template = gemmaTemplate(systemPrompt: sp)
            logger.info("[generate] テンプレート更新完了")
        }

        let generationStart = Date()

        // ── 生成タスク（Swift Task でラップ → cancel() 可能にする） ──
        // (String, Int): 出力テキスト + トークン数 のタプルを返す
        let genTask = Task<(String, Int), Never> { [weak self] in
            guard let self, let llm = self.llm else {
                self?.logger.error("[generate] genTask: self または llm が nil")
                return ("", 0)
            }

            var tokenCount = 0
            var accumulated = ""

            await llm.respond(to: prompt) { responseStream in
                var output = ""
                for await token in responseStream {
                    if Task.isCancelled { break }
                    output += token
                    tokenCount += 1
                    onToken(token)
                }
                accumulated = output
                return output
            }
            // BUG-5修正: カスタムコールバックパス (respond(to:with:)) では postprocess() が
            // 呼ばれるだけで llm.output は更新されない。
            // llm.output へのフォールバックは常に "" を返すため除去し、accumulated を直接使用する。
            // accumulated が空 = トークンが0件 (モデル失敗) → ChatService 側で "[応答なし]" に変換。
            return (accumulated, tokenCount)
        }
        currentGenerationTask = Task { _ = await genTask.value }

        // ── タイムアウトタスク ──
        let timeoutSeconds = generationTimeoutSeconds
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                // タイムアウト発火: まだ生成中なら genTask をキャンセル
                await MainActor.run { [weak self] in
                    guard let self, self.state == .generating else { return }
                    self.logger.warning("[generate] タイムアウト (\(timeoutSeconds)秒) — genTask をキャンセル")
                    self.generationTimedOut = true
                    genTask.cancel()
                }
            } catch {
                // genTask が先に完了して timeoutTask が cancel された場合は無視
            }
        }

        // 生成完了を待つ
        let (finalOutput, tokenCount) = await genTask.value
        timeoutTask.cancel()
        currentGenerationTask = nil

        // トークン速度を計算
        let elapsed = Date().timeIntervalSince(generationStart)
        if elapsed > 0 && tokenCount > 0 {
            tokensPerSecond = Double(tokenCount) / elapsed
        }

        let result: String
        if generationTimedOut {
            result = finalOutput.isEmpty ? "[タイムアウト: 応答なし]" : finalOutput + " [タイムアウト]"
            logger.warning("[generate] タイムアウト完了: \(tokenCount) tokens / \(String(format: "%.1f", elapsed))秒")
        } else if generationCancelled || genTask.isCancelled {
            result = finalOutput.isEmpty ? "[生成中断]" : finalOutput + " [中断]"
            logger.info("[generate] 中断: \(tokenCount) tokens")
        } else {
            result = finalOutput
            logger.info("[generate] 完了: \(tokenCount) tokens / \(String(format: "%.1f", elapsed))秒 / \(String(format: "%.1f", self.tokensPerSecond)) tok/s")
            if !result.isEmpty {
                logger.info("[generate] 出力先頭100文字: \(result.prefix(100))")
            } else {
                logger.warning("[generate] 出力が空 — モデルがトークンを生成しなかった可能性")
            }
        }

        state = .ready
        generationCancelled = false
        generationTimedOut = false
        return result
    }

    // MARK: - Generation Control

    /// 推論をキャンセル（ストリーミング中に停止ボタンで呼ぶ） BUG-4修正
    func stopGeneration() {
        guard state == .generating else { return }
        logger.info("[stopGeneration] ユーザーによる中断リクエスト")
        if currentModelType.isCloud {
            CloudLLMService.shared.cancel()
            state = .ready
        } else {
            generationCancelled = true
            currentGenerationTask?.cancel()
            currentGenerationTask = nil
        }
    }

    /// 推論中かどうか
    var isGenerating: Bool {
        state == .generating
    }

    var isModelLoaded: Bool {
        llm != nil && state == .ready
    }

    func unloadModel() {
        stopMemoryMonitor()
        llm = nil
        state = .notLoaded
        downloadProgress = nil
        memoryUsageMB = 0
        logger.info("Model unloaded")
    }

    /// キャッシュされたモデルファイルを削除（再ダウンロード用）
    func deleteModelCache(for type: ModelType) {
        let localURL = localModelURL(for: type)
        try? FileManager.default.removeItem(at: localURL)
        UserDefaults.standard.removeObject(forKey: "modelCached_\(type.rawValue)")
        logger.info("Model cache deleted for \(type.displayName)")
    }

    /// モデルを切り替える
    func switchModel(to type: ModelType) async {
        if type == currentModelType { return }
        // ローカル→クラウド or クラウド→ローカルの場合、ローカルモデルをアンロード
        if !type.isCloud {
            unloadModel()
            await loadModel(type: type)
        } else {
            // クラウドモデルに切り替える場合はローカルモデルをアンロード
            if currentModelType.isLocal { unloadModel() }
            currentModelType = type
            state = .ready   // クラウドモデルは常に「使用可能」扱い
        }
    }

    // MARK: - Cloud Generation

    /// クラウドAIへのルーティング生成（CloudLLMService に委譲）
    private func generateCloud(
        prompt: String,
        systemPrompt: String,
        conversationHistory: [(role: String, content: String)],
        onToken: @escaping (String) -> Void
    ) async -> String {

        guard let provider = currentModelType.cloudProvider else {
            return "[エラー] クラウドプロバイダーが不明です"
        }

        guard KeychainService.shared.hasAPIKey(for: provider) else {
            return "[\(provider.displayName) のAPIキーが設定されていません。設定 → モデルから入力してください]"
        }

        state = .generating

        let history = conversationHistory.map {
            CloudMessage(role: $0.role, content: $0.content)
        }

        let modelID = currentModelType.cloudModelID

        do {
            let result = try await CloudLLMService.shared.generate(
                provider: provider,
                modelID: modelID,
                systemPrompt: systemPrompt,
                history: history,
                userPrompt: prompt,
                onToken: { token in
                    onToken(token)
                }
            )
            state = .ready
            return result
        } catch CloudLLMError.cancelled {
            state = .ready
            return "[生成中断]"
        } catch {
            state = .ready
            logger.error("[generateCloud] エラー: \(error.localizedDescription)")
            return "[クラウドAIエラー] \(error.localizedDescription)"
        }
    }

    /// クラウドモデルの生成を停止
    func stopCloudGeneration() {
        CloudLLMService.shared.cancel()
        state = .ready
    }
}
