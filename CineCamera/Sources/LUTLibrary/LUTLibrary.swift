import Foundation

public enum LUTCategory: String, Codable, CaseIterable {
    case neutral
    case filmEmulation
    case displayTransform
    case stylized
    case userImported

    public var displayName: String {
        switch self {
        case .neutral:          return "Neutral"
        case .filmEmulation:    return "Film Emulation"
        case .displayTransform: return "Display Transform"
        case .stylized:         return "Stylized"
        case .userImported:     return "User Imported"
        }
    }
}

public enum LUTSourceFormat: String, Codable {
    case cube
    case threeDL
    case procedural
}

/// Catalog entry — pairs a `LUT3D` mesh with metadata. The mesh itself is
/// not `Codable` (it's potentially large and binary); persist looks by id
/// and re-resolve them through a `LUTLibrary` at apply time.
public struct LUTCatalogEntry: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let category: LUTCategory
    public let sourceFormat: LUTSourceFormat
    public let lut: LUT3D

    public init(id: String,
                name: String,
                category: LUTCategory,
                sourceFormat: LUTSourceFormat,
                lut: LUT3D) {
        self.id = id
        self.name = name
        self.category = category
        self.sourceFormat = sourceFormat
        self.lut = lut
    }
}

public enum LUTLibraryError: Error {
    case duplicateId(String)
    case notFound(String)
    case invalidDirectory(URL)
    case parseFailed(URL, Error)
}

/// In-memory registry of `LUTCatalogEntry`s keyed by id, with optional disk
/// scanning of `.cube` and `.3dl` files. The id used for a scanned file is
/// the filename without extension (e.g. `kodak_2383.cube` → `kodak_2383`).
public struct LUTLibrary {

    public private(set) var entries: [String: LUTCatalogEntry]

    public init(entries: [LUTCatalogEntry] = []) throws {
        var map: [String: LUTCatalogEntry] = [:]
        for entry in entries {
            if map[entry.id] != nil { throw LUTLibraryError.duplicateId(entry.id) }
            map[entry.id] = entry
        }
        self.entries = map
    }

    // MARK: - Reads

    public var all: [LUTCatalogEntry] {
        return entries.values.sorted { $0.id < $1.id }
    }

    public func entry(id: String) -> LUTCatalogEntry? {
        return entries[id]
    }

    public func lut(id: String) -> LUT3D? {
        return entries[id]?.lut
    }

    public func entries(in category: LUTCategory) -> [LUTCatalogEntry] {
        return all.filter { $0.category == category }
    }

    public var count: Int { return entries.count }

    public var categories: [LUTCategory] {
        return LUTCategory.allCases.filter { cat in
            entries.values.contains { $0.category == cat }
        }
    }

    // MARK: - Mutations

    public mutating func add(_ entry: LUTCatalogEntry) throws {
        if entries[entry.id] != nil { throw LUTLibraryError.duplicateId(entry.id) }
        entries[entry.id] = entry
    }

    public mutating func upsert(_ entry: LUTCatalogEntry) {
        entries[entry.id] = entry
    }

    @discardableResult
    public mutating func remove(id: String) -> LUTCatalogEntry? {
        return entries.removeValue(forKey: id)
    }

    // MARK: - Disk scan

    /// Scan a directory for `.cube` and `.3dl` files, parsing each into a
    /// `LUTCatalogEntry`. Recurses one level deep. Existing entries are
    /// preserved unless `overwrite` is true.
    @discardableResult
    public mutating func scan(directory: URL,
                               category: LUTCategory = .userImported,
                               overwrite: Bool = false,
                               fileManager: FileManager = .default) throws -> Int {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw LUTLibraryError.invalidDirectory(directory)
        }
        let urls = try fileManager.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil)
        var added = 0
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let format: LUTSourceFormat
            let lut: LUT3D
            switch ext {
            case "cube":
                format = .cube
                do { lut = try LUTParser.loadCube(at: url) }
                catch { throw LUTLibraryError.parseFailed(url, error) }
            case "3dl":
                format = .threeDL
                do { lut = try LUTParser.load3DL(at: url) }
                catch { throw LUTLibraryError.parseFailed(url, error) }
            default:
                continue
            }
            let id = url.deletingPathExtension().lastPathComponent
            if !overwrite, entries[id] != nil { continue }
            let entry = LUTCatalogEntry(id: id,
                                        name: lut.title ?? id,
                                        category: category,
                                        sourceFormat: format,
                                        lut: lut)
            entries[id] = entry
            added += 1
        }
        return added
    }
}
