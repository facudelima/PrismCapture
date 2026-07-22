import Foundation
import AppKit

/// Checks GitHub Releases for a newer PrismCapture build and can download/install it.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    static let githubOwner = "facudelima"
    static let githubRepo = "PrismCapture"
    static let releasesURL = URL(string: "https://github.com/facudelima/PrismCapture/releases")!

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(current: String, latest: String)
        case updateAvailable(current: String, latest: String, notes: String?, downloadURL: URL?)
        case downloading(progress: Double)
        case installing
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    var currentVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "0"
    }

    var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    var displayVersion: String { "v\(currentVersion)" }

    var isUpdateAvailable: Bool {
        if case .updateAvailable = status { return true }
        return false
    }

    private init() {}

    func checkForUpdates(silent: Bool = false) async {
        if !silent {
            status = .checking
        } else if case .idle = status {
            status = .checking
        }

        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()
            let latest = Self.normalizeVersion(release.tagName)
            let current = Self.normalizeVersion(currentVersion)

            if Self.compareVersions(latest, current) > 0 {
                let asset = release.assets.first {
                    $0.name.lowercased().hasSuffix("-macos.zip")
                        || $0.name.lowercased() == "prismcapture.app.zip"
                        || ($0.name.lowercased().contains("prismcapture") && $0.name.lowercased().hasSuffix(".zip"))
                }
                status = .updateAvailable(
                    current: currentVersion,
                    latest: latest,
                    notes: release.body,
                    downloadURL: asset.flatMap { URL(string: $0.url) }
                )
            } else {
                status = .upToDate(current: currentVersion, latest: latest)
            }
        } catch {
            if silent {
                // Don't surface transient network/auth errors from background checks.
                if case .checking = status {
                    status = .idle
                }
                return
            }
            status = .error(error.localizedDescription)
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    func downloadAndInstall() async {
        guard case let .updateAvailable(_, latest, _, downloadURL) = status else { return }
        guard let downloadURL else {
            openReleasesPage()
            return
        }

        status = .downloading(progress: 0)
        do {
            let zipURL = try await download(from: downloadURL) { [weak self] fraction in
                Task { @MainActor in
                    self?.status = .downloading(progress: fraction)
                }
            }
            status = .installing
            try install(zipURL: zipURL, versionLabel: latest)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - GitHub

    private struct GHRelease: Decodable {
        let tagName: String
        let body: String?
        let assets: [GHAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case assets
        }
    }

    private struct GHAsset: Decodable {
        let name: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
        }
    }

    private func fetchLatestRelease() async throws -> GHRelease {
        let url = URL(string: "https://api.github.com/repos/\(Self.githubOwner)/\(Self.githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PrismCapture/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let token = resolveGitHubToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.network
        }
        if http.statusCode == 401 || http.statusCode == 404 {
            throw UpdateError.privateRepoNeedsAuth
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.http(http.statusCode)
        }
        return try JSONDecoder().decode(GHRelease.self, from: data)
    }

    /// Prefer Settings token; else Keychain entry for github.com (same as `gh`/git on this Mac).
    private func resolveGitHubToken() -> String? {
        if let stored = UserDefaults.standard.string(forKey: "githubUpdateToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }
        return readKeychainGitHubToken()
    }

    private func readKeychainGitHubToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-internet-password", "-s", "github.com", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let token, !token.isEmpty else { return nil }
            return token
        } catch {
            return nil
        }
    }

    // MARK: - Download / install

    private func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("PrismCapture/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let token = resolveGitHubToken() {
            // Private release assets need auth + accept octet-stream for API URLs;
            // browser_download_url usually works with token as query is not needed for GH.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        }

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }
        progress(1)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrismCapture-update-\(UUID().uuidString).zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    private func install(zipURL: URL, versionLabel: String) throws {
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

        // Prefer replacing the running bundle; fall back to /Applications.
        let running = Bundle.main.bundleURL
        let target: URL = {
            if running.path.contains("/Applications/") || running.lastPathComponent == "PrismCapture.app" {
                return running
            }
            return URL(fileURLWithPath: "/Applications/PrismCapture.app")
        }()

        let script = """
        #!/bin/bash
        set -e
        sleep 1
        /usr/bin/xattr -cr "\(appURL.path)" || true
        /usr/bin/codesign --force --deep --sign - "\(appURL.path)" >/dev/null 2>&1 || true
        /bin/rm -rf "\(target.path)"
        /bin/cp -R "\(appURL.path)" "\(target.path)"
        /usr/bin/xattr -cr "\(target.path)" || true
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
        for case let url as URL in enumerator {
            if url.pathExtension == "app", url.lastPathComponent == "PrismCapture.app" {
                return url
            }
        }
        return nil
    }

    // MARK: - Version helpers

    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") { s.removeFirst() }
        return s
    }

    /// Returns 1 if a > b, -1 if a < b, 0 if equal.
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
        case privateRepoNeedsAuth
        case downloadFailed
        case unzipFailed
        case appMissingInZip

        var errorDescription: String? {
            switch self {
            case .network: return "No se pudo conectar con GitHub."
            case .http(let code): return "GitHub respondió \(code)."
            case .privateRepoNeedsAuth:
                return "Repo privado: necesitás un token de GitHub (Ajustes → Actualizaciones) o estar logueado en el Keychain."
            case .downloadFailed: return "Falló la descarga del update."
            case .unzipFailed: return "No se pudo descomprimir el update."
            case .appMissingInZip: return "El zip no contiene PrismCapture.app."
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
