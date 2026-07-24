import SwiftUI
import AppKit

@main
struct PrismCaptureApp: App {
    @NSApplicationDelegateAdaptor(PrismAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        // Asset catalog has Any + Dark appearances (original, two-tone prism).
        MenuBarExtra("PrismCapture", image: "MenuBarPrism") {
            MenuBarExtraView()
                .environmentObject(appState)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}

final class PrismAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppSettings.shared.applyAppearance()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await UpdateService.shared.checkForUpdates(silent: true)
        }
    }
}
