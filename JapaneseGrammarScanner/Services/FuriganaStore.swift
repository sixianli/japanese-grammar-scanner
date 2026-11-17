import Foundation

/// 预先离线生成的假名注音表（Resources/Grammar/furigana.json，由 tools/make_furigana.py 生成）。
/// 只收录含汉字的日语文本；每段文本被切成若干片段，汉字片段带读音。
final class FuriganaStore {
    struct Segment: Hashable {
        let base: String
        let ruby: String?
    }

    static let shared = FuriganaStore()

    private let table: [String: [Segment]]

    init(bundle: Bundle = .main) {
        var urls: [URL] = []
        for sub in [nil, "Grammar"] as [String?] {
            if let u = bundle.url(forResource: "furigana", withExtension: "json", subdirectory: sub) { urls.append(u) }
        }
        guard let url = urls.first,
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [[Any]]] else {
            table = [:]
            return
        }
        var t: [String: [Segment]] = [:]
        t.reserveCapacity(raw.count)
        for (text, segs) in raw {
            t[text] = segs.compactMap { pair in
                guard let base = pair.first as? String else { return nil }
                return Segment(base: base, ruby: pair.count > 1 ? pair[1] as? String : nil)
            }
        }
        table = t
    }

    /// 查不到（不含汉字或未收录）时返回整段无注音。
    func segments(for text: String) -> [Segment] {
        table[text] ?? [Segment(base: text, ruby: nil)]
    }

    func hasRuby(_ text: String) -> Bool {
        table[text]?.contains { $0.ruby != nil } ?? false
    }
}
