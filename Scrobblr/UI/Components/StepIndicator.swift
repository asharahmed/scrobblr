import SwiftUI

/// Custom multi-step indicator: filled dots for completed steps, current step
/// gets an accent capsule, future steps are muted. Tappable to jump back.
struct StepIndicator: View {
    let count: Int
    let current: Int
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(fill(for: i))
                    .frame(width: i == current ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: current)
                    .onTapGesture {
                        guard let onSelect, i < current else { return }
                        onSelect(i)
                    }
            }
        }
    }

    private func fill(for i: Int) -> some ShapeStyle {
        if i == current { return AnyShapeStyle(Color.accentColor) }
        if i < current { return AnyShapeStyle(Color.accentColor.opacity(0.45)) }
        return AnyShapeStyle(Color.secondary.opacity(0.3))
    }
}
