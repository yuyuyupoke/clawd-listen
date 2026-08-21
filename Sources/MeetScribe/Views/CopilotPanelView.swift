import SwiftUI
import AppKit

/// 小窓右カラム。AIが会議を傍聴して支援する「Copilotパネル」。
/// (旧 ScribeQAView のタイプ入力式 Q&A を置き換え)
/// - 上部: 全体像パネル (目的/議題/現在地、自動更新)
/// - 中央: Catchup要約カード (新しい順)
/// - 下部: Catchupボタン (3/5/10分) + 任意の分数の入力欄
struct CopilotPanelView: View {
    let state: AppState

    /// Catchup ボタンの分数。
    ///
    /// 1分は削除した (短すぎて使われていない — 1分ぶんの発話は約570字で、
    /// 「一文サマリ + 箇条書き3〜6点」に要約する意味がほとんど無い)。
    /// 任意入力では1分も受け付けるので、機能が失われるわけではない
    /// (`CatchupWindowInput.minMinutes`)。
    /// テストで固定するため internal。
    static let catchupMinutes = [3, 5, 10]

    /// 任意の分数の入力。
    ///
    /// **実行後もクリアしない。** 同じ分数を続けて使う場面 (長い離席で10分→10分、
    /// 授業で15分→15分) が普通なので毎回打ち直すのは手間だし、値が残っていても
    /// 実行には Enter か「要約」ボタンの明示操作が必要なので勝手に走ることはない。
    /// 残った値がそのまま「次に実行される分数」として見えているぶん、誤爆はむしろ気づきやすい。
    @State private var customMinutesText = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.3)
            overviewPanel
            Divider().opacity(0.3)
            catchupList
            Divider().opacity(0.3)
            catchupButtonBar
        }
    }

    // MARK: - ヘッダ (Scribe アイコン + ステータス + サポート)

    private var headerBar: some View {
        HStack(spacing: 8) {
            meetscribeIcon
            VStack(alignment: .leading, spacing: 1) {
                Text("Scribe")
                    .font(.scaled(12, weight: .semibold))
                Text(statusText)
                    .font(.scaled(9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            supportButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        if state.isCatchupRunning { return "要約を生成中…" }
        if state.isRunning { return "会議を傍聴しています" }
        return "待機中"
    }

    /// 開発の応援 (note へ遷移)。いつでも押せるさりげない常設導線。
    /// 保存直後に出る `TranscriptListView` の応援バナーとは役割が違うので両方置く。
    private var supportButton: some View {
        Button(action: { SupportLink.open() }) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.scaled(11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("開発を応援する")
        .help("\(SupportLink.suggestedAmountLabel)で開発を応援する（note が開きます）")
    }

    private var meetscribeIcon: some View {
        Group {
            if let url = Bundle.main.url(forResource: "Scribe", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - 全体像パネル

    @ViewBuilder
    private var overviewPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "map.fill")
                    .font(.scaled(10))
                    .foregroundStyle(.blue)
                Text("全体像")
                    .font(.scaled(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if state.isOverviewUpdating {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
            }
            if let overview = state.overview {
                VStack(alignment: .leading, spacing: 3) {
                    overviewRow(label: "目的", text: overview.purpose)
                    if !overview.agenda.isEmpty {
                        overviewRow(label: "議題", text: overview.agenda.map { "・\($0)" }.joined(separator: "  "))
                    }
                    overviewRow(label: "現在", text: overview.currentTopic)
                }
            } else {
                Text(state.isRunning
                     ? "👂 傍聴中… 発話が溜まると全体像を表示します"
                     : "録音を開始すると、AIが会議の目的・議題を自動で把握します")
                    .font(.scaled(10))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func overviewRow(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.scaled(9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            Text(text)
                .font(.scaled(10))
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Catchup カード一覧

    private var catchupList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if state.catchupCards.isEmpty {
                    placeholder
                }
                ForEach(state.catchupCards) { card in
                    catchupCard(card)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⏱ 下のボタン・分数入力で直近の内容に追いつけます")
                .font(.scaled(11))
                .foregroundStyle(.secondary)
            Text("離席から戻った時・聞き逃した時に、その間の要約を数秒で表示します")
                .font(.scaled(9))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.top, 4)
    }

    private func catchupCard(_ card: CatchupCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: card.isError ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                    .font(.scaled(9))
                    .foregroundStyle(card.isError ? .red : .orange)
                Text("\(card.periodLabel)（\(card.minutes)分）")
                    .font(.scaled(9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(card.text)
                .font(.scaled(11))
                .foregroundStyle(card.isError ? Color.red.opacity(0.9) : .primary.opacity(0.95))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(card.isError ? Color.red.opacity(0.08) : Color.secondary.opacity(0.08))
        )
    }

    // MARK: - Catchup ボタン行

    /// 固定ボタン行 + 任意分数の入力行。
    ///
    /// **2行に分けている理由は幅。** 右カラムは HSplitView のドラッグで `minWidth: 200` まで
    /// 縮められ、さらに ⌘+ (`uiScale`) で文字が拡大する。1行に「アイコン + ボタン3個 +
    /// 入力欄 + 実行ボタン」を並べると縮めた時に確実にはみ出す
    /// (1分を削って空いた幅ぶんでは足りない)。小窓では幅のほうが貴重なので、
    /// 縦に1行 (約20pt) 増やすほうを選ぶ。
    private var catchupButtonBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            catchupPresetRow
            customCatchupRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// 固定分数のボタン行。末尾の `Spacer()` が左詰めを作っているので消さないこと。
    private var catchupPresetRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.scaled(11))
                .foregroundStyle(state.isRunning ? .orange : .secondary.opacity(0.5))
                .help("Catchup: 直近N分の要約")
            ForEach(Self.catchupMinutes, id: \.self) { minutes in
                catchupButton(minutes: minutes)
            }
            if state.isCatchupRunning {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
    }

    /// 任意の分数 (1〜30) を入力して実行する行。Enter でも「要約」ボタンでも走る。
    private var customCatchupRow: some View {
        let validation = CatchupWindowInput.validate(customMinutesText)
        let minutes = try? validation.get()
        // 固定ボタンと同じ条件: 録音中かつ Catchup 実行中でないときだけ使える
        let usable = state.isRunning && !state.isCatchupRunning
        let enabled = usable && minutes != nil
        let helpText = customRowHelp(validation: validation, usable: usable)
        let showsInvalidInput = !customMinutesText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && minutes == nil

        return HStack(spacing: 4) {
            TextField(
                "\(CatchupWindowInput.minMinutes)-\(CatchupWindowInput.maxMinutes)",
                text: $customMinutesText
            )
            .textFieldStyle(.roundedBorder)
            .font(.scaled(10))
            .multilineTextAlignment(.trailing)
            .frame(width: 40)
            // 入力欄自体は常に編集可能にしておく。**実行**だけを `usable` で止める
            // (下の Button と `runCustomCatchup` の guard)。
            // 入力中に Catchup が走り始めた瞬間に欄が disabled になると、
            // 打ちかけの数字とフォーカスが飛んで打ち直しになる。
            .onSubmit { runCustomCatchup() }
            // 無効な入力は枠を赤くする (このアプリの赤 = エラー: 失敗カードと同じ語彙)。
            // 何が悪いのかは help に文言で出す。
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red.opacity(0.55), lineWidth: 1)
                    .opacity(showsInvalidInput ? 1 : 0)
            )
            .help(helpText)
            .accessibilityLabel("Catchup の分数")
            Text("分")
                .font(.scaled(9))
                .foregroundStyle(.secondary)
            Button { runCustomCatchup() } label: {
                Text("要約")
                    .font(.scaled(10))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(enabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .help(helpText)
            Spacer()
        }
    }

    /// 入力欄・実行ボタンのツールチップ。**無効なときは理由が分かるようにする。**
    /// 入力の問題 (範囲外・非整数) を状態の問題 (録音していない) より優先して出す
    /// = ユーザーが直せることを先に見せる。
    private func customRowHelp(
        validation: Result<Int, CatchupWindowInput.Rejection>,
        usable: Bool
    ) -> String {
        switch validation {
        case .failure(let rejection):
            // 空欄は「エラー」ではないので、使えない状態ならそちらを案内する
            if rejection == .empty, !usable { return unusableReason }
            return rejection.message
        case .success(let minutes):
            if !usable { return unusableReason }
            return "直近\(minutes)分を日本語で要約"
        }
    }

    private var unusableReason: String {
        state.isRunning ? "要約を生成中です" : "録音中のみ使えます"
    }

    /// 入力欄からの実行。`onSubmit` はボタンが disabled でも飛んでくるので、
    /// ここでも状態と入力の両方を確認する
    /// (判定の出典は `CatchupWindowInput.validate` の一箇所だけに保つ)。
    private func runCustomCatchup() {
        guard state.isRunning, !state.isCatchupRunning else { return }
        guard case .success(let minutes) = CatchupWindowInput.validate(customMinutesText) else { return }
        CopilotController.shared.requestCatchup(minutes: minutes)
    }

    private func catchupButton(minutes: Int) -> some View {
        let enabled = state.isRunning && !state.isCatchupRunning
        return Button {
            CopilotController.shared.requestCatchup(minutes: minutes)
        } label: {
            Text("\(minutes)分")
                .font(.scaled(10))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(enabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled
              ? "直近\(minutes)分を日本語で要約"
              : (state.isRunning ? "要約を生成中です" : "録音中のみ使えます"))
    }
}
