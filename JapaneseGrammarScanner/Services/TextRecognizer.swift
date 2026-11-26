import CoreGraphics
import ImageIO
import Vision

enum TextRecognizer {
    static func recognize(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        fast: Bool = false
    ) throws -> (text: String, lines: [RecognizedLine]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = fast ? 0.02 : 0

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        var result = assemble(observations)
        if !fast, orientation == .up {
            TextBandFinder.refine(&result.lines, image: cgImage)
        }
        return result
    }

    static func assemble(_ observations: [VNRecognizedTextObservation]) -> (text: String, lines: [RecognizedLine]) {
        var text = ""
        var lines: [RecognizedLine] = []
        var previous: CGRect?
        let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?", "」", "』", "…"]
        let bodyHeight = medianBodyLineHeight(observations)

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !JapaneseText.isForeign(trimmed) else { continue }
            guard !isCutOffNeighbor(obs.boundingBox, bodyHeight: bodyHeight) else { continue }
            let lineText = JapaneseText.maskForeignSegments(trimmed)

            if let prev = previous {
                let last = text.trimmingCharacters(in: CharacterSet(charactersIn: "　")).last
                let continues = !(last.map(sentenceEnders.contains) ?? false)
                    && isContinuation(previous: prev, next: obs.boundingBox)
                if !continues { text += "\n" }
            }
            let start = (text as NSString).length
            text += lineText
            let range = NSRange(location: start, length: (lineText as NSString).length)
            previous = obs.boundingBox

            let original = candidate.string
            let offsetInOriginal = (original as NSString).range(of: trimmed).location

            lines.append(RecognizedLine(
                rangeInText: range,
                text: lineText,
                boundingBox: obs.boundingBox,
                boxForRange: { local in
                    let shifted = NSRange(location: local.location + offsetInOriginal, length: local.length)
                    guard let r = Range(shifted, in: original),
                          let box = try? candidate.boundingBox(for: r) else { return nil }
                    return box.boundingBox
                },
                quad: [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft],
                quadForRange: { local in
                    let shifted = NSRange(location: local.location + offsetInOriginal, length: local.length)
                    guard let r = Range(shifted, in: original),
                          let box = try? candidate.boundingBox(for: r) else { return nil }
                    return [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft]
                }
            ))
        }
        return (text, lines)
    }

    static func medianBodyLineHeight(_ observations: [VNRecognizedTextObservation]) -> CGFloat? {
        let heights = observations.compactMap { obs -> CGFloat? in
            guard let s = obs.topCandidates(1).first?.string else { return nil }
            let ja = s.unicodeScalars.filter { JapaneseText.isKana($0) || JapaneseText.isKanji($0) }.count
            return ja >= 4 ? obs.boundingBox.height : nil
        }.sorted()
        guard !heights.isEmpty else { return nil }
        return heights[heights.count / 2]
    }

    static func isCutOffNeighbor(_ box: CGRect, bodyHeight: CGFloat?) -> Bool {
        let edge: CGFloat = 0.005
        let touches = box.minX < edge || box.maxX > 1 - edge || box.minY < edge || box.maxY > 1 - edge
        guard touches, let body = bodyHeight, body > 0 else { return false }
        return box.height > body * 1.3 || box.height < body * 0.5
    }

    static func isContinuation(previous p: CGRect, next n: CGRect) -> Bool {
        let lineHeight = max(min(p.height, n.height), 1e-6)
        let gap = (p.minY - n.maxY) / lineHeight
        guard gap >= -3.5, gap <= 1.2 else { return false }
        guard p.maxX >= n.maxX - 1.5 * lineHeight else { return false }
        return n.minX <= p.minX + 2.5 * lineHeight
    }
}

enum JapaneseText {
    static func isKana(_ u: Unicode.Scalar) -> Bool {
        (0x3041...0x3096).contains(u.value) || (0x30A1...0x30FA).contains(u.value) || u.value == 0x30FC
    }

    static func isKanji(_ u: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(u.value) || u == "々" || u == "〆"
    }

    static func isForeign<S: StringProtocol>(_ s: S) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let kana = letters.filter(isKana).count
        let japanese = letters.filter { isKana($0) || isKanji($0) }.count
        if japanese == 0 { return true }
        return letters.count >= 4 && Double(kana) / Double(letters.count) < 0.05
    }

    private static let separators: Set<Character> = ["（", "）", "(", ")", "／", "/", "｜", "|", "：", ":"]

    static func maskForeignSegments(_ line: String) -> String {
        var out = ""
        var segment = ""
        func flush() {
            if isForeign(segment) {
                out += String(repeating: "　", count: (segment as NSString).length)
            } else {
                out += segment
            }
            segment = ""
        }
        for ch in line {
            if separators.contains(ch) {
                flush()
                out.append(ch)
            } else {
                segment.append(ch)
            }
        }
        flush()
        return out
    }
}
