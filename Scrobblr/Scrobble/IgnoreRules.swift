import Foundation
import Combine

/// User-configurable list of artist + track ignore rules.
///
/// Each entry is either an exact (case-insensitive) string match or a regex.
/// Rules persist as JSON in UserDefaults. the list is small (<100 entries
/// for any realistic user) so a database is overkill.
///
/// Two checks: `shouldIgnoreArtist(_:)` for the artist tag in isolation, and
/// `shouldIgnoreTrack(artist:title:)` for the artist+title pair. ScrobbleEngine
/// consults both at enqueue time AND before `track.updateNowPlaying` so
/// ignored tracks don't even surface as Now Playing.
@MainActor
final class IgnoreRules: ObservableObject {
    static let shared = IgnoreRules()
    private static let storageKey = "ignoreRules.v1"

    struct Rule: Codable, Identifiable, Hashable {
        var id: UUID = UUID()
        var pattern: String
        var isRegex: Bool
        var scope: Scope

        enum Scope: String, Codable, CaseIterable {
            case artist          // matches artist name
            case track           // matches "Artist | Title" combo
        }
    }

    @Published private(set) var rules: [Rule] = []

    init() {
        load()
    }

    // MARK: - Public matching API

    func shouldIgnoreArtist(_ artist: String) -> Bool {
        rules.contains { rule in
            guard rule.scope == .artist else { return false }
            return matches(rule, against: artist)
        }
    }

    func shouldIgnoreTrack(artist: String, title: String) -> Bool {
        if shouldIgnoreArtist(artist) { return true }
        let combined = "\(artist) | \(title)"
        return rules.contains { rule in
            guard rule.scope == .track else { return false }
            return matches(rule, against: combined)
        }
    }

    private func matches(_ rule: Rule, against value: String) -> Bool {
        if rule.isRegex {
            guard let re = try? NSRegularExpression(pattern: rule.pattern,
                                                    options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return re.firstMatch(in: value, options: [], range: range) != nil
        }
        return value.range(of: rule.pattern, options: [.caseInsensitive]) != nil
    }

    // MARK: - Mutation

    func add(pattern: String, isRegex: Bool, scope: Rule.Scope) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // De-duplicate by (pattern, isRegex, scope).
        guard !rules.contains(where: {
            $0.pattern == trimmed && $0.isRegex == isRegex && $0.scope == scope
        }) else { return }
        rules.append(Rule(pattern: trimmed, isRegex: isRegex, scope: scope))
        persist()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        rules.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Rule].self, from: data) else {
            return
        }
        self.rules = decoded
    }

    private func persist() {
        let data = (try? JSONEncoder().encode(rules)) ?? Data()
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
