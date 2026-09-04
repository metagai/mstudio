import SwiftUI

/// 额度流水：把钱的去向摊开给用户看。
///
/// `credit_ledger` 一直只写不读。2026-08-01 的事故里我们弄丢了一位新用户付过钱的成片，
/// 退了额度、按原 prompt 重出了一版 —— 而他在产品里**没有任何地方能看到这件事发生过**，
/// 只知道"四个 credits 花掉、片子全部失败"。
///
/// 信任不会因为我们修好了就自动回来。**它得被看见。**
@MainActor
final class MetagCreditsModel: ObservableObject {
    /// 已经有货的模型 —— 理由同 `MetagMyFilmsModel(preloaded:)`：
    /// 这一屏此前只被看过「正在载入」那一版。
    convenience init(preloaded: [MetagGateway.CreditEntry]) {
        self.init()
        items = preloaded
        seeded = true
    }

    private var seeded = false
    @Published private(set) var items: [MetagGateway.CreditEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    func load() async {
        guard !seeded else { return }
        loading = true
        defer { loading = false }
        do {
            items = try await MetagGateway.creditActivity()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MetagCreditsView: View {
    @StateObject private var model: MetagCreditsModel

    init(model: MetagCreditsModel = MetagCreditsModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(L10n.string("Credit activity")).font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
            if model.loading && model.items.isEmpty {
                Text(L10n.string("Loading…")).font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.secondaryColor)
            // **和「我的作品」同一个形状，上一轮我只修了那一边。**
            //
            // `error` 排在 `items` 前面：流水已经加载好之后，任何一次失败
            // 都会把整屏账单顶掉。而账单是"我的钱去哪了" ——
            // 让它因为一次网络抖动整屏消失，比不报错更吓人。
            //
            // 取不到流水才顶替；流水在的时候那句话贴在上面（下面那一支）。
            } else if let e = model.error, model.items.isEmpty {
                Text(e).font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.secondaryColor)
            } else if model.items.isEmpty {
                Text(L10n.string("No credit activity yet")).font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.secondaryColor)
            } else {
                // 流水在的时候，这一次的失败贴在**上面**，不取代它。
                if let e = model.error {
                    Text(e)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Status.warningColor)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        ForEach(model.items) { e in row(e) }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(AppTheme.Spacing.mdLg)
        .frame(width: 360)
        .task { await model.load() }
    }

    private func row(_ e: MetagGateway.CreditEntry) -> some View {
        let d = Self.describe(e)
        return HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(d.label)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(d.isRefund ? AppTheme.Status.successColor : AppTheme.Text.primaryColor)
                    // 原始理由**可查但不摆在正文**：对账要得到它，
                    // 而用户的账单上不该出现 `director_run` 这种下划线代码。
                    .help(Text(verbatim: e.reason))
                if let title = e.title, !title.isEmpty {
                    Text(title).font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Text.secondaryColor).lineLimit(1)
                }
                Text(Self.when(e.at)).font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            Spacer()
            Text(e.delta > 0 ? "+\(e.delta)" : "\(e.delta)")
                .font(.system(size: AppTheme.FontSize.sm)).monospacedDigit()
                .foregroundStyle(e.delta > 0 ? AppTheme.Status.successColor : AppTheme.Text.secondaryColor)
        }
    }

    /// 每一种流水说人话。**退款要说清楚为什么退** —— 只写"退款"等于没说，
    /// 而"系统原因"是推卸：是我们把它弄丢了。
    ///
    /// 文案走 `L()`：这里是**账单**，而账单用用户看不懂的语言写，等于没给。
    @MainActor
    static func describe(_ e: MetagGateway.CreditEntry) -> (label: String, isRefund: Bool) {
        let (key, isRefund) = reasonKey(e)
        // **`L10n.key` 只把 key 原样还回来，得再查一次才是那门语言的话。**
        //
        // 2026-09-02 取景器照到的中文界面「额度流水」下面四行全是英文：
        //   Film / Top-up / Signup credits /
        //   Refunded — we lost this film and cannot recover it
        // 最后那句恰恰是**最需要被读懂的一句**（我们弄丢了你的片子，钱退了），
        // 而中文用户一个字都读不了。上面那句注释写着"账单用用户看不懂的语言写，
        // 等于没给"—— 意图一直是对的，只是少了最后这一步。
        // （同一个形状：重拍右键菜单五处也是 `L10n.key` 该用 `L10n.string`。）
        return (L10n.string(key: key), isRefund)
    }

    /// 这一笔是什么。**只挑 key，不查表** —— 查表交给上面那一处收口。
    @MainActor
    private static func reasonKey(_ e: MetagGateway.CreditEntry) -> (String, Bool) {
        switch e.reason {
        case "signup":               return (L10n.key("Signup credits"), false)
        case "purchase":             return (L10n.key("Top-up"), false)
        case "refund":               return (L10n.key("Subscription refund"), true)
        case "refund_failed":        return (L10n.key("Refunded — this generation failed"), true)
        case "refund_lost_artifact": return (L10n.key("Refunded — we lost this film and cannot recover it"), true)
        case "refund_incident_regen":return (L10n.key("Refunded — we covered the cost of remaking it"), true)
        case "generate":             return (L10n.key("Film"), false)
        case "vision_plan":          return (L10n.key("The assistant read your timeline"), false)
        case "image_edit", "mcp:image_edit": return (L10n.key("Image edit"), false)
        case "voice_clone":          return (L10n.key("Voice clone"), false)
        case "voice_tts", "mcp:voice_tts":  return (L10n.key("Speech"), false)
        default:
            if e.reason.hasPrefix("refund:") { return (L10n.key("Refunded — that step did not complete"), true) }
            // 认不出的理由原样显示。**不要翻译它，也不要写"其他"** ——
            // 原始理由至少能被搜索和对账，"其他"什么都不是。
            //
            // 2026-09-02：我一度把它改成「额度变动」，理由是不该让用户在账单上
            // 看见 `director_run` 这种下划线代码。**单测当场红**，而它是对的：
            // 那句话让产品**假装看得懂一个它不认识的理由**，比一个丑但真实的
            // 字符串更糟。真正该做的是**把新理由翻译过来**（上面那张表），
            // 而不是给所有不认识的东西套一个和善的壳。
            return (e.reason, e.delta > 0)
        }
    }

    /// **别写死 `M/d`** —— 欧洲用户会把 9/1 读成 1 月 9 日，而且它不跟界面语言走。
    /// 用 `AppLocalization.relativeString`，和「我的作品」那一列同一种写法
    /// （那边为同一个问题已经改过，并在注释里点名了这个坑；一个仓库里
    /// 同一种时间不该有两种写法）。
    @MainActor
    private static func when(_ epoch: Double) -> String {
        AppLocalization.shared.relativeString(
            for: Date(timeIntervalSince1970: epoch), style: .short
        )
    }
}
