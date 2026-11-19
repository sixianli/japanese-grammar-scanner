import CoreImage
import UIKit
import Vision
import XCTest
@testable import JapaneseGrammarScanner

/// 识别准确度评测（只在 CI 的 ocr-eval 任务中运行）：
/// 对 tests/ocr/samples 下的真实照片跑 Vision 文字识别，把原始结果（每一行的文字、位置、置信度）
/// 和当前流程识别出的语法点写成 JSON，供离线对比不同改进方案。
/// 通过环境变量 TEST_RUNNER_OCR_SAMPLES / TEST_RUNNER_OCR_OUT 指定目录；未设置时跳过。
final class OCREvalTests: XCTestCase {
    func testDumpRecognitionResults() throws {
        let env = ProcessInfo.processInfo.environment
        guard let samples = env["OCR_SAMPLES"], let outDir = env["OCR_OUT"] else {
            throw XCTSkip("未设置 OCR_SAMPLES / OCR_OUT")
        }
        let fm = FileManager.default
        try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let files = try fm.contentsOfDirectory(atPath: samples).filter { $0.lowercased().hasSuffix(".jpg") }.sorted()
        let configs = (env["OCR_CONFIGS"] ?? "base,corrected").split(separator: ",").map(String.init)
        let matcher = GrammarLibrary.shared.matcher

        for file in files {
            guard let image = UIImage(contentsOfFile: (samples as NSString).appendingPathComponent(file))?.normalizedForOCR(),
                  let cg = image.cgImage else { continue }
            var record: [String: Any] = ["file": file, "width": cg.width, "height": cg.height]
            for config in configs {
                let start = Date()
                var input = cg
                var corners: [[Double]]? = nil
                if config == "corrected", let (corrected, quad) = DocumentCorrector.correct(cg) {
                    input = corrected
                    corners = quad.map { [Double($0.x), Double($0.y)] }
                }
                if config == "tiled" {
                    // 分块识别试验：整页 + 2×2 重叠分块，合并去重后输出各行（只评测文字与语法，不出框）
                    let merged = try Self.tiledLines(input)
                    record[config] = [
                        "lines": merged.map { ["text": $0.text, "confidence": $0.confidence,
                                               "box": [$0.box.minX, $0.box.minY, $0.box.width, $0.box.height].map { Double($0) }] },
                        "seconds": Date().timeIntervalSince(start),
                    ] as [String: Any]
                    continue
                }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = config == "jaOnly" ? ["ja-JP"] : ["ja-JP", "en-US"]
                request.usesLanguageCorrection = config == "lc"  // 与 App 一致默认关闭；lc：打开语言纠错做对比
                try VNImageRequestHandler(cgImage: input, options: [:]).perform([request])
                let observations = request.results ?? []
                let lines: [[String: Any]] = observations.compactMap { obs in
                    guard let c = obs.topCandidates(1).first else { return nil }
                    let b = obs.boundingBox
                    // quad：Vision 给出的整行四边形（左上原点，左上、右上、右下、左下），用来检查框的高度是否贴字
                    let quad = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft].flatMap { [Double($0.x), Double(1 - $0.y)] }
                    return ["text": c.string, "confidence": c.confidence,
                            "box": [b.minX, b.minY, b.width, b.height].map { Double($0) }, "quad": quad]
                }
                var assembled = TextRecognizer.assemble(observations)
                TextBandFinder.refine(&assembled.lines, image: input)
                let result = ScanAnalyzer.analyze(text: assembled.text, lines: assembled.lines, matcher: matcher)
                // 高亮框：采用 Vision 逐字位置的算「精确」；Vision 拿不到的算「估算」；拿到但和等宽估算明显不一致而被弃用的算「弃用」
                var exact = 0, estimated = 0, rejected = 0
                for cluster in result.clusters {
                    for line in assembled.lines {
                        let overlap = NSIntersectionRange(cluster.range, line.rangeInText)
                        guard overlap.length > 0 else { continue }
                        let local = NSRange(location: overlap.location - line.rangeInText.location, length: overlap.length)
                        if line.boxForRange(local) == nil {
                            estimated += 1
                        } else if ScanAnalyzer.substringBox(line: line, local: local) == ScanAnalyzer.estimatedBox(line: line, local: local) {
                            rejected += 1
                        } else {
                            exact += 1
                        }
                    }
                }
                let boxes: [[String: Any]] = result.boxes.map { box in
                    let ids = result.clusters.first { $0.id == box.clusterID }?.grammarIDs ?? []
                    return ["grammar": ids, "cluster": box.clusterID,
                            "rect": [box.rect.minX, box.rect.minY, box.rect.width, box.rect.height].map { Double($0) },
                            "quad": box.quad.flatMap { [Double($0.x), Double($0.y)] }]
                }
                // 高亮块：包含的语法点、每个语法点命中的原文、实际框出的片段
                let clusters: [[String: Any]] = result.clusters.map { c in
                    ["id": c.id, "grammar": c.grammarIDs, "matched": c.matchedTexts,
                     "segments": c.ranges.map { (assembled.text as NSString).substring(with: $0) }]
                }
                var entry: [String: Any] = [
                    "boxStats": ["exact": exact, "estimated": estimated, "rejected": rejected],
                    "boxes": boxes,
                    "clusters": clusters,
                    "lines": lines,
                    "text": assembled.text,
                    "grammar": result.orderedGrammarIDs,
                    "seconds": Date().timeIntervalSince(start),
                ]
                if let corners { entry["documentQuad"] = corners }
                record[config] = entry
            }
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            let name = (file as NSString).deletingPathExtension + ".json"
            try data.write(to: URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(name)))
        }
    }

    struct Line { var text: String; var confidence: Float; var box: CGRect }

    /// 整页识别一次，再把图片切成 2×2 有重叠的块分别识别；块里识别出、整页漏掉的行补进来。
    /// 坐标统一换算到整张图的 Vision 归一化坐标（原点左下）。
    static func tiledLines(_ image: CGImage) throws -> [Line] {
        func recognize(_ img: CGImage) throws -> [Line] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: img, options: [:]).perform([request])
            return (request.results ?? []).compactMap { obs in
                guard let c = obs.topCandidates(1).first else { return nil }
                return Line(text: c.string, confidence: c.confidence, box: obs.boundingBox)
            }
        }
        var lines = try recognize(image)
        let W = CGFloat(image.width), H = CGFloat(image.height)
        let overlap: CGFloat = 0.12
        for row in 0..<2 {
            for col in 0..<2 {
                // 像素坐标（原点左上）
                let x0 = max(0, CGFloat(col) * 0.5 - overlap / 2) * W
                let x1 = min(1, CGFloat(col) * 0.5 + 0.5 + overlap / 2) * W
                let y0 = max(0, CGFloat(row) * 0.5 - overlap / 2) * H
                let y1 = min(1, CGFloat(row) * 0.5 + 0.5 + overlap / 2) * H
                let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).integral
                guard let tile = image.cropping(to: rect) else { continue }
                for var l in try recognize(tile) {
                    // 块内归一化（原点左下）→ 整图归一化（原点左下）
                    let bx = (rect.minX + l.box.minX * rect.width) / W
                    let byTop = rect.minY + (1 - l.box.maxY) * rect.height // 像素，原点左上
                    let bh = l.box.height * rect.height / H
                    l.box = CGRect(x: bx, y: 1 - byTop / H - bh, width: l.box.width * rect.width / W, height: bh)
                    // 和已有的行明显重叠就视为同一行：保留字数多的
                    if let i = lines.firstIndex(where: { overlapRatio($0.box, l.box) > 0.3 }) {
                        if l.text.count > lines[i].text.count + 1, !touchesTileEdge(l.box, rect, W, H) { lines[i] = l }
                    } else if !touchesTileEdge(l.box, rect, W, H) {
                        lines.append(l)
                    }
                }
            }
        }
        // 按从上到下、从左到右排序（Vision 的整页顺序在合并后不再适用）
        return lines.sorted { a, b in
            let h = min(a.box.height, b.box.height)
            if abs(a.box.midY - b.box.midY) > h * 0.6 { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }
    }

    /// 被块的边界截断的行不可信（字被切掉一半）
    static func touchesTileEdge(_ box: CGRect, _ tile: CGRect, _ W: CGFloat, _ H: CGFloat) -> Bool {
        let e: CGFloat = 4
        let px = box.minX * W, px2 = box.maxX * W
        let pyTop = (1 - box.maxY) * H, pyBottom = (1 - box.minY) * H
        return (px - tile.minX < e && tile.minX > 0) || (tile.maxX - px2 < e && tile.maxX < W)
            || (pyTop - tile.minY < e && tile.minY > 0) || (tile.maxY - pyBottom < e && tile.maxY < H)
    }

    /// 交集占较小框的比例
    static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? (i.width * i.height) / smaller : 0
    }
}
