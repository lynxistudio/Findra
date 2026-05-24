import Foundation

final class SearchManager {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    func search(query: String, limit: Int = 500) -> [IndexedFile] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return dbManager.searchFiles(query: trimmed, limit: limit)
    }
}