import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// 找出照片中的书页并做透视校正（拍歪、斜拍的书页拉正后，文字识别更准）。完全在本机完成。
enum DocumentCorrector {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// 返回校正后的图片和书页四个角（Vision 归一化坐标：左下原点）。
    /// 没找到书页、书页太小或几乎已经是正的时返回 nil（直接用原图）。
    static func correct(_ image: CGImage) -> (CGImage, [CGPoint])? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let doc = request.results?.first, doc.confidence > 0.5 else { return nil }
        let quad = [doc.topLeft, doc.topRight, doc.bottomRight, doc.bottomLeft]
        // 书页至少占画面的 30%，否则可能是误检（例如书里的一个方框）
        guard polygonArea(quad) > 0.3 else { return nil }
        // 几乎是整张图且没有明显倾斜时，不需要校正
        if isNearlyFullFrame(quad) { return nil }

        let w = CGFloat(image.width), h = CGFloat(image.height)
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = px(doc.topLeft)
        filter.topRight = px(doc.topRight)
        filter.bottomRight = px(doc.bottomRight)
        filter.bottomLeft = px(doc.bottomLeft)
        guard let output = filter.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return (cg, quad)
    }

    private static func polygonArea(_ p: [CGPoint]) -> CGFloat {
        var a: CGFloat = 0
        for i in p.indices {
            let j = (i + 1) % p.count
            a += p[i].x * p[j].y - p[j].x * p[i].y
        }
        return abs(a) / 2
    }

    private static func isNearlyFullFrame(_ quad: [CGPoint]) -> Bool {
        let corners = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        return zip(quad, corners).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 0.04 }
    }
}
