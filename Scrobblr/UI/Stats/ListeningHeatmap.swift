import SwiftUI

/// GitHub-style listening heatmap.
///
/// Renders the last ~90 days as a grid of small rounded squares, colored by
/// scrobble count. Days with no plays are dim; busy days glow accent.
/// Hover shows the exact date + count via Tooltip.
struct ListeningHeatmap: View {
    let buckets: [Date: Int]
    let days: Int

    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = 3
    private let cal = Calendar.current

    var body: some View {
        let columns = orderedColumns
        let maxCount = max(1, buckets.values.max() ?? 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Day-of-week labels on the left.
                VStack(alignment: .trailing, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(weekdayLabel(i))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(height: cellSize)
                    }
                }
                .padding(.top, 14) // align below month labels

                // Grid of week columns, each containing up to 7 day cells.
                VStack(alignment: .leading, spacing: 4) {
                    monthLabels(for: columns)
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: spacing) {
                                ForEach(0..<7, id: \.self) { weekday in
                                    cell(for: dayInWeek(week, weekday: weekday), maxCount: maxCount)
                                }
                            }
                        }
                    }
                }
            }
            legend(maxCount: maxCount)
        }
    }

    // MARK: - Cells

    private func cell(for date: Date?, maxCount: Int) -> some View {
        let count = date.flatMap { buckets[cal.startOfDay(for: $0)] } ?? 0
        let level = intensityLevel(count: count, max: maxCount)
        let color = colorForLevel(level)
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: cellSize, height: cellSize)
            .help(date.map { tooltip(for: $0, count: count) } ?? "")
    }

    private func intensityLevel(count: Int, max: Int) -> Int {
        if count == 0 { return 0 }
        let ratio = Double(count) / Double(max)
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 0.75 { return 3 }
        return 4
    }

    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return Color.accentColor.opacity(0.25)
        case 2: return Color.accentColor.opacity(0.5)
        case 3: return Color.accentColor.opacity(0.75)
        default: return Color.accentColor
        }
    }

    private func tooltip(for date: Date, count: Int) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return count == 0
            ? "\(f.string(from: date)): no scrobbles"
            : "\(f.string(from: date)): \(count) scrobble\(count == 1 ? "" : "s")"
    }

    // MARK: - Grid math

    /// One week per column. Returns an array where each element is the
    /// Date of the Sunday (or week start in current locale) of that column.
    private var orderedColumns: [Date] {
        let now = Date()
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weeksBack = (days + 6) / 7
        return (0..<weeksBack).reversed().compactMap { wb in
            cal.date(byAdding: .weekOfYear, value: -wb, to: weekStart)
        }
    }

    private func dayInWeek(_ weekStart: Date, weekday: Int) -> Date? {
        guard let d = cal.date(byAdding: .day, value: weekday, to: weekStart) else { return nil }
        // Don't render future days.
        return d <= Date() ? d : nil
    }

    private func weekdayLabel(_ index: Int) -> String {
        // Show only Mon, Wed, Fri to avoid clutter.
        switch index {
        case 1: return "M"
        case 3: return "W"
        case 5: return "F"
        default: return ""
        }
    }

    private func monthLabels(for columns: [Date]) -> some View {
        // Mark the column where the month changes vs the previous column.
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                let monthSymbol: String? = {
                    guard i == 0 || cal.component(.month, from: col) != cal.component(.month, from: columns[i - 1])
                    else { return nil }
                    let f = DateFormatter()
                    f.dateFormat = "MMM"
                    return f.string(from: col)
                }()
                Text(monthSymbol ?? "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: cellSize, alignment: .leading)
            }
        }
        .frame(height: 10)
    }

    private func legend(maxCount: Int) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(colorForLevel(level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}
