import SwiftUI

struct HomeView: View {
    @Bindable private var onboarding = OnboardingStore.shared
    @Bindable private var changelog = ChangelogStore.shared

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar()
                .frame(width: AppTheme.Settings.sidebarWidth)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.Background.baseColor)
        }
        .frame(
            minWidth: AppTheme.Window.homeMin.width,
            maxWidth: .infinity,
            minHeight: AppTheme.Window.homeMin.height,
            maxHeight: .infinity
        )
        .background(AppTheme.Background.surfaceColor)
        .focusEffectDisabled()
        .task { await VisualModelLoader.shared.prepare() }
        .onAppear { changelog.checkForWhatsNew() }
        .overlay {
            ZStack {
                if !onboarding.isComplete {
                    OnboardingOverlay(onboarding: onboarding)
                } else if let entry = changelog.pending {
                    UpdateOverlay(entry: entry, changelogURL: changelog.changelogURL) {
                        changelog.dismiss()
                    }
                }
            }
            .allowsHitTesting(isModalOverlayPresented)
        }
        .animation(.easeInOut(duration: AppTheme.Anim.transition), value: isModalOverlayPresented)
    }

    private var isModalOverlayPresented: Bool {
        !onboarding.isComplete || changelog.pending != nil
    }

    /// 首屏的主角是那一句问话，不是项目列表 —— 所以它拿走上面那一整块留白，
    /// 项目列表退到分隔线以下。窗口再矮也能滚到，不靠"应该放得下"。
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHero()
                    .padding(.horizontal, AppTheme.Spacing.xlXxl)
                    .padding(.top, AppTheme.Spacing.xxxl)
                    .padding(.bottom, AppTheme.Spacing.xxxl)

                Divider()
                    .overlay(AppTheme.Border.subtleColor)
                    .padding(.horizontal, AppTheme.Spacing.xlXxl)
                    .padding(.bottom, AppTheme.Spacing.xxl)

                SampleProjectsStrip()
                MyProjectsSection()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct HomeSidebar: View {
    @Bindable private var account = AccountService.shared
    @Bindable private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if account.isSignedIn {
                IdentityStrip()
            }

            VStack(alignment: .leading, spacing: 2) {
                SidebarRowButton(
                    label: L10n.string("New Project"),
                    systemImage: "plus",
                    action: { AppState.shared.createProjectInteractively() }
                )
                SidebarRowButton(
                    label: L10n.string("Open Project"),
                    systemImage: "folder",
                    action: { AppState.shared.openProjectFromPanel() }
                )
            }
            .padding(.horizontal, AppTheme.Spacing.smMd)
            .padding(.vertical, AppTheme.Spacing.md)

            Spacer(minLength: 0)

            UpdateSidebarCard()
                .padding(.horizontal, AppTheme.Spacing.smMd)
                .padding(.bottom, AppTheme.Spacing.sm)
                .animation(.easeInOut(duration: AppTheme.Anim.transition), value: updater.updateAvailable)

            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 侧栏底部那一块。**一条分隔线，两行同样的字。**
    ///
    /// 原来这里是两种控件并排：登录是个 `Menu`（系统小箭头、自己的高亮、
    /// `mdLg` 左边距），设置是 `SidebarRowButton`（`smMd` 左边距、我们的高亮）。
    /// **两行字对不齐、两种高亮、一个有箭头一个没有** —— 单独看每行都正常，
    /// 并排看就是"这两行不是一套东西"。而它是首页上除了那句问话之外
    /// 唯一常驻的东西，他每次打开都看见。
    ///
    /// 现在两行共用 `SidebarRowLabel`：同一条左轴、同一个行高、同一种悬停。
    /// 上面加一条分隔线 —— 它们是**出口**，不是内容的延续。
    ///
    /// 登录走 `SignInMenu`：这里原来自己抄了一遍那个 provider 循环，
    /// 于是"登录入口只有一处"这件事又有了第二处。
    @ViewBuilder
    private var footer: some View {
        Divider()
            .overlay(AppTheme.Border.subtleColor)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.xs)

        VStack(alignment: .leading, spacing: 0) {
            if !account.isSignedIn && !account.isMisconfigured {
                SignInMenu {
                    SidebarRowLabel(
                        label: account.isSigningIn ? L10n.string("Opening…") : L10n.string("Sign in"),
                        systemImage: "person.crop.circle"
                    )
                    .hoverHighlight(cornerRadius: AppTheme.Radius.xl)
                    .contentShape(Capsule(style: .continuous))
                }
                // 系统那个小箭头去掉：它让这一行比旁边那行多一个零件。
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }

            SidebarRowButton(
                label: L10n.string("Settings"),
                systemImage: "gearshape",
                action: { SettingsWindowController.shared.show() }
            )
        }
        .padding(.horizontal, AppTheme.Spacing.smMd)
        .padding(.bottom, AppTheme.Spacing.md)
    }
}

// MARK: - Home window controller

@MainActor
final class HomeWindowController: NSWindowController {
    static let shared = HomeWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: HomeView().appLocalization().tint(AppTheme.Accent.primary))
        hostingController.sizingOptions = .minSize
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(AppTheme.Window.homeDefault)
        window.minSize = AppTheme.Window.homeMin
        window.title = "METAG"
        window.backgroundColor = AppTheme.Background.base
        window.isOpaque = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior = [.fullScreenNone]
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
