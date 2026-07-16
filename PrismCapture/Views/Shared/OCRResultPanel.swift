import SwiftUI

/// Standalone OCR panel wrapper used by the editor.
struct OCRPanelHost: View {
    @ObservedObject var viewModel: AnnotationViewModel

    var body: some View {
        if viewModel.showOCRPanel {
            OCRResultPanel(text: $viewModel.ocrText, isPresented: $viewModel.showOCRPanel)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
