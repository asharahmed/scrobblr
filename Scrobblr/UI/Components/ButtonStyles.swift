import SwiftUI

/// Pill-shaped primary action button. Subtle gradient, scales-down + dims
/// when pressed, lifts on hover. Designed to read as "this is THE action".
struct PrimaryActionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay {
                        // Top highlight rim. subtle "pressed glass" feel.
                        Capsule(style: .continuous)
                            .stroke(LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .top, endPoint: .center
                            ), lineWidth: 1)
                    }
                    .shadow(color: Color.accentColor.opacity(hovering ? 0.45 : 0.25),
                            radius: hovering ? 10 : 6, x: 0, y: hovering ? 4 : 2)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.015 : 1.0))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Secondary muted pill. bordered translucent capsule. Use for skip / cancel.
struct SecondaryActionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(.quaternary.opacity(hovering ? 0.7 : 0.45))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.separator.opacity(0.6), lineWidth: 0.5)
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Plain-text "tertiary" link-style button. For skip-for-now-ish actions.
struct LinkActionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hovering ? Color.accentColor : .secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Icon-only button (in menu bar footer etc). Square padded, soft hover.
struct SoftIconButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .frame(width: 28, height: 22)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(hovering ? 0.55 : 0.0))
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
