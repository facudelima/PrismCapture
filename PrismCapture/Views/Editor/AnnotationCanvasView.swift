import SwiftUI

struct AnnotationCanvasView: View {
    @ObservedObject var viewModel: AnnotationViewModel

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedImageRect(in: geo.size)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(0.18))

                Image(nsImage: viewModel.image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
                    .frame(width: fitted.width, height: fitted.height)
                    .overlay {
                        Canvas { context, _ in
                            for annotation in viewModel.annotations {
                                draw(annotation, in: &context)
                            }
                            if let draft = viewModel.draft {
                                draw(draft, in: &context)
                            }
                            if let crop = viewModel.cropRect {
                                context.stroke(
                                    Path(roundedRect: crop, cornerRadius: 2),
                                    with: .color(.white),
                                    lineWidth: 1.5
                                )
                            }
                        }
                        .gesture(drawGesture(in: fitted))
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .frame(minHeight: 240)
    }

    private func fittedImageRect(in size: CGSize) -> CGRect {
        let imageSize = viewModel.image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func drawGesture(in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = map(value.location, in: fitted)
                if viewModel.draft == nil && viewModel.cropRect == nil
                    && ![.text, .emoji, .marker].contains(viewModel.selectedTool) {
                    viewModel.beginStroke(at: point)
                } else if [.text, .emoji, .marker].contains(viewModel.selectedTool) {
                    // handled on ended as tap
                } else {
                    viewModel.continueStroke(to: point)
                }
            }
            .onEnded { value in
                let point = map(value.location, in: fitted)
                if [.text, .emoji, .marker].contains(viewModel.selectedTool) {
                    viewModel.beginStroke(at: point)
                    return
                }
                viewModel.endStroke()
            }
    }

    private func map(_ location: CGPoint, in fitted: CGRect) -> CGPoint {
        // Location is relative to the overlay (image frame).
        let imageSize = viewModel.image.size
        let scaleX = imageSize.width / max(fitted.width, 1)
        let scaleY = imageSize.height / max(fitted.height, 1)
        return CGPoint(x: location.x * scaleX, y: location.y * scaleY)
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext) {
        let color = annotation.color
        switch annotation.tool {
        case .rectangle:
            context.stroke(Path(roundedRect: annotation.rect, cornerRadius: 2), with: .color(color), lineWidth: annotation.lineWidth)
        case .circle:
            context.stroke(Path(ellipseIn: annotation.rect), with: .color(color), lineWidth: annotation.lineWidth)
        case .line:
            guard annotation.points.count >= 2 else { return }
            var path = Path()
            path.move(to: annotation.points[0])
            path.addLine(to: annotation.points[1])
            context.stroke(path, with: .color(color), lineWidth: annotation.lineWidth)
        case .arrow:
            guard annotation.points.count >= 2 else { return }
            drawArrow(from: annotation.points[0], to: annotation.points[1], color: color, width: annotation.lineWidth, in: &context)
        case .pencil, .highlighter:
            guard let first = annotation.points.first else { return }
            var path = Path()
            path.move(to: first)
            for p in annotation.points.dropFirst() { path.addLine(to: p) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round))
        case .blur, .pixelate:
            context.fill(Path(annotation.rect), with: .color(.black.opacity(0.25)))
            context.stroke(Path(annotation.rect), with: .color(color.opacity(0.6)), lineWidth: 1)
        case .text:
            if let p = annotation.points.first {
                context.draw(
                    Text(annotation.text).font(.system(size: 18, weight: .medium)).foregroundStyle(color),
                    at: p,
                    anchor: .topLeading
                )
            }
        case .marker:
            if let p = annotation.points.first {
                let r: CGFloat = 14
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
                context.draw(
                    Text("\(annotation.markerNumber)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white),
                    at: p,
                    anchor: .center
                )
            }
        case .emoji:
            if let p = annotation.points.first {
                context.draw(Text(annotation.emoji).font(.system(size: 28)), at: p, anchor: .topLeading)
            }
        case .select, .crop:
            break
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: Color, width: CGFloat, in context: inout GraphicsContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(16, width * 4.0)
        let headWidth = max(12, width * 3.2)
        let clampedHead = min(headLength, length * 0.45)
        let shaftEnd = CGPoint(
            x: end.x - clampedHead * cos(angle),
            y: end.y - clampedHead * sin(angle)
        )

        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: shaftEnd)
        context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))

        let perpX = -sin(angle)
        let perpY = cos(angle)
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: shaftEnd.x + (headWidth / 2) * perpX, y: shaftEnd.y + (headWidth / 2) * perpY))
        head.addLine(to: CGPoint(x: shaftEnd.x - (headWidth / 2) * perpX, y: shaftEnd.y - (headWidth / 2) * perpY))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}
