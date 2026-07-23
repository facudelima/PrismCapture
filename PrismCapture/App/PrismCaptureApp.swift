import SwiftUI
import AppKit

@main
struct PrismCaptureApp: App {
    @NSApplicationDelegateAdaptor(PrismAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        // `image:` loads the template asset reliably in the status item.
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
            // Quiet check a few seconds after launch.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await UpdateService.shared.checkForUpdates(silent: true)
        }
    }
}
