import XCTest
@testable import MeetScribeCore

/// 任意分数 Catchup の入力検証。
///
/// 「押せるのに何も起きない」「意図しない分数で走る」を防ぐのがこの純関数の役目なので、
/// 有効値・無効値・境界・全角・空白をここで固定する。
final class CatchupWindowInputTests: XCTestCase {

    private func minutes(_ raw: String) -> Int? {
        try? CatchupWindowInput.validate(raw).get()
    }

    private func rejection(_ raw: String) -> CatchupWindowInput.Rejection? {
        switch CatchupWindowInput.validate(raw) {
        case .success: return nil
        case .failure(let rejection): return rejection
        }
    }

    // MARK: - 受け付ける範囲

    /// 範囲は 1〜30分。ここを動かすとコスト・情報密度の根拠 (下記) が崩れるので数値ごと固定する。
    /// 上限30分 = 約17,000字 / $0.0072 per 回 (1コマ約$0.25の3%)。
    func test_allowedRange_isOneToThirty() {
        XCTAssertEqual(CatchupWindowInput.minMinutes, 1)
        XCTAssertEqual(CatchupWindowInput.maxMinutes, 30)
        XCTAssertEqual(CatchupWindowInput.allowedRange, 1...30)
    }

    func test_validate_validValues() {
        XCTAssertEqual(minutes("1"), 1)
        XCTAssertEqual(minutes("3"), 3)
        XCTAssertEqual(minutes("15"), 15)
        XCTAssertEqual(minutes("30"), 30)
    }

    /// 固定ボタンの分数は当然すべて有効 (ボタンと入力欄で挙動が食い違わないこと)。
    func test_validate_presetButtonValuesAreAllValid() {
        for preset in CopilotPanelView.catchupMinutes {
            XCTAssertEqual(minutes("\(preset)"), preset, "preset \(preset) が入力欄で無効になっている")
        }
    }

    // MARK: - 前後の空白 / 全角

    func test_validate_allowsSurroundingWhitespace() {
        XCTAssertEqual(minutes(" 5 "), 5)
        XCTAssertEqual(minutes("\n10\t"), 10)
        XCTAssertEqual(minutes("  30"), 30)
    }

    /// 日本語IMEのまま打つと全角になるのが普通なので受け付ける。
    func test_validate_acceptsFullwidthDigits() {
        XCTAssertEqual(minutes("５"), 5)
        XCTAssertEqual(minutes("１５"), 15)
        XCTAssertEqual(minutes("３０"), 30)
        // 全角でも上限判定は同じ
        XCTAssertEqual(rejection("３１"), .tooLarge)
    }

    // MARK: - 弾くもの

    func test_validate_rejectsEmpty() {
        XCTAssertEqual(rejection(""), .empty)
        XCTAssertEqual(rejection("   "), .empty)
        XCTAssertEqual(rejection("\n\t"), .empty)
        // 全角スペースのみも空扱い
        XCTAssertEqual(rejection("　"), .empty)
    }

    func test_validate_rejectsNonIntegers() {
        XCTAssertEqual(rejection("abc"), .notAnInteger)
        XCTAssertEqual(rejection("3.5"), .notAnInteger)
        XCTAssertEqual(rejection("5分"), .notAnInteger)
        XCTAssertEqual(rejection("1 0"), .notAnInteger)
        // Int("+3") は通ってしまうので自前で弾いていることの確認
        XCTAssertEqual(rejection("+3"), .notAnInteger)
        // 負数も非整数扱い (カテゴリは違っても弾かれることが要件)
        XCTAssertEqual(rejection("-1"), .notAnInteger)
    }

    func test_validate_rejectsZeroAndBelow() {
        XCTAssertEqual(rejection("0"), .tooSmall)
        XCTAssertEqual(rejection("00"), .tooSmall)
    }

    func test_validate_rejectsAboveMaximum() {
        XCTAssertEqual(rejection("31"), .tooLarge)
        XCTAssertEqual(rejection("60"), .tooLarge)
        XCTAssertEqual(rejection("120"), .tooLarge)
    }

    /// 桁溢れするような巨大な数も「上限超過」として弾く (クラッシュも success もしない)。
    func test_validate_rejectsHugeNumbers() {
        XCTAssertEqual(rejection("99999999999999999999999999"), .tooLarge)
        XCTAssertEqual(rejection(String(repeating: "9", count: 500)), .tooLarge)
    }

    /// **上限超過を黙って丸めない。** 31分と打って30分で走ると
    /// 「なぜこの範囲なのか」がユーザーに分からなくなる。
    func test_validate_doesNotSilentlyClampToMaximum() {
        for raw in ["31", "45", "999"] {
            XCTAssertNil(minutes(raw), "\(raw) が丸められて有効になっている")
        }
    }

    /// 弾いた理由は上限を伝えること (UI はこの文言をそのまま出す)。
    func test_rejectionMessages_conveyTheBounds() {
        XCTAssertTrue(
            CatchupWindowInput.Rejection.tooLarge.message.contains("\(CatchupWindowInput.maxMinutes)"),
            "上限超過の文言に上限値が含まれていない"
        )
        XCTAssertTrue(
            CatchupWindowInput.Rejection.empty.message.contains("\(CatchupWindowInput.maxMinutes)"),
            "空欄の案内に上限値が含まれていない"
        )
        for rejection: CatchupWindowInput.Rejection in [.empty, .notAnInteger, .tooSmall, .tooLarge] {
            XCTAssertFalse(rejection.message.isEmpty)
        }
    }
}

/// Catchup 実行側 (固定ボタンの構成・入力クリップ・タイムアウト)。
@MainActor
final class CatchupExecutionTests: XCTestCase {

    // MARK: - 固定ボタンの構成

    /// 1分ボタンを削除したこと (短すぎて使われていない: 1分 ≒ 570字で
    /// 「一文サマリ + 箇条書き3〜6点」に要約する意味が薄い) を固定する。
    /// 任意入力では1分も受け付けるので機能自体は残っている。
    func test_catchupPresetMinutes_dropsOneMinute() {
        XCTAssertEqual(CopilotPanelView.catchupMinutes, [3, 5, 10])
        XCTAssertFalse(CopilotPanelView.catchupMinutes.contains(1))
        for preset in CopilotPanelView.catchupMinutes {
            XCTAssertTrue(CatchupWindowInput.allowedRange.contains(preset))
        }
    }

    // MARK: - 入力クリップ

    func test_clipForCatchup_underLimit_isUnchanged() {
        let text = String(repeating: "あ", count: 99)
        XCTAssertEqual(CopilotController.clipForCatchup(text, limit: 100), text)
    }

    /// 境界: ちょうど上限なら触らない。
    func test_clipForCatchup_exactlyAtLimit_isUnchanged() {
        let text = String(repeating: "あ", count: 100)
        let clipped = CopilotController.clipForCatchup(text, limit: 100)
        XCTAssertEqual(clipped, text)
        XCTAssertEqual(clipped.count, 100)
    }

    /// 超過時は**末尾 (直近側)** が残る。Catchup は「直近N分に追いつく」機能なので
    /// 削るなら古い側から。
    func test_clipForCatchup_overLimit_keepsSuffix() {
        let text = "古い部分" + String(repeating: "x", count: 50) + "最新の発話"
        let clipped = CopilotController.clipForCatchup(text, limit: 10)
        XCTAssertEqual(clipped.count, 10)
        XCTAssertTrue(clipped.hasSuffix("最新の発話"))
        XCTAssertFalse(clipped.contains("古い部分"))
    }

    /// 境界: 上限+1字でちょうど1字だけ落ちる (先頭が落ちる)。
    func test_clipForCatchup_oneOverLimit_dropsOnlyTheFirstCharacter() {
        let text = "abcdef"
        let clipped = CopilotController.clipForCatchup(text, limit: 5)
        XCTAssertEqual(clipped, "bcdef")
    }

    func test_clipForCatchup_emptyAndZeroLimit() {
        XCTAssertEqual(CopilotController.clipForCatchup("", limit: 100), "")
        XCTAssertEqual(CopilotController.clipForCatchup("abc", limit: 0), "")
    }

    /// **上限30分を素で通せる幅であること。** ここが実測字数を下回ると、ユーザーが
    /// 明示的に指定した範囲の古い側が黙って落ちる。
    /// 上限30分 × 発話速度の実測中央値 571字/分 = 約17,130字。
    func test_catchupContextChars_coversMaximumWindowAtMeasuredSpeechRate() {
        let maxWindowChars = CatchupWindowInput.measuredCharsPerMinute * CatchupWindowInput.maxMinutes
        XCTAssertGreaterThanOrEqual(
            CopilotController.catchupContextChars,
            maxWindowChars,
            "上限30分の発話 (約\(maxWindowChars)字) がクリップされてしまう"
        )
        // 早口・多人数で中央値の1.4倍まで振れても素通しできる幅を確保する
        XCTAssertGreaterThanOrEqual(
            Double(CopilotController.catchupContextChars),
            Double(maxWindowChars) * 1.4
        )
        XCTAssertEqual(CopilotController.catchupContextChars, 24_000)
        // 自動で何度も走る Overview より広いのは意図通り (押した時だけ・範囲は明示指定)
        XCTAssertGreaterThan(
            CopilotController.catchupContextChars,
            CopilotController.overviewContextChars
        )
    }

    func test_measuredCharsPerMinute_matchesMeasurement() {
        // 10セッションの実測中央値。上限とクリップ幅の根拠なので固定する
        XCTAssertEqual(CatchupWindowInput.measuredCharsPerMinute, 571)
    }

    // MARK: - タイムアウト

    /// 20秒では入力が増えた時に足りない (`TranscriptCleaner` を 20→40 に上げたのと同じ理由)。
    /// 失敗すると「要約の生成に失敗しました」カードが残り、押し直す手間になる。
    func test_catchupTimeout_matchesCleanerBatchTimeout() {
        XCTAssertEqual(CopilotController.catchupTimeoutSeconds, 40)
        XCTAssertEqual(
            CopilotController.catchupTimeoutSeconds,
            TranscriptCleaner.batchTimeoutSeconds,
            "cleaner と同じ理由で延ばした値なので揃えておく"
        )
        XCTAssertGreaterThan(CopilotController.catchupTimeoutSeconds, 20)
    }
}
