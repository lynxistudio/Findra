import Foundation

final class SearchManager {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    func search(query: String, limit: Int = 10000) -> [IndexedFile] {
        // NSTextField can occasionally retain accessibility/input-method metadata after a line break.
        // Findra's query field is single-line, so search only the visible first line.
        let firstLine = query.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return dbManager.searchFiles(query: trimmed, limit: limit)
    }
}
