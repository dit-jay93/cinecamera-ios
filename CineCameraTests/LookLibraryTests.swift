import XCTest
import simd
@testable import CinePipeline

final class LookLibraryTests: XCTestCase {

    private func tmpDir(_ name: String = #function) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinecamera-tests")
            .appendingPathComponent(name + "-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Look JSON round-trip preserves every metadata field + the embedded graph.
    func test_look_codableRoundTrip() throws {
        var graph = PipelineGraph()
        graph.whiteBalance = .init(targetKelvin: 4300, tint: 14)
        graph.cdl = CDLPresets.tealAndOrange.parameters
        graph.grain = .init(profile: FilmGrainProfiles.classicNegative,
                            iso: 1600, intensityMultiplier: 0.7, seed: 42)
        graph.filter = .init(filter: CinemaFilters.proMist1, intensity: 0.6)
        let look = Look(id: "test.look", name: "Test Look",
                        subtitle: "round trip", category: .cinematic,
                        graph: graph, lutReferenceId: "lut.identity",
                        creditedTo: "tester")

        let data = try JSONEncoder().encode(look)
        let decoded = try JSONDecoder().decode(Look.self, from: data)
        XCTAssertEqual(decoded, look)
    }

    // The library refuses duplicate ids on construction.
    func test_library_rejectsDuplicateOnInit() {
        let a = Look(id: "x", name: "A", category: .cinematic, graph: .identity)
        let b = Look(id: "x", name: "B", category: .stylized, graph: .identity)
        XCTAssertThrowsError(try LookLibrary(looks: [a, b])) { error in
            guard case LookLibraryError.duplicateId(let id) = error else {
                return XCTFail("expected duplicateId, got \(error)")
            }
            XCTAssertEqual(id, "x")
        }
    }

    // add() refuses duplicate; upsert() overwrites silently.
    func test_library_addVsUpsert() throws {
        var lib = try LookLibrary()
        let a = Look(id: "x", name: "A", category: .cinematic, graph: .identity)
        try lib.add(a)
        XCTAssertThrowsError(try lib.add(a))

        let b = Look(id: "x", name: "B", category: .stylized, graph: .identity)
        lib.upsert(b)
        XCTAssertEqual(lib.look(id: "x")?.name, "B")
        XCTAssertEqual(lib.look(id: "x")?.category, .stylized)
    }

    // remove() returns the dropped look.
    func test_library_remove() throws {
        var lib = try LookLibrary(looks: [
            Look(id: "x", name: "A", category: .cinematic, graph: .identity)
        ])
        XCTAssertEqual(lib.count, 1)
        XCTAssertNotNil(lib.remove(id: "x"))
        XCTAssertEqual(lib.count, 0)
        XCTAssertNil(lib.remove(id: "missing"))
    }

    // looks(in:) filters correctly; categories reports only present ones.
    func test_library_categoryFilter() throws {
        let lib = try LookLibrary(looks: [
            Look(id: "a", name: "A", category: .cinematic, graph: .identity),
            Look(id: "b", name: "B", category: .stylized,  graph: .identity),
            Look(id: "c", name: "C", category: .cinematic, graph: .identity)
        ])
        XCTAssertEqual(lib.looks(in: .cinematic).map { $0.id }, ["a", "c"])
        XCTAssertEqual(lib.looks(in: .stylized).map { $0.id },  ["b"])
        XCTAssertEqual(Set(lib.categories), Set([.cinematic, .stylized]))
    }

    // Disk save → load round-trips the entire library.
    func test_library_diskRoundTrip() throws {
        let lib = FactoryLooks.defaultLibrary()
        let dir = tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try lib.save(to: dir)
        let restored = try LookLibrary.load(from: dir)
        XCTAssertEqual(restored.count, lib.count)
        for look in lib.all {
            XCTAssertEqual(restored.look(id: look.id), look)
        }
    }

    // load() refuses a non-existent or non-directory path.
    func test_library_loadFromMissingDirectoryThrows() {
        let bogus = URL(fileURLWithPath: "/var/empty/cinecamera-not-a-dir-\(UUID().uuidString)")
        XCTAssertThrowsError(try LookLibrary.load(from: bogus))
    }

    // merge() respects the overwrite flag.
    func test_library_merge() throws {
        var base = try LookLibrary(looks: [
            Look(id: "a", name: "Base A", category: .cinematic, graph: .identity)
        ])
        let other = try LookLibrary(looks: [
            Look(id: "a", name: "Other A", category: .stylized,  graph: .identity),
            Look(id: "b", name: "Other B", category: .stylized,  graph: .identity)
        ])
        var merged = base
        merged.merge(other, overwrite: false)
        XCTAssertEqual(merged.look(id: "a")?.name, "Base A")
        XCTAssertEqual(merged.look(id: "b")?.name, "Other B")

        base.merge(other, overwrite: true)
        XCTAssertEqual(base.look(id: "a")?.name, "Other A")
    }

    // Factory catalog: ids are unique and every category has at least one look.
    func test_factory_idsAreUnique() {
        let ids = FactoryLooks.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate look ids: \(ids)")
    }

    func test_factory_coversEveryCategory() {
        let categories = Set(FactoryLooks.all.map { $0.category })
        for c in LookCategory.allCases {
            XCTAssertTrue(categories.contains(c), "missing factory look in category \(c)")
        }
    }

    func test_factory_atLeastTwelveLooks() {
        XCTAssertGreaterThanOrEqual(FactoryLooks.all.count, 12)
    }

    // Each factory look applies to a midtone pixel without producing NaN/Inf.
    func test_factory_appliesCleanly() {
        let probe = SIMD3<Float>(0.5, 0.5, 0.5)
        for look in FactoryLooks.all {
            let out = look.graph.applyPixel(probe)
            for c in [out.x, out.y, out.z] {
                XCTAssertFalse(c.isNaN, "NaN from \(look.id)")
                XCTAssertFalse(c.isInfinite, "Inf from \(look.id)")
            }
        }
    }

    // Per-tile apply works for at least one filter-bearing factory look
    // (exercises bloom + grain in combination).
    func test_factory_perTileExecutes() {
        let pixels = Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 16 * 16)
        let look = FactoryLooks.nightInTheCity
        let out = look.graph.applyTile(pixels, width: 16, height: 16, frame: 0)
        XCTAssertEqual(out.count, pixels.count)
        for v in out {
            XCTAssertFalse(v.x.isNaN)
        }
    }
}
