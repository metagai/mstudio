import SwiftUI

/// 全 app 唯一的登录入口。
///
/// **"Sign in" 不许自己替他挑一家。** 头像里那一颗此前一点就直接打开 Google
/// 授权页 —— 四种方式里另外三种在那颗按钮上根本不存在（2026-08-31 创始人实测：
/// 「毫无征兆地跳到了 Google 登录」）。装了这个 app 的人不一定有 Google 账号，
/// 国内用户基本上没有，而微信那条链路我们刚接好。
///
/// 所以它是个**菜单**：点开先看见四家，选哪一家由他决定。
/// `AccountService.signInWithGoogle()` 已经删掉了 —— 一个"登录"入口
/// 想悄悄跳 Google，得先自己写死 `.google`，而那是守卫在盯的事。
struct SignInMenu<Label: View>: View {
    private let label: () -> Label

    @Bindable private var account = AccountService.shared

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        Menu {
            ForEach(MetagAuth.Provider.allCases, id: \.self) { provider in
                Button(provider.title) { Task { await account.signIn(with: provider) } }
            }
        } label: {
            label()
        }
        .disabled(account.isSigningIn)
    }
}

extension SignInMenu where Label == SignInLabel {
    /// 最常见的那一种：一句话。
    init() { self.init { SignInLabel() } }
}

/// 按钮上**不提任何一家的名字** —— 名字在菜单里；写死一家就等于替他选了。
struct SignInLabel: View {
    @Bindable private var account = AccountService.shared

    var body: some View {
        Text(account.isSigningIn ? L10n.string("Opening…") : L10n.string("Sign in"))
    }
}
