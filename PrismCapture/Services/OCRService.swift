import AppKit
import Vision

@MainActor
final class OCRService {
    static let shared = OCRService()

    func extractText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Prefer the system language(s), then fall back to Spanish/English.
            var languages = Locale.preferredLanguages
            for fallback in ["es-ES", "en-US"] where !languages.contains(where: { $0.hasPrefix(String(fallback.prefix(2))) }) {
                languages.append(fallback)
            }
            request.recognitionLanguages = Array(languages.prefix(5))

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func search(query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        L10n.string("Invalid image for OCR.")
    }
}
