import XCTest
@testable import CinePipeline

final class NDRecommenderTests: XCTestCase {

    // pickFilter: 0 stops → none.
    func test_pickFilter_zero() {
        XCTAssertEqual(NDRecommender.pickFilter(forStops: 0), .none)
    }

    // 0.99 stops → none (rounds down).
    func test_pickFilter_underOne() {
        XCTAssertEqual(NDRecommender.pickFilter(forStops: 0.99), .none)
    }

    // exactly 3 stops → ND8.
    func test_pickFilter_threeStops() {
        XCTAssertEqual(NDRecommender.pickFilter(forStops: 3.0), .nd8)
    }

    // 4.5 stops → ND16 (4 stops, doesn't reach ND32 = 5 stops).
    func test_pickFilter_fourPointFive() {
        XCTAssertEqual(NDRecommender.pickFilter(forStops: 4.5), .nd16)
    }

    // 9 stops → ND128 (max in catalog, even though 9>7).
    func test_pickFilter_overSeven() {
        XCTAssertEqual(NDRecommender.pickFilter(forStops: 9.0), .nd128)
    }

    // Bright noon scene: AE picks 1/2000 @ ISO 100 native; we want 1/48 @
    // ISO 100. Required ND = log2((1/(1/2000)) / (1/(1/48))) = log2(2000/48)
    // ≈ 5.38 stops → ND32 (5 stops).
    func test_recommend_brightSun() {
        let r = NDRecommender.recommend(currentShutter: 1.0 / 2000.0,
                                         currentISO: 100,
                                         nativeISO: 100,
                                         targetFrameRate: 24,
                                         shutterAngle: 180)
        XCTAssertEqual(r.requiredStops, log2(2000.0 / 48.0), accuracy: 0.01)
        XCTAssertEqual(r.suggestedFilter, .nd32)
        XCTAssertFalse(r.isUnderExposed)
    }

    // Already at cinematic shutter: no ND required.
    func test_recommend_alreadyMatched() {
        let r = NDRecommender.recommend(currentShutter: 1.0 / 48.0,
                                         currentISO: 100,
                                         nativeISO: 100,
                                         targetFrameRate: 24,
                                         shutterAngle: 180)
        XCTAssertEqual(r.requiredStops, 0, accuracy: 0.01)
        XCTAssertEqual(r.suggestedFilter, .none)
        XCTAssertFalse(r.isUnderExposed)
    }

    // Dark scene: AE pushed shutter to 1/24 @ ISO 800; cinematic target
    // (1/48 @ ISO 100) is brighter → required stops are negative, mark
    // under-exposed.
    func test_recommend_underExposed() {
        let r = NDRecommender.recommend(currentShutter: 1.0 / 24.0,
                                         currentISO: 800,
                                         nativeISO: 100,
                                         targetFrameRate: 24,
                                         shutterAngle: 180)
        XCTAssertLessThan(r.requiredStops, 0)
        XCTAssertEqual(r.suggestedFilter, .none)
        XCTAssertTrue(r.isUnderExposed)
    }

    // ND filter stops are correct.
    func test_filterStops() {
        XCTAssertEqual(NDFilter.nd2.stops,   1)
        XCTAssertEqual(NDFilter.nd4.stops,   2)
        XCTAssertEqual(NDFilter.nd8.stops,   3)
        XCTAssertEqual(NDFilter.nd16.stops,  4)
        XCTAssertEqual(NDFilter.nd32.stops,  5)
        XCTAssertEqual(NDFilter.nd64.stops,  6)
        XCTAssertEqual(NDFilter.nd128.stops, 7)
    }
}
