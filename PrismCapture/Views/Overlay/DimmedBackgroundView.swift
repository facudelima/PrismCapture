import SwiftUI

struct DimmedBackgroundView: View {
    let selection: CGRect
    var windowHighlight: CGRect?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let full = Path(CGRect(origin: .zero, size: size))
            // macOS Screenshot–style veil: cool gray in light, deep dim in dark.
            let veil: Color = colorScheme == .dark
                ? Color.black.opacity(0.52)
                : Color(red: 0.55, green: 0.57, blue: 0.60).opacity(0.38)
            context.fill(full, with: .color(veil))

            if let windowHighlight, windowHighlight.width > 1 {
                context.blendMode = .destinationOut
                context.fill(Path(roundedRect: windowHighlight, cornerRadius: 6), with: .color(.white))
                context.blendMode = .normal
                context.stroke(
                    Path(roundedRect: windowHighlight, cornerRadius: 6),
                    with: .color(.white.opacity(0.9)),
                    lineWidth: 2
                )
            } else if selection.width > 1, selection.height > 1 {
                context.blendMode = .destinationOut
                context.fill(Path(selection), with: .color(.white))
                context.blendMode = .normal
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}
