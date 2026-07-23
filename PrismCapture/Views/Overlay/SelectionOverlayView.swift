import SwiftUI
import AppKit

struct SelectionOverlayView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DimmedBackgroundView(
                    selection: viewModel.selectionRect,
                    windowHighlight: nil
                )
                .allowsHitTesting(false)

                if viewModel.selectionRect.width > 2, viewModel.selectionRect.height > 2 {
                    selectionChrome
                        .allowsHitTesting(false)

                    CaptureToolbarView(viewModel: viewModel)
                        .position(viewModel.toolbarCenter(in: geo.size))
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(true)
                        .zIndex(10)
                }

                if let toast = viewModel.toastMessage {
                    ToastView(message: toast)
                        .position(x: geo.size.width / 2, y: 48)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                viewModel.overlaySize = geo.size
            }
            .onChange(of: geo.size) { _, newSize in
                viewModel.overlaySize = newSize
            }
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

    private var selectionChrome: some View {
        let border = colorScheme == .dark ? Color.white.opacity(0.95) : Color.white.opacity(0.98)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(border, lineWidth: 1.5)
            .background {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 3)
                    .blur(radius: 0.4)
            }
            .frame(width: viewModel.selectionRect.width, height: viewModel.selectionRect.height)
            .position(x: viewModel.selectionRect.midX, y: viewModel.selectionRect.midY)
    }
}
