import Testing

@testable import PalmierPro

/// 标题栏宿主视图是定宽的：放不下就**静默裁掉**按钮，不会报错也不会换行。
/// 按钮从一个加到三个时踩过这个坑，所以把"装得下"钉住。
struct TitleBarPanelToggleTests {
    @Test func leadingTitlebarFitsThreePanelButtons() {
        let needed = AppTheme.IconSize.lg * 3 + AppTheme.Spacing.smMd + AppTheme.Spacing.xxs
        #expect(AppTheme.Window.projectTitlebarLeadingWidth >= needed)
    }
}
