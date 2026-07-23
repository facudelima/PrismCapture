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

    /// Ensures permission is available. Avoids re-prompting when TCC already granted
    /// (common right after an in-app update while ScreenCaptureKit is still settling).
    func ensureScreenRecordingPermission() async -> Bool {
        if await canCaptureScreens() {
            return true
        }

        // Already allowed in System Settings — wait instead of calling
        // CGRequestScreenCaptureAccess() again (that feels like “asking again”).
        if CGPreflightScreenCaptureAccess() {
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if await canCaptureScreens() {
                    return true
                }
            }
            return await canCaptureScreens()
        }

        // First-time (or previously denied): show the system prompt once.
        _ = CGRequestScreenCaptureAccess()

        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if await canCaptureScreens() {
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
