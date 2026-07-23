import Foundation
import AppKit

/// Checks public GitHub Releases and can download + replace the installed app.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    static let githubOwner = "facudelima"
    static let githubRepo = "PrismCapture"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(latest: String, downloadURL: URL)
        case downloading(progress: Double)
        case installing
        case error(String)
    }

    @Published private(set) var status: Status = .idle

    var currentVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return (short?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "0"
    }

    var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    var displayVersion: String { "v\(currentVersion)" }

    var isUpdateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    private init() {}

    /// Silent check on launch / menu open. Surfaces errors only when `silent == false`.
    func checkForUpdates(silent: Bool = false) async {
        if case .downloading = status { return }
        if case .installing = status { return }

        if !silent { status = .checking }
        else if case .idle = status { status = .checking }

        do {
            let release = try await fetchLatestRelease()
            let latest = Self.normalizeVersion(release.tagName)
            let current = Self.normalizeVersion(currentVersion)

            guard Self.compareVersions(latest, current) > 0 else {
                status = .upToDate
                return
            }

            guard let asset = release.assets.first(where: { asset in
                let name = asset.name.lowercased()
                return name.hasSuffix("-macos.zip")
                    || (name.contains("prismcapture") && name.hasSuffix(".zip"))
            }),
                  let url = URL(string: asset.browserDownloadURL) else {
                if silent {
                    status = .idle
                } else {
                    status = .error("Hay una versión nueva pero no hay zip para descargar.")
                }
                return
            }

            status = .available(latest: latest, downloadURL: url)
        } catch {
            if silent {
                if case .checking = status { status = .idle }
                return
            }
            status = .error(error.localizedDescription)
        }
    }

    /// Downloads the zip, replaces the app, and relaunches.
    func installAvailableUpdate() async {
        guard case let .available(latest, downloadURL) = status else { return }
        status = .downloading(progress: 0)
        do {
            let zipURL = try await download(from: downloadURL)
            status = .installing
            try scheduleInstall(zipURL: zipURL, versionLabel: latest)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - GitHub (public releases — no token)

    private struct GHRelease: Decodable {
        let tagName: String
        let assets: [GHAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct GHAsset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private func fetchLatestRelease() async throws -> GHRelease {
        let url = URL(string: "https://api.github.com/repos/\(Self.githubOwner)/\(Self.githubRepo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PrismCapture/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.http(http.statusCode)
        }
        return try JSONDecoder().decode(GHRelease.self, from: data)
    }

    private func download(from url: URL) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("PrismCapture/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismCapture-update-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        status = .downloading(progress: 1)
        return dest
    }

    private func scheduleInstall(zipURL: URL, versionLabel: String) throws {
        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory.appendingPathComponent("PrismCapture-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw UpdateError.unzipFailed }

        guard let appURL = findApp(in: extractDir) else { throw UpdateError.appMissingInZip }

        let running = Bundle.main.bundleURL
        let target: URL = {
            if running.path.hasSuffix(".app") {
                return running
            }
            return URL(fileURLWithPath: "/Applications/PrismCapture.app")
        }()

        let script = """
        #!/bin/bash
        set -e
        sleep 1
        # Clear quarantine only — do NOT re-sign (would break TCC / Screen Recording).
        /usr/bin/xattr -dr com.apple.quarantine "\(appURL.path)" 2>/dev/null || true
        /usr/bin/xattr -cr "\(appURL.path)" 2>/dev/null || true
        /bin/rm -rf "\(target.path)"
        /bin/cp -R "\(appURL.path)" "\(target.path)"
        /usr/bin/xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null || true
        /usr/bin/open "\(target.path)"
        /bin/rm -rf "\(extractDir.path)" "\(zipURL.path)"
        """
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("prism-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]
        try task.run()

        NSApp.terminate(nil)
    }

    private func findApp(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.pathExtension == "app" && url.lastPathComponent == "PrismCapture.app" {
            return url
        }
        return nil
    }

    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") { s.removeFirst() }
        return s
    }

    static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    enum UpdateError: LocalizedError {
        case network
        case http(Int)
        case downloadFailed
        case unzipFailed
        case appMissingInZip

        var errorDescription: String? {
            switch self {
            case .network: return "Sin conexión con el servidor de actualizaciones."
            case .http(let code): return "No se pudo consultar actualizaciones (\(code))."
            case .downloadFailed: return "Falló la descarga."
            case .unzipFailed: return "No se pudo descomprimir la actualización."
            case .appMissingInZip: return "El paquete de actualización está incompleto."
            }
        }
    }
}
