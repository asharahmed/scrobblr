import SwiftUI
import AppKit

/// Hero icon used at the top of every onboarding step. Subtle breathe +
/// gradient sheen. non-loop, just enough to suggest "alive" without
/// distracting.
private struct HeroIconView: View {
    let symbol: String
    let tint: Color

    @State private var breathe = false
    @State private var shimmerX: CGFloat = -1.2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: [tint, tint.opacity(0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                    // Diagonal shimmer that drifts across once on appear.
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.35), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: 60)
                    .rotationEffect(.degrees(20))
                    .offset(x: shimmerX * 90)
                    .blendMode(.plusLighter)
                    .mask(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .shadow(color: tint.opacity(0.35), radius: 18, x: 0, y: 6)
                .scaleEffect(breathe ? 1.02 : 1.0)
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(20)
                .symbolEffect(.pulse.byLayer, options: .repeating)
                .scaleEffect(breathe ? 1.03 : 1.0)
        }
        .frame(width: 88, height: 88)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 1.6).delay(0.2)) {
                shimmerX = 1.2
            }
        }
    }
}

/// The first-launch welcome window. Single source of truth for permission
/// requests. none of macOS's prompts fire until the user has clicked a
/// labelled button in here explaining what's about to happen.
struct WelcomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var model: OnboardingViewModel

    init(coordinator: AppCoordinator) {
        _model = StateObject(wrappedValue: OnboardingViewModel(coordinator: coordinator))
    }

    var body: some View {
        ZStack {
            // Subtle gradient background, layered over window material for depth.
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.clear, Color.accentColor.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 24)
                Rectangle()
                    .fill(.separator.opacity(0.5))
                    .frame(height: 0.5)
                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 560, height: 480)
        .background(WindowConfigurator(hideTitle: true))
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch model.step {
            case .welcome:     welcomeStep
            case .credentials: credentialsStep
            case .lastFM:      lastFMStep
            case .music:       musicStep
            case .finish:      finishStep
            }
        }
        .id(model.step)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.step)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            heroIcon(symbol: "waveform", tint: .pink)
            VStack(spacing: 8) {
                Text("Welcome to Scrobblr")
                    .font(.system(size: 26, weight: .bold))
                Text("Track what you listen to in Apple Music on Last.fm.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
            featureRow(icon: "music.note", text: "Scrobbles plays that pass Last.fm's 50% or 4-minute rule")
            featureRow(icon: "wifi.slash", text: "Queues offline and submits when you're back online")
            featureRow(icon: "lock.shield", text: "Talks only to Last.fm and Apple. No analytics.")
            Spacer(minLength: 0)
        }
    }

    // MARK: - Step 2: BYOK credentials

    @State private var apiKeyInput: String = ""
    @State private var sharedSecretInput: String = ""
    @State private var credsError: String? = nil

    private var credentialsStep: some View {
        VStack(spacing: 16) {
            heroIcon(symbol: "key.horizontal.fill", tint: .pink)
            VStack(spacing: 6) {
                Text("Add your Last.fm API key")
                    .font(.system(size: 22, weight: .bold))
                Text("Last.fm asks each app to register its own key. It's free and takes 30 seconds.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                Link(destination: URL(string: "https://www.last.fm/api/account/create")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open Last.fm API registration").font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)

                Text("Use any application name. Leave Callback URL and Homepage blank. Last.fm will show you a 32-character API Key and a 32-character Shared Secret.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("32 hex characters", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disableAutocorrection(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shared Secret").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    SecureField("32 hex characters", text: $sharedSecretInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                if let err = credsError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 11))
                        Text(err).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .onAppear {
            apiKeyInput = coordinator.credentials.apiKey ?? ""
            sharedSecretInput = coordinator.credentials.sharedSecret ?? ""
        }
    }

    /// Validate and store BYOK credentials, then advance.
    private func saveCredentialsAndAdvance() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = sharedSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count == 32, secret.count == 32 else {
            credsError = "Both values must be exactly 32 characters."
            return
        }
        guard key.allSatisfy({ $0.isHexDigit }), secret.allSatisfy({ $0.isHexDigit }) else {
            credsError = "API key and secret should be hexadecimal (a-f, 0-9)."
            return
        }
        do {
            try coordinator.setCredentials(apiKey: key, sharedSecret: secret)
            credsError = nil
            model.advance()
        } catch {
            credsError = "Couldn't save to Keychain: \(error.localizedDescription)"
        }
    }

    // MARK: - Step 3: Last.fm

    private var lastFMStep: some View {
        VStack(spacing: 18) {
            heroIcon(symbol: "person.circle.fill", tint: .pink)
            VStack(spacing: 8) {
                Text("Connect your Last.fm account")
                    .font(.system(size: 22, weight: .bold))
                Text(lastFMSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
            lastFMStatus
            Spacer(minLength: 0)
        }
    }

    private var lastFMSubtitle: String {
        if coordinator.isAuthenticated {
            return "Signed in as \(coordinator.username ?? "")."
        }
        switch coordinator.authPhase {
        case .awaitingApproval: return "Approve Scrobblr in the browser tab we just opened. We'll detect it automatically."
        case .fetchingToken, .completing: return "Talking to Last.fm…"
        case .idle: return "We'll open Last.fm in your browser. After you approve, Scrobblr will sign you in automatically."
        }
    }

    @ViewBuilder
    private var lastFMStatus: some View {
        if coordinator.isAuthenticated {
            statusCard(symbol: "checkmark.seal.fill", color: .green,
                       title: "Connected", subtitle: coordinator.username ?? "")
        } else if coordinator.authPhase == .awaitingApproval {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…").font(.callout).foregroundStyle(.secondary)
            }
        } else if let err = coordinator.authError {
            statusCard(symbol: "exclamationmark.triangle.fill", color: .orange,
                       title: "Sign-in didn't complete", subtitle: err)
        }
    }

    // MARK: - Step 3: Music

    private var musicStep: some View {
        VStack(spacing: 18) {
            heroIcon(symbol: "waveform.badge.magnifyingglass", tint: .pink)
            VStack(spacing: 8) {
                Text("Allow access to Music")
                    .font(.system(size: 22, weight: .bold))
                Text(musicSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
            musicStatus
            Spacer(minLength: 0)
        }
    }

    private var musicSubtitle: String {
        switch model.musicPermission {
        case .granted:
            return "Scrobblr can read what's playing."
        case .denied:
            return "Permission was previously denied. Open System Settings to re-enable."
        case .targetNotRunning, .notDetermined:
            return "Scrobblr reads the currently playing track from Music. macOS will ask permission once. Click Allow on the system prompt."
        }
    }

    @ViewBuilder
    private var musicStatus: some View {
        switch model.musicPermission {
        case .granted:
            statusCard(symbol: "checkmark.seal.fill", color: .green,
                       title: "Music access granted", subtitle: "You're all set.")
        case .denied:
            VStack(spacing: 12) {
                statusCard(symbol: "xmark.seal.fill", color: .orange,
                           title: "Permission denied", subtitle: "Open System Settings → Privacy & Security → Automation and enable Music for Scrobblr.")
                Button("Open System Settings") {
                    AutomationPermission.openSystemSettings()
                }
                .buttonStyle(.bordered)
            }
        case .targetNotRunning, .notDetermined:
            if model.musicProbeInFlight {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for system prompt…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Step 4: Finish

    private var finishStep: some View {
        VStack(spacing: 18) {
            heroIcon(symbol: "sparkles", tint: .pink)
            VStack(spacing: 8) {
                Text("You're all set")
                    .font(.system(size: 22, weight: .bold))
                Text("Scrobblr lives in your menu bar. Click the waveform icon to see what's playing.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                settingsRow {
                    Toggle(isOn: $model.launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch Scrobblr at login").font(.body)
                            Text("Recommended.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer (back / step indicator / action)

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(SoftIconButtonStyle())
            .opacity(model.step == .welcome ? 0 : 1)
            .disabled(model.step == .welcome)
            .help("Back")

            StepIndicator(
                count: OnboardingViewModel.Step.allCases.count,
                current: model.step.rawValue,
                onSelect: { i in
                    if let s = OnboardingViewModel.Step(rawValue: i) { model.step = s }
                }
            )
            Spacer()
            stepActions
        }
    }

    @ViewBuilder
    private var stepActions: some View {
        HStack(spacing: 10) {
            switch model.step {
            case .welcome:
                Button("Get started") { model.advance() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)

            case .credentials:
                Button("Save and continue") { saveCredentialsAndAdvance() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)

            case .lastFM:
                if coordinator.isAuthenticated {
                    Button("Continue") { model.advance() }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else if coordinator.authPhase == .awaitingApproval {
                    Button("Cancel") { coordinator.cancelAuth() }
                        .buttonStyle(LinkActionButtonStyle())
                    Button("Continue without signing in") { model.advance() }
                        .buttonStyle(SecondaryActionButtonStyle())
                } else {
                    Button("Skip") { model.advance() }
                        .buttonStyle(LinkActionButtonStyle())
                    Button("Sign in with Last.fm") {
                        Task { await coordinator.beginAuth() }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }

            case .music:
                switch model.musicPermission {
                case .granted:
                    Button("Continue") { model.advance() }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                case .denied:
                    Button("Skip for now") { model.advance() }
                        .buttonStyle(SecondaryActionButtonStyle())
                default:
                    Button("Skip") { model.advance() }
                        .buttonStyle(LinkActionButtonStyle())
                    Button("Grant access") {
                        Task { await model.requestMusicPermission() }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(model.musicProbeInFlight)
                    .keyboardShortcut(.defaultAction)
                }

            case .finish:
                Button("Done") { model.finish() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Reusable bits

    private func heroIcon(symbol: String, tint: Color) -> some View {
        HeroIconView(symbol: symbol, tint: tint)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
    }

    private func statusCard(symbol: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func settingsRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
    }
}
