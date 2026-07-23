import SwiftUI
import AppKit

struct EditorWindowView: View {
    @ObservedObject var annotationVM: AnnotationViewModel
    @ObservedObject var captureVM: CaptureViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var dragFileURL: URL?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                EditorToolbarView(viewModel: annotationVM, captureVM: captureVM)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                AnnotationCanvasView(viewModel: annotationVM)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            OCRPanelHost(viewModel: annotationVM)
                .padding(16)
                .animation(.prismSpring, value: annotationVM.showOCRPanel)

            if let toast = captureVM.toastMessage {
                ToastView(message: toast)
                    .padding(.top, 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background {
            VisualEffectBackground()
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear {
            prepareDragItem()
        }
        .focusable()
        .onKeyPress(keys: [.init("c")]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            copyImage()
            return .handled
        }
        .onKeyPress(keys: [.init("s")]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            saveImage()
            return .handled
        }
        .onKeyPress(keys: [.init("z")]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) {
                annotationVM.redo()
            } else {
                annotationVM.undo()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
            return .handled
        }
    }

    private func copyImage() {
        ClipboardService.shared.copyImage(annotationVM.renderedImage())
        OverlayWindowController.shared.closeInPlaceEditor(copyIfNeeded: false)
    }

    private func saveImage() {
        if let url = FileService.shared.savePanel(image: annotationVM.renderedImage(), format: settings.imageFormat) {
            HistoryViewModel.shared.add(image: annotationVM.renderedImage(), fileURL: url, remoteURL: annotationVM.remoteURL, ocrText: annotationVM.ocrText.isEmpty ? nil : annotationVM.ocrText)
            if settings.clipboardBehavior == .copyOnSave {
                ClipboardService.shared.copyImage(annotationVM.renderedImage())
            }
            captureVM.showToast(L10n.string("Saved"))
            prepareDragItem(url: url)
        }
    }

    private func prepareDragItem(url: URL? = nil) {
        if let url {
            dragFileURL = url
            return
        }
        if let temp = try? FileService.shared.save(
            annotationVM.renderedImage(),
            to: FileManager.default.temporaryDirectory,
            format: settings.imageFormat
        ) {
            dragFileURL = temp
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
