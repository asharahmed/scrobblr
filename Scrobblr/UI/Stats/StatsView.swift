import SwiftUI

/// Stats window. NavigationSplitView with section sidebar; toolbar carries
/// the period selector. Three list-style sections (Tracks, Artists, Albums)
/// plus a heatmap.
struct StatsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var model: StatsViewModel

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case overview, tracks, artists, albums, calendar
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: "Overview"
            case .tracks:   "Top Tracks"
            case .artists:  "Top Artists"
            case .albums:   "Top Albums"
            case .calendar: "Listening Calendar"
            }
        }
        var icon: String {
            switch self {
            case .overview: "chart.bar.fill"
            case .tracks:   "music.note"
            case .artists:  "person.2.fill"
            case .albums:   "square.stack.fill"
            case .calendar: "calendar"
            }
        }
        var tint: Color {
            switch self {
            case .overview: .pink
            case .tracks:   .indigo
            case .artists:  .orange
            case .albums:   .teal
            case .calendar: .green
            }
        }
    }

    @State private var selection: Section? = .overview

    init(coordinator: AppCoordinator) {
        _model = StateObject(wrappedValue: StatsViewModel(coordinator: coordinator))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 230)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 540, ideal: 640)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 580)
        .toolbar {
            ToolbarItem(placement: .principal) {
                periodPicker
            }
            ToolbarItem(placement: .primaryAction) {
                refreshButton
            }
        }
        .task { await model.loadIfNeeded() }
    }

    private var sidebar: some View {
        List(Section.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label {
                    Text(section.label).font(.system(size: 13))
                        .padding(.leading, 2)
                } icon: {
                    sectionIcon(section)
                }
            }
            .padding(.vertical, 1)
        }
        .listStyle(.sidebar)
    }

    private func sectionIcon(_ s: Section) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [s.tint, s.tint.opacity(0.7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: s.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let username = coordinator.username {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        detailHeader(username: username)
                        switch selection ?? .overview {
                        case .overview: OverviewView()
                        case .tracks:   TopTracksView()
                        case .artists:  TopArtistsView()
                        case .albums:   TopAlbumsView()
                        case .calendar: CalendarSectionView()
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                notSignedIn
            }
        }
        .environmentObject(model)
        .background(.windowBackground)
    }

    private var notSignedIn: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Sign in to view stats")
                .font(.system(size: 14, weight: .semibold))
            Text("Open Settings → Account to sign in to Last.fm.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailHeader(username: String) -> some View {
        let s = selection ?? .overview
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [s.tint, s.tint.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: s.tint.opacity(0.25), radius: 4, y: 1)
                Image(systemName: s.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.label)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                Text(periodSubtitle(username: username))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.loading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func periodSubtitle(username: String) -> String {
        let period = model.period.label
        return "\(username) · \(period)"
    }

    private var periodPicker: some View {
        Picker("Period", selection: $model.period) {
            ForEach(LastFMPeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 480)
    }

    private var refreshButton: some View {
        Button {
            Task { await model.reload() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: model.loading)
        }
        .disabled(model.loading)
        .help("Refresh from Last.fm")
    }
}

// MARK: - Overview

private struct OverviewView: View {
    @EnvironmentObject var model: StatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroTiles
            twoColumn
        }
    }

    private var heroTiles: some View {
        HStack(spacing: 14) {
            tile(label: "Plays", value: model.totalPlaysInPeriod, tint: .pink)
            tile(label: "Artists", value: model.uniqueArtists, tint: .orange)
            tile(label: "Albums", value: model.uniqueAlbums, tint: .teal)
            tile(label: "Tracks", value: model.topTracks.count, tint: .indigo)
        }
    }

    private func tile(label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(formatted(value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var twoColumn: some View {
        HStack(alignment: .top, spacing: 14) {
            statsListColumn(title: "Top Artists", items: model.topArtists.prefix(10).map {
                ListItem(rank: $0.rank, primary: $0.name, secondary: nil, count: $0.playCount, url: $0.url)
            })
            statsListColumn(title: "Top Tracks", items: model.topTracks.prefix(10).map {
                ListItem(rank: $0.rank, primary: $0.title, secondary: $0.artist, count: $0.playCount, url: $0.url)
            })
        }
    }

    private func statsListColumn(title: String, items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().opacity(0.5) }
                    rankedRow(item).padding(.vertical, 6)
                }
                if items.isEmpty { emptyHint }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var emptyHint: some View {
        Text("Nothing for this period yet.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private func rankedRow(_ item: ListItem) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", item.rank))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.primary).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let s = item.secondary {
                    Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(item.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if let url = item.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private struct ListItem: Identifiable {
        let id = UUID()
        let rank: Int
        let primary: String
        let secondary: String?
        let count: Int
        let url: URL?
    }
}

// MARK: - Top Tracks

private struct TopTracksView: View {
    @EnvironmentObject var model: StatsViewModel

    var body: some View {
        rankedList(items: model.topTracks.map {
            (id: $0.id, rank: $0.rank, primary: $0.title, secondary: $0.artist,
             count: $0.playCount, url: $0.url)
        }, emptyText: "No tracks for this period.")
    }
}

// MARK: - Top Artists

private struct TopArtistsView: View {
    @EnvironmentObject var model: StatsViewModel

    var body: some View {
        rankedList(items: model.topArtists.map {
            (id: $0.id, rank: $0.rank, primary: $0.name, secondary: nil,
             count: $0.playCount, url: $0.url)
        }, emptyText: "No artists for this period.")
    }
}

// MARK: - Top Albums

private struct TopAlbumsView: View {
    @EnvironmentObject var model: StatsViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14, alignment: .top)
    ]

    var body: some View {
        if model.topAlbums.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.topAlbums) { album in
                    AlbumTile(album: album)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No albums for this period.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// Album cover tile with cover image, title, artist, and play count.
/// Falls back to iTunes Search via ArtworkFetcher when Last.fm has no
/// image (or returns the documented "no artwork" placeholder).
private struct AlbumTile: View {
    let album: TopAlbum
    @State private var imageData: Data? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(hovering ? 0.45 : 0.30),
                        radius: hovering ? 10 : 6, x: 0, y: hovering ? 4 : 2)
                .scaleEffect(hovering ? 1.02 : 1.0)
                .animation(.spring(response: 0.32, dampingFraction: 0.75), value: hovering)
                .onHover { hovering = $0 }
                .overlay(alignment: .topLeading) {
                    rankBadge
                }
                .overlay(alignment: .bottomTrailing) {
                    playCountBadge
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(album.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = album.url { NSWorkspace.shared.open(url) }
        }
        .help(album.url?.absoluteString ?? "")
        .task { await loadCover() }
    }

    @ViewBuilder
    private var cover: some View {
        ZStack {
            // Identity-derived placeholder, same approach as the menu bar
            // artwork. Always visually present even before the cover loads.
            placeholderGradient
                .overlay {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            if let data = imageData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
    }

    private var placeholderGradient: some View {
        // Hash the album's identity-equivalent string for stable color.
        let key = "\(album.artist.lowercased())|\(album.title.lowercased())"
        var h: UInt64 = 5381
        for b in key.utf8 { h = ((h << 5) &+ h) &+ UInt64(b) }
        let hue = Double(h % 1000) / 1000.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.7, brightness: 0.75),
                Color(hue: hue, saturation: 0.55, brightness: 0.5)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var rankBadge: some View {
        Text(String(format: "%02d", album.rank))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(7)
    }

    private var playCountBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill").font(.system(size: 8, weight: .bold))
            Text("\(album.playCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(7)
    }

    private func loadCover() async {
        if let url = album.imageURL,
           // Skip Last.fm's "no artwork" placeholder fingerprint.
           !url.absoluteString.contains("2a96cbd8b46e442fc41c2b86b821562f") {
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                await MainActor.run { withAnimation { imageData = data } }
                return
            }
        }
        // Fallback: ArtworkFetcher (iTunes Search + Last.fm chain).
        let identity = "album:\(album.artist.lowercased())|\(album.title.lowercased())"
        let data = await ArtworkFetcher.shared.fetch(
            identity: identity, artist: album.artist, title: album.title
        )
        if let data {
            await MainActor.run { withAnimation { imageData = data } }
        }
    }
}

private struct ListRowTuple {
    let id: UUID
    let rank: Int
    let primary: String
    let secondary: String?
    let count: Int
    let url: URL?
}

private func rankedList(items: [(id: UUID, rank: Int, primary: String, secondary: String?, count: Int, url: URL?)],
                        emptyText: String) -> some View {
    Group {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            let maxCount = Double(items.first?.count ?? 1)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().opacity(0.5) }
                    rankedListRow(item: item, maxCount: maxCount).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private func rankedListRow(item: (id: UUID, rank: Int, primary: String, secondary: String?, count: Int, url: URL?),
                           maxCount: Double) -> some View {
    HStack(spacing: 12) {
        Text(String(format: "%02d", item.rank))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 28, alignment: .trailing)
        VStack(alignment: .leading, spacing: 1) {
            Text(item.primary).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if let s = item.secondary {
                Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        Spacer(minLength: 16)
        // Inline mini-bar proportional to the top item's count, plus the
        // numeric play count to the right.
        HStack(spacing: 8) {
            Capsule()
                .fill(.tint.opacity(0.25))
                .frame(width: 80 * (Double(item.count) / maxCount), height: 5)
                .frame(width: 80, alignment: .leading)
            Text("\(item.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
                .monospacedDigit()
        }
        if let url = item.url {
            Link(destination: url) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Calendar

private struct CalendarSectionView: View {
    @EnvironmentObject var model: StatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Last 90 days")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 12) {
                ListeningHeatmap(buckets: model.heatmap, days: 90)
                summary
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var summary: some View {
        let total = model.heatmap.values.reduce(0, +)
        let active = model.heatmap.values.filter { $0 > 0 }.count
        let best = model.heatmap.max(by: { $0.value < $1.value })
        let busiestText: String? = {
            guard let best, best.value > 0 else { return nil }
            let f = DateFormatter()
            f.dateStyle = .medium
            return "\(f.string(from: best.key)) (\(best.value))"
        }()
        return HStack(spacing: 24) {
            stat("Plays", "\(total)")
            stat("Days active", "\(active)")
            if let busiestText {
                stat("Busiest", busiestText)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}
