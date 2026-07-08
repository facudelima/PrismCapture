import Foundation
import AppKit

@MainActor
final class UploadService {
    static let shared = UploadService()

    struct UploadResult: Equatable {
        let url: URL
        let deleteHash: String?
    }

    func upload(_ image: NSImage, provider: UploadProvider) async throws -> UploadResult {
        switch provider {
        case .none:
            throw UploadError.noProvider
        case .imgur:
            return try await uploadToImgur(image)
        case .custom:
            return try await uploadToCustom(image)
        }
    }

    func delete(remoteURL: String, deleteHash: String?, provider: UploadProvider) async throws {
        switch provider {
        case .imgur:
            guard let deleteHash else { throw UploadError.missingDeleteHash }
            var request = URLRequest(url: URL(string: "https://api.imgur.com/3/image/\(deleteHash)")!)
            request.httpMethod = "DELETE"
            request.setValue("Client-ID \(imgurClientID)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UploadError.deleteFailed
            }
        case .custom, .none:
            throw UploadError.unsupportedDelete
        }
    }

    // MARK: - Private

    /// Public anonymous client id placeholder — replace in Settings / secrets for production.
    private var imgurClientID: String { "YOUR_IMGUR_CLIENT_ID" }

    private func uploadToImgur(_ image: NSImage) async throws -> UploadResult {
        guard let data = image.data(using: .png)?.base64EncodedString() else {
            throw UploadError.encodingFailed
        }

        var request = URLRequest(url: URL(string: "https://api.imgur.com/3/image")!)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(imgurClientID)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "image=\(data)&type=base64".data(using: .utf8)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.uploadFailed
        }

        struct ImgurResponse: Decodable {
            struct DataPayload: Decodable {
                let link: String
                let deletehash: String?
            }
            let data: DataPayload
            let success: Bool
        }

        let decoded = try JSONDecoder().decode(ImgurResponse.self, from: responseData)
        guard decoded.success, let url = URL(string: decoded.data.link) else {
            throw UploadError.uploadFailed
        }
        return UploadResult(url: url, deleteHash: decoded.data.deletehash)
    }

    private func uploadToCustom(_ image: NSImage) async throws -> UploadResult {
        let endpoint = AppSettings.shared.customUploadURL
        guard let url = URL(string: endpoint), !endpoint.isEmpty else {
            throw UploadError.invalidEndpoint
        }
        guard let data = image.data(using: .png) else {
            throw UploadError.encodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"capture.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.uploadFailed
        }

        if let link = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let resultURL = URL(string: link),
           link.hasPrefix("http") {
            return UploadResult(url: resultURL, deleteHash: nil)
        }

        struct Generic: Decodable { let url: String? }
        if let decoded = try? JSONDecoder().decode(Generic.self, from: responseData),
           let link = decoded.url,
           let resultURL = URL(string: link) {
            return UploadResult(url: resultURL, deleteHash: nil)
        }

        throw UploadError.uploadFailed
    }
}

enum UploadError: LocalizedError {
    case noProvider
    case encodingFailed
    case uploadFailed
    case deleteFailed
    case missingDeleteHash
    case unsupportedDelete
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .noProvider: return "Configura un proveedor de subida en Ajustes."
        case .encodingFailed: return "No se pudo preparar la imagen."
        case .uploadFailed: return "Error al subir la captura."
        case .deleteFailed: return "No se pudo eliminar la captura remota."
        case .missingDeleteHash: return "Falta el hash de eliminación."
        case .unsupportedDelete: return "Este proveedor no soporta borrado."
        case .invalidEndpoint: return "URL de subida personalizada inválida."
        }
    }
}
