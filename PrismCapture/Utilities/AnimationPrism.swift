import SwiftUI

extension Animation {
    static let prismSpring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let prismSoft = Animation.spring(response: 0.48, dampingFraction: 0.9)
    static let prismSnappy = Animation.spring(response: 0.28, dampingFraction: 0.78)
}

extension View {
    /// Glass chrome tuned to look like macOS Screenshot (gray light / dark material).
    func prismGlass(cornerRadius: CGFloat = 18) -> some View {
        modifier(PrismGlassModifier(cornerRadius: cornerRadius))
    }
}

private struct PrismGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillStyle)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: strokeColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 18, y: 8)
        }
    }

    private var fillStyle: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        // Light: gray Screenshot-like bar (not pure white glass).
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.82, green: 0.83, blue: 0.85).opacity(0.92),
                    Color(red: 0.74, green: 0.75, blue: 0.78).opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var strokeColors: [Color] {
        if colorScheme == .dark {
            return [.white.opacity(0.45), .white.opacity(0.08)]
        }
        return [
            Color.white.opacity(0.65),
            Color.black.opacity(0.08)
        ]
    }
}
