// SessionListView.swift
// Memoria for iPhone - Session List (Phase 2)
// NavigationSplitView対応のセッション一覧画面
// ThemeManager対応

import SwiftUI

// MARK: - Session Display Model

/// セッション一覧表示用のビューモデル（メッセージ数・プレビューを含む）
struct SessionDisplayItem: Identifiable {
    let session: Session
    let messageCount: Int
    let lastMessagePreview: String?

    var id: Int64? { session.id }
}

// MARK: - SessionListView

struct SessionListView: View {
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @State private var sessions: [SessionDisplayItem] = []
    @State private var selectedSessionId: Int64?
    @State private var searchText = ""
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: SessionDisplayItem?
    @State private var pulseAnimation = false
    // ② スワイプヒント: 初回のみ表示
    @AppStorage("swipeHintDismissed") private var swipeHintDismissed = false
    // リネーム用
    @State private var showRenameAlert = false
    @State private var sessionToRename: SessionDisplayItem?
    @State private var renameText = ""
    // 設定画面（sheet で表示 — NavigationLink push ではなく sheet にすることで
    // ContentView の NavigationStack との三重ネストを回避し、戻るボタンバグを防止）
    @State private var showSettings = false

    private let db = DatabaseService.shared

    var body: some View {
        Group {
            if sessions.isEmpty && searchText.isEmpty {
                welcomeView
            } else {
                sessionList
            }
        }
        .background(theme.colors.base)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // NavigationLink(destination:) から Button + sheet に変更
                // 理由: SettingsView を NavigationLink で push すると ContentView の
                // NavigationStack に SettingsView 独自の NavigationStack がネストされ、
                // Back ボタンの挙動が壊れる（ChatView が再 push される）
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(theme.colors.subtext0)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(loc)
        }
        .onAppear {
            loadSessions()
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .onChange(of: chatService.currentSessionId) { _, newId in
            loadSessions()
            selectedSessionId = newId
        }
        // リネームアラート
        .alert(loc["rename_session_title"], isPresented: $showRenameAlert) {
            TextField(loc["session_title_placeholder"], text: $renameText)
            Button(loc["save"]) {
                if let item = sessionToRename, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    renameSession(item, newTitle: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            Button(loc["cancel"], role: .cancel) {}
        } message: {
            Text(loc["rename_session_msg"])
        }
    }

    // MARK: - Welcome View（空状態）

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Orbital ロゴ
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
                    .frame(width: 100, height: 100)
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
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-30))

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28))
                    .foregroundColor(theme.colors.blue)
            }

            VStack(spacing: 8) {
                Text(loc["welcome_heading"])
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(theme.colors.text)

                Text(loc["welcome_sub"])
                    .font(.subheadline)
                    .foregroundColor(theme.colors.subtext0)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                featureRow(icon: "lock.shield", color: theme.colors.green, text: loc["feature_offline"])
                featureRow(icon: "brain", color: theme.colors.mauve, text: loc["feature_memory"])
                featureRow(icon: "globe", color: theme.colors.blue, text: loc["feature_multilang"])
            }
            .padding(.top, 8)

            // 新規セッション作成ボタン
            newSessionButton
                .padding(.top, 16)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.base)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 28)

            Text(text)
                .font(.subheadline)
                .foregroundColor(theme.colors.subtext0)

            Spacer()
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            // 検索バー
            searchBar

            // ② スワイプヒント（初回のみ表示 / 検索中は非表示）
            if !swipeHintDismissed && searchText.isEmpty && !sessions.isEmpty {
                swipeHintBar
            }

            // セッション一覧
            List {
                ForEach(filteredSessions) { item in
                    // NavigationLink(value:) + simultaneousGestureはSwiftUIのバグで
                    // タップが無効化されるケースがあるため、Buttonによるプログラム制御ナビゲーションに変更
                    Button {
                        // 検索ハイライトキーワードをセット
                        chatService.highlightKeyword = searchText.isEmpty ? nil : searchText
                        // セッションを選択してナビゲーション
                        if let id = item.session.id {
                            selectedSessionId = id
                            chatService.selectSession(id: id)
                        }
                    } label: {
                        SessionRowView(
                            item: item,
                            isSelected: selectedSessionId == item.session.id
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        (selectedSessionId == item.session.id ? theme.colors.surface1 : Color.clear)
                            .animation(.easeInOut(duration: 0.2), value: selectedSessionId)
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                deleteSession(item)
                            }
                        } label: {
                            Label(loc["delete"], systemImage: "trash")
                        }
                        // リネームアクション
                        Button {
                            sessionToRename = item
                            renameText = item.session.title
                            showRenameAlert = true
                        } label: {
                            Label(loc["rename_session"], systemImage: "pencil")
                        }
                        .tint(theme.colors.blue)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.colors.base)

            // 下部の新規セッションボタン
            newSessionButton
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(theme.colors.base)
        }
    }

    // MARK: - Swipe Hint Bar（初回のみ表示）

    private var swipeHintBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.left")
                .font(.system(size: 12))
                .foregroundColor(theme.colors.blue)
            Text(loc["swipe_hint"])
                .font(.system(size: 12))
                .foregroundColor(theme.colors.subtext0)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    swipeHintDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.colors.overlay0)
                    .padding(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.colors.blue.opacity(0.06))
        .overlay(
            Rectangle()
                .fill(theme.colors.blue.opacity(0.15))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(theme.colors.overlay0)

            TextField(loc["search_sessions"], text: $searchText)
                .font(.subheadline)
                .foregroundColor(theme.colors.text)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    withAnimation {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.colors.overlay0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.colors.surface0)
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - New Session Button

    private var newSessionButton: some View {
        Button {
            createNewSession()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.bubble.fill")
                    .font(.system(size: 18))
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)

                Text(loc["new_conversation"])
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundColor(theme.colors.base)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [theme.colors.blue, theme.colors.mauve],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: theme.colors.blue.opacity(pulseAnimation ? 0.4 : 0.15), radius: pulseAnimation ? 12 : 6, y: 4)
        }
    }

    // MARK: - Filtered Sessions

    private var filteredSessions: [SessionDisplayItem] {
        if searchText.isEmpty {
            return sessions
        }
        // DBのfull-text検索（メッセージ全文 + タイトルを対象）
        do {
            let matchingSessions = try db.searchSessions(query: searchText)
            let matchingIds = Set(matchingSessions.compactMap { $0.id })
            return sessions.filter { item in
                guard let id = item.session.id else { return false }
                return matchingIds.contains(id)
            }
        } catch {
            // フォールバック: クライアント側フィルタ
            let query = searchText.lowercased()
            return sessions.filter { item in
                item.session.title.lowercased().contains(query) ||
                (item.lastMessagePreview?.lowercased().contains(query) ?? false)
            }
        }
    }

    // MARK: - Actions

    private func loadSessions() {
        do {
            // 効率的なクエリ: セッションごとに最新1件だけ取得（全メッセージ読み込み回避）
            let previews = try db.getSessionsWithPreview()
            sessions = previews.map { preview in
                SessionDisplayItem(
                    session: preview.session,
                    messageCount: preview.messageCount,
                    lastMessagePreview: preview.lastMessage
                )
            }
        } catch {
            print("[SessionListView] Failed to load sessions: \(error)")
        }
    }

    private func createNewSession() {
        // ナビゲーション含めてChatService内で完結する
        chatService.createNewSession()
        if let newId = chatService.currentSessionId {
            selectedSessionId = newId
        }
        loadSessions()
    }

    private func renameSession(_ item: SessionDisplayItem, newTitle: String) {
        do {
            try db.updateSessionTitle(item.session, title: newTitle)
            loadSessions()
        } catch {
            print("[SessionListView] Failed to rename session: \(error)")
        }
    }

    private func deleteSession(_ item: SessionDisplayItem) {
        do {
            try db.deleteSession(item.session)
            sessions.removeAll { $0.session.id == item.session.id }
            // 削除したのが現在のセッションなら選択解除
            if selectedSessionId == item.session.id {
                selectedSessionId = nil
            }
        } catch {
            print("[SessionListView] Failed to delete session: \(error)")
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    let item: SessionDisplayItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // アバターアイコン
            sessionAvatar

            // セッション情報
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.colors.text)
                        .lineLimit(1)

                    Spacer()

                    Text(relativeDate(item.session.updatedAt))
                        .font(.system(size: 11))
                        .foregroundColor(theme.colors.overlay0)
                }

                if let preview = item.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 13))
                        .foregroundColor(theme.colors.subtext0)
                        .lineLimit(2)
                }

                // メッセージ数バッジ
                if item.messageCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 10))
                        Text("\(item.messageCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(theme.colors.overlay0)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? theme.colors.surface1 : theme.colors.surface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? theme.colors.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Session Avatar

    private var sessionAvatar: some View {
        let icons = [
            "brain.head.profile", "bubble.left.fill", "text.bubble.fill",
            "lightbulb.fill", "star.fill", "heart.fill",
            "book.fill", "pencil.and.outline", "globe"
        ]
        let colors = [theme.colors.blue, theme.colors.mauve, theme.colors.green, theme.colors.peach]

        let hashValue = abs(item.session.title.hashValue)
        let icon = icons[hashValue % icons.count]
        let color = colors[hashValue % colors.count]

        return ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 44, height: 44)

            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
        }
    }

    // MARK: - Relative Date

    private func relativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return loc["just_now"]
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(format: loc["min_ago_fmt"], minutes)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(format: loc["hour_ago_fmt"], hours)
        } else if interval < 172800 {
            return loc["yesterday"]
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return String(format: loc["days_ago_fmt"], days)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview {
    SessionListView()
        .environmentObject(ChatService())
        .environmentObject(ThemeManager.shared)
        .environmentObject(LocalizationService.shared)
}
