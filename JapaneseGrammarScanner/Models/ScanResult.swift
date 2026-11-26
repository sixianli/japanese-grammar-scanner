import CoreGraphics
import Foundation

struct GrammarMatch: Hashable {
    let grammarID: String
    let range: NSRange
}

struct HighlightCluster: Identifiable, Hashable {
    let id: Int
    let range: NSRange
    let grammarIDs: [String]
    var ranges: [NSRange] = []
    var matchedTexts: [String: String] = [:]

    init(id: Int, range: NSRange, grammarIDs: [String], ranges: [NSRange] = [], matchedTexts: [String: String] = [:]) {
        self.id = id
        self.range = range
        self.grammarIDs = grammarIDs
        self.ranges = ranges.isEmpty ? [range] : ranges
        self.matchedTexts = matchedTexts
    }

    func excerpt(for id: String) -> String? {
        guard let t = matchedTexts[id]?.replacingOccurrences(of: "\n", with: "") else { return nil }
        guard t.count > 12 else { return t }
        return String(t.prefix(5)) + "…" + String(t.suffix(5))
    }
}

struct RecognizedLine {
    let rangeInText: NSRange
    let text: String
    let boundingBox: CGRect
    let boxForRange: (NSRange) -> CGRect?
    var quad: [CGPoint] = []
    var quadForRange: (NSRange) -> [CGPoint]? = { _ in nil }
    var band: TextBand? = nil
}

struct HighlightBox: Identifiable, Hashable {
    let id: UUID
    let clusterID: Int
    let rect: CGRect
    let quad: [CGPoint]
    var source: (line: Int, range: NSRange)? = nil

    init(id: UUID = UUID(), clusterID: Int, rect: CGRect, quad: [CGPoint]? = nil, source: (line: Int, range: NSRange)? = nil) {
        self.id = id
        self.source = source
        self.clusterID = clusterID
        self.rect = rect
        self.quad = quad ?? [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                             CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
    static func == (a: HighlightBox, b: HighlightBox) -> Bool {
        a.id == b.id && a.clusterID == b.clusterID && a.rect == b.rect && a.quad == b.quad
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(clusterID)
    }
}

struct ScanResult {
    let text: String
    let matches: [GrammarMatch]
    let clusters: [HighlightCluster]
    var boxes: [HighlightBox]
    var pageIsCurved = false

    static let empty = ScanResult(text: "", matches: [], clusters: [], boxes: [])

    func matchedText(for id: String) -> String? {
        guard let m = matches.first(where: { $0.grammarID == id }), NSMaxRange(m.range) <= (text as NSString).length else { return nil }
        return (text as NSString).substring(with: m.range)
    }

    var orderedGrammarIDs: [String] {
        var seen = Set<String>()
        return matches.sorted { $0.range.location < $1.range.location }
            .compactMap { seen.insert($0.grammarID).inserted ? $0.grammarID : nil }
    }
}
