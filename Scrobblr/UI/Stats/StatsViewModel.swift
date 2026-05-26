import Foundation
import Combine

/// Stats window data fetcher + cache.
///
/// One instance per Stats window; holds the currently selected period and
/// the four data slices (tracks, artists, albums, heatmap). Refetches when
/// the period changes; otherwise caches per-period.
@MainActor
final class StatsViewModel: ObservableObject {
    @Published var period: LastFMPeriod = .oneMonth {
        didSet {
            guard period != oldValue else { return }
            Task { await reload() }
        }
    }

    @Published private(set) var topTracks: [TopTrack] = []
    @Published private(set) var topArtists: [TopArtist] = []
    @Published private(set) var topAlbums: [TopAlbum] = []
    @Published private(set) var heatmap: [Date: Int] = [:]
    @Published private(set) var loading: Bool = false
    @Published private(set) var error: String? = nil

    private let coordinator: AppCoordinator
    private var cacheTracks: [LastFMPeriod: [TopTrack]] = [:]
    private var cacheArtists: [LastFMPeriod: [TopArtist]] = [:]
    private var cacheAlbums: [LastFMPeriod: [TopAlbum]] = [:]

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func loadIfNeeded() async {
        if !topTracks.isEmpty { return }
        await reload()
    }

    func reload() async {
        guard let username = coordinator.username else {
            error = "Sign in to view stats."
            return
        }
        loading = true
        defer { loading = false }
        error = nil

        let p = period
        if let cached = cacheTracks[p],
           let cAr = cacheArtists[p],
           let cAl = cacheAlbums[p] {
            topTracks = cached
            topArtists = cAr
            topAlbums = cAl
            // Heatmap is period-independent (always last 90 days).
            if heatmap.isEmpty { await reloadHeatmap(username: username) }
            return
        }

        async let tracksTask = coordinator.client.topTracks(username: username, period: p, limit: 50)
        async let artistsTask = coordinator.client.topArtists(username: username, period: p, limit: 50)
        async let albumsTask = coordinator.client.topAlbums(username: username, period: p, limit: 50)

        let (tracks, artists, albums) = await (tracksTask, artistsTask, albumsTask)
        cacheTracks[p] = tracks
        cacheArtists[p] = artists
        cacheAlbums[p] = albums
        topTracks = tracks
        topArtists = artists
        topAlbums = albums

        if heatmap.isEmpty { await reloadHeatmap(username: username) }
    }

    /// Aggregate the last ~90 days into day buckets for the heatmap.
    private func reloadHeatmap(username: String) async {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let scrobbles = await coordinator.client.recentScrobbles(username: username, since: since, pages: 8)
        var buckets: [Date: Int] = [:]
        let cal = Calendar.current
        for s in scrobbles {
            let day = cal.startOfDay(for: s.playedAt)
            buckets[day, default: 0] += 1
        }
        heatmap = buckets
    }

    // MARK: - Computed totals

    var totalPlaysInPeriod: Int {
        topTracks.reduce(0) { $0 + $1.playCount }
    }
    var uniqueArtists: Int { topArtists.count }
    var uniqueAlbums: Int { topAlbums.count }
}
