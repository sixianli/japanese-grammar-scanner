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
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = config == "jaOnly" ? ["ja-JP"] : ["ja-JP", "en-US"]
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: input, options: [:]).perform([request])
                let observations = request.results ?? []
                let lines: [[String: Any]] = observations.compactMap { obs in
                    guard let c = obs.topCandidates(1).first else { return nil }
                    let b = obs.boundingBox
                    return ["text": c.string, "confidence": c.confidence,
                            "box": [b.minX, b.minY, b.width, b.height].map { Double($0) }]
                }
                let assembled = TextRecognizer.assemble(observations)
                let result = ScanAnalyzer.analyze(text: assembled.text, lines: assembled.lines, matcher: matcher)
                // 高亮框：Vision 能给出逐字位置的算「精确」，拿不到时按字数比例估算的算「估算」
                var exact = 0, estimated = 0
                for cluster in result.clusters {
                    for line in assembled.lines {
                        let overlap = NSIntersectionRange(cluster.range, line.rangeInText)
                        guard overlap.length > 0 else { continue }
                        let local = NSRange(location: overlap.location - line.rangeInText.location, length: overlap.length)
                        if line.boxForRange(local) != nil { exact += 1 } else { estimated += 1 }
                    }
                }
                let boxes: [[String: Any]] = result.boxes.map { box in
                    let ids = result.clusters.first { $0.id == box.clusterID }?.grammarIDs ?? []
                    return ["grammar": ids, "rect": [box.rect.minX, box.rect.minY, box.rect.width, box.rect.height].map { Double($0) }]
                }
                var entry: [String: Any] = [
                    "boxStats": ["exact": exact, "estimated": estimated],
                    "boxes": boxes,
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
}
