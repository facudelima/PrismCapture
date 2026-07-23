import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var captureVM = CaptureViewModel()
    @Published var historyVM = HistoryViewModel.shared
    @Published var showHistory = false

    private var settingsCloseObserver: NSObjectProtocol?

    private init() {
        HotkeyService.shared.register { [weak self] mode in
            self?.captureVM.start(mode: mode)
        }
    }

    func captureArea() { captureVM.start(mode: .area) }
    func captureFullscreen() { captureVM.start(mode: .fullscreen) }
    func captureWindow() { captureVM.start(mode: .window) }

    /// Call before/with `SettingsLink`: agent apps need `.regular` so Settings can appear.
    func prepareSettingsPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where window.className.contains("MenuBarExtra") {
            window.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.watchSettingsWindowClose()
        }
    }

    private func watchSettingsWindowClose() {
        if let settingsCloseObserver {
            NotificationCenter.default.removeObserver(settingsCloseObserver)
            self.settingsCloseObserver = nil
        }

        guard let settingsWindow = NSApp.windows.first(where: { window in
            window.isVisible
                && window.styleMask.contains(.titled)
                && window.canBecomeKey
                && !window.className.contains("MenuBarExtra")
        }) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let titledVisible = NSApp.windows.contains {
                    $0.isVisible && $0.styleMask.contains(.titled) && !$0.className.contains("MenuBarExtra")
                }
                if !titledVisible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            return
        }

        settingsWindow.makeKeyAndOrderFront(nil)

        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: settingsWindow,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                NSApp.setActivationPolicy(.accessory)
                if let observer = self.settingsCloseObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.settingsCloseObserver = nil
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if NSApp.activationPolicy() == .regular,
               !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) && !$0.className.contains("MenuBarExtra") }) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
