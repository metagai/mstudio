import SwiftUI

struct LanguagePane: View {
    @State private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(L("Language"))
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(L("Applies immediately. Untranslated text falls back to English."))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            Spacer(minLength: 0)
            Picker("", selection: $l10n.language) {
                ForEach(L10n.Language.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .onChange(of: l10n.language) { _, _ in
            // Engine display names arrive per-language from the gateway.
            Task { await ModelCatalog.shared.load() }
        }
    }
}
