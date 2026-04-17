// OnboardingView.swift
// Memoria for iPhone - 初回起動オンボーディング + 免責事項
// Phase 5: 商用リリース向け法的表示・帰属表示

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var theme: ThemeManager
    let onAccept: () -> Void

    @State private var currentPage: Int = 0
    @State private var agreementChecked: Bool = false

    private let totalPages = 3

    var body: some View {
        ZStack {
            // 背景
            theme.colors.base.ignoresSafeArea()

            VStack(spacing: 0) {
                // ページインジケーター
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? theme.colors.blue : theme.colors.surface1)
                            .frame(width: i == currentPage ? 20 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.top, 24)

                // ページコンテンツ
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    disclaimerPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // ナビゲーションボタン
                navigationButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 28) {
            Spacer()

            // アイコン（Orbital デザイン）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.colors.surface0, theme.colors.surface1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: theme.colors.blue.opacity(0.3), radius: 20)

                // 外リング
                Circle()
                    .stroke(theme.colors.lavender.opacity(0.5), lineWidth: 2)
                    .frame(width: 100, height: 100)

                // 中リング
                Circle()
                    .stroke(theme.colors.blue.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 70, height: 70)

                // M 文字
                Text("M")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.colors.text)
            }

            VStack(spacing: 12) {
                Text("Memoriaへようこそ")
                    .font(.title.bold())
                    .foregroundColor(theme.colors.text)

                Text("あなたとの会話を記憶する\nプライベートAIアシスタント")
                    .font(.body)
                    .foregroundColor(theme.colors.subtext0)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // バッジ
            HStack(spacing: 12) {
                onboardingBadge(icon: "lock.shield.fill", text: "完全オフライン", color: theme.colors.green)
                onboardingBadge(icon: "brain", text: "記憶機能", color: theme.colors.mauve)
                onboardingBadge(icon: "mic.fill", text: "音声入力", color: theme.colors.blue)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Memoriaの特徴")
                .font(.title2.bold())
                .foregroundColor(theme.colors.text)

            VStack(spacing: 16) {
                featureRow(
                    icon: "iphone",
                    iconColor: theme.colors.blue,
                    title: "iPhoneの中だけで動作",
                    description: "AIの処理はすべてiPhone内で完結。データがデバイスの外に出ることはありません。"
                )
                featureRow(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    iconColor: theme.colors.sapphire,
                    title: "会話を記憶する",
                    description: "セッションをまたいで会話内容を要約・記憶。文脈を持ったパーソナルアシスタントです。"
                )
                featureRow(
                    icon: "cpu",
                    iconColor: theme.colors.teal,
                    title: "Powered by Gemma (Google DeepMind)",
                    description: "最新のオープンソースLLMを使用。iPhone 16以降ではより高性能なGemma 4も利用可能です。"
                )
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Page 3: Disclaimer

    private var disclaimerPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 16)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(theme.colors.yellow)

                Text("ご利用前にお読みください")
                    .font(.title2.bold())
                    .foregroundColor(theme.colors.text)

                disclaimerBox(
                    title: "⚠️ AIの回答精度について",
                    body: "Memoriaが生成する回答は、AIモデルが推測したものです。内容の正確性・完全性・適時性を一切保証しません。重要な判断（医療・法律・財務等）には専門家にご相談ください。AIの回答を参考にした結果生じたいかなる損害についても、開発者は責任を負いません。"
                )

                disclaimerBox(
                    title: "🤖 使用AIモデルについて",
                    body: "本アプリはGoogle DeepMindが開発したGemma（オープンモデル）をローカル実行します。モデルはHuggingFaceよりダウンロードされます。利用にはGoogle Gemma利用規約への同意が必要です。"
                )

                disclaimerBox(
                    title: "🔒 プライバシーについて",
                    body: "会話データはiPhone内にのみ保存されます。マイクは音声入力にのみ使用し、録音データは一切保存・送信しません。"
                )

                // 同意チェックボックス
                Button {
                    withAnimation(.spring(response: 0.2)) {
                        agreementChecked.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: agreementChecked
                              ? "checkmark.square.fill"
                              : "square")
                            .font(.system(size: 22))
                            .foregroundColor(agreementChecked ? theme.colors.blue : theme.colors.overlay0)

                        Text("上記の免責事項を読み、理解した上で自己責任においてMemoriaを利用することに同意します。")
                            .font(.footnote)
                            .foregroundColor(theme.colors.subtext1)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(agreementChecked
                                  ? theme.colors.blue.opacity(0.1)
                                  : theme.colors.surface0)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(agreementChecked ? theme.colors.blue : theme.colors.surface1,
                                            lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)

                Spacer().frame(height: 12)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            if currentPage < totalPages - 1 {
                // 次へボタン
                Button {
                    withAnimation {
                        currentPage += 1
                    }
                } label: {
                    Text("次へ")
                        .font(.body.weight(.semibold))
                        .foregroundColor(theme.colors.base)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(theme.colors.blue)
                        )
                }

                if currentPage > 0 {
                    Button {
                        withAnimation { currentPage -= 1 }
                    } label: {
                        Text("戻る")
                            .font(.body)
                            .foregroundColor(theme.colors.subtext0)
                    }
                }
            } else {
                // 最終ページ: 同意して始めるボタン
                Button {
                    guard agreementChecked else { return }
                    UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                    onAccept()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("同意してMemoriaを始める")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(agreementChecked ? theme.colors.base : theme.colors.subtext0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(agreementChecked
                                  ? theme.colors.green
                                  : theme.colors.surface1)
                    )
                }
                .disabled(!agreementChecked)
                .animation(.easeInOut(duration: 0.2), value: agreementChecked)

                Button {
                    withAnimation { currentPage -= 1 }
                } label: {
                    Text("戻る")
                        .font(.body)
                        .foregroundColor(theme.colors.subtext0)
                }
            }
        }
    }

    // MARK: - Helpers

    private func onboardingBadge(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundColor(theme.colors.subtext0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.surface0)
        )
    }

    private func featureRow(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.colors.text)
                Text(description)
                    .font(.caption)
                    .foregroundColor(theme.colors.subtext0)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.surface0)
        )
    }

    private func disclaimerBox(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(theme.colors.text)
            Text(body)
                .font(.caption)
                .foregroundColor(theme.colors.subtext0)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.surface0)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.colors.surface1, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(onAccept: {})
        .environmentObject(ThemeManager.shared)
}
