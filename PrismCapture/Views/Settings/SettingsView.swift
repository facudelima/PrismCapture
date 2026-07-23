import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var updates = UpdateService.shared
    @State private var permissionOK = false
    @Environment(\.colorScheme) private var colorScheme

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard(title: L10n.string("General")) {
                    toggleRow(L10n.string("Open at Login"), isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    ))
                    divider
                    toggleRow(L10n.string("Show toast when copying"), isOn: $settings.showToastOnCopy)
                    Text(L10n.string("Esc cancels · Copy / ⌘C saves to the clipboard."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                settingsCard(title: L10n.string("Files")) {
                    toggleRow(L10n.string("Auto-save on capture"), isOn: $settings.autoSave)
                    divider
                    toggleRow(L10n.string("Also copy when saving"), isOn: Binding(
                        get: { settings.clipboardBehavior == .copyOnSave },
                        set: { settings.clipboardBehavior = $0 ? .copyOnSave : .never }
                    ))
                    divider
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.string("Save folder"))
                                .font(.system(size: 13, weight: .medium))
                            Text(settings.defaultSaveFolder.isEmpty
                                 ? settings.resolvedSaveFolder.path
                                 : settings.defaultSaveFolder)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button(L10n.string("Choose…")) { viewModel.chooseSaveFolder() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                settingsCard(title: L10n.string("Appearance")) {
                    Picker(L10n.string("Theme"), selection: Binding(
                        get: { settings.theme },
                        set: { newValue in
                            Task { @MainActor in
                                await Task.yield()
                                settings.applyTheme(newValue)
                            }
                        }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(L10n.string("Language follows your Mac’s System Settings."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                settingsCard(title: L10n.string("Permissions & Shortcuts")) {
                    HStack {
                        Label(
                            permissionOK
                                ? L10n.string("Screen permission granted")
                                : L10n.string("Screen permission required"),
                            systemImage: permissionOK ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(permissionOK ? Color.secondary : Color.orange)
                        Spacer()
                        Button(L10n.string("System…")) {
                            PermissionService.shared.openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    divider

                    ShortcutRecorderButton(
                        title: L10n.string("Capture Area"),
                        binding: Binding(
                            get: { settings.hotkeyArea },
                            set: { settings.hotkeyArea = $0 }
                        ),
                        isConflict: settings.hotkeyArea == settings.hotkeyFullscreen
                    )
                    ShortcutRecorderButton(
                        title: L10n.string("Full Screen"),
                        binding: Binding(
                            get: { settings.hotkeyFullscreen },
                            set: { settings.hotkeyFullscreen = $0 }
                        ),
                        isConflict: settings.hotkeyFullscreen == settings.hotkeyArea
                    )

                    labeledShortcut(L10n.string("Copy & Close"), "⌘C")
                    labeledShortcut(L10n.string("Save"), "⌘S")
                    labeledShortcut(L10n.string("Cancel"), "Esc")

                    divider

                    Button(L10n.string("Reset capture shortcuts")) {
                        settings.resetHotkeys()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))

                    Text(L10n.string("Click a shortcut and press the new combination. Esc cancels recording."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                settingsCard(title: L10n.string("About")) {
                    HStack {
                        Text(L10n.string("Version"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("v\(appVersion) (\(appBuild))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(aboutStatusText)
                        .font(.caption)
                        .foregroundStyle(aboutStatusColor)

                    HStack(spacing: 8) {
                        if case .available(let latest, _) = updates.status {
                            Button(L10n.format("Update to v%@", latest)) {
                                Task { await updates.installAvailableUpdate() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button(L10n.string("Check for Updates")) {
                                Task { await updates.checkForUpdates(silent: false) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled({
                                if case .checking = updates.status { return true }
                                if case .downloading = updates.status { return true }
                                if case .installing = updates.status { return true }
                                return false
                            }())
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(settingsChrome)
        .frame(width: 460, height: 580)
        .task {
            permissionOK = await PermissionService.shared.canCaptureScreens()
            await updates.checkForUpdates(silent: true)
        }
        .onAppear { tintSettingsWindow() }
        .onChange(of: settings.theme) { _, _ in
            Task { @MainActor in
                await Task.yield()
                tintSettingsWindow()
            }
        }
        .onChange(of: colorScheme) { _, _ in
            Task { @MainActor in
                await Task.yield()
                tintSettingsWindow()
            }
        }
    }

    private var aboutStatusText: String {
        switch updates.status {
        case .idle: return L10n.string("You can check for a new version.")
        case .checking: return L10n.string("Checking…")
        case .upToDate: return L10n.string("Up to date.")
        case .available(let latest, _): return L10n.format("A new version is available: v%@.", latest)
        case .downloading(let p): return L10n.format("Downloading… %lld%%", Int(p * 100))
        case .installing: return L10n.string("Installing and relaunching…")
        case .error(let message): return message
        }
    }

    private var aboutStatusColor: Color {
        switch updates.status {
        case .available: return .orange
        case .error: return .red
        default: return .secondary
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(cardStroke, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, y: 4)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(height: 1)
    }

    private var cardFill: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.07))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.55),
                    Color.white.opacity(0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.7)
    }

    private var settingsChrome: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 0.12, green: 0.12, blue: 0.14)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.79, blue: 0.81),
                        Color(red: 0.70, green: 0.72, blue: 0.74)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .font(.system(size: 13, weight: .medium))
    }

    private func labeledShortcut(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                }
        }
    }

    private func tintSettingsWindow() {
        DispatchQueue.main.async {
            let grayLight = NSColor(calibratedRed: 0.74, green: 0.75, blue: 0.77, alpha: 1)
            let grayDark = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1)
            for window in NSApp.windows where window.styleMask.contains(.titled)
                && !window.className.contains("MenuBarExtra") {
                let useDark: Bool = {
                    switch settings.theme {
                    case .dark: return true
                    case .light: return false
                    case .system:
                        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    }
                }()
                window.backgroundColor = useDark ? grayDark : grayLight
                window.isOpaque = true
                window.titlebarAppearsTransparent = true
            }
        }
    }
}
