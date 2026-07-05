import AppKit
import ScreenCaptureKit

@MainActor
final class PermissionService {
    static let shared = PermissionService()

    /// Last known good state after a successful ScreenCaptureKit probe.
    private(set) var didSucceedShareableContent = false

    /// Fast but sometimes stale under Xcode / ad-hoc signing.
    var preflightGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Reliable check: actually ask ScreenCaptureKit for shareable content.
    func canCaptureScreens() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            didSucceedShareableContent = true
            return true
        } catch {
            didSucceedShareableContent = false
            return false
        }
    }

    /// Ensures permission is available. Triggers the system prompt when needed.
    /// Returns true if capture should proceed.
    func ensureScreenRecordingPermission() async -> Bool {
        if await canCaptureScreens() {
            return true
        }

        // Triggers TCC prompt (or no-ops if already decided).
        // Return value is unreliable after the user already toggled Settings —
        // especially with Debug builds from Xcode — so we always re-probe SCK.
        _ = CGRequestScreenCaptureAccess()

        if await canCaptureScreens() {
            return true
        }

        // TCC can take a beat to settle after the user clicks Allow.
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await canCaptureScreens() {
                return true
            }
            if CGPreflightScreenCaptureAccess(), await canCaptureScreens() {
                return true
            }
        }

        return false
    }

    func openScreenRecordingSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    var recoveryHint: String {
        """
        Si el permiso ya está activado: apagá y prendé “PrismCapture” en \
        Ajustes › Privacidad › Grabación de pantalla, y reiniciá la app \
        (los builds de Xcode cuentan como otra app).
        """
    }
}
