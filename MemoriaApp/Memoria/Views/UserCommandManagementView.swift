// UserCommandManagementView.swift
// Memoria for iPhone - カスタムコマンド管理画面
// 設定から開くカスタム "/" コマンドの一覧・追加・削除ビュー

import SwiftUI

// MARK: - UserCommandManagementView

struct UserCommandManagementView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @StateObject private var db = DatabaseService.shared

    @State private var commands: [UserCommand] = []
    @State private var showAddSheet = false
    @State private var commandToDelete: UserCommand? = nil
    @State private var showDeleteAlert = false
    /// 編集対象コマンド（nilなら新規作成シート）
    @State private var commandToEdit: UserCommand? = nil

    var body: some View {
        ZStack {
            theme.colors.base.ignoresSafeArea()

            if commands.isEmpty {
                emptyState
            } else {
                commandList
            }
        }
        .navigationTitle(loc["cmd_manage_title"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.colors.surface0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                        .foregroundColor(theme.colors.blue)
                }
            }
        }
        // 新規追加シート
        .sheet(isPresented: $showAddSheet, onDismiss: loadCommands) {
            AddCommandView()
                .environmentObject(theme)
                .environmentObject(loc)
        }
        // 編集シート（commandToEdit が非nilになると開く）
        .sheet(item: $commandToEdit, onDismiss: loadCommands) { cmd in
            AddCommandView(editingCommand: cmd)
                .environmentObject(theme)
                .environmentObject(loc)
        }
        .alert(loc["cmd_delete_confirm"], isPresented: $showDeleteAlert, presenting: commandToDelete) { cmd in
            Button(loc["delete"], role: .destructive) {
                deleteCommand(cmd)
            }
            Button(loc["cancel"], role: .cancel) {}
        } message: { cmd in
            Text("/\(cmd.name)")
        }
        .onAppear { loadCommands() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(theme.colors.overlay0)

            VStack(spacing: 6) {
                Text(loc["cmd_manage_empty"])
                    .font(.headline)
                    .foregroundColor(theme.colors.text)
                Text(loc["cmd_manage_empty_sub"])
                    .font(.subheadline)
                    .foregroundColor(theme.colors.subtext0)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text(loc["cmd_add_title"])
                        .fontWeight(.semibold)
                }
                .foregroundColor(theme.colors.base)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.colors.blue)
                )
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Command List

    private var commandList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, cmd in
                    commandRow(cmd)
                    if index < commands.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                            .background(theme.colors.surface1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.colors.surface0)
            )
            .padding(16)

            // 使い方ガイド
            usageNote
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        }
    }

    private func commandRow(_ cmd: UserCommand) -> some View {
        HStack(spacing: 14) {
            // コマンド名バッジ
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.colors.blue.opacity(0.12))
                    .frame(width: 42, height: 42)
                Text("/")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.colors.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("/\(cmd.name)")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundColor(theme.colors.text)
                    .lineLimit(1)
                if !cmd.commandDescription.isEmpty {
                    Text(cmd.commandDescription)
                        .font(.caption)
                        .foregroundColor(theme.colors.subtext0)
                        .lineLimit(1)
                }
                // テンプレートプレビュー
                Text(cmd.promptTemplate)
                    .font(.caption2)
                    .foregroundColor(theme.colors.overlay0)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // 編集ボタン
            Button {
                commandToEdit = cmd
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15))
                    .foregroundColor(theme.colors.blue.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)

            // 削除ボタン
            Button {
                commandToDelete = cmd
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                    .foregroundColor(theme.colors.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var usageNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(theme.colors.blue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(loc["cmd_usage_label"])
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.colors.subtext0)
                Text(loc["cmd_usage_example"])
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(theme.colors.blue)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.surface0)
        )
    }

    // MARK: - Helpers

    private func loadCommands() {
        commands = (try? db.getAllUserCommands()) ?? []
    }

    private func deleteCommand(_ cmd: UserCommand) {
        guard let id = cmd.id else { return }
        try? db.deleteUserCommand(id: id)
        loadCommands()
    }
}

// MARK: - AddCommandView

struct AddCommandView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var loc: LocalizationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var db = DatabaseService.shared

    /// 編集対象（nilなら新規作成モード）
    let editingCommand: UserCommand?

    @State private var nameInput: String = ""
    @State private var descInput: String = ""
    @State private var templateInput: String = ""
    @State private var validationError: String? = nil
    @FocusState private var focusedField: Field?

    enum Field { case name, desc, template }

    /// 編集モードかどうか
    private var isEditMode: Bool { editingCommand != nil }

    init(editingCommand: UserCommand? = nil) {
        self.editingCommand = editingCommand
    }

    // Reserved built-in command names
    private let reservedNames: Set<String> = [
        "help", "english", "japanese", "spanish",
        "cal", "remember", "memory", "clear", "addcommand"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // フォーム
                    formCard

                    // テンプレートヒント（ステップ式）
                    templateHint

                    // バリデーションエラー
                    if let error = validationError {
                        errorBanner(error)
                    }

                    // 保存ボタン
                    saveButton
                }
                .padding(20)
            }
            .background(theme.colors.base.ignoresSafeArea())
            .navigationTitle(isEditMode ? loc["cmd_edit_title"] : loc["cmd_add_title"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.colors.surface0, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc["cancel"]) { dismiss() }
                        .foregroundColor(theme.colors.subtext0)
                }
            }
            .onAppear {
                // 編集モードのとき既存値をプリセット
                if let cmd = editingCommand {
                    nameInput = cmd.name
                    descInput = cmd.commandDescription
                    templateInput = cmd.promptTemplate
                }
            }
        }
        .preferredColorScheme(theme.preferredColorScheme)
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // コマンド名（編集モードでは変更不可）
            if isEditMode {
                readonlyNameRow
            } else {
                fieldRow(
                    label: loc["cmd_name_label"],
                    placeholder: loc["cmd_field_name"],
                    text: $nameInput,
                    field: .name,
                    prefix: "/"
                ) { nameInput = $0.filter { $0.isLetter || $0.isNumber || $0 == "_" }.lowercased() }
            }

            Divider().padding(.horizontal, 14).background(theme.colors.surface1)

            // 説明
            fieldRow(
                label: loc["cmd_desc_label"],
                placeholder: loc["cmd_field_desc"],
                text: $descInput,
                field: .desc,
                prefix: nil
            )

            Divider().padding(.horizontal, 14).background(theme.colors.surface1)

            // テンプレート
            templateField
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.colors.surface0)
        )
    }

    /// 編集モード用: コマンド名は変更不可の表示専用行
    private var readonlyNameRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc["cmd_name_label"])
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.colors.subtext0)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            HStack(spacing: 4) {
                Text("/")
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundColor(theme.colors.blue)
                    .padding(.leading, 14)
                Text(nameInput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(theme.colors.text)
                Spacer()
                // 変更不可バッジ
                Text(loc["cmd_name_readonly"])
                    .font(.caption2)
                    .foregroundColor(theme.colors.overlay0)
                    .padding(.trailing, 14)
            }
            .padding(.bottom, 12)
        }
    }

    private func fieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        prefix: String?,
        onChange: ((String) -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.colors.subtext0)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            HStack(spacing: 4) {
                if let prefix {
                    Text(prefix)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundColor(theme.colors.blue)
                        .padding(.leading, 14)
                }
                TextField(placeholder, text: text)
                    .font(prefix != nil ? .system(.body, design: .monospaced) : .body)
                    .foregroundColor(theme.colors.text)
                    .focused($focusedField, equals: field)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.leading, prefix == nil ? 14 : 2)
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
                    .onChange(of: text.wrappedValue) { _, newVal in
                        onChange?(newVal)
                    }
            }
        }
    }

    private var templateField: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc["cmd_template_label"])
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.colors.subtext0)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            TextEditor(text: $templateInput)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(theme.colors.text)
                .focused($focusedField, equals: .template)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 90)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .overlay(alignment: .topLeading) {
                    if templateInput.isEmpty {
                        Text(loc["cmd_field_template"])
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(theme.colors.overlay0)
                            .padding(.leading, 14)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }

            // {input} ワンタップ挿入ボタン
            HStack {
                Spacer()
                Button {
                    let needsSpace = !templateInput.isEmpty
                        && !templateInput.hasSuffix(" ")
                        && !templateInput.hasSuffix("\n")
                    templateInput += (needsSpace ? " " : "") + "{input}"
                    focusedField = .template
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text(loc["cmd_input_insert_btn"])
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(theme.colors.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(theme.colors.blue.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Template Hint（コマンドの仕組み説明）

    private var templateHint: some View {
        VStack(alignment: .leading, spacing: 12) {

            // タイトル
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.colors.yellow)
                Text(loc["cmd_hint_title"])
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.colors.yellow)
            }

            // フィールド説明3行
            VStack(alignment: .leading, spacing: 7) {
                hintFieldRow(label: loc["cmd_name_label"],     desc: loc["cmd_hint_name_desc"])
                hintFieldRow(label: loc["cmd_desc_label"],     desc: loc["cmd_hint_desc_desc"])
                hintFieldRow(label: loc["cmd_template_label"], desc: loc["cmd_hint_template_desc"])
            }

            Divider()
                .background(theme.colors.yellow.opacity(0.25))

            // 使用例
            VStack(alignment: .leading, spacing: 6) {
                Text(loc["cmd_hint_example_title"])
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(theme.colors.subtext0)

                VStack(alignment: .leading, spacing: 5) {
                    hintExRow(label: loc["cmd_hint_ex_template_label"],
                              value: loc["cmd_hint_ex_template_val"],
                              valueColor: theme.colors.subtext1)

                    Divider().padding(.vertical, 1)

                    hintExRow(label: loc["cmd_hint_ex_input_label"],
                              value: loc["cmd_hint_ex_input_val"],
                              valueColor: theme.colors.blue)

                    HStack {
                        Spacer().frame(width: 72)
                        Text("↓")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.colors.overlay0)
                    }

                    hintExRow(label: loc["cmd_hint_ex_send_label"],
                              value: loc["cmd_hint_ex_send_val"],
                              valueColor: theme.colors.green)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors.surface1)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.yellow.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.colors.yellow.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func hintFieldRow(label: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.colors.blue)
            Text(" — ")
                .font(.system(size: 11))
                .foregroundColor(theme.colors.overlay0)
            Text(desc)
                .font(.system(size: 11))
                .foregroundColor(theme.colors.subtext0)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hintExRow(label: String, value: String, valueColor: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.colors.subtext0)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(valueColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(theme.colors.red)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundColor(theme.colors.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.red.opacity(0.08))
        )
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveCommand()
        } label: {
            Text(loc["save"])
                .font(.body.weight(.semibold))
                .foregroundColor(theme.colors.base)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canSave ? theme.colors.blue : theme.colors.surface1)
                )
        }
        .disabled(!canSave)
        .animation(.easeInOut(duration: 0.2), value: canSave)
    }

    // MARK: - Validation & Save

    private var canSave: Bool {
        !nameInput.trimmingCharacters(in: .whitespaces).isEmpty &&
        !templateInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveCommand() {
        let desc = descInput.trimmingCharacters(in: .whitespaces)
        let template = templateInput.trimmingCharacters(in: .whitespaces)

        // 編集モード: description / template だけ更新（name変更不可）
        if let cmd = editingCommand, let id = cmd.id {
            do {
                try db.updateUserCommand(id: id, description: desc, promptTemplate: template)
                validationError = nil
                dismiss()
            } catch {
                validationError = error.localizedDescription
            }
            return
        }

        // 新規作成モード
        let name = nameInput.trimmingCharacters(in: .whitespaces).lowercased()

        // 名前バリデーション
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if name.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
            validationError = loc["cmd_name_invalid"]
            return
        }

        // 予約名チェック
        if reservedNames.contains(name) {
            validationError = loc["cmd_name_duplicate"]
            return
        }

        // 重複チェック
        let existing = (try? db.getAllUserCommands()) ?? []
        if existing.contains(where: { $0.name.lowercased() == name }) {
            validationError = loc["cmd_name_duplicate"]
            return
        }

        // 保存
        do {
            try db.addUserCommand(name: name, description: desc, promptTemplate: template)
            validationError = nil
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        UserCommandManagementView()
            .environmentObject(ThemeManager.shared)
            .environmentObject(LocalizationService.shared)
    }
}
