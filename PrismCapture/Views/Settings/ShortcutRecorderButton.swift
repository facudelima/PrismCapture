import SwiftUI
import AppKit

/// Click to record a new global shortcut. Esc cancels recording.
struct ShortcutRecorderButton: View {
    let title: String
    @Binding var binding: HotkeyBinding
    let isConflict: Bool

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                startRecording()
            } label: {
                Text(isRecording ? "Presioná teclas…" : binding.displayString)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(isRecording ? Color.accentColor : (isConflict ? Color.orange : Color.primary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isConflict && !isRecording ? Color.orange.opacity(0.7) : .clear, lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Esc para cancelar" : "Clic para cambiar el atajo")
        }
        .onDisappear { stopRecording(keepValue: true) }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels
                stopRecording(keepValue: true)
                return nil
            }
            if let next = HotkeyBinding.from(nsEvent: event) {
                binding = next
                stopRecording(keepValue: true)
                return nil
            }
            return nil
        }
    }

    private func stopRecording(keepValue: Bool) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        _ = keepValue
    }
}
