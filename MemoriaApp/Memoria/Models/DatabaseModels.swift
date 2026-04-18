// DatabaseModels.swift
// Memoria for iPhone - GRDB Data Models
// Mac版SQLiteスキーマをSwift/GRDBで再実装

import Foundation
import GRDB

// MARK: - Session（会話セッション）
// MutablePersistableRecord を使うことで insert 後に id が自動設定される
struct Session: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64?
    var title: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "sessions"

    // 新規セッション作成用
    init(title: String = "新しい会話") {
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // GRDB: insert 後に自動採番された id をセットバック（BUG-3 修正）
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // Association: Session has many Messages
    static let messages = hasMany(Message.self)
    var messages: QueryInterfaceRequest<Message> {
        request(for: Session.messages)
    }

    // Association: Session has many MemorySummaries
    static let memorySummaries = hasMany(MemorySummary.self)
}

// MARK: - Message（チャットメッセージ）
// MutablePersistableRecord を使うことで insert 後に id が自動設定される
struct Message: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64?
    var role: String          // "user", "assistant", "system"
    var content: String
    var createdAt: Date
    var sessionId: Int64

    static let databaseTableName = "messages"

    // Association: Message belongs to Session
    static let session = belongsTo(Session.self)

    init(role: String, content: String, sessionId: Int64) {
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.sessionId = sessionId
    }

    // GRDB: insert 後に自動採番された id をセットバック
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - MemorySummary（セッション内記憶圧縮）
struct MemorySummary: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var summary: String
    var messageCount: Int
    var createdAt: Date
    var sessionId: Int64

    static let databaseTableName = "memory_summaries"

    // Association: MemorySummary belongs to Session
    static let session = belongsTo(Session.self)

    init(summary: String, messageCount: Int, sessionId: Int64) {
        self.summary = summary
        self.messageCount = messageCount
        self.createdAt = Date()
        self.sessionId = sessionId
    }
}

// MARK: - GlobalMemory（グローバルメモリ - /remember）
struct GlobalMemory: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var content: String
    var source: String        // "manual" or "auto"
    var createdAt: Date

    static let databaseTableName = "global_memory"

    init(content: String, source: String = "manual") {
        self.content = content
        self.source = source
        self.createdAt = Date()
    }
}

// MARK: - UserCommand（ユーザー定義コマンド）
struct UserCommand: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var name: String
    var commandDescription: String
    var promptTemplate: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "user_commands"

    // カラム名のマッピング（descriptionはSwift予約語に近いため）
    enum CodingKeys: String, CodingKey {
        case id, name
        case commandDescription = "description"
        case promptTemplate = "prompt_template"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(name: String, description: String, promptTemplate: String) {
        self.name = name.lowercased().replacingOccurrences(of: "/", with: "").replacingOccurrences(of: " ", with: "_")
        self.commandDescription = description
        self.promptTemplate = promptTemplate
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
