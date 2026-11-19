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

    /// 把 Vision 的各行拼成一段文字，用于语法匹配：
    /// - 同一段落里因为排版折行的句子接起来；标题、列表项、不同段落之间换行，语法规则不会跨行误匹配
    ///   （例如标题「〜とは限らない」和下一行「意味）〜が…」被连成「は限らない意味）〜が」而命中「〜は〜が〜」）；
    /// - 几乎没有假名的行（中文、英文、越南文、韩文释义）不参与匹配；行内的外文片段用空白替换（保持位置不变，框不会错位）。
    /// 规则在 95 张实拍照片上评测过，见 docs/ocr-eval/runs/。
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

            // trim 之后需要重新在原始字符串中定位
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

    /// 正文行的典型行高（至少 4 个日文字的行的中位数）
    static func medianBodyLineHeight(_ observations: [VNRecognizedTextObservation]) -> CGFloat? {
        let heights = observations.compactMap { obs -> CGFloat? in
            guard let s = obs.topCandidates(1).first?.string else { return nil }
            let ja = s.unicodeScalars.filter { JapaneseText.isKana($0) || JapaneseText.isKanji($0) }.count
            return ja >= 4 ? obs.boundingBox.height : nil
        }.sorted()
        guard !heights.isEmpty else { return nil }
        return heights[heights.count / 2]
    }

    /// 邻页入镜：贴着照片边缘被截断、字号又明显和正文不同的行（多半是旁边另一页或另一本书），不参与识别
    static func isCutOffNeighbor(_ box: CGRect, bodyHeight: CGFloat?) -> Bool {
        let edge: CGFloat = 0.005
        let touches = box.minX < edge || box.maxX > 1 - edge || box.minY < edge || box.maxY > 1 - edge
        guard touches, let body = bodyHeight, body > 0 else { return false }
        return box.height > body * 1.3 || box.height < body * 0.5
    }

    /// 下一行是不是上一行的折行续写（Vision 归一化坐标，原点在左下角）：
    /// 两行上下相邻（斜拍时行框会互相重叠，允许重叠）、上一行基本写满（右端不比下一行短太多）、下一行没有明显缩进。
    static func isContinuation(previous p: CGRect, next n: CGRect) -> Bool {
        let lineHeight = max(min(p.height, n.height), 1e-6)
        let gap = (p.minY - n.maxY) / lineHeight
        guard gap >= -3.5, gap <= 1.2 else { return false }
        guard p.maxX >= n.maxX - 1.5 * lineHeight else { return false }
        return n.minX <= p.minX + 2.5 * lineHeight
    }
}

/// 判断文字是不是日文（用于排除教材里的中文、英文等释义）
enum JapaneseText {
    static func isKana(_ u: Unicode.Scalar) -> Bool {
        (0x3041...0x3096).contains(u.value) || (0x30A1...0x30FA).contains(u.value) || u.value == 0x30FC
    }

    static func isKanji(_ u: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(u.value) || u == "々" || u == "〆"
    }

    /// 非日文：没有任何假名和汉字（英文、韩文、越南文等），或者 4 个字以上却几乎没有假名（中文）
    static func isForeign<S: StringProtocol>(_ s: S) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let kana = letters.filter(isKana).count
        let japanese = letters.filter { isKana($0) || isKanji($0) }.count
        if japanese == 0 { return true }
        return letters.count >= 4 && Double(kana) / Double(letters.count) < 0.05
    }

    private static let separators: Set<Character> = ["（", "）", "(", ")", "／", "/", "｜", "|", "：", ":"]

    /// 行内的外文片段（如「夜市：night market／夜市／야시장」里的英文、韩文）换成等长的全角空格，
    /// 保证每个字在整行里的位置不变（高亮框按位置定位）
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
