import AppKit
import SwiftUI

struct MCPInstructionsPane: View {
    @Bindable private var appState = AppState.shared
    @State private var installError: String?
    @State private var token: String?
    @State private var tokenError: String?
    @State private var isRotating = false

    private var mcpEndpoint: String { "http://127.0.0.1:\(MCPService.port)/mcp" }

    /// Placeholder keeps the snippets copyable-looking while the token loads; the copy controls
    /// stay hidden until the real token is in hand.
    private var displayToken: String { token ?? "…" }

    /// For clients whose config format cannot carry a header.
    private var keyedEndpoint: String { "\(mcpEndpoint)?key=\(displayToken)" }

    private var claudeCodeCommand: String {
        "claude mcp add --transport http metag-mac \(mcpEndpoint) --header \"Authorization: Bearer \(displayToken)\""
    }

    private var codexCommand: String {
        "codex mcp add metag-mac --url \"\(keyedEndpoint)\""
    }

    private var cursorJSONConfig: String {
        """
        {
          "mcpServers": {
            "metag-mac": {
              "type": "http",
              "url": "\(keyedEndpoint)"
            }
          }
        }
        """
    }

    private var cursorDeepLink: URL? {
        let config: [String: String] = ["type": "http", "url": keyedEndpoint]
        guard
            token != nil,
            let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]),
            let encoded = data.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "cursor://anysphere.cursor-deeplink/mcp/install?name=metag-mac&config=\(encoded)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                Text("Connect an external agent to inspect and edit the open METAG project. The server listens on this Mac only and requires the access token below.")
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                if let refusal = appState.mcpService?.lastRefusal {
                    refusalNotice(refusal)
                }

                SettingsGroup(title: "Server URL") {
                    endpointRow
                }

                SettingsGroup(title: "Access token") {
                    tokenSection
                }

                SettingsGroup(title: "Connect an agent") {
                    agentList
                }
            }
            .frame(maxWidth: AppTheme.Settings.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, AppTheme.Spacing.xlXxl)
            .padding(.bottom, AppTheme.Spacing.xxl)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task { await loadToken() }
        .alert(
            "Unable to install",
            isPresented: Binding(
                get: { installError != nil },
                set: { if !$0 { installError = nil } }
            )
        ) {
            Button("Dismiss") { installError = nil }
        } message: {
            Text(installError ?? "Try again.")
        }
    }

    private var endpointRow: some View {
        CodeBlockView(
            content: mcpEndpoint,
            fontSize: AppTheme.FontSize.sm,
            foreground: AppTheme.Text.primaryColor,
            verticalPadding: AppTheme.Spacing.smMd
        )
    }

    @ViewBuilder
    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            if let tokenError {
                Text(tokenError)
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Status.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                CodeBlockView(
                    content: displayToken,
                    fontSize: AppTheme.FontSize.xs,
                    showsCopy: token != nil
                )
                HStack(spacing: AppTheme.Spacing.md) {
                    Text("Kept in ~/Library/Application Support/PalmierPro/mcp-token, readable only by you. The bundled Claude Desktop connector reads it automatically.")
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: AppTheme.Spacing.md)
                    Button(action: rotate) {
                        Text(isRotating ? "Regenerating…" : "Regenerate")
                            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                            .foregroundStyle(AppTheme.Accent.link)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .pointerStyle(.link)
                    .disabled(isRotating || token == nil)
                    .help("Issues a new token. Every connected agent must be reconnected with the new configuration.")
                }
            }
        }
    }

    private func refusalNotice(_ refusal: MCPAccessRefusal) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.Status.warningColor)
            Text(noticeText(refusal))
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, AppTheme.Spacing.md)
        .themedSurface(AppTheme.Background.raisedColor, cornerRadius: AppTheme.Radius.sm)
    }

    private func noticeText(_ refusal: MCPAccessRefusal) -> String {
        switch refusal {
        case .browserRequest:
            "A web page tried to reach this server and was blocked. Browser requests are never accepted."
        case .missingToken:
            "An agent was refused because it sent no access token. Re-add it with one of the configurations below."
        case .invalidToken:
            "An agent was refused because its access token is stale. Re-add it with one of the configurations below."
        }
    }

    private func loadToken() async {
        do {
            token = try await MCPAccessTokenStore.shared.current()
            tokenError = nil
        } catch {
            token = nil
            tokenError = "METAG could not create an access token, so the MCP server is not accepting connections. \(Log.detail(error))"
        }
    }

    private func rotate() {
        isRotating = true
        Task {
            defer { isRotating = false }
            do {
                token = try await AppState.shared.rotateMCPAccessToken()
                tokenError = nil
            } catch {
                tokenError = "METAG could not issue a new access token. \(Log.detail(error))"
            }
        }
    }

    private var agentList: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            claudeDesktopSection
            agentDivider
            claudeCodeSection
            agentDivider
            codexSection
            agentDivider
            cursorSection
        }
    }

    private var cursorSection: some View {
        agentSection(
            .cursor,
            name: "Cursor",
            description: "Install the METAG MCP server in Cursor.",
            action: ("Install in Cursor", openCursor)
        ) {
            ManualFallback(
                intro: "Add this configuration to ~/.cursor/mcp.json.",
                code: cursorJSONConfig
            )
        }
    }

    private var claudeDesktopSection: some View {
        agentSection(
            .claude,
            name: "Claude Desktop",
            description: "Install the bundled METAG connector.",
            action: ("Install in Claude Desktop", openClaudeDesktopBundle)
        ) {
            EmptyView()
        }
    }

    private var claudeCodeSection: some View {
        agentSection(
            .claude,
            name: "Claude Code",
            description: "Run this command once in Terminal."
        ) {
            CodeBlockView(content: claudeCodeCommand, showsCopy: token != nil)
        }
    }

    private var codexSection: some View {
        agentSection(
            .codex,
            name: "Codex",
            description: "Run this command once in Terminal."
        ) {
            CodeBlockView(content: codexCommand, showsCopy: token != nil)
        }
    }

    private var agentDivider: some View {
        Divider().overlay(AppTheme.Border.subtleColor)
    }

    private func agentSection<Details: View>(
        _ agent: SkillExternalAgent,
        name: String,
        description: String,
        action: (label: String, perform: () -> Void)? = nil,
        @ViewBuilder details: () -> Details
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                agentIdentity(agent: agent, name: name, description: description)
                if let action {
                    Spacer(minLength: AppTheme.Spacing.md)
                    externalAction(action.label, action: action.perform)
                }
            }
            details()
        }
        .padding(.vertical, AppTheme.Spacing.mdLg)
    }

    private func agentIdentity(agent: SkillExternalAgent, name: String, description: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ExternalAgentLogo(agent: agent, size: AppTheme.IconSize.lgXl)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(name)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(description)
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func externalAction(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xxs) {
                Text(label)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.regular))
            }
            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
            .foregroundStyle(AppTheme.Accent.link)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .pointerStyle(.link)
    }

    private func openCursor() {
        guard let cursorDeepLink else {
            installError = tokenError ?? "The access token is still loading. Try again in a moment."
            return
        }
        NSWorkspace.shared.open(cursorDeepLink, configuration: .init(), completionHandler: nil)
    }

    private func openClaudeDesktopBundle() {
        guard let bundleURL = claudeDesktopBundleURL else {
            installError = "The METAG connector could not be found. Reinstall METAG, then try again."
            return
        }
        guard let claudeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") else {
            installError = "Install Claude Desktop, then try again."
            return
        }

        NSWorkspace.shared.open(
            [bundleURL],
            withApplicationAt: claudeURL,
            configuration: .init()
        ) { _, error in
            guard error != nil else { return }
            Task { @MainActor in
                installError = "Claude Desktop could not open the METAG connector. Update Claude Desktop, then try again."
            }
        }
    }

    private var claudeDesktopBundleURL: URL? {
        BundledResource.url("metag.mcpb")
    }
}

private struct CodeBlockView: View {
    let content: String
    var fontSize = AppTheme.FontSize.xs
    var foreground = AppTheme.Text.secondaryColor
    var verticalPadding = AppTheme.Spacing.md
    var showsCopy = true

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            Text(content)
                .font(.system(size: fontSize, weight: AppTheme.FontWeight.regular, design: .monospaced))
                .foregroundStyle(foreground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsCopy { CopyButton(value: content) }
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, verticalPadding)
        .themedSurface(AppTheme.Background.raisedColor, cornerRadius: AppTheme.Radius.sm)
    }
}

private struct ManualFallback: View {
    let intro: String
    let code: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Button(action: toggle) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.regular))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Manual setup")
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                }
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(intro)
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                    CodeBlockView(content: code)
                }
            }
        }
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: AppTheme.Anim.hover)) {
            expanded.toggle()
        }
    }
}

private struct CopyButton: View {
    private static let feedbackDuration: Duration = .seconds(1.4)

    let value: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(copied ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor)
                .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy")
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: Self.feedbackDuration)
            copied = false
        }
    }
}

#Preview {
    MCPInstructionsPane()
        .frame(width: AppTheme.Settings.contentMaxWidth, height: AppTheme.Settings.skillDetailMinHeight)
        .background(AppTheme.Background.surfaceColor)
}
