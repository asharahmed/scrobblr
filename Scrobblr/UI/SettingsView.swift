import SwiftUI
import AppKit

/// Settings window. replaces the old 3-tab layout with a NavigationSplitView
/// sidebar, the macOS-13+ idiom Apple themselves adopted in System Settings.
/// Each section is a self-contained rich view rather than a flat form.
struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selection: Section? = .account

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case account, playback, general, activity, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .account:  "Account"
            case .playback: "Playback"
            case .general:  "General"
            case .activity: "Activity"
            case .about:    "About"
            }
        }
        var icon: String {
            switch self {
            case .account:  "person.crop.circle"
            case .playback: "waveform"
            case .general:  "gearshape"
            case .activity: "clock.arrow.circlepath"
            case .about:    "info.circle"
            }
        }
        var tint: Color {
            switch self {
            case .account:  .pink
            case .playback: .indigo
            case .general:  .gray
            case .activity: .green
            case .about:    .blue
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 480, ideal: 520)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 520)
    }

    private var sidebar: some View {
        List(Section.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label {
                    Text(section.label)
                        .font(.system(size: 13))
                        .padding(.leading, 2)
                } icon: {
                    sidebarIcon(section)
                }
            }
            .padding(.vertical, 1)
        }
        .listStyle(.sidebar)
    }

    private func sidebarIcon(_ section: Section) -> some View {
        sectionIcon(section, size: 20, symbolSize: 11, corner: 5)
    }

    /// Reusable section glyph. Used at multiple sizes (sidebar 20pt,
    /// detail header 32pt) without `.scaleEffect`, which would blur.
    private func sectionIcon(_ section: Section, size: CGFloat, symbolSize: CGFloat, corner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(
                    colors: [section.tint, section.tint.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .shadow(color: section.tint.opacity(0.25), radius: size > 24 ? 4 : 0, x: 0, y: size > 24 ? 1 : 0)
            Image(systemName: section.icon)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailHeader
                Group {
                    switch selection ?? .account {
                    case .account:  AccountSectionView()
                    case .playback: PlaybackSectionView()
                    case .general:  GeneralSectionView()
                    case .activity: ActivitySectionView()
                    case .about:    AboutSectionView()
                    }
                }
                .id(selection)
                .transition(.opacity)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.15), value: selection)
        .background(.windowBackground)
    }

    private var detailHeader: some View {
        let section = selection ?? .account
        return HStack(spacing: 14) {
            sectionIcon(section, size: 36, symbolSize: 18, corner: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.label)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                Text(subtitleFor(section))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func subtitleFor(_ s: Section) -> String {
        switch s {
        case .account:
            return coordinator.username.map { "Signed in as \($0)" } ?? "Manage your Last.fm connection"
        case .playback:
            let activeFilters = activePlaybackFilterCount
            if activeFilters > 0 {
                return "\(activeFilters) active filter\(activeFilters == 1 ? "" : "s")"
            }
            return "How Scrobblr reads from Music.app"
        case .general:
            return UserScrobbleSettings.shared.isPaused ? "Scrobbling paused" : "App behaviour and startup"
        case .activity:
            let n = coordinator.engine.queueCount
            if n > 0 { return "\(n) pending submission\(n == 1 ? "" : "s")" }
            return "Recent scrobbles and queue"
        case .about:
            return "Credits, version, and links"
        }
    }

    /// Counts the user-overridable filters that are currently affecting scrobbles.
    private var activePlaybackFilterCount: Int {
        let s = UserScrobbleSettings.shared
        var n = 0
        if s.thresholdPercent != 0.5 || s.thresholdSeconds != 240 { n += 1 }
        if s.skipPodcasts { n += 1 }
        if s.skipAudiobooks { n += 1 }
        if s.skipMusicVideos { n += 1 }
        if !IgnoreRules.shared.rules.isEmpty { n += 1 }
        return n
    }
}

// MARK: - Reusable section building blocks

private struct SettingsCard<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary.opacity(0.4))
                }
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Account

private struct AccountSectionView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coordinator.isAuthenticated {
                signedInCard
            } else {
                authCard
            }
            if let e = coordinator.authError {
                errorBanner(e)
            }
            CredentialsCard()
        }
    }

    private var signedInCard: some View {
        SettingsCard(footer: "Scrobblr talks only to ws.audioscrobbler.com using your session key. No account password is ever stored.") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coordinator.username ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("Signed in to Last.fm")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                Divider()
                // Buttons flow as a wrap-friendly row. Sign out is separated by
                // a divider so it doesn't sit visually next to the links.
                HStack(spacing: 8) {
                    Link(destination: profileURL) {
                        Label("Profile", systemImage: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    Link(destination: URL(string: "https://www.last.fm/settings/applications")!) {
                        Label("Authorizations", systemImage: "lock.shield")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(role: .destructive) {
                        coordinator.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var profileAvatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.pink, .pink.opacity(0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .shadow(color: .pink.opacity(0.25), radius: 6, x: 0, y: 2)
            if let initial = coordinator.username?.first.map(String.init)?.uppercased(),
               !initial.isEmpty {
                Text(initial)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var profileURL: URL {
        let escaped = (coordinator.username ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://www.last.fm/user/\(escaped)")
            ?? URL(string: "https://www.last.fm")!
    }

    @ViewBuilder
    private var authCard: some View {
        SettingsCard {
            switch coordinator.authPhase {
            case .idle:           connectPrompt
            case .fetchingToken:  progressBlock(title: "Connecting…", subtitle: "Requesting authorization from Last.fm")
            case .awaitingApproval: awaitingBlock
            case .completing:     progressBlock(title: "Finishing sign-in…", subtitle: "Exchanging token for session")
            }
        }
    }

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.pink.opacity(0.15))
                    Image(systemName: "link").foregroundStyle(.pink).font(.system(size: 16))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to Last.fm").font(.system(size: 13, weight: .semibold))
                    Text("Approve Scrobblr in your browser. We'll sign you in automatically.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await coordinator.beginAuth() }
            } label: {
                Label("Sign in with Last.fm", systemImage: "safari")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    private var awaitingBlock: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.pink.opacity(0.15))
                ProgressView().controlSize(.small).scaleEffect(0.85)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for approval").font(.system(size: 13, weight: .semibold))
                Text("Once you approve in the browser, Scrobblr will detect it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                coordinator.cancelAuth()
            } label: {
                Label("Cancel", systemImage: "xmark")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
        }
    }

    private func progressBlock(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - BYOK credentials card

private struct CredentialsCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var credentials = Credentials.shared
    @State private var editing = false
    @State private var apiKeyInput = ""
    @State private var sharedSecretInput = ""
    @State private var err: String? = nil

    var body: some View {
        SettingsCard(
            title: "Last.fm API key",
            footer: "Scrobblr uses your own Last.fm API key. Register one at last.fm/api/account/create. It's free."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if credentials.isConfigured && !editing {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(.green.opacity(0.18))
                            Image(systemName: "key.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("API key configured").font(.system(size: 13, weight: .semibold))
                            // Show first 4 + ellipsis + last 4 of the API key.
                            // Shared secret never displayed.
                            Text(maskedKeyPreview)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button {
                            startEdit()
                        } label: {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("API Key (32 hex chars)", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .disableAutocorrection(true)
                        SecureField("Shared Secret (32 hex chars)", text: $sharedSecretInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        if let e = err {
                            Text(e).font(.system(size: 11)).foregroundStyle(.orange)
                        }
                        HStack {
                            Link(destination: URL(string: "https://www.last.fm/api/account/create")!) {
                                Label("Get a key", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            if editing {
                                Button("Cancel") { editing = false; err = nil }
                                    .buttonStyle(.bordered)
                            }
                            Button("Save") { save() }
                                .buttonStyle(.borderedProminent)
                                .disabled(apiKeyInput.isEmpty || sharedSecretInput.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private var maskedKeyPreview: String {
        guard let key = credentials.apiKey, key.count >= 8 else { return "" }
        let head = key.prefix(4)
        let tail = key.suffix(4)
        return "\(head)···\(tail)"
    }

    private func startEdit() {
        apiKeyInput = ""
        sharedSecretInput = ""
        err = nil
        editing = true
    }

    private func save() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = sharedSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count == 32 && secret.count == 32,
              key.allSatisfy({ $0.isHexDigit }),
              secret.allSatisfy({ $0.isHexDigit }) else {
            err = "Both must be 32 hex characters."
            return
        }
        do {
            try coordinator.setCredentials(apiKey: key, sharedSecret: secret)
            editing = false
            err = nil
        } catch {
            err = error.localizedDescription
        }
    }
}

// MARK: - Playback

private struct PlaybackSectionView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var probeStatus: AutomationPermission.Status = .notDetermined
    @State private var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: "Music access",
                footer: "Required for the smooth-progress bar and for fallback metadata on tracks that distributed notifications don't fully describe. macOS handles permission in Privacy & Security → Automation."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    statusBlock
                    HStack {
                        Button {
                            refresh()
                        } label: {
                            Label("Recheck", systemImage: "arrow.clockwise").font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .disabled(refreshing)
                        if probeStatus == .denied {
                            Button {
                                AutomationPermission.openSystemSettings()
                            } label: {
                                Label("Open System Settings", systemImage: "gearshape").font(.system(size: 12))
                            }
                            .buttonStyle(.borderedProminent)
                        } else if probeStatus != .granted {
                            Button {
                                Task { await requestAccess() }
                            } label: {
                                Label("Grant access", systemImage: "checkmark.shield").font(.system(size: 12))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                }
            }

            subsectionHeader("Filters")
            ThresholdCard()
            ContentFilterCard()
            IgnoreListCard()
        }
        .onAppear { refresh() }
    }

    private func subsectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
            .padding(.top, 8)
    }

    private var statusBlock: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle).font(.system(size: 13, weight: .semibold))
                Text(statusDetail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var statusIcon: some View {
        let (sym, color): (String, Color) = switch probeStatus {
        case .granted:          ("checkmark", .green)
        case .denied:           ("xmark",     .orange)
        case .notDetermined:    ("questionmark", .secondary)
        case .targetNotRunning: ("circle.dashed", .secondary)
        }
        return ZStack {
            Circle().fill(color.opacity(0.18))
            Image(systemName: sym)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 32, height: 32)
    }

    private var statusTitle: String {
        switch probeStatus {
        case .granted:          "Music access granted"
        case .denied:           "Music access denied"
        case .notDetermined:    "Music access not yet requested"
        case .targetNotRunning: "Music isn't running"
        }
    }

    private var statusDetail: String {
        switch probeStatus {
        case .granted:          "Polling for precise position info is enabled."
        case .denied:           "Scrobblr can still detect track changes via distributed notifications, but the progress bar and Tahoe-fallback metadata won't work."
        case .notDetermined:    "Click Grant access. macOS will show a permission prompt."
        case .targetNotRunning: "Launch Apple Music and click Recheck."
        }
    }


    private func refresh() {
        refreshing = true
        probeStatus = AutomationPermission.status(forBundleID: "com.apple.Music")
        if probeStatus == .granted {
            coordinator.observer.enablePlaybackPolling()
        }
        refreshing = false
    }

    private func requestAccess() async {
        _ = await MusicAppBridge.shared.snapshot()
        try? await Task.sleep(for: .seconds(1))
        refresh()
    }
}

// MARK: - General

private struct GeneralSectionView: View {
    @ObservedObject private var loginItem = LoginItem.shared
    @State private var launchAtLogin: Bool = LoginItem.shared.isEnabled
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: "Startup",
                footer: "Scrobblr runs in the menu bar. Closing the welcome window doesn't quit the app."
            ) {
                VStack(spacing: 12) {
                    SettingsRow(
                        title: "Launch at login",
                        subtitle: "Start Scrobblr automatically when you sign in to your Mac"
                    ) {
                        Toggle("", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: launchAtLogin) { _, new in
                                if !loginItem.setEnabled(new) {
                                    DispatchQueue.main.async { launchAtLogin = loginItem.isEnabled }
                                }
                            }
                    }
                }
            }

            SettingsCard(
                title: "Notifications",
                footer: "Optional banner when a new track starts playing. Toggling on will trigger the macOS permission prompt."
            ) {
                NowPlayingToggleRow()
            }

            SettingsCard(title: "Updates", footer: "Scrobblr checks for new versions daily. Updates are verified with EdDSA; only releases signed by the official key install.") {
                SettingsRow(title: "Software updates", subtitle: "Check for and install new versions") {
                    Button("Check now…") { Updater.shared.checkForUpdates() }
                        .buttonStyle(.bordered)
                        .disabled(!Updater.shared.canCheckForUpdates)
                }
            }

            SettingsCard(title: "Welcome", footer: "Replay the first-time setup flow.") {
                SettingsRow(title: "Welcome window", subtitle: "Open the onboarding flow") {
                    Button("Show…") { coordinator.showWelcome() }
                        .buttonStyle(.bordered)
                }
            }

            SettingsCard(
                title: "Support",
                footer: "Diagnostics include the last hour of app.scrobblr log entries and the queue file with track names redacted. Review before attaching to a bug report."
            ) {
                VStack(spacing: 10) {
                    SettingsRow(title: "Export diagnostics", subtitle: "Save a .zip to your Desktop") {
                        DiagnosticsExportButton()
                    }
                    Divider().opacity(0.5)
                    SettingsRow(title: "Report a bug", subtitle: "Opens GitHub Issues in your browser") {
                        Link(destination: URL(string: "https://github.com/asharahmed/scrobblr/issues/new")!) {
                            Label("Open", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

private struct DiagnosticsExportButton: View {
    @State private var state: ExportState = .idle
    enum ExportState: Equatable {
        case idle, exporting, done(URL), failed
    }

    var body: some View {
        HStack(spacing: 8) {
            if case .done = state {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12))
                    .symbolEffect(.bounce, value: state)
            } else if case .failed = state {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
            }
            Button {
                Task { await run() }
            } label: {
                HStack(spacing: 6) {
                    if state == .exporting {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Exporting…").font(.system(size: 12))
                    } else {
                        Text("Export…").font(.system(size: 12))
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(state == .exporting)
        }
        .animation(.easeOut(duration: 0.15), value: state)
    }

    private func run() async {
        state = .exporting
        if let url = await Diagnostics.exportToDesktop() {
            state = .done(url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            state = .failed
        }
        try? await Task.sleep(for: .seconds(3))
        state = .idle
    }
}

// MARK: - Activity

private struct ActivitySectionView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var todayCount: Int? = nil
    @State private var weekCount: Int? = nil
    @State private var statsLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coordinator.isAuthenticated { statsCard }
            PauseCard()
            queueCard
            recentCard
            LovedTracksCard()
        }
        .task(id: coordinator.engine.recentScrobbles.count) {
            await refreshStats()
        }
    }

    private var statsCard: some View {
        SettingsCard(title: "Last.fm totals") {
            HStack(spacing: 24) {
                statTile(value: todayCount, label: "Today")
                Divider().frame(height: 32)
                statTile(value: weekCount, label: "Last 7 days")
                Spacer()
                Button {
                    Task { await refreshStats(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: statsLoading)
                }
                .buttonStyle(.borderless)
                .disabled(statsLoading)
                .help("Refresh from Last.fm")
            }
        }
    }

    private func statTile(value: Int?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if let v = value {
                    Text(formatted(v))
                        .contentTransition(.numericText())
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .tracking(-0.5)
            .animation(.snappy, value: value)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
        }
        .frame(minWidth: 80, alignment: .leading)
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func refreshStats(force: Bool = false) async {
        guard let username = coordinator.username else { return }
        if !force, todayCount != nil, weekCount != nil { return }
        statsLoading = true
        defer { statsLoading = false }
        let cal = Calendar.current
        let dayStart = Int(cal.startOfDay(for: Date()).timeIntervalSince1970)
        let weekStart = Int(Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970)
        async let day = coordinator.client.recentTrackCount(username: username, since: dayStart)
        async let week = coordinator.client.recentTrackCount(username: username, since: weekStart)
        let (d, w) = await (day, week)
        await MainActor.run {
            self.todayCount = d
            self.weekCount = w
        }
    }

    private var queueIndicatorColor: Color {
        if coordinator.engine.isFlushing { return .accentColor }
        return coordinator.engine.queueCount == 0 ? .green : .secondary
    }

    private var queueIndicatorSymbol: String {
        coordinator.engine.queueCount == 0 ? "checkmark" : "tray.fill"
    }

    private var queueCard: some View {
        SettingsCard(
            title: "Submission queue",
            footer: "Pending scrobbles are held locally and submitted in batches. Offline plays catch up automatically when you reconnect."
        ) {
            VStack(spacing: 12) {
                let queueCount = coordinator.engine.queueCount
                let isFlushing = coordinator.engine.isFlushing
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(queueIndicatorColor.opacity(0.18))
                        if isFlushing {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        } else {
                            Image(systemName: queueIndicatorSymbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(queueIndicatorColor)
                        }
                    }
                    .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(queueCount) pending")
                            .font(.system(size: 13, weight: .semibold))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: queueCount)
                        Text(isFlushing ? "Submitting now…" : (queueCount == 0 ? "Up to date" : "Will submit shortly"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                HStack(spacing: 8) {
                    Button {
                        Task {
                            let url = await coordinator.queue.fileURL()
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        Label("Reveal queue file", systemImage: "folder").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        coordinator.engine.requestFlushNow()
                    } label: {
                        Label("Submit now", systemImage: "arrow.up.circle").font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.engine.queueCount == 0 || coordinator.engine.isFlushing)
                    Spacer()
                    Button("Discard pending…", role: .destructive) {
                        Task {
                            _ = await coordinator.queue.clearAll()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.engine.queueCount == 0)
                }
                .font(.system(size: 12))
            }
        }
    }

    private var recentCard: some View {
        SettingsCard(title: "Recent scrobbles") {
            if coordinator.engine.recentScrobbles.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("No scrobbles yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Play something in Apple Music. Scrobbles past Last.fm's threshold appear here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // `LastScrobble` is Hashable on (title, artist, uploadedAt, playedAt)
                    // which is unique-enough in practice for animations.
                    ForEach(Array(coordinator.engine.recentScrobbles.enumerated()), id: \.element) { i, s in
                        if i > 0 { Divider().opacity(0.5) }
                        scrobbleRow(s)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func scrobbleRow(_ s: ScrobbleEngine.LastScrobble) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 11))
                .foregroundStyle(.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(s.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(relativeTime(s.uploadedAt))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func relativeTime(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s/60))m" }
        if s < 86400 { return "\(Int(s/3600))h" }
        return "\(Int(s/86400))d"
    }
}

// MARK: - About

private struct AboutSectionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            SettingsCard(title: "What it does") {
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Scrobbles when a track passes 50% or 4 minutes")
                    bullet("Queues plays offline and retries on reconnect")
                    bullet("Streams and Apple Music Radio are never scrobbled")
                    bullet("Album art via the free iTunes Search API")
                    bullet("No analytics. Talks only to Last.fm and Apple.")
                }
            }
            SettingsCard(title: "Privacy") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scrobblr doesn't run a server. It talks to Last.fm to submit plays and to Apple's anonymous iTunes Search API for album art. That's all outbound network traffic.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().opacity(0.5)
                    linkRow("Privacy policy", "What we read, send, and store",
                            "https://github.com/ashar/scrobblr/blob/main/PRIVACY.md")
                }
            }

            SettingsCard(title: "Open-source credits") {
                VStack(alignment: .leading, spacing: 10) {
                    linkRow("Last.fm Web Services", "Scrobble and authentication API",
                            "https://www.last.fm/api")
                    linkRow("Apple iTunes Search API", "Anonymous artwork lookup",
                            "https://performance-partners.apple.com/search-api")
                    linkRow("Sparkle", "Software update framework",
                            "https://sparkle-project.org")
                }
            }

            Text("Last.fm® is owned by CBS Interactive Inc. Apple Music® is owned by Apple Inc. Scrobblr is independent and unaffiliated.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.top, 4)
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.pink, .pink.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(color: .pink.opacity(0.35), radius: 10, x: 0, y: 4)
                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scrobblr").font(.system(size: 19, weight: .bold)).tracking(-0.25)
                Text("Version \(version) (\(build))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Last.fm scrobblr for Apple Music on macOS")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 12, alignment: .leading)
                .padding(.top, 3)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linkRow(_ title: String, _ subtitle: String, _ urlString: String) -> some View {
        Link(destination: URL(string: urlString)!) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
}

// MARK: - Threshold

private struct ThresholdCard: View {
    @ObservedObject private var settings = UserScrobbleSettings.shared

    var body: some View {
        SettingsCard(
            title: "Scrobble threshold",
            footer: "Defaults match Last.fm's official rules: 50% of duration or 4 minutes, whichever first."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Percent played").font(.system(size: 12.5))
                        Spacer()
                        Text("\(Int(settings.thresholdPercent * 100))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.thresholdPercent, in: 0.2...0.95, step: 0.05) {
                        Text("Percent")
                    } minimumValueLabel: {
                        Text("20%").font(.system(size: 10)).foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Text("95%").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Absolute cap").font(.system(size: 12.5))
                        Spacer()
                        Text("\(Int(settings.thresholdSeconds))s")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.thresholdSeconds, in: 60...600, step: 30) {
                        Text("Seconds")
                    } minimumValueLabel: {
                        Text("1m").font(.system(size: 10)).foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Text("10m").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                Divider().opacity(0.5)
                // Always-present reset button. Disabled state when at
                // defaults so the card never jumps height as the user
                // drags sliders past / back to the defaults.
                HStack {
                    let atDefaults = settings.thresholdPercent == 0.5
                                  && settings.thresholdSeconds == 240
                    Image(systemName: atDefaults ? "checkmark.circle.fill" : "slider.horizontal.below.rectangle")
                        .font(.system(size: 11))
                        .foregroundStyle(atDefaults ? .green : .orange)
                    Text(atDefaults ? "At Last.fm defaults" : "Custom thresholds active")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to defaults") {
                        settings.thresholdPercent = 0.5
                        settings.thresholdSeconds = 240
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(atDefaults)
                }
            }
        }
    }
}

// MARK: - Content filter

private struct ContentFilterCard: View {
    @ObservedObject private var settings = UserScrobbleSettings.shared

    var body: some View {
        SettingsCard(
            title: "Content filter",
            footer: "Filtered kinds never reach Last.fm."
        ) {
            VStack(spacing: 8) {
                filterRow(symbol: "mic.fill",   tint: .purple, label: "Skip podcasts",      isOn: $settings.skipPodcasts)
                filterRow(symbol: "book.fill",  tint: .brown,  label: "Skip audiobooks",    isOn: $settings.skipAudiobooks)
                filterRow(symbol: "video.fill", tint: .indigo, label: "Skip music videos",  isOn: $settings.skipMusicVideos)
            }
        }
    }

    private func filterRow(symbol: String, tint: Color, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(isOn.wrappedValue ? 0.18 : 0.10))
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? tint : .secondary)
            }
            .frame(width: 22, height: 22)
            Text(label).font(.system(size: 12.5))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Ignore list

private struct IgnoreListCard: View {
    @ObservedObject private var rules = IgnoreRules.shared
    @State private var newPattern = ""
    @State private var newIsRegex = false
    @State private var newScope: IgnoreRules.Rule.Scope = .artist

    var body: some View {
        SettingsCard(
            title: "Ignored artists and tracks",
            footer: "Matches are case-insensitive. Regex uses NSRegularExpression syntax (the macOS default). Both Now Playing updates and queue submissions are suppressed for ignored items."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if rules.rules.isEmpty {
                    Text("No rules. Every track is scrobbled.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rules.rules.enumerated()), id: \.element.id) { i, rule in
                            if i > 0 { Divider().opacity(0.5) }
                            ruleRow(rule)
                        }
                    }
                }
                Divider().opacity(0.5)
                Text("Add a rule".uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                // Row 1: full-width pattern field. Row 2: scope picker +
                // regex toggle + add button. Two rows give the text field
                // room to breathe at narrow detail widths.
                TextField(newIsRegex ? "Regex pattern" : "Text to match (case-insensitive)", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: newIsRegex ? .monospaced : .default))
                    .onSubmit { addRule() }
                HStack(spacing: 10) {
                    Text("Match")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $newScope) {
                        Text("Artist").tag(IgnoreRules.Rule.Scope.artist)
                        Text("Track").tag(IgnoreRules.Rule.Scope.track)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Toggle("Regex", isOn: $newIsRegex)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    Spacer()
                    Button("Add rule") { addRule() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func ruleRow(_ rule: IgnoreRules.Rule) -> some View {
        HStack(spacing: 8) {
            Text(rule.scope == .artist ? "Artist" : "Track")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
            if rule.isRegex {
                Image(systemName: "asterisk")
                    .font(.system(size: 8))
                    .foregroundStyle(.indigo)
                    .help("Regex")
            }
            Text(rule.pattern)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                rules.remove(id: rule.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Remove rule")
        }
        .padding(.vertical, 5)
    }

    private func addRule() {
        let p = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        rules.add(pattern: p, isRegex: newIsRegex, scope: newScope)
        newPattern = ""
    }
}

// MARK: - Pause

private struct PauseCard: View {
    @ObservedObject private var settings = UserScrobbleSettings.shared

    var body: some View {
        SettingsCard(
            title: "Pause scrobbling",
            footer: settings.isPaused
              ? "Plays continue locally; nothing is sent to Last.fm until you resume."
              : "Temporarily stop sending scrobbles without quitting the app."
        ) {
            if settings.isPaused {
                pausedView
            } else {
                activeView
            }
        }
    }

    private var activeView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("Scrobbling active")
                    .font(.system(size: 12.5))
            }
            Spacer()
            Menu {
                Button("30 minutes") { settings.pauseFor(30 * 60) }
                Button("1 hour")     { settings.pauseFor(60 * 60) }
                Button("3 hours")    { settings.pauseFor(3 * 60 * 60) }
                Button("Until tomorrow") { settings.pauseFor(24 * 60 * 60) }
                Divider()
                Button("Indefinitely") { settings.pauseIndefinitely() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
                    Text("Pause").font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 4)
            }
            .menuStyle(.button)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var pausedView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.orange.opacity(0.18))
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Paused").font(.system(size: 13, weight: .semibold))
                Text(pausedSubtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                settings.resume()
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var pausedSubtitle: String {
        guard let until = settings.pauseUntil else { return "" }
        if until == .distantFuture { return "Until you resume manually" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return "Until \(f.string(from: until))"
    }
}

// MARK: - Notifications toggle

private struct NowPlayingToggleRow: View {
    @ObservedObject private var settings = UserScrobbleSettings.shared
    @State private var authorized: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                title: "Now Playing banner",
                subtitle: "Show a macOS notification when a new track starts"
            ) {
                Toggle("", isOn: $settings.showNowPlayingNotifications)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: settings.showNowPlayingNotifications) { _, new in
                        if new {
                            Task {
                                let ok = await NowPlayingNotifier.requestAuthorization()
                                await MainActor.run { authorized = ok }
                                if !ok {
                                    // System denied; un-toggle so the UI matches reality.
                                    await MainActor.run { settings.showNowPlayingNotifications = false }
                                }
                            }
                        }
                    }
            }
            if settings.showNowPlayingNotifications, authorized == false {
                permissionWarning
            }
        }
        .task { authorized = await NowPlayingNotifier.currentAuthorization() }
    }

    private var permissionWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("macOS denied notifications. Re-enable under System Settings → Notifications → Scrobblr.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(8)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Loved tracks

private struct LovedTracksCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var loved: [LastFMClient.LovedTrack] = []
    @State private var loading = false
    @State private var loaded = false

    var body: some View {
        SettingsCard(title: "Loved tracks") {
            VStack(alignment: .leading, spacing: 0) {
                if loved.isEmpty && loaded {
                    emptyView
                } else if loved.isEmpty && loading {
                    loadingView
                } else if loved.isEmpty {
                    placeholder
                } else {
                    ForEach(Array(loved.prefix(15).enumerated()), id: \.element.id) { i, t in
                        if i > 0 { Divider().opacity(0.5) }
                        row(t).padding(.vertical, 6)
                    }
                    if loved.count > 15 {
                        Divider().opacity(0.5)
                        moreLink
                    }
                }
            }
        }
        .task(id: coordinator.username) { await reload() }
    }

    private func row(_ t: LastFMClient.LovedTrack) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10))
                .foregroundStyle(.pink)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(t.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let url = t.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Click the heart in the menu bar to love the current track.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading from Last.fm…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No loved tracks yet.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var moreLink: some View {
        Link(destination: profileLovedURL) {
            HStack(spacing: 6) {
                Text("View all on Last.fm")
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.pink)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private var profileLovedURL: URL {
        let u = (coordinator.username ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://www.last.fm/user/\(u)/loved")
            ?? URL(string: "https://www.last.fm")!
    }

    private func reload() async {
        guard let username = coordinator.username else { return }
        loading = true
        defer { loading = false }
        let result = await coordinator.client.lovedTracks(username: username, limit: 25)
        await MainActor.run {
            self.loved = result
            self.loaded = true
        }
    }
}
