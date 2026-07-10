import Foundation
import ServiceManagement
import AppKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings = AppSettings.shared

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignore registration failures in unsigned debug builds.
        }
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultSaveFolder = url.path
        }
    }
}
