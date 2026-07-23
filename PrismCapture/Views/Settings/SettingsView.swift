import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var updates = UpdateService.shared
    @State private var permissionOK = false
    @State private var githubTokenDraft = UserDefaults.standard.string(forKey: "githubUpdateToken") ?? ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard(title: "General") {
                    toggleRow("Abrir al iniciar sesión", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    ))
                    divider
                    toggleRow("Mostrar aviso al copiar", isOn: $settings.showToastOnCopy)
                    Text("Esc cancela · Copiar / ⌘C guarda en el portapapeles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                settingsCard(title: "Actualizaciones") {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Versión instalada")
                                .font(.system(size: 13, weight: .medium))
                            Text("\(updates.displayVersion) (build \(updates.currentBuild))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusBadge
                    }

                    divider

                    Text(updateDetailText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(updateDetailColor)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Buscar ahora") {
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

                        if case .updateAvailable = updates.status {
                            Button("Instalar…") {
                                Task { await updates.downloadAndInstall() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Releases…") {
                            updates.openReleasesPage()
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }

                    divider

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Token GitHub (opcional)")
                            .font(.system(size: 13, weight: .medium))
                        SecureField("ghp_… para repo privado", text: $githubTokenDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        HStack {
                            Button("Guardar token") {
                                let trimmed = githubTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    UserDefaults.standard.removeObject(forKey: "githubUpdateToken")
                                } else {
                                    UserDefaults.standard.set(trimmed, forKey: "githubUpdateToken")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Borrar") {
                                githubTokenDraft = ""
                                UserDefaults.standard.removeObject(forKey: "githubUpdateToken")
                            }
                            .buttonStyle(.plain)
                            .controlSize(.small)
                            .foregroundStyle(.secondary)
                        }
                        Text("El repo es privado: sin token usa el de Keychain (github.com) si existe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard(title: "Archivos") {
                    toggleRow("Guardar automáticamente al capturar", isOn: $settings.autoSave)
                    divider
                    toggleRow("Copiar también al guardar", isOn: Binding(
                        get: { settings.clipboardBehavior == .copyOnSave },
                        set: { settings.clipboardBehavior = $0 ? .copyOnSave : .never }
                    ))
                    divider
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Carpeta de guardado")
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
                        Button("Elegir…") { viewModel.chooseSaveFolder() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                settingsCard(title: "Apariencia") {
                    Picker("Tema", selection: Binding(
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
                }

                settingsCard(title: "Permisos y atajos") {
                    HStack {
                        Label(
                            permissionOK ? "Permiso de pantalla concedido" : "Falta permiso de pantalla",
                            systemImage: permissionOK ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(permissionOK ? Color.secondary : Color.orange)
                        Spacer()
                        Button("Sistema…") {
                            PermissionService.shared.openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    divider

                    ShortcutRecorderButton(
                        title: "Capturar área",
                        binding: Binding(
                            get: { settings.hotkeyArea },
                            set: { settings.hotkeyArea = $0 }
                        ),
                        isConflict: settings.hotkeyArea == settings.hotkeyFullscreen
                            || settings.hotkeyArea == settings.hotkeyWindow
                    )
                    ShortcutRecorderButton(
                        title: "Pantalla completa",
                        binding: Binding(
                            get: { settings.hotkeyFullscreen },
                            set: { settings.hotkeyFullscreen = $0 }
                        ),
                        isConflict: settings.hotkeyFullscreen == settings.hotkeyArea
                            || settings.hotkeyFullscreen == settings.hotkeyWindow
                    )
                    ShortcutRecorderButton(
                        title: "Ventana",
                        binding: Binding(
                            get: { settings.hotkeyWindow },
                            set: { settings.hotkeyWindow = $0 }
                        ),
                        isConflict: settings.hotkeyWindow == settings.hotkeyArea
                            || settings.hotkeyWindow == settings.hotkeyFullscreen
                    )

                    labeledShortcut("Copiar y cerrar", "⌘C")
                    labeledShortcut("Guardar", "⌘S")
                    labeledShortcut("Cancelar", "Esc")

                    divider

                    Button("Restablecer atajos de captura") {
                        settings.resetHotkeys()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))

                    Text("Clic en un atajo y presioná la nueva combinación. Esc cancela la grabación.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(18)
        }
        .background(settingsChrome)
        .frame(width: 460, height: 620)
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

    private var statusBadge: some View {
        Text(badgeLabel)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(badgeColor.opacity(0.15))
            }
    }

    private var badgeLabel: String {
        switch updates.status {
        case .upToDate: return "Al día"
        case .updateAvailable: return "Nueva"
        case .checking: return "…"
        case .error: return "Error"
        case .downloading: return "↓"
        case .installing: return "…"
        case .idle: return updates.displayVersion
        }
    }

    private var badgeColor: Color {
        switch updates.status {
        case .updateAvailable: return .orange
        case .upToDate: return .green
        case .error: return .red
        default: return .secondary
        }
    }

    private var updateDetailText: String {
        switch updates.status {
        case .idle:
            return "Todavía no se verificó contra GitHub."
        case .checking:
            return "Consultando releases…"
        case .upToDate(_, let latest):
            return "Última en GitHub: v\(latest). No hay nada nuevo."
        case .updateAvailable(_, let latest, _, _):
            return "Hay una versión nueva: v\(latest). Podés instalarla desde acá."
        case .downloading(let p):
            return "Descargando… \(Int(p * 100))%"
        case .installing:
            return "Reemplazando la app y reiniciando…"
        case .error(let message):
            return message
        }
    }

    private var updateDetailColor: Color {
        switch updates.status {
        case .updateAvailable: return .orange
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
