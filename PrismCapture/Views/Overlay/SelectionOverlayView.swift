import SwiftUI
import AppKit

struct SelectionOverlayView: View {
    @ObservedObject var viewModel: CaptureViewModel
    /// Top-left of this screen inside the global multi-monitor overlay space.
    var screenOriginInOverlay: CGPoint = .zero
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let localSelection = viewModel.selectionRect.offsetBy(
                dx: -screenOriginInOverlay.x,
                dy: -screenOriginInOverlay.y
            )
            let toolbarGlobal = viewModel.toolbarCenter(in: viewModel.overlaySize)
            let toolbarLocal = CGPoint(
                x: toolbarGlobal.x - screenOriginInOverlay.x,
                y: toolbarGlobal.y - screenOriginInOverlay.y
            )
            let toolbarVisible = CGRect(origin: .zero, size: geo.size)
                .insetBy(dx: -40, dy: -40)
                .contains(toolbarLocal)

            ZStack {
                DimmedBackgroundView(
                    selection: localSelection,
                    windowHighlight: nil
                )
                .allowsHitTesting(false)

                if localSelection.width > 2, localSelection.height > 2 {
                    selectionChrome(for: localSelection)
                        .allowsHitTesting(false)

                    if toolbarVisible {
                        CaptureToolbarView(viewModel: viewModel)
                            .position(toolbarLocal)
                            .transition(.scale.combined(with: .opacity))
                            .allowsHitTesting(true)
                            .zIndex(10)
                    }
                }

                if let toast = viewModel.toastMessage {
                    ToastView(message: toast)
                        .position(x: geo.size.width / 2, y: 48)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear {
            NSCursor.crosshair.push()
        }
        .onDisappear {
            NSCursor.pop()
        }
    }

    private func selectionChrome(for localSelection: CGRect) -> some View {
        let border = colorScheme == .dark ? Color.white.opacity(0.95) : Color.white.opacity(0.98)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(border, lineWidth: 1.5)
            .background {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 3)
                    .blur(radius: 0.4)
            }
            .frame(width: localSelection.width, height: localSelection.height)
            .position(x: localSelection.midX, y: localSelection.midY)
    }
}
