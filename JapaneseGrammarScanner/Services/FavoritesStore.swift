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

    private func save() {
        defaults.set(ids, forKey: Self.key)
    }
}
