import Foundation
import Vision

enum AppleOCR {
    static func recognize(_ cgImage: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US", "zh-Hant"]
        let merge = UserDefaults.standard.object(forKey: "mergeOCRLines") as? Bool ?? true
        return try await Task.detached(priority: .userInitiated) {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return (text, observation.boundingBox)
            }.sorted { $0.1.maxY > $1.1.maxY }
            guard merge else { return lines.map(\.0).joined(separator: "\n") }
            return paragraphs(lines)
        }.value
    }

    // shortcut: horizontal single-column text only; use a layout engine for columns or vertical writing.
    private static func paragraphs(_ lines: [(String, CGRect)]) -> String {
        var result = ""
        var previous: CGRect?
        for (text, box) in lines {
            if let previous {
                let height = max(previous.height, box.height)
                let gap = previous.minY - box.maxY
                let aligned = abs(previous.minX - box.minX) < height * 0.8
                let sameColumn =
                    previous.intersection(
                        CGRect(
                            x: box.minX, y: previous.minY,
                            width: box.width, height: previous.height)
                    ).width > min(previous.width, box.width) * 0.7
                if aligned && sameColumn && gap >= 0 && gap < height * 0.8 {
                    let latinBoundary = result.last?.isASCII == true && text.first?.isASCII == true
                    if latinBoundary { result += " " }
                } else {
                    result += "\n\n"
                }
            }
            result += text
            previous = box
        }
        return result
    }
}
