import CoreGraphics
import ImageIO
import Vision

/// 使用 Apple Vision 框架做端侧日文 OCR（不联网、不使用大模型）。
enum TextRecognizer {
    /// 识别图片中的文字，返回按阅读顺序拼好的整段文本和每一行的位置信息。
    static func recognize(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        fast: Bool = false
    ) throws -> (text: String, lines: [RecognizedLine]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate // 日文只在 accurate 模式下支持
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = !fast
        request.minimumTextHeight = fast ? 0.02 : 0

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return assemble(observations)
    }

    /// 把 Vision 返回的各行拼成一段文本。
    /// 日文没有空格，书本排版的换行是任意的，所以行与行直接相连；只有上一行以句末标点结尾时才插入换行。
    /// 这样跨行的语法（例如行尾“〜てし”、下一行“まった”）也能被识别出来。
    static func assemble(_ observations: [VNRecognizedTextObservation]) -> (text: String, lines: [RecognizedLine]) {
        var text = ""
        var lines: [RecognizedLine] = []
        let sentenceEnders: Set<Character> = ["。", "！", "？", "!", "?", "」", "』", "…"]

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let lineText = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !lineText.isEmpty else { continue }

            if let last = text.last, sentenceEnders.contains(last) {
                text += "\n"
            }
            let start = (text as NSString).length
            text += lineText
            let range = NSRange(location: start, length: (lineText as NSString).length)

            // trim 之后需要重新在原始字符串中定位
            let original = candidate.string
            let offsetInOriginal = (original as NSString).range(of: lineText).location

            lines.append(RecognizedLine(
                rangeInText: range,
                text: lineText,
                boundingBox: obs.boundingBox,
                boxForRange: { local in
                    let shifted = NSRange(location: local.location + offsetInOriginal, length: local.length)
                    guard let r = Range(shifted, in: original),
                          let box = try? candidate.boundingBox(for: r) else { return nil }
                    return box.boundingBox
                }
            ))
        }
        return (text, lines)
    }
}

extension TextRecognizer {
    /// 相机实时帧识别。
    static func recognize(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> (text: String, lines: [RecognizedLine]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])
        return assemble(request.results ?? [])
    }
}
