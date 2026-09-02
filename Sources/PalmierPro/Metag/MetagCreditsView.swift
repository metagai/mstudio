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
    @Published private(set) var items: [MetagGateway.CreditEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    func load() async {
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
    @StateObject private var model = MetagCreditsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(L10n.string("Credit activity")).font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
            if model.loading && model.items.isEmpty {
                Text(L10n.string("Loading…")).font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.secondaryColor)
            } else if let e = model.error {
                Text(e).font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.secondaryColor)
            } else if model.items.isEmpty {
                Text(L10n.string("No credit activity yet")).font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.secondaryColor)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        ForEach(model.items) { e in row(e) }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(AppTheme.Spacing.md)
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
            return (e.reason, e.delta > 0)
        }
    }

    private static func when(_ epoch: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }
}
