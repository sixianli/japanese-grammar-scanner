import SwiftUI

/// 全屏查看识别结果图片：双指缩放、拖动平移、双击放大/还原；高亮框随图片一起缩放，点击可查看讲解。
struct ZoomableScanView: View {
    let image: UIImage
    let result: ScanResult
    let library: GrammarLibrary
    let onSelect: (HighlightCluster) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        HighlightOverlay(
                            result: result,
                            imageSize: image.size,
                            fit: .fit,
                            library: library,
                            lineWidth: 1.2 / scale,
                            showsCountBadge: scale < 2.5
                        ) { cluster in
                            onSelect(cluster)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in scale = min(8, max(1, lastScale * value.magnification)) }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale <= 1.01 { withAnimation { reset() } }
                                },
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1 else { return }
                                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut) {
                            if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
            }
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel(Text("关闭"))
            .padding()

            VStack {
                Spacer()
                Text("双指缩放查看原文，点击高亮查看讲解")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}
