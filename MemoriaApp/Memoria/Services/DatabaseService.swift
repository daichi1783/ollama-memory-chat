// DatabaseService.swift
// Memoria for iPhone - SQLite Database Service (GRDB.swift)
// Mac版 memory_manager.py のSwift移植
// Phase 2: バックグラウンドDB操作、エラーハンドリング強化、プレビュー付きセッション一覧、検索、ユーザー定義コマンドCRUD

import Foundation
import GRDB
import Combine
import os.log

// MARK: - Database Errors

enum DatabaseError: LocalizedError {
    case notInitialized
    case sessionNotFound(Int64)
    case commandNotFound(String)
    case duplicateCommand(String)
    case invalidInput(String)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "データベースが初期化されていません"
        case .sessionNotFound(let id):
            return "セッションが見つかりません (ID: \(id))"
        case .commandNotFound(let name):
            return "コマンドが見つかりません: /\(name)"
        case .duplicateCommand(let name):
            return "コマンド /\(name) は既に存在します"
        case .invalidInput(let reason):
            return "不正な入力: \(reason)"
        case .migrationFailed(let detail):
            return "マイグレーション失敗: \(detail)"
        }
    }
}

// MARK: - Session Preview DTO

struct SessionPreview {
    let session: Session
    let lastMessage: String?
    let messageCount: Int
}

// MARK: - Database Stats DTO

struct DatabaseStats {
    let sessionCount: Int
    let messageCount: Int
    let globalMemoryCount: Int
    let summaryCount: Int
    let databaseSizeBytes: Int64
}

class DatabaseService: ObservableObject {
    static let shared = DatabaseService()

    private var dbQueue: DatabaseQueue?
    @Published var isReady: Bool = false
    @Published var setupError: String?
    private let logger = Logger(subsystem: "com.memoria.app", category: "Database")

    // 記憶圧縮の閾値（N往復 = N*2メッセージごと）
    let compressionThreshold: Int = 10

    private init() {
        do {
            try setupDatabase()
            isReady = true
            logger.info("Database setup completed successfully")
        } catch {
            logger.fault("Database setup failed: \(error.localizedDescription)")
            setupError = error.localizedDescription
            // fatalErrorは使わない — UIでエラーを表示する
        }
    }

    /// DBが初期化済みかチェックし、未初期化なら例外をスロー
    private func requireDB() throws -> DatabaseQueue {
        guard let db = dbQueue else {
            throw DatabaseError.notInitialized
        }
        return db
    }

    // MARK: - Database Setup

    private func setupDatabase() throws {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = documentsURL.appendingPathComponent("memoria.db")
        logger.info("Database path: \(dbURL.path)")

        var config = Configuration()
        // WALモード有効化（バックグラウンド操作との並行性向上）
        // prepareDatabase はトランザクション外で実行されるため PRAGMA が正常に動作する
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)

        // マイグレーション実行
        do {
            guard let db = dbQueue else { throw DatabaseError.notInitialized }
            try migrator.migrate(db)
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
            throw DatabaseError.migrationFailed(error.localizedDescription)
        }
    }

    // MARK: - Schema Migration

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            // sessions テーブル
            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull().defaults(to: "新しい会話")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // messages テーブル
            try db.create(table: "messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("sessionId", .integer).notNull()
                    .references("sessions", onDelete: .cascade)
            }

            // memory_summaries テーブル
            try db.create(table: "memory_summaries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("summary", .text).notNull()
                t.column("messageCount", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("sessionId", .integer).notNull()
                    .references("sessions", onDelete: .cascade)
            }

            // global_memory テーブル
            try db.create(table: "global_memory") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content", .text).notNull()
                t.column("source", .text).notNull().defaults(to: "manual")
                t.column("createdAt", .datetime).notNull()
            }

            // user_commands テーブル
            try db.create(table: "user_commands") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("description", .text).notNull()
                t.column("prompt_template", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }

        // Phase 2: インデックス追加（検索・プレビュー高速化）
        migrator.registerMigration("v2_add_indexes") { db in
            // メッセージのセッション別取得を高速化
            try db.create(
                index: "idx_messages_sessionId_createdAt",
                on: "messages",
                columns: ["sessionId", "createdAt"]
            )
            // セッション検索用にタイトルインデックス
            try db.create(
                index: "idx_sessions_title",
                on: "sessions",
                columns: ["title"]
            )
            // ユーザーコマンド名で高速検索
            try db.create(
                index: "idx_user_commands_name",
                on: "user_commands",
                columns: ["name"]
            )
        }

        return migrator
    }

    // MARK: - Background Database Access

    /// バックグラウンドスレッドでDB読み取りを実行
    private func readInBackground<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [dbQueue] in
                guard let dbQueue = dbQueue else {
                    continuation.resume(throwing: DatabaseError.notInitialized)
                    return
                }
                do {
                    let result = try dbQueue.read(block)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// バックグラウンドスレッドでDB書き込みを実行
    private func writeInBackground<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [dbQueue] in
                guard let dbQueue = dbQueue else {
                    continuation.resume(throwing: DatabaseError.notInitialized)
                    return
                }
                do {
                    let result = try dbQueue.write(block)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Session CRUD

    func createSession(title: String = "新しい会話") throws -> Session {
        try requireDB().write { db in
            // BUG-3修正: var にすることで MutablePersistableRecord の didInsert が id をセットバックする
            var session = Session(title: title)
            try session.insert(db)
            // insert 後は session.id に自動採番された値が入っている
            return session
        }
    }

    func getAllSessions() throws -> [Session] {
        try requireDB().read { db in
            try Session.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    func getSession(id: Int64) throws -> Session {
        try requireDB().read { db in
            guard let session = try Session.fetchOne(db, key: id) else {
                throw DatabaseError.sessionNotFound(id)
            }
            return session
        }
    }

    func updateSessionTitle(_ session: Session, title: String) throws {
        try requireDB().write { db in
            var updated = session
            updated.title = title
            updated.updatedAt = Date()
            try updated.update(db)
        }
    }

    func deleteSession(_ session: Session) throws {
        try requireDB().write { db in
            _ = try session.delete(db)
        }
        logger.info("Session deleted: \(session.id ?? -1)")
    }

    /// セッション削除（ID指定）
    func deleteSession(id: Int64) throws {
        let session = try getSession(id: id)
        try deleteSession(session)
    }

    // MARK: - Session Preview（プレビュー付きセッション一覧）

    /// セッション一覧をプレビュー付きで取得（最終メッセージ＆メッセージ数）
    func getSessionsWithPreview() throws -> [SessionPreview] {
        try requireDB().read { db in
            let sessions = try Session.order(Column("updatedAt").desc).fetchAll(db)

            return try sessions.map { session in
                guard let sessionId = session.id else {
                    return SessionPreview(session: session, lastMessage: nil, messageCount: 0)
                }

                // 最新メッセージを1件取得
                let lastMessage = try Message
                    .filter(Column("sessionId") == sessionId)
                    .order(Column("createdAt").desc)
                    .limit(1)
                    .fetchOne(db)

                // メッセージ数
                let count = try Message
                    .filter(Column("sessionId") == sessionId)
                    .fetchCount(db)

                // プレビュー文字列（先頭80文字に制限）
                let preview: String? = lastMessage.map { msg in
                    let raw = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.count > 80 ? String(raw.prefix(80)) + "..." : raw
                }

                return SessionPreview(
                    session: session,
                    lastMessage: preview,
                    messageCount: count
                )
            }
        }
    }

    /// バックグラウンドでプレビュー付きセッション一覧を取得
    func getSessionsWithPreviewAsync() async throws -> [SessionPreview] {
        try await readInBackground { db in
            let sessions = try Session.order(Column("updatedAt").desc).fetchAll(db)

            return try sessions.map { session in
                guard let sessionId = session.id else {
                    return SessionPreview(session: session, lastMessage: nil, messageCount: 0)
                }

                let lastMessage = try Message
                    .filter(Column("sessionId") == sessionId)
                    .order(Column("createdAt").desc)
                    .limit(1)
                    .fetchOne(db)

                let count = try Message
                    .filter(Column("sessionId") == sessionId)
                    .fetchCount(db)

                let preview: String? = lastMessage.map { msg in
                    let raw = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    return raw.count > 80 ? String(raw.prefix(80)) + "..." : raw
                }

                return SessionPreview(
                    session: session,
                    lastMessage: preview,
                    messageCount: count
                )
            }
        }
    }

    // MARK: - Session Search

    /// セッション検索（タイトルとメッセージ内容をLIKE検索）
    func searchSessions(query: String) throws -> [Session] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try getAllSessions() }

        return try requireDB().read { db in
            let pattern = "%\(trimmed)%"

            // タイトル一致 OR メッセージ内容一致のセッションを返す
            let sql = """
                SELECT DISTINCT s.*
                FROM sessions s
                LEFT JOIN messages m ON m.sessionId = s.id
                WHERE s.title LIKE ?
                   OR m.content LIKE ?
                ORDER BY s.updatedAt DESC
                """
            return try Session.fetchAll(db, sql: sql, arguments: [pattern, pattern])
        }
    }

    // MARK: - Message CRUD

    func addMessage(role: String, content: String, sessionId: Int64) throws -> Message {
        try requireDB().write { db in
            // BUG-3修正: var にすることで MutablePersistableRecord の didInsert が id をセットバックする
            var message = Message(role: role, content: content, sessionId: sessionId)
            try message.insert(db)

            // セッションのupdatedAtを更新
            if var session = try Session.fetchOne(db, key: sessionId) {
                session.updatedAt = Date()
                try session.update(db)
            }

            return message
        }
    }

    func getMessages(sessionId: Int64, limit: Int? = nil) throws -> [Message] {
        try requireDB().read { db in
            var request = Message
                .filter(Column("sessionId") == sessionId)
                .order(Column("createdAt").asc)
            if let limit = limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    func getRecentMessages(sessionId: Int64, count: Int = 30) throws -> [Message] {
        try requireDB().read { db in
            let messages = try Message
                .filter(Column("sessionId") == sessionId)
                .order(Column("createdAt").desc)
                .limit(count)
                .fetchAll(db)
            return messages.reversed()
        }
    }

    func getMessageCount(sessionId: Int64) throws -> Int {
        try requireDB().read { db in
            try Message
                .filter(Column("sessionId") == sessionId)
                .fetchCount(db)
        }
    }

    // MARK: - Memory Compression（記憶圧縮）

    /// 圧縮が必要かどうか判定
    func shouldCompress(sessionId: Int64) throws -> Bool {
        let messageCount = try getMessageCount(sessionId: sessionId)
        let lastSummary = try getLatestSummary(sessionId: sessionId)
        let lastSummarizedCount = lastSummary?.messageCount ?? 0
        let newMessages = messageCount - lastSummarizedCount
        return newMessages >= compressionThreshold * 2
    }

    /// 最新のサマリーを取得
    func getLatestSummary(sessionId: Int64) throws -> MemorySummary? {
        try requireDB().read { db in
            try MemorySummary
                .filter(Column("sessionId") == sessionId)
                .order(Column("createdAt").desc)
                .fetchOne(db)
        }
    }

    /// サマリーを保存
    func saveSummary(summary: String, messageCount: Int, sessionId: Int64) throws {
        try requireDB().write { db in
            let memorySummary = MemorySummary(
                summary: summary,
                messageCount: messageCount,
                sessionId: sessionId
            )
            try memorySummary.insert(db)
        }
        logger.info("Summary saved for session \(sessionId), messageCount: \(messageCount)")
    }

    // MARK: - Global Memory（グローバルメモリ）

    func addGlobalMemory(content: String, source: String = "manual") throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DatabaseError.invalidInput("メモリ内容が空です")
        }
        try requireDB().write { db in
            let memory = GlobalMemory(content: trimmed, source: source)
            try memory.insert(db)
        }
    }

    func getAllGlobalMemories() throws -> [GlobalMemory] {
        try requireDB().read { db in
            try GlobalMemory.order(Column("id").desc).fetchAll(db)
        }
    }

    func deleteGlobalMemory(id: Int64) throws {
        try requireDB().write { db in
            _ = try GlobalMemory.deleteOne(db, key: id)
        }
    }

    // MARK: - User Commands CRUD（ユーザー定義コマンド）

    /// ユーザー定義コマンドを追加
    @discardableResult
    func addUserCommand(name: String, description: String, promptTemplate: String) throws -> UserCommand {
        let cleanName = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: " ", with: "_")

        guard !cleanName.isEmpty else {
            throw DatabaseError.invalidInput("コマンド名が空です")
        }
        guard !promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DatabaseError.invalidInput("プロンプトテンプレートが空です")
        }

        // 組み込みコマンドとの重複チェック
        let builtinCommands = ["help", "clear", "remember", "memory", "english", "japanese", "spanish", "cal"]
        guard !builtinCommands.contains(cleanName) else {
            throw DatabaseError.duplicateCommand(cleanName)
        }

        return try requireDB().write { db in
            // 既存コマンドとの重複チェック
            if try UserCommand.filter(Column("name") == cleanName).fetchOne(db) != nil {
                throw DatabaseError.duplicateCommand(cleanName)
            }

            let command = UserCommand(name: cleanName, description: description, promptTemplate: promptTemplate)
            try command.insert(db)
            return command
        }
    }

    /// 全ユーザー定義コマンドを取得
    func getAllUserCommands() throws -> [UserCommand] {
        try requireDB().read { db in
            try UserCommand.order(Column("name").asc).fetchAll(db)
        }
    }

    /// ユーザー定義コマンドを名前で取得
    func getUserCommand(name: String) throws -> UserCommand? {
        let cleanName = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "")

        return try requireDB().read { db in
            try UserCommand
                .filter(Column("name") == cleanName)
                .fetchOne(db)
        }
    }

    /// ユーザー定義コマンドを削除
    func deleteUserCommand(id: Int64) throws {
        try requireDB().write { db in
            guard try UserCommand.deleteOne(db, key: id) else {
                throw DatabaseError.commandNotFound("id=\(id)")
            }
        }
    }

    /// ユーザー定義コマンドを更新
    func updateUserCommand(id: Int64, description: String?, promptTemplate: String?) throws {
        try requireDB().write { db in
            guard var command = try UserCommand.fetchOne(db, key: id) else {
                throw DatabaseError.commandNotFound("id=\(id)")
            }
            if let description = description {
                command.commandDescription = description
            }
            if let promptTemplate = promptTemplate {
                command.promptTemplate = promptTemplate
            }
            command.updatedAt = Date()
            try command.update(db)
        }
    }

    // MARK: - System Prompt Builder

    func buildSystemPrompt(basePrompt: String, sessionId: Int64) throws -> String {
        var parts: [String] = [basePrompt]

        // グローバルメモリを注入
        let memories = try getAllGlobalMemories()
        if !memories.isEmpty {
            let memoryLines = memories.map { "・\($0.content)" }.joined(separator: "\n")
            parts.append("\n【ユーザーについての記憶】\n\(memoryLines)")
        }

        // セッションサマリーを注入
        if let summary = try getLatestSummary(sessionId: sessionId) {
            parts.append("\n【このセッションの記憶】\n\(summary.summary)")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Database Export（バックアップ）

    /// データベースファイルを一時ディレクトリにコピーして共有用URLを返す
    func exportDatabase() throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dbURL = documentsURL.appendingPathComponent("memoria.db")

        guard fileManager.fileExists(atPath: dbURL.path) else {
            logger.error("Database file not found for export at: \(dbURL.path)")
            throw DatabaseError.notInitialized
        }

        let tempDir = fileManager.temporaryDirectory
        let exportFileName = "memoria_backup_\(Int(Date().timeIntervalSince1970)).db"
        let exportURL = tempDir.appendingPathComponent(exportFileName)

        // 既存の一時ファイルがあれば削除
        if fileManager.fileExists(atPath: exportURL.path) {
            try fileManager.removeItem(at: exportURL)
        }

        // WALチェックポイントを実行して全データをメインDBファイルに書き出す
        do {
            try requireDB().write { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
        } catch {
            logger.warning("WAL checkpoint before export failed: \(error.localizedDescription)")
        }

        try fileManager.copyItem(at: dbURL, to: exportURL)
        logger.info("Database exported to: \(exportURL.path)")
        return exportURL
    }

    // MARK: - Database Statistics

    /// データベースの統計情報を取得
    func getDatabaseStats() throws -> DatabaseStats {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dbURL = documentsURL.appendingPathComponent("memoria.db")

        var dbSize: Int64 = 0
        if let attrs = try? fileManager.attributesOfItem(atPath: dbURL.path),
           let fileSize = attrs[.size] as? Int64 {
            dbSize = fileSize
        }

        // WAL/SHMファイルのサイズも加算
        let walURL = documentsURL.appendingPathComponent("memoria.db-wal")
        let shmURL = documentsURL.appendingPathComponent("memoria.db-shm")
        if let walAttrs = try? fileManager.attributesOfItem(atPath: walURL.path),
           let walSize = walAttrs[.size] as? Int64 {
            dbSize += walSize
        }
        if let shmAttrs = try? fileManager.attributesOfItem(atPath: shmURL.path),
           let shmSize = shmAttrs[.size] as? Int64 {
            dbSize += shmSize
        }

        return try requireDB().read { db in
            let sessionCount = try Session.fetchCount(db)
            let messageCount = try Message.fetchCount(db)
            let globalMemoryCount = try GlobalMemory.fetchCount(db)
            let summaryCount = try MemorySummary.fetchCount(db)

            return DatabaseStats(
                sessionCount: sessionCount,
                messageCount: messageCount,
                globalMemoryCount: globalMemoryCount,
                summaryCount: summaryCount,
                databaseSizeBytes: dbSize
            )
        }
    }

    // MARK: - Automatic Old Session Cleanup

    /// 指定日数より古いセッションとその関連データ（メッセージ・サマリー）を削除
    /// - Parameter days: この日数より古いセッションを削除（デフォルト90日）
    /// - Returns: 削除されたセッション数
    @discardableResult
    func cleanupOldSessions(olderThan days: Int = 90) throws -> Int {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return 0
        }

        let deletedCount = try requireDB().write { db -> Int in
            // カスケード削除が設定されているため、セッション削除で関連メッセージ・サマリーも削除される
            let sessions = try Session
                .filter(Column("updatedAt") < cutoffDate)
                .fetchAll(db)

            var count = 0
            for session in sessions {
                if try session.delete(db) {
                    count += 1
                }
            }
            return count
        }

        if deletedCount > 0 {
            logger.info("Cleaned up \(deletedCount) sessions older than \(days) days")
        }
        return deletedCount
    }
}
