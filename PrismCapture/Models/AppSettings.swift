import Foundation
import SwiftUI
import AppKit

enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case jpeg
    case webp

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var fileExtension: String { rawValue }

    var utTypeIdentifier: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .webp: return "public.webp"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Appearance to stamp onto overlay windows. For Auto, mirror the current system look
    /// so NSHostingView materials resolve correctly (nil alone is flaky on agent apps).
    func resolvedWindowAppearance(effective: NSAppearance = NSApp.effectiveAppearance) -> NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .system:
            let match = effective.bestMatch(from: [.darkAqua, .aqua])
            return NSAppearance(named: match == .darkAqua ? .darkAqua : .aqua)
        }
    }
}

enum UploadProvider: String, CaseIterable, Identifiable, Codable {
    case none
    case imgur
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Ninguno"
        case .imgur: return "Imgur"
        case .custom: return "Personalizado"
        }
    }
}

enum ClipboardBehavior: String, CaseIterable, Identifiable, Codable {
    case never
    case copyOnSave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Solo con Copiar / ⌘C"
        case .copyOnSave: return "También al guardar"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("autoSave") var autoSave = false
    @AppStorage("defaultSaveFolder") var defaultSaveFolder = ""
    @AppStorage("imageFormat") var imageFormatRaw = ImageFormat.png.rawValue
    @AppStorage("clipboardBehavior") var clipboardBehaviorRaw = ClipboardBehavior.never.rawValue
    @AppStorage("uploadProvider") var uploadProviderRaw = UploadProvider.none.rawValue
    @AppStorage("customUploadURL") var customUploadURL = ""
    @AppStorage("showToastOnCopy") var showToastOnCopy = true
    @AppStorage("playSound") var playSound = false

    /// Persisted separately from `@AppStorage` so Picker updates don't publish mid-render.
    @Published private(set) var theme: AppTheme

    @AppStorage("hotkeyAreaJSON") private var hotkeyAreaJSON = HotkeyBinding.areaDefault.jsonString
    @AppStorage("hotkeyFullscreenJSON") private var hotkeyFullscreenJSON = HotkeyBinding.fullscreenDefault.jsonString

    private var themeObserver: NSObjectProtocol?
    private static let themeDefaultsKey = "theme"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.themeDefaultsKey) ?? AppTheme.system.rawValue
        theme = AppTheme(rawValue: raw) ?? .system

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.applyAppearance()
        }

        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                guard self.theme == .system else { return }
                self.applyAppearance()
            }
        }
    }

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: imageFormatRaw) ?? .png }
        set { imageFormatRaw = newValue.rawValue }
    }

    var clipboardBehavior: ClipboardBehavior {
        get { ClipboardBehavior(rawValue: clipboardBehaviorRaw) ?? .never }
        set { clipboardBehaviorRaw = newValue.rawValue }
    }

    var uploadProvider: UploadProvider {
        get { UploadProvider(rawValue: uploadProviderRaw) ?? .none }
        set { uploadProviderRaw = newValue.rawValue }
    }

    /// Safe to call from a `Picker` / view action — publishes outside the current render.
    func applyTheme(_ newTheme: AppTheme) {
        guard theme != newTheme else { return }
        theme = newTheme
        UserDefaults.standard.set(newTheme.rawValue, forKey: Self.themeDefaultsKey)
        Task { @MainActor in
            await Task.yield()
            applyAppearance()
        }
    }

    /// Forces light/dark on menu bar + capture overlays. Does not publish `objectWillChange`.
    func applyAppearance() {
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light, .dark:
            NSApp.appearance = theme.nsAppearance
        }

        let windowAppearance = theme.resolvedWindowAppearance()
        for window in NSApp.windows {
            if theme == .system {
                window.appearance = nil
            } else {
                window.appearance = windowAppearance
            }
        }
    }

    var hotkeyArea: HotkeyBinding {
        get { HotkeyBinding.decode(hotkeyAreaJSON) ?? .areaDefault }
        set {
            hotkeyAreaJSON = newValue.jsonString
            objectWillChange.send()
            HotkeyService.shared.reregister()
        }
    }

    var hotkeyFullscreen: HotkeyBinding {
        get { HotkeyBinding.decode(hotkeyFullscreenJSON) ?? .fullscreenDefault }
        set {
            hotkeyFullscreenJSON = newValue.jsonString
            objectWillChange.send()
            HotkeyService.shared.reregister()
        }
    }

    var resolvedSaveFolder: URL {
        if !defaultSaveFolder.isEmpty {
            return URL(fileURLWithPath: defaultSaveFolder)
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrismCapture", isDirectory: true)
    }

    func resetHotkeys() {
        hotkeyArea = .areaDefault
        hotkeyFullscreen = .fullscreenDefault
    }
}

private extension HotkeyBinding {
    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static func decode(_ json: String) -> HotkeyBinding? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }
}
