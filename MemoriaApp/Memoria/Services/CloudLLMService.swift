// CloudLLMService.swift
// Memoria for iPhone - Cloud AI Streaming Service
// Phase 6: OpenAI / Claude (Anthropic) / Gemini (Google) SSEストリーミング対応

import Foundation
import os.log

// MARK: - Cloud LLM Error

enum CloudLLMError: LocalizedError {
    case noAPIKey(APIProvider)
    case networkUnavailable
    case httpError(Int, String)
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let provider):
            return "\(provider.displayName) のAPIキーが設定されていません"
        case .networkUnavailable:
            return "インターネット接続がありません。クラウドAIにはネット接続が必要です"
        case .httpError(let code, let message):
            return "APIエラー (HTTP \(code)): \(message)"
        case .invalidResponse:
            return "APIからの応答を解析できませんでした"
        case .cancelled:
            return "[生成中断]"
        }
    }
}

// MARK: - Cloud Message

struct CloudMessage {
    let role: String   // "user" or "assistant"
    let content: String
}

// MARK: - CloudLLMService

@MainActor
final class CloudLLMService {
    static let shared = CloudLLMService()
    private init() {}

    private let logger = Logger(subsystem: "com.memoria.app", category: "CloudLLM")
    private var currentTask: Task<Void, Never>?

    /// 生成をキャンセル
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Unified Generate

    /// プロバイダーを自動判定してストリーミング生成
    func generate(
        provider: APIProvider,
        modelID: String,
        systemPrompt: String,
        history: [CloudMessage],
        userPrompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let apiKey = KeychainService.shared.getAPIKey(for: provider) else {
            throw CloudLLMError.noAPIKey(provider)
        }

        logger.info("[Cloud] Provider=\(provider.displayName) Model=\(modelID)")

        switch provider {
        case .openai:
            return try await generateOpenAI(
                modelID: modelID, apiKey: apiKey,
                systemPrompt: systemPrompt, history: history,
                userPrompt: userPrompt, onToken: onToken
            )
        case .claude:
            return try await generateClaude(
                modelID: modelID, apiKey: apiKey,
                systemPrompt: systemPrompt, history: history,
                userPrompt: userPrompt, onToken: onToken
            )
        case .gemini:
            return try await generateGemini(
                modelID: modelID, apiKey: apiKey,
                systemPrompt: systemPrompt, history: history,
                userPrompt: userPrompt, onToken: onToken
            )
        }
    }

    // MARK: - OpenAI

    private func generateOpenAI(
        modelID: String,
        apiKey: String,
        systemPrompt: String,
        history: [CloudMessage],
        userPrompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": userPrompt])

        let body: [String: Any] = [
            "model": modelID,
            "messages": messages,
            "stream": true,
            "max_tokens": 4096,
            "temperature": 0.7
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        return try await streamSSE(
            request: request,
            tokenParser: { line in
                guard line.hasPrefix("data: ") else { return nil }
                let jsonStr = String(line.dropFirst(6))
                if jsonStr == "[DONE]" { return "" }

                guard let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let delta = first["delta"] as? [String: Any],
                      let text = delta["content"] as? String else { return nil }
                return text
            },
            onToken: onToken
        )
    }

    // MARK: - Claude (Anthropic)

    private func generateClaude(
        modelID: String,
        apiKey: String,
        systemPrompt: String,
        history: [CloudMessage],
        userPrompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {

        var messages: [[String: String]] = []
        for msg in history {
            let role = msg.role == "assistant" ? "assistant" : "user"
            messages.append(["role": role, "content": msg.content])
        }
        messages.append(["role": "user", "content": userPrompt])

        let body: [String: Any] = [
            "model": modelID,
            "system": systemPrompt,
            "messages": messages,
            "stream": true,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        return try await streamSSE(
            request: request,
            tokenParser: { line in
                guard line.hasPrefix("data: ") else { return nil }
                let jsonStr = String(line.dropFirst(6))

                guard let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

                // content_block_delta イベントのみテキストを抽出
                guard let type = json["type"] as? String, type == "content_block_delta",
                      let delta = json["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String, deltaType == "text_delta",
                      let text = delta["text"] as? String else { return nil }
                return text
            },
            onToken: onToken
        )
    }

    // MARK: - Gemini (Google)

    private func generateGemini(
        modelID: String,
        apiKey: String,
        systemPrompt: String,
        history: [CloudMessage],
        userPrompt: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {

        // Gemini の会話履歴フォーマット
        var contents: [[String: Any]] = []
        for msg in history {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }
        contents.append([
            "role": "user",
            "parts": [["text": userPrompt]]
        ])

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096,
                "temperature": 0.7
            ]
        ]

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):streamGenerateContent?alt=sse&key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        return try await streamSSE(
            request: request,
            tokenParser: { line in
                guard line.hasPrefix("data: ") else { return nil }
                let jsonStr = String(line.dropFirst(6))

                guard let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let first = candidates.first,
                      let content = first["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let part = parts.first,
                      let text = part["text"] as? String else { return nil }
                return text
            },
            onToken: onToken
        )
    }

    // MARK: - SSE Stream Core

    /// URLSession.bytes を使ってSSEストリームを行単位で処理する共通実装
    /// - tokenParser: SSEの1行を受け取り、トークン文字列を返す（nil=スキップ、""=終了）
    private func streamSSE(
        request: URLRequest,
        tokenParser: @escaping (String) -> String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        // HTTPステータスコードチェック
        if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
            // エラーボディを読み取る（最大2KB）
            var errBody = ""
            var count = 0
            for try await byte in asyncBytes {
                errBody += String(UnicodeScalar(byte))
                count += 1
                if count > 2048 { break }
            }
            logger.error("[Cloud] HTTP \(httpResp.statusCode): \(errBody)")
            throw CloudLLMError.httpError(httpResp.statusCode, parseErrorMessage(errBody))
        }

        var accumulated = ""

        for try await line in asyncBytes.lines {
            if Task.isCancelled { throw CloudLLMError.cancelled }

            guard let token = tokenParser(line) else { continue }
            if token.isEmpty { continue }  // [DONE] や空行

            accumulated += token
            onToken(token)
        }

        logger.info("[Cloud] 生成完了: \(accumulated.count) chars")
        return accumulated
    }

    // MARK: - Helpers

    private func parseErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body.prefix(200).description
        }
        // OpenAI / Claude / Gemini 共通のエラー構造を試みる
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let message = json["message"] as? String { return message }
        return body.prefix(200).description
    }
}
