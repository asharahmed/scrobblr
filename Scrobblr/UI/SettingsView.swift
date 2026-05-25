import SwiftUI
import AppKit

/// Settings window — replaces the old 3-tab layout with a NavigationSplitView
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
                        .font(.system(size: 12.5))
                } icon: {
                    sidebarIcon(section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarIcon(_ section: Section) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(
                    colors: [section.tint, section.tint.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Image(systemName: section.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
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
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.18), value: selection)
        .background(.windowBackground)
    }

    private var detailHeader: some View {
        let section = selection ?? .account
        return HStack(spacing: 12) {
            sidebarIcon(section)
                .scaleEffect(1.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(section.label)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.25)
                Text(subtitleFor(section))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func subtitleFor(_ s: Section) -> String {
        switch s {
        case .account:  "Manage your Last.fm connection"
        case .playback: "How Scrobblr reads from Music.app"
        case .general:  "App behaviour and startup"
        case .activity: "Recent scrobbles and pending queue"
        case .about:    "Credits, version, and links"
        }
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
                HStack(spacing: 12) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in").font(.system(size: 13, weight: .semibold))
                        Text(coordinator.username ?? "—")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                HStack {
                    Link(destination: profileURL) {
                        Label("View profile", systemImage: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    Link(destination: URL(string: "https://www.last.fm/settings/applications")!) {
                        Label("Manage authorizations", systemImage: "lock.shield")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Sign out", role: .destructive) {
                        coordinator.signOut()
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
            Text(String((coordinator.username?.first ?? "?")).uppercased())
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
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
                    Text("Approve Scrobblr in your browser — we'll sign you in automatically.")
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
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for approval").font(.system(size: 13, weight: .semibold))
                Text("Once you approve in the browser, Scrobblr will detect it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { coordinator.cancelAuth() }
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
            footer: "Scrobblr talks to Last.fm using YOUR API key. Register one at last.fm/api/account/create — it's free and keeps your scrobbling working even if a shared key gets revoked."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if credentials.isConfigured && !editing {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Configured").font(.system(size: 13, weight: .semibold))
                            Text("Key ending …\(String(credentials.apiKey?.suffix(4) ?? "").lowercased())")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Replace…") { startEdit() }
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

            SettingsCard(title: "Scrobble rules") {
                VStack(alignment: .leading, spacing: 8) {
                    bulletRow(text: "Submit when played ≥ 50% of the track, or ≥ 4 minutes")
                    bulletRow(text: "Tracks shorter than 30 seconds are never scrobbled")
                    bulletRow(text: "Apple Music Radio and other streams are excluded")
                    bulletRow(text: "Plays under 5 seconds are debounced as skips")
                }
            }
        }
        .onAppear { refresh() }
    }

    private var statusBlock: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.system(size: 13, weight: .semibold))
                Text(statusDetail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusIcon: some View {
        let (sym, color): (String, Color) = switch probeStatus {
        case .granted:          ("checkmark.seal.fill", .green)
        case .denied:           ("xmark.seal.fill",     .orange)
        case .notDetermined:    ("questionmark.circle", .secondary)
        case .targetNotRunning: ("circle.dashed",       .secondary)
        }
        return Image(systemName: sym).font(.system(size: 22)).foregroundStyle(color)
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
        case .notDetermined:    "Click Grant access — macOS will show a permission prompt."
        case .targetNotRunning: "Launch Apple Music and click Recheck."
        }
    }

    private func bulletRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.indigo)
                .frame(width: 12, alignment: .leading)
                .padding(.top, 3)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                footer: "Scrobblr runs entirely in the menu bar — it has no Dock icon. Closing the welcome window doesn't quit the app."
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

            SettingsCard(title: "Updates", footer: "Scrobblr checks for new versions via Sparkle. Update signatures are verified with EdDSA — only releases signed by the official key are installed.") {
                SettingsRow(title: "Software updates", subtitle: "Check for and install new versions") {
                    Button("Check now…") { Updater.shared.checkForUpdates() }
                        .buttonStyle(.bordered)
                        .disabled(!Updater.shared.canCheckForUpdates)
                }
            }

            SettingsCard(title: "Welcome", footer: "Run the first-time setup flow again — useful for granting permissions you previously skipped.") {
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
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if case .failed = state {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            Button {
                Task { await run() }
            } label: {
                if state == .exporting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Export…").font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .disabled(state == .exporting)
        }
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
            queueCard
            recentCard
        }
        .task(id: coordinator.engine.recentScrobbles.count) {
            await refreshStats()
        }
    }

    private var statsCard: some View {
        SettingsCard(title: "Last.fm totals") {
            HStack(spacing: 18) {
                statTile(value: todayCount, label: "Today")
                Rectangle().fill(.separator.opacity(0.5)).frame(width: 0.5, height: 28)
                statTile(value: weekCount, label: "Last 7 days")
                Spacer()
                Button {
                    Task { await refreshStats(force: true) }
                } label: {
                    Image(systemName: statsLoading ? "ellipsis.circle" : "arrow.clockwise")
                        .font(.system(size: 12))
                        .symbolEffect(.variableColor, isActive: statsLoading)
                }
                .buttonStyle(.borderless)
                .disabled(statsLoading)
                .help("Refresh from Last.fm")
            }
        }
    }

    private func statTile(value: Int?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map(formatted) ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.4)
        }
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

    private var queueCard: some View {
        SettingsCard(
            title: "Submission queue",
            footer: "Pending scrobbles are held locally and submitted in batches. Offline plays catch up automatically when you reconnect."
        ) {
            VStack(spacing: 12) {
                SettingsRow(
                    title: "\(coordinator.engine.queueCount) pending",
                    subtitle: coordinator.engine.isFlushing ? "Submitting now…" : "Idle"
                ) {
                    if coordinator.engine.isFlushing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: coordinator.engine.queueCount == 0 ? "checkmark.circle.fill" : "tray.full")
                            .foregroundStyle(coordinator.engine.queueCount == 0 ? .green : .secondary)
                    }
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
                    Text("Play something in Apple Music — scrobbles past Last.fm's threshold appear here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(coordinator.engine.recentScrobbles.enumerated()), id: \.offset) { i, s in
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
                    bullet("No background telemetry — talks only to Last.fm and Apple")
                }
            }
            SettingsCard(title: "Privacy") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scrobblr doesn't run a server and the author doesn't receive your data. It talks to Last.fm to submit plays and to Apple's anonymous iTunes Search API for album art — that's the entire outbound network surface.")
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

            Text("Last.fm is a registered trademark of CBS Interactive Inc. Apple Music is a trademark of Apple Inc. Scrobblr is not affiliated with, endorsed by, or sponsored by Last.fm or Apple.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.top, 4)
            Text("Made with care on macOS.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
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
