import SwiftUI

/// 界面明暗。**默认跟随系统** —— 用户的系统已经表达过偏好，开箱就该尊重它。
///
/// 放在「通用」的最上面：长时间剪辑的人第一件想调的就是这个，
/// 而它此前根本不存在（窗口被写死成亮色，见 AppearancePreference 的注释）。
struct AppearancePane: View {
    @State private var mode = AppearancePreference.mode

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(L("Appearance"))
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(L("Applies immediately. Dark is easier on the eyes for long sessions."))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            Spacer(minLength: 0)
            Picker("", selection: $mode) {
                ForEach(AppearanceMode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: mode) { _, new in
                AppearancePreference.mode = new
            }
        }
    }
}
