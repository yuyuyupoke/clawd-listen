import Foundation

/// Catchup の「任意の分数」入力の検証。
///
/// 固定ボタン (3/5/10分) だけでは「15分席を外した」「授業の前半30分を聞き逃した」に
/// 対応できないため、分数を直接入力できるようにした。その入力を受け付けるかどうかの
/// 判定は View から切り出してここに置く — 境界 (上限・全角・空白) をテストで固定できる形にし、
/// 「押せるのに何も起きない」「意図しない分数で走る」のどちらも起こさないため。
///
/// **黙って丸めない。** 上限を超えた入力を上限値にクランプすると、31分と打ったのに
/// 30分で実行され、ユーザーには「なぜこの範囲になったのか」が分からない。
/// 無効として弾き、理由 (= 上限) を伝える。
enum CatchupWindowInput {

    /// 発話速度の実測中央値 (字/分)。10セッションの実測値。
    /// 上限・クリップ幅の根拠になるのでここを唯一の出典にする。
    static let measuredCharsPerMinute = 571

    /// 受け付ける下限 (分)。
    ///
    /// 1分は固定ボタンから外した (短すぎて使われていない) が、任意入力では受け付ける。
    /// 「今の一言を聞き逃した」の用途はボタンを並べる価値はないだけで、
    /// 打ち込まれたなら意図は明確だから。
    static let minMinutes = 1

    /// 受け付ける上限 (分)。
    ///
    /// 根拠はコストではなく**情報密度**:
    /// - コスト: 30分 = 約17,000字 (= `measuredCharsPerMinute` × 30) で 1回 $0.0072。
    ///   1コマ総額 約$0.25 の3%にすぎず、制約にならない。
    /// - 情報密度: Catchup の出力形式は「一文サマリ + 箇条書き3〜6点」で固定なので、
    ///   入力範囲を広げても出力量は増えない。30分より広い範囲を6点に圧縮しても
    ///   薄まるだけで「離席から戻って数秒で追いつく」用途を満たさなくなる。
    ///   会議全体の把握は上の全体像パネル (Overview) の役割。
    static let maxMinutes = 30

    /// 受け付ける範囲 (分)。
    static var allowedRange: ClosedRange<Int> { minMinutes...maxMinutes }

    /// 入力を弾いた理由。UI はこの `message` をそのまま出す。
    /// `Result` の Failure に載せるため `Error` に適合させている (投げる用途はない)。
    enum Rejection: Error, Equatable {
        /// 空 (または空白のみ)
        case empty
        /// 整数として読めない (小数・符号付き・文字混在など)
        case notAnInteger
        /// 下限未満 (0 以下)
        case tooSmall
        /// 上限超過 (桁溢れするような巨大な数もここ)
        case tooLarge

        var message: String {
            switch self {
            case .empty:
                return "分数を入力してください（\(minMinutes)〜\(maxMinutes)分）"
            case .notAnInteger:
                return "整数で入力してください（\(minMinutes)〜\(maxMinutes)分）"
            case .tooSmall:
                return "\(minMinutes)分以上を指定してください"
            case .tooLarge:
                return "上限は\(maxMinutes)分です。それより長い範囲は上の「全体像」で把握できます"
            }
        }
    }

    /// 入力文字列を分数として解釈する。副作用なし。
    ///
    /// 受け付ける形:
    /// - 前後の空白・改行は許容 (コピペ由来の空白で弾かない)
    /// - **全角数字を受け付ける** (「３０」→ 30)。日本語IMEのまま打つと全角になるのが普通で、
    ///   ここで弾くと「数字を入れたのに整数じゃないと言われる」体験になる
    /// - 桁区切りやプラス記号は受け付けない (`Int("+3")` は通ってしまうので自前で判定する)
    static func validate(_ raw: String) -> Result<Int, Rejection> {
        // 全角→半角。英字も半角化されるが、数字以外は後段で弾かれるので害はない。
        let halfwidth = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        let trimmed = halfwidth.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return .failure(.empty) }
        // ASCII 数字のみ。"3.5" / "-1" / "+3" / "3 0" / "abc" はここで落ちる。
        // (負数は .notAnInteger 扱いだが、message が有効範囲を伝えるので実害はない)
        guard trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return .failure(.notAnInteger)
        }
        // 全桁が数字なのに Int にならないのは桁溢れ = 上限超過。
        guard let minutes = Int(trimmed) else { return .failure(.tooLarge) }
        if minutes < minMinutes { return .failure(.tooSmall) }
        if minutes > maxMinutes { return .failure(.tooLarge) }
        return .success(minutes)
    }
}
