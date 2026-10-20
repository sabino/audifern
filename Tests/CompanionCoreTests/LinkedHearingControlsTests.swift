import XCTest
@testable import CompanionCore

final class LinkedHearingControlsTests: XCTestCase {
    func testLinkedStepsPreserveAnExistingAsymmetricBalance() throws {
        let state = try XCTUnwrap(LinkedHearingControls(aids: [
            .init(level: -3, muted: false, range: -8...4),
            .init(level: 1, muted: true, range: -5...3)
        ]))
        XCTAssertNil(state.sharedLevel)
        XCTAssertFalse(state.allMuted)
        XCTAssertEqual(state.levels(adjustingBy: 1), [-2, 2])
        XCTAssertEqual(state.levels(adjustingBy: -1), [-4, 0])
        XCTAssertNil(state.levels(adjustingBy: 2))
    }

    func testOneEarAtItsLimitBlocksTheWholeLinkedStep() throws {
        let state = try XCTUnwrap(LinkedHearingControls(aids: [
            .init(level: 0, muted: true, range: -8...4),
            .init(level: 0, muted: true, range: 0...0)
        ]))
        XCTAssertEqual(state.sharedLevel, 0)
        XCTAssertTrue(state.allMuted)
        XCTAssertNil(state.levels(adjustingBy: 1))
        XCTAssertNil(state.levels(adjustingBy: -1))
        XCTAssertNil(LinkedHearingControls(aids: Array(state.aids.prefix(1))))
        XCTAssertNil(LinkedHearingControls(aids: [.init(level: 5, muted: false, range: -8...4), state.aids[1]]))
    }
}
