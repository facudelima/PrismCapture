import SwiftUI
import AppKit

struct MenuBarExtraView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var updates = UpdateService.shared
    @State private var hoveredAction: String?
    @State private var permissionOK = false

    private var menuChrome: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.92)
            : Color(red: 0.74, green: 0.75, blue: 0.77).opacity(0.95)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35).padding(.vertical, 8)
            captureSection
            Divider().opacity(0.35).padding(.vertical, 8)
            updatesSection
            Divider().opacity(0.35).padding(.vertical, 8)
            footer
        }
        .padding(14)
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(menuChrome)
        }
        .prismGlass(cornerRadius: 20)
        .padding(6)
        .task {
            permissionOK = await PermissionService.shared.canCaptureScreens()
            await updates.checkForUpdates(silent: true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("MenuBarPrism")
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("PrismCapture")
                    .font(.system(size: 15, weight: .semibold))
                Text(permissionOK ? L10n.string("Ready to capture") : L10n.string("Screen permission missing"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(permissionOK ? Color.secondary : Color.orange)
            }
            Spacer()
            Text(updates.displayVersion)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(updates.isUpdateAvailable ? Color.orange : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
        }
        .padding(.horizontal, 4)
    }

    private var captureSection: some View {
        VStack(spacing: 4) {
            menuRow(L10n.string("Area"), shortcut: settings.hotkeyArea.displayString, icon: "rectangle.dashed") {
                appState.captureArea()
            }
            menuRow(L10n.string("Full Screen"), shortcut: settings.hotkeyFullscreen.displayString, icon: "rectangle.on.rectangle") {
                appState.captureFullscreen()
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

            switch updates.status {
            case .available(let latest, _):
                menuRow(L10n.format("Update to v%@", latest), shortcut: nil, icon: "arrow.down.app.fill") {
                    Task { await updates.installAvailableUpdate() }
                }
            case .downloading, .installing, .checking:
                EmptyView()
            default:
                menuRow(L10n.string("Check for Updates"), shortcut: nil, icon: "arrow.triangle.2.circlepath") {
                    Task { await updates.checkForUpdates(silent: false) }
                }
            }
        }
    }

    private var statusLine: String {
        switch updates.status {
        case .idle:
            return L10n.format("Version %@", updates.currentVersion)
        case .checking:
            return L10n.string("Checking for updates…")
        case .upToDate:
            return L10n.string("You're up to date")
        case .available(_, _):
            return L10n.string("Update available")
        case .downloading(let p):
            return L10n.format("Downloading… %lld%%", Int(p * 100))
        case .installing:
            return L10n.string("Installing and relaunching…")
        case .error(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch updates.status {
        case .available: return .orange
        case .error: return .red
        default: return .secondary
        }
    }

    private var footer: some View {
        let settingsTitle = L10n.string("Settings…")
        return VStack(spacing: 4) {
            if !permissionOK {
                menuRow(L10n.string("Open Permissions…"), shortcut: nil, icon: "hand.raised") {
                    PermissionService.shared.openScreenRecordingSettings()
                }
            }

            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                    Text(settingsTitle)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("⌘,")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(hoveredAction == settingsTitle ? 0.14 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.prismSnappy) {
                    hoveredAction = hovering ? settingsTitle : nil
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                appState.prepareSettingsPresentation()
            })

            menuRow(L10n.string("Quit"), shortcut: "⌘Q", icon: "power") {
                NSApp.terminate(nil)
            }
        }
    }

    private func menuRow(_ title: String, shortcut: String?, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(hoveredAction == title ? 0.14 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.prismSnappy) {
                hoveredAction = hovering ? title : nil
            }
        }
    }
}
