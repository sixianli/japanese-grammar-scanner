import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// 照片里「墨迹」的分布图：字的笔画为白、纸面为黑（灰度图）。
///
/// 识别结果页不再画框，而是把语法所在的那几个字直接染成主题色：
/// 用这张图当遮罩，只有笔画会被染色，纸面保持原样（纸面上再垫一层淡淡的荧光笔底色）。
/// 纸面明暗不均（阴影、弯页）时，按每处附近最亮的纸色做基准，所以阴影里的字也能染上。
enum InkMask {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func make(from image: CGImage, maxSide: CGFloat = 1600) -> CGImage? {
        var input = CIImage(cgImage: image)
        let longest = max(input.extent.width, input.extent.height)
        if longest > maxSide {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = input
            f.scale = Float(maxSide / longest)
            f.aspectRatio = 1
            guard let scaled = f.outputImage else { return nil }
            input = scaled
        }
        let extent = input.extent

        // 灰度
        let mono = CIFilter.colorControls()
        mono.inputImage = input
        mono.saturation = 0
        guard let gray = mono.outputImage else { return nil }

        // 附近的纸色：局部最大值（半径约为一个字高）
        let paper = CIFilter.morphologyMaximum()
        paper.inputImage = gray.clampedToExtent()
        paper.radius = Float(max(extent.width, extent.height) / 100)
        guard let background = paper.outputImage?.cropped(to: extent) else { return nil }

        // 比纸色暗多少：纸色 − 灰度
        let diff = CIFilter.subtractBlendMode()
        diff.inputImage = gray
        diff.backgroundImage = background
        guard let darker = diff.outputImage else { return nil }

        // 放大并去掉纸面上的细微起伏：(差值 − 0.025) × 2.5，夹到 0…1，再稍微加粗笔画
        let scale = CIFilter.colorMatrix()
        scale.inputImage = darker
        let k: CGFloat = 2.5
        scale.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
        scale.gVector = CIVector(x: k, y: 0, z: 0, w: 0)
        scale.bVector = CIVector(x: k, y: 0, z: 0, w: 0)
        scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        scale.biasVector = CIVector(x: -0.025 * k, y: -0.025 * k, z: -0.025 * k, w: 0)
        guard let stretched = scale.outputImage else { return nil }
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = stretched
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = clamp.outputImage
        gamma.power = 0.8
        guard let ink = gamma.outputImage?.cropped(to: extent) else { return nil }

        return context.createCGImage(ink, from: extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }
}
