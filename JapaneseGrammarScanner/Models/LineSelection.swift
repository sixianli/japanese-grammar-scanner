import CoreGraphics
import Foundation

enum LineSelection {
    static func analyzesRightAway(lineCount: Int) -> Bool {
        lineCount <= 2
    }

    static func lineQuads(_ lines: [RecognizedLine]) -> [[CGPoint]] {
        lines.map { line in
            let box = line.boundingBox
            let quad = line.quad.count == 4 ? line.quad
                : [CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY),
                   CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.minY)]
            return ScanAnalyzer.flip(ScanAnalyzer.bandFitted(quad, line: line) ?? quad)
        }
    }

    static func line(at point: CGPoint, quads: [[CGPoint]], slack: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (i, q) in quads.enumerated() where q.count == 4 {
            let a = mid(q[0], q[3]), b = mid(q[1], q[2])
            let half = max(distance(q[0], q[3]), distance(q[1], q[2])) / 2
            let d = distanceToSegment(point, a, b)
            guard d <= half + slack else { continue }
            if best == nil || d < best!.distance { best = (i, d) }
        }
        return best?.index
    }

    static func span(from a: Int, to b: Int) -> Set<Int> {
        Set(min(a, b)...max(a, b))
    }

    static func outlines(selected: Set<Int>, quads: [[CGPoint]], pad: CGFloat) -> [[CGPoint]] {
        let sorted = selected.filter { quads.indices.contains($0) && quads[$0].count == 4 }.sorted()
        var groups: [[Int]] = []
        for i in sorted {
            if let last = groups.last?.last, last == i - 1, adjacent(quads[last], quads[i]) {
                groups[groups.count - 1].append(i)
            } else {
                groups.append([i])
            }
        }
        return groups.map { group in
            let first = quads[group[0]]
            let d = unit(sub(first[1], first[0]), fallback: CGPoint(x: 1, y: 0))
            let n = CGPoint(x: -d.y, y: d.x)
            let points = group.flatMap { quads[$0] }
            let along = points.map { dot($0, d) }, across = points.map { dot($0, n) }
            let a0 = along.min()! - pad, a1 = along.max()! + pad
            let c0 = across.min()! - pad, c1 = across.max()! + pad
            func p(_ a: CGFloat, _ c: CGFloat) -> CGPoint { CGPoint(x: d.x * a + n.x * c, y: d.y * a + n.y * c) }
            return [p(a0, c0), p(a1, c0), p(a1, c1), p(a0, c1)]
        }
    }

    private static func adjacent(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        let d = unit(sub(a[1], a[0]), fallback: CGPoint(x: 1, y: 0))
        let n = CGPoint(x: -d.y, y: d.x)
        let height = max(distance(a[0], a[3]), distance(b[0], b[3]), 0.0001)
        let gap = abs(dot(center(b), n) - dot(center(a), n))
        let ra = (a.map { dot($0, d) }.min()!, a.map { dot($0, d) }.max()!)
        let rb = (b.map { dot($0, d) }.min()!, b.map { dot($0, d) }.max()!)
        return gap <= 2.5 * height && min(ra.1, rb.1) > max(ra.0, rb.0)
    }

    private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    private static func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func center(_ q: [CGPoint]) -> CGPoint {
        CGPoint(x: q.map(\.x).reduce(0, +) / CGFloat(q.count), y: q.map(\.y).reduce(0, +) / CGFloat(q.count))
    }
    private static func unit(_ p: CGPoint, fallback: CGPoint) -> CGPoint {
        let len = hypot(p.x, p.y)
        return len > 0.000001 ? CGPoint(x: p.x / len, y: p.y / len) : fallback
    }
    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = sub(b, a)
        let len2 = dot(ab, ab)
        guard len2 > 0 else { return distance(p, a) }
        let t = min(max(dot(sub(p, a), ab) / len2, 0), 1)
        return distance(p, CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t))
    }
}

extension ScanResult {
    func limited(toLines selected: Set<Int>, of lines: [RecognizedLine]) -> ScanResult {
        let ranges = selected.filter { lines.indices.contains($0) }.map { lines[$0].rangeInText }
        func touches(_ r: NSRange) -> Bool { ranges.contains { NSIntersectionRange($0, r).length > 0 } }
        let kept = matches.filter { touches($0.range) }
        let keptClusters: [HighlightCluster] = clusters.compactMap { cluster in
            let ids = cluster.grammarIDs.filter { id in
                kept.contains { $0.grammarID == id && NSIntersectionRange($0.range, cluster.range).length > 0 }
            }
            guard !ids.isEmpty else { return nil }
            return HighlightCluster(id: cluster.id, range: cluster.range, grammarIDs: ids, ranges: cluster.ranges,
                                    matchedTexts: cluster.matchedTexts.filter { ids.contains($0.key) })
        }
        let clusterIDs = Set(keptClusters.map(\.id))
        let keptBoxes = boxes.filter { box in
            guard clusterIDs.contains(box.clusterID), let source = box.source else { return false }
            return selected.contains(source.line)
        }
        var result = ScanResult(text: text, matches: kept, clusters: keptClusters, boxes: keptBoxes)
        result.pageIsCurved = pageIsCurved
        return result
    }
}
