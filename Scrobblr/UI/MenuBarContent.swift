import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            divider
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(height: 0.5)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13, weight: .semibold))
            Text("Scrobblr")
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.1)
            Spacer()
            if let u = coordinator.username {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                    Text(u)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: Capsule(style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Content area (varies by state)

    @ViewBuilder
    private var content: some View {
        if !coordinator.isAuthenticated {
            signInPrompt
        } else if let track = coordinator.observer.snapshot.track {
            nowPlayingCard(track: track)
        } else {
            idleState
        }
    }

    // MARK: - Now Playing

    @ViewBuilder
    private func nowPlayingCard(track: Track) -> some View {
        let snap = coordinator.observer.snapshot
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                artworkView(for: track)
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        HStack(alignment: .top, spacing: 6) {
                            Text(track.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .tracking(-0.1)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            loveButton(for: track)
                        }
                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let album = track.album {
                            Text(album)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .id(track.identity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    Spacer(minLength: 2)
                    originBadge(track.origin, state: snap.state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: track.identity)
            if let dur = track.durationSeconds, dur > 0 {
                ScrubBar(position: snap.position ?? 0, duration: dur)
                    .animation(.linear(duration: 0.25), value: snap.position ?? 0)
            }
        }
    }

    @ViewBuilder
    private func artworkView(for track: Track) -> some View {
        Group {
            if let img = coordinator.observer.artwork {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [.gray.opacity(0.28), .gray.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 24))
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        .id(track.identity)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.7).combined(with: .opacity),
                removal: .scale(scale: 1.05).combined(with: .opacity)
            )
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: track.identity)
    }

    private func loveButton(for track: Track) -> some View {
        let isLoved = coordinator.engine.lovedIdentity == track.identity
        return Button {
            coordinator.engine.loveCurrent()
        } label: {
            Image(systemName: isLoved ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isLoved ? .pink : .secondary)
                .symbolEffect(.bounce, value: isLoved)
                .contentShape(Rectangle())
                .padding(.top, 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoved || !coordinator.isAuthenticated)
        .help(isLoved ? "Loved on Last.fm" : "Love on Last.fm")
    }

    private func originBadge(_ origin: Track.Origin, state: PlayerState) -> some View {
        let (icon, label, color): (String, String, Color) = switch (state, origin) {
        case (.paused, _):                     ("pause.fill",                          "Paused",                  .secondary)
        case (.stopped, _):                    ("stop.fill",                           "Stopped",                 .secondary)
        case (.playing, .localFile):           ("internaldrive",                       "Library",                 .green)
        case (.playing, .appleMusicCatalog):   ("applelogo",                           "Apple Music",             .pink)
        case (.playing, .stream):              ("antenna.radiowaves.left.and.right",   "Stream",                  .orange)
        case (.playing, .podcast):             ("mic.fill",                            "Podcast",                 .purple)
        case (.playing, .audiobook):           ("book.fill",                           "Audiobook",               .brown)
        case (.playing, .musicVideo):          ("video.fill",                          "Music Video",             .indigo)
        case (.playing, .unknown):             ("music.note",                          "Playing",                 .secondary)
        }
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(label).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule(style: .continuous))
    }

    // MARK: - Empty states

    private var signInPrompt: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12))
                Image(systemName: "music.note.list")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 52, height: 52)
            VStack(spacing: 4) {
                Text("Connect Last.fm")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Sign in to start scrobbling.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button("Sign in") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var idleState: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating)
            Text("Nothing playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Start a song in Apple Music")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coordinator.isAuthenticated {
                statusRow
            }
            HStack(spacing: 2) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(SoftIconButtonStyle())
                .help("Open Settings")

                if coordinator.isAuthenticated, let u = coordinator.username {
                    Button {
                        if let escaped = u.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                           let url = URL(string: "https://www.last.fm/user/\(escaped)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .buttonStyle(SoftIconButtonStyle())
                    .help("View profile on Last.fm")
                }

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    coordinator.showWelcome()
                } label: {
                    Image(systemName: "hand.wave")
                }
                .buttonStyle(SoftIconButtonStyle())
                .help("Show welcome / re-run setup")

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(LinkActionButtonStyle())
                    .keyboardShortcut("q")
                    .help("Quit Scrobblr (⌘Q)")
            }
            .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        Group {
            if UserScrobbleSettings.shared.isPaused {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Scrobbling paused")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Resume") { UserScrobbleSettings.shared.resume() }
                        .buttonStyle(LinkActionButtonStyle())
                        .font(.system(size: 10))
                }
            } else if coordinator.engine.needsReauth {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Re-authentication needed")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Re-sign-in") {
                        Task { await coordinator.beginAuth() }
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                    .buttonStyle(LinkActionButtonStyle())
                    .font(.system(size: 10))
                }
            } else if let err = coordinator.engine.lastError {
                statusLine(icon: "exclamationmark.circle", color: .red, text: err)
            } else if coordinator.engine.isFlushing {
                statusLine(
                    icon: "arrow.triangle.2.circlepath",
                    color: .accentColor,
                    text: "Submitting…",
                    spinning: true
                )
            } else if let last = coordinator.engine.lastScrobbled {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: last)
                    Text("Scrobbled \(last.title) · \(relativeTime(last.uploadedAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .id(last)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: last)
            } else if coordinator.engine.queueCount > 0 {
                statusLine(
                    icon: "tray.full",
                    color: .secondary,
                    text: "\(coordinator.engine.queueCount) waiting"
                )
            } else {
                statusLine(icon: "checkmark.seal", color: .secondary, text: "Connected")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func statusLine(icon: String, color: Color, text: String, spinning: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: spinning)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func relativeTime(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        return "\(Int(s/86400))d ago"
    }
}

// MARK: - ScrubBar

/// Polished progress bar. hover reveals exact elapsed/remaining time,
/// thicker than the default ProgressView, custom gradient fill.
private struct ScrubBar: View {
    let position: Double
    let duration: Double
    @State private var hovering = false

    var body: some View {
        let clamped = max(0, min(position, duration))
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: hovering ? 5 : 3)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * clamped / duration,
                               height: hovering ? 5 : 3)
                        .shadow(color: Color.accentColor.opacity(hovering ? 0.4 : 0),
                                radius: 3, x: 0, y: 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
            HStack {
                Text(timeString(clamped))
                Spacer()
                Text("−" + timeString(duration - clamped))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(hovering ? .primary : .secondary)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }

    private func timeString(_ s: Double) -> String {
        let total = max(0, Int(s))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
