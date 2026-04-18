// GlobalMemoryManagementView.swift
// Memoria for iPhone - グローバルメモリ一覧・管理画面
// /remember で登録した記憶の一覧表示・個別削除・手動追加

import SwiftUI

struct GlobalMemoryManagementView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    private let db = DatabaseService.shared

    @State private var memories: [GlobalMemory] = []
    @State private var showAddAlert = false
    @State private var newMemoryText = ""
    @State private var memoryToDelete: GlobalMemory? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        ZStack {
            theme.colors.base.ignoresSafeArea()

            if memories.isEmpty {
                emptyState
            } else {
                memoryList
            }
        }
        .navigationTitle(loc["mem_manage_title"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.surface0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newMemoryText = ""
                    showAddAlert = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                        .foregroundColor(theme.colors.blue)
                }
            }
        }
        // 手動追加アラート
        .alert(loc["mem_add_title"], isPresented: $showAddAlert) {
            TextField(loc["mem_add_placeholder"], text: $newMemoryText)
                .autocorrectionDisabled()
            Button(loc["save"]) {
                let trimmed = newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try? db.addGlobalMemory(content: trimmed, source: "manual")
                    loadMemories()
                }
            }
            .disabled(newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(loc["cancel"], role: .cancel) {}
        } message: {
            Text(loc["mem_add_msg"])
        }
        // 個別削除確認アラート
        .alert(loc["mem_delete_confirm"], isPresented: $showDeleteAlert, presenting: memoryToDelete) { mem in
            Button(loc["delete"], role: .destructive) {
                if let id = mem.id {
                    try? db.deleteGlobalMemory(id: id)
                    loadMemories()
                }
            }
            Button(loc["cancel"], role: .cancel) {}
        } message: { mem in
            Text(mem.content.prefix(60) + (mem.content.count > 60 ? "…" : ""))
        }
        .onAppear { loadMemories() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 52))
                .foregroundColor(theme.colors.overlay0)

            VStack(spacing: 6) {
                Text(loc["mem_empty_title"])
                    .font(.headline)
                    .foregroundColor(theme.colors.text)
                Text(loc["mem_empty_sub"])
                    .font(.subheadline)
                    .foregroundColor(theme.colors.subtext0)
                    .multilineTextAlignment(.center)
            }

            Button {
                newMemoryText = ""
                showAddAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text(loc["mem_add_title"])
                        .fontWeight(.semibold)
                }
                .foregroundColor(theme.colors.base)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.colors.mauve)
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Memory List

    private var memoryList: some View {
        VStack(spacing: 0) {
            // 件数ヘッダー
            HStack {
                Text(String(format: loc["mem_count_fmt"], memories.count))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.colors.subtext0)
                Spacer()
                Text(loc["mem_hint"])
                    .font(.caption2)
                    .foregroundColor(theme.colors.overlay0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach(memories) { memory in
                    memoryRow(memory)
                        .listRowBackground(theme.colors.surface0)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                memoryToDelete = memory
                                showDeleteAlert = true
                            } label: {
                                Label(loc["delete"], systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.colors.base)
        }
    }

    private func memoryRow(_ memory: GlobalMemory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // ソースアイコン
            ZStack {
                Circle()
                    .fill(sourceColor(memory.source).opacity(0.13))
                    .frame(width: 36, height: 36)
                Image(systemName: sourceIcon(memory.source))
                    .font(.system(size: 15))
                    .foregroundColor(sourceColor(memory.source))
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(memory.content)
                    .font(.subheadline)
                    .foregroundColor(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    // ソースバッジ
                    Text(sourceLabel(memory.source))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(sourceColor(memory.source))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(sourceColor(memory.source).opacity(0.12))
                        )

                    // 日付
                    Text(relativeDate(memory.createdAt))
                        .font(.caption2)
                        .foregroundColor(theme.colors.overlay0)
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.surface0)
        )
    }

    // MARK: - Helpers

    private func loadMemories() {
        memories = (try? db.getAllGlobalMemories()) ?? []
    }

    private func sourceIcon(_ source: String) -> String {
        switch source {
        case "manual":  return "hand.point.right.fill"
        case "auto":    return "sparkles"
        default:        return "brain"
        }
    }

    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "manual":  return theme.colors.blue
        case "auto":    return theme.colors.mauve
        default:        return theme.colors.subtext0
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "manual":  return loc["mem_source_manual"]
        case "auto":    return loc["mem_source_auto"]
        default:        return source
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return loc["just_now"] }
        if interval < 3600 { return String(format: loc["min_ago_fmt"], Int(interval / 60)) }
        if interval < 86400 { return String(format: loc["hour_ago_fmt"], Int(interval / 3600)) }
        if interval < 172800 { return loc["yesterday"] }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        GlobalMemoryManagementView()
            .environmentObject(ThemeManager.shared)
            .environmentObject(LocalizationService.shared)
    }
}
