import XCTest
import simd
@testable import CinePipeline

final class LUTLibraryTests: XCTestCase {

    private func tmpDir(_ name: String = #function) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinecamera-lut-tests")
            .appendingPathComponent(name + "-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func approx(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float = 1e-3) -> Bool {
        return abs(a.x - b.x) < accuracy && abs(a.y - b.y) < accuracy && abs(a.z - b.z) < accuracy
    }

    // Unique-id enforcement.
    func test_library_rejectsDuplicateOnInit() throws {
        let lut = LUT3D.identity(size: 9)
        let a = LUTCatalogEntry(id: "x", name: "A", category: .neutral,
                                 sourceFormat: .procedural, lut: lut)
        let b = LUTCatalogEntry(id: "x", name: "B", category: .stylized,
                                 sourceFormat: .procedural, lut: lut)
        XCTAssertThrowsError(try LUTLibrary(entries: [a, b]))
    }

    // add/upsert/remove primitives.
    func test_library_mutations() throws {
        var lib = try LUTLibrary()
        let lut = LUT3D.identity(size: 9)
        let a = LUTCatalogEntry(id: "x", name: "A", category: .neutral,
                                 sourceFormat: .procedural, lut: lut)
        try lib.add(a)
        XCTAssertThrowsError(try lib.add(a))

        let b = LUTCatalogEntry(id: "x", name: "B", category: .stylized,
                                 sourceFormat: .procedural, lut: lut)
        lib.upsert(b)
        XCTAssertEqual(lib.entry(id: "x")?.name, "B")
        XCTAssertEqual(lib.entry(id: "x")?.category, .stylized)

        XCTAssertNotNil(lib.remove(id: "x"))
        XCTAssertNil(lib.remove(id: "x"))
    }

    // Category filter and presence reporting.
    func test_library_categories() throws {
        let lut = LUT3D.identity(size: 9)
        let a = LUTCatalogEntry(id: "a", name: "A", category: .neutral,
                                 sourceFormat: .procedural, lut: lut)
        let b = LUTCatalogEntry(id: "b", name: "B", category: .stylized,
                                 sourceFormat: .procedural, lut: lut)
        let c = LUTCatalogEntry(id: "c", name: "C", category: .neutral,
                                 sourceFormat: .procedural, lut: lut)
        let lib = try LUTLibrary(entries: [a, b, c])
        XCTAssertEqual(lib.entries(in: .neutral).map { $0.id }, ["a", "c"])
        XCTAssertEqual(lib.entries(in: .stylized).map { $0.id }, ["b"])
        XCTAssertEqual(Set(lib.categories), Set([.neutral, .stylized]))
    }

    // Disk scan: write two LUTs to a directory, scan, verify ids and content.
    func test_library_directoryScan() throws {
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lutA = LUT3D.identity(size: 9)
        let lutB = LUTBaker.bake(cdl: CDLPresets.bleachBypass.parameters,
                                  size: 9, title: "Bleach")
        try LUTParser.saveCube(lutA, to: dir.appendingPathComponent("identity_test.cube"))
        try LUTParser.saveCube(lutB, to: dir.appendingPathComponent("bleach_test.cube"))

        var lib = try LUTLibrary()
        let added = try lib.scan(directory: dir, category: .userImported)
        XCTAssertEqual(added, 2)
        XCTAssertNotNil(lib.lut(id: "identity_test"))
        XCTAssertNotNil(lib.lut(id: "bleach_test"))
        XCTAssertEqual(lib.entry(id: "identity_test")?.category, .userImported)

        // Re-scan without overwrite must skip existing ids.
        let again = try lib.scan(directory: dir, overwrite: false)
        XCTAssertEqual(again, 0)
    }

    // Scanning a missing directory throws invalidDirectory.
    func test_library_scanMissingDirThrows() {
        var lib = try! LUTLibrary()
        let bogus = URL(fileURLWithPath: "/var/empty/cinecamera-no-such-dir-\(UUID().uuidString)")
        XCTAssertThrowsError(try lib.scan(directory: bogus))
    }

    // Factory LUTs: ids unique, every category has at least one entry.
    func test_factoryLUTs_idsUniqueAndCategoriesCovered() {
        let ids = FactoryLUTs.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        let cats = Set(FactoryLUTs.all.map { $0.category })
        XCTAssertTrue(cats.contains(.neutral))
        XCTAssertTrue(cats.contains(.filmEmulation))
        XCTAssertTrue(cats.contains(.stylized))
        XCTAssertTrue(cats.contains(.displayTransform))
    }

    // Identity factory LUT must round-trip a sampled point unchanged.
    func test_factoryIdentity_isPassthrough() {
        let lut = FactoryLUTs.identity.lut
        let probe = SIMD3<Float>(0.42, 0.13, 0.77)
        XCTAssertTrue(approx(lut.sample(probe), probe, accuracy: 1e-3))
    }

    // sRGB encode is monotonic and pushes 0.5 well above linear (~0.735).
    func test_factorySRGB_encodesMidGreyHigher() {
        let out = FactoryLUTs.srgbEncode.lut.sample(SIMD3<Float>(0.5, 0.5, 0.5))
        XCTAssertEqual(out.x, 0.7354, accuracy: 0.02)
        XCTAssertEqual(out.y, 0.7354, accuracy: 0.02)
        XCTAssertEqual(out.z, 0.7354, accuracy: 0.02)
    }

    // Resolver: a look with no LUT id returns the graph untouched.
    func test_resolver_noLutReferenceIsPassthrough() throws {
        let look = FactoryLooks.kodakVisionDay
        XCTAssertNil(look.lutReferenceId)
        let lib = FactoryLUTs.defaultLibrary()
        let graph = try LookResolver.resolve(look, in: lib)
        XCTAssertNil(graph.lut)
    }

    // Resolver: missing LUT id throws in strict mode, returns graph in lax mode.
    func test_resolver_missingLutBehavior() throws {
        var look = FactoryLooks.kodakVisionDay
        look.lutReferenceId = "factory.does_not_exist"
        let lib = FactoryLUTs.defaultLibrary()
        XCTAssertThrowsError(try LookResolver.resolve(look, in: lib, strict: true))
        let graph = try LookResolver.resolve(look, in: lib, strict: false)
        XCTAssertNil(graph.lut)
    }

    // Resolver: a look with a valid LUT id ends up with the LUT mesh wired in.
    func test_resolver_populatesLUTStage() throws {
        var look = FactoryLooks.kodakVisionDay
        look.lutReferenceId = FactoryLUTs.tealAndOrange.id
        let lib = FactoryLUTs.defaultLibrary()
        let graph = try LookResolver.resolve(look, in: lib,
                                              amount: 0.7,
                                              interpolation: .tetrahedral)
        XCTAssertNotNil(graph.lut)
        XCTAssertEqual(graph.lut?.amount ?? 0, Float(0.7), accuracy: 1e-6)
        XCTAssertEqual(graph.lut?.interpolation, .tetrahedral)
        XCTAssertEqual(graph.lut?.lut.size, FactoryLUTs.tealAndOrange.lut.size)
    }

    // Save a Look (which has a lutReferenceId) → JSON → load → resolve →
    // applying produces the same pixel as resolving the in-memory original.
    func test_lookJsonRoundTrip_thenResolveApplies() throws {
        var look = FactoryLooks.bleachBypass
        look.lutReferenceId = FactoryLUTs.bleachBypass.id

        let data = try JSONEncoder().encode(look)
        let decoded = try JSONDecoder().decode(Look.self, from: data)
        XCTAssertEqual(decoded.lutReferenceId, look.lutReferenceId)

        let lib = FactoryLUTs.defaultLibrary()
        let probe = SIMD3<Float>(0.4, 0.5, 0.6)

        let direct  = try LookResolver.resolve(look,    in: lib).applyPixel(probe)
        let restored = try LookResolver.resolve(decoded, in: lib).applyPixel(probe)
        XCTAssertTrue(approx(direct, restored, accuracy: 1e-5))
    }
}
