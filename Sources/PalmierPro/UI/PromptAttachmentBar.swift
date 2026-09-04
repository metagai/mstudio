import SwiftUI

/// 输入框下面那排卡片。**摆的是他刚粘进来的稿子，不是一段被吞掉的文字。**
struct PromptAttachmentBar: View {
    @Binding var attachments: [PromptAttachment]
    /// 超出网关上限的字数。**超了就说** —— 悄悄砍掉后一半，他不会知道。
    var overflow: Int?
    /// 「我只收了这些」。灰色小字，不是红条 —— 它不是错误。
    var notices: [PromptPaste.Notice] = []

    var body: some View {
        if !attachments.isEmpty || !notices.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                ForEach(attachments) { attachment in
                    card(attachment)
                }
                ForEach(notices, id: \.self) { notice in
                    Text(verbatim: notice.text)
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.mutedColor)
                }
                if let overflow {
                    Text(L10n.string("That's \(overflow.formatted()) characters over the limit. Trim it, or remove one."))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Status.errorColor)
                }
            }
        }
    }

    /// 图片给真缩略图，稿子给一个说得出它是什么的图标。
    @ViewBuilder
    private func thumbnail(_ attachment: PromptAttachment) -> some View {
        if let url = attachment.imageURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
        } else {
            Image(systemName: attachment.symbol)
                .font(.system(size: AppTheme.FontSize.smMd))
                .foregroundStyle(AppTheme.Text.mutedColor)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
        }
    }

    private func card(_ attachment: PromptAttachment) -> some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            // 图片摆真的缩略图 —— **他贴的是哪一张，一眼就该认得出来**；
            // 一个通用的相机图标等于让他自己回想。
            thumbnail(attachment)

            Text(verbatim: attachment.title)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .lineLimit(1)
                .truncationMode(.middle)

            // **镜数只在稿子里真写着的时候才说。** 猜一个数字印上去，
            // 他会以为我们已经读懂了这份剧本 —— 那比不印更糟。
            if let shots = attachment.shots {
                Text(L10n.string("\(shots.formatted()) shots"))
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Accent.brand)
                    .monospacedDigit()
            }

            if let characters = attachment.characters {
                Text(L10n.string("\(characters.formatted()) characters"))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .frame(width: AppTheme.IconSize.smMd, height: AppTheme.IconSize.smMd)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.string("Remove"))
            .accessibilityLabel(Text(L10n.string("Remove")))
        }
        .padding(.horizontal, AppTheme.Spacing.smMd)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .cardSurface(
            AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.subtle), cornerRadius: AppTheme.Radius.md, border: AppTheme.Border.subtleColor, borderWidth: AppTheme.BorderWidth.hairline
        )
    }
}
