import SwiftUI

struct ModelsPane: View {
    private var prefs = ModelPreferences.shared
    private var catalog = ModelCatalog.shared
    private var account = AccountService.shared

    @State private var query = ""

    private struct Row: Identifiable {
        let id: String
        let displayName: String
        /// 这一档是什么（`1080p · 5s` 这类）。
        let spec: String?
        /// **这一档适合拍什么，一句话。** 报价单里本来就有，
        /// 草案表那边也早就在显示 —— 而这一屏一直没用。
        ///
        /// 一张只有名字和开关的库存清单，不是一套可以挑的积木：
        /// 他看不出"前沿"和"专业"差在哪，只能靠猜。
        let blurb: String?
        /// 每镜多少 credits。**挑一档就是在花钱**，而这一屏原来一个数字都没有。
        let creditsPerShot: Int?
        let paidOnly: Bool
        let providerIconKey: String?
    }

    private struct Section: Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    private func isLocked(_ row: Row) -> Bool { row.paidOnly && !account.isPaid }

    private var sections: [Section] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func prepare(_ rows: [Row]) -> [Row] {
            let matched = q.isEmpty ? rows : rows.filter { $0.displayName.lowercased().contains(q) }
            // Available models first, locked (paid-only) ones grouped at the bottom.
            return matched.filter { !isLocked($0) } + matched.filter { isLocked($0) }
        }
        return [
            Section(id: "image", title: L10n.string("Image"),
                    rows: prepare(catalog.image.map { row(for: $0.entry) })),
            Section(id: "video", title: L10n.string("Video"),
                    rows: prepare(catalog.video.map { row(for: $0.entry) })),
            Section(id: "audio", title: L10n.string("Audio"),
                    rows: prepare(catalog.audio.map { row(for: $0.entry) })),
        ].filter { !$0.rows.isEmpty }
    }

    private func row(for entry: CatalogEntry) -> Row {
        Row(
            id: entry.id,
            displayName: entry.displayName,
            spec: entry.description?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? entry.description?.trimmingCharacters(in: .whitespaces) : nil,
            blurb: entry.blurb?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? entry.blurb?.trimmingCharacters(in: .whitespaces) : nil,
            creditsPerShot: entry.creditsPerShot,
            paidOnly: entry.paidOnly,
            providerIconKey: entry.providerIconKey
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            searchBar

            if sections.isEmpty {
                Text(catalog.isLoaded
                    ? L10n.string("No models match \"\(query)\".")
                    : L10n.string("Loading models…"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .padding(.top, AppTheme.Spacing.lg)
            } else {
                ForEach(sections) { section in
                    sectionView(section)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.mutedColor)
            TextField(L10n.string("Search models"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.primaryColor)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .cardSurface(
            AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.subtle), cornerRadius: AppTheme.Radius.md, border: AppTheme.Border.primaryColor, borderWidth: AppTheme.BorderWidth.thin
        )
    }

    private func sectionView(_ section: Section) -> some View {
        SettingsSection(title: section.title) {
            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    modelRow(row)
                    if index < section.rows.count - 1 {
                        Divider().overlay(AppTheme.Border.subtleColor)
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }

    @ViewBuilder
    private func modelRow(_ row: Row) -> some View {
        let locked = isLocked(row)
        HStack(spacing: AppTheme.Spacing.md) {
            if let iconKey = row.providerIconKey {
                ProviderLogo(iconKey: iconKey, size: AppTheme.IconSize.md)
                    .opacity(locked ? AppTheme.Opacity.medium : AppTheme.Opacity.opaque)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(row.displayName)
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(locked ? AppTheme.Text.tertiaryColor : AppTheme.Text.primaryColor)
                // **这一档适合拍什么。** 有就说，没有就不说 ——
                // 不给一句凑出来的介绍。
                if let blurb = row.blurb {
                    Text(verbatim: blurb)
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 规格和单价并排：**挑一档就是在花钱**，
                // 而这一屏原来一个数字都没有。
                HStack(spacing: AppTheme.Spacing.xs) {
                    if let spec = row.spec {
                        Text(verbatim: spec)
                    }
                    if let price = row.creditsPerShot {
                        if row.spec != nil { Text(verbatim: "·") }
                        Text(L10n.string("\(price.formatted()) credits / shot"))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.mutedColor)
            }
            Spacer(minLength: AppTheme.Spacing.lg)
            if locked {
                Button(L10n.string("Subscribe")) {
                    SettingsWindowController.shared.show(tab: .account)
                }
                .buttonStyle(.capsule(.secondary))
            } else {
                Toggle(String(), isOn: Binding(
                    get: { prefs.isEnabled(row.id) },
                    set: { prefs.setEnabled(row.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(row.displayName)
            }
        }
        .padding(.vertical, AppTheme.Spacing.smMd)
    }
}
