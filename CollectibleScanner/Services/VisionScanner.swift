import Foundation
import UIKit
import Vision

enum VisionScannerError: LocalizedError {
    case unsupportedImage
    case noSignalsFound

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "The selected image could not be scanned."
        case .noSignalsFound:
            return "No text or barcode was detected. Try a clearer photo."
        }
    }
}

final class VisionScanner {
    func scan(image: UIImage) async throws -> ScanPayload {
        guard let cgImage = image.cgImage else {
            throw VisionScannerError.unsupportedImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = .accurate
                textRequest.usesLanguageCorrection = true

                let barcodeRequest = VNDetectBarcodesRequest()
                barcodeRequest.symbologies = [.ean13, .ean8, .upce, .code128, .code39, .qr]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([textRequest, barcodeRequest])

                    let textResults = textRequest.results ?? []
                    let barcodeResults = barcodeRequest.results ?? []

                    let textLines = textResults
                        .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    let barcodes = barcodeResults
                        .compactMap { $0.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    if textLines.isEmpty && barcodes.isEmpty {
                        throw VisionScannerError.noSignalsFound
                    }

                    continuation.resume(returning: ScanPayload(textLines: textLines.uniqued(), barcodes: barcodes.uniqued()))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
