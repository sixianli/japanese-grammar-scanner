import Foundation

/// 收藏的语法点，保存在本地 UserDefaults。最近收藏的排在前面。
@MainActor
final class FavoritesStore: ObservableObject {
    private static let key = "favoriteGrammarIDs"
    private let defaults: UserDefaults

    @Published private(set) var ids: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = defaults.stringArray(forKey: Self.key) ?? []
    }

    func isFavorite(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if let idx = ids.firstIndex(of: id) {
            ids.remove(at: idx)
        } else {
            ids.insert(id, at: 0)
        }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        ids.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        ids.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// 同形语法合并后，把旧 id 换成新 id（去重、保持顺序）。
    func migrate(aliases: [String: String]) {
        guard ids.contains(where: { aliases[$0] != nil }) else { return }
        var seen = Set<String>()
        ids = ids.map { aliases[$0] ?? $0 }.filter { seen.insert($0).inserted }
        save()
    }

    private func save() {
        defaults.set(ids, forKey: Self.key)
    }
}
