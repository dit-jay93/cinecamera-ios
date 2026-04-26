import Foundation

public enum LookLibraryError: Error {
    case duplicateId(String)
    case notFound(String)
    case invalidDirectory(URL)
    case decodeFailed(URL, Error)
}

/// In-memory registry of looks, keyed by id, with optional disk persistence.
/// Each look on disk is a single `<id>.look.json` file in a chosen directory,
/// so users can drop new looks in by hand or sync them via iCloud Documents.
public struct LookLibrary {

    public private(set) var looks: [String: Look]

    public init(looks: [Look] = []) throws {
        var map: [String: Look] = [:]
        for look in looks {
            if map[look.id] != nil { throw LookLibraryError.duplicateId(look.id) }
            map[look.id] = look
        }
        self.looks = map
    }

    // MARK: - Reads

    public var all: [Look] {
        return looks.values.sorted { $0.id < $1.id }
    }

    public func look(id: String) -> Look? {
        return looks[id]
    }

    public func looks(in category: LookCategory) -> [Look] {
        return all.filter { $0.category == category }
    }

    public var count: Int { return looks.count }

    public var categories: [LookCategory] {
        return LookCategory.allCases.filter { cat in
            looks.values.contains { $0.category == cat }
        }
    }

    // MARK: - Mutations

    public mutating func add(_ look: Look) throws {
        if looks[look.id] != nil { throw LookLibraryError.duplicateId(look.id) }
        looks[look.id] = look
    }

    /// Insert or replace by id.
    public mutating func upsert(_ look: Look) {
        looks[look.id] = look
    }

    @discardableResult
    public mutating func remove(id: String) -> Look? {
        return looks.removeValue(forKey: id)
    }

    public mutating func merge(_ other: LookLibrary, overwrite: Bool = false) {
        for (id, look) in other.looks {
            if overwrite || looks[id] == nil { looks[id] = look }
        }
    }

    // MARK: - Disk I/O

    private static let fileSuffix = ".look.json"

    public func save(to directory: URL,
                     fileManager: FileManager = .default) throws {
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: directory.path, isDirectory: &isDir) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else if !isDir.boolValue {
            throw LookLibraryError.invalidDirectory(directory)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for look in looks.values {
            let url = directory.appendingPathComponent(look.id + LookLibrary.fileSuffix)
            let data = try encoder.encode(look)
            try data.write(to: url, options: .atomic)
        }
    }

    public static func load(from directory: URL,
                             fileManager: FileManager = .default) throws -> LookLibrary {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw LookLibraryError.invalidDirectory(directory)
        }
        let entries = try fileManager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        var looks: [Look] = []
        for url in entries where url.lastPathComponent.hasSuffix(fileSuffix) {
            let data = try Data(contentsOf: url)
            do {
                let look = try decoder.decode(Look.self, from: data)
                looks.append(look)
            } catch {
                throw LookLibraryError.decodeFailed(url, error)
            }
        }
        return try LookLibrary(looks: looks)
    }
}
