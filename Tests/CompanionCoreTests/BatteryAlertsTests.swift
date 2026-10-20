import Foundation
import XCTest
@testable import CompanionCore

final class BatteryAlertsTests: XCTestCase {
    private let all = Set(BatteryAlertThreshold.allCases)

    func testDistinctDownwardMilestonesAndStrictLowBatteryBoundary() throws {
        var state = BatteryAlertDeviceState()
        XCTAssertNil(state.observe(percentage: 80, enabledThresholds: all))
        for (level, threshold) in [(50, BatteryAlertThreshold.fifty), (30, .thirty), (20, .twenty)] {
            let decision = try XCTUnwrap(state.observe(percentage: level, enabledThresholds: all))
            XCTAssertEqual(decision.threshold, threshold)
            XCTAssertEqual(decision.percentage, level)
            XCTAssertTrue(state.markDelivered(decision))
            XCTAssertNil(state.observe(percentage: level, enabledThresholds: all))
        }
        XCTAssertNil(state.observe(percentage: 10, enabledThresholds: all))
        let low = try XCTUnwrap(state.observe(percentage: 9, enabledThresholds: all))
        XCTAssertEqual(low.threshold, .low)
        XCTAssertTrue(state.markDelivered(low))
        XCTAssertNil(state.observe(percentage: 0, enabledThresholds: all))
    }

    func testLargeDropCoalescesIntoOneCurrentAlert() throws {
        var state = BatteryAlertDeviceState()
        state.observe(percentage: 85, enabledThresholds: all)
        let low = try XCTUnwrap(state.observe(percentage: 8, enabledThresholds: all))
        XCTAssertEqual(low.threshold, .low)
        XCTAssertEqual(low.coveredThresholds, all)
        XCTAssertTrue(state.markDelivered(low))
        XCTAssertTrue(state.pendingThresholds.isEmpty)
        XCTAssertNil(state.observe(percentage: 7, enabledThresholds: all))
    }

    func testFirstReadingDoesNotInventFiftyCrossingAndAlreadyLowAlertsOnce() throws {
        for baseline in [100, 51, 50, 49, 35, 31] {
            var state = BatteryAlertDeviceState()
            XCTAssertNil(state.observe(percentage: baseline, enabledThresholds: all))
        }
        for (level, expected) in [(30, BatteryAlertThreshold.thirty), (25, .thirty), (20, .twenty), (10, .twenty), (9, .low)] {
            var state = BatteryAlertDeviceState()
            let initial = try XCTUnwrap(state.observe(percentage: level, enabledThresholds: all))
            XCTAssertEqual(initial.threshold, expected)
            XCTAssertFalse(initial.coveredThresholds.contains(.fifty))
            XCTAssertTrue(state.markDelivered(initial))
            XCTAssertNil(state.observe(percentage: level, enabledThresholds: all))
        }
    }

    func testHysteresisRequiresRechargeRatherThanThresholdJitter() throws {
        var state = BatteryAlertDeviceState()
        state.observe(percentage: 80, enabledThresholds: all)
        let first = try XCTUnwrap(state.observe(percentage: 50, enabledThresholds: all))
        XCTAssertTrue(state.markDelivered(first))
        for reading in [51, 50, 54, 49] { XCTAssertNil(state.observe(percentage: reading, enabledThresholds: all)) }
        XCTAssertNil(state.observe(percentage: 55, enabledThresholds: all))
        XCTAssertEqual(state.observe(percentage: 50, enabledThresholds: all)?.threshold, .fifty)

        var lowState = BatteryAlertDeviceState()
        let initialLow = try XCTUnwrap(lowState.observe(percentage: 9, enabledThresholds: [.low]))
        XCTAssertTrue(lowState.markDelivered(initialLow))
        for reading in [10, 9, 14, 9] { XCTAssertNil(lowState.observe(percentage: reading, enabledThresholds: [.low])) }
        lowState.observe(percentage: 15, enabledThresholds: [.low])
        XCTAssertEqual(lowState.observe(percentage: 9, enabledThresholds: [.low])?.threshold, .low)
    }

    func testDeliveryFailureStaysPendingAcrossSerializationAndNewReading() throws {
        let id = UUID().uuidString
        var state = BatteryAlertDeviceState()
        state.observe(percentage: 80, enabledThresholds: all)
        let pending = try XCTUnwrap(state.observe(percentage: 30, enabledThresholds: all))
        XCTAssertFalse(state.handledThresholds.contains(.thirty))
        let data = try BatteryAlertArchive(devices: [id: state]).encoded()
        var restored = try XCTUnwrap(BatteryAlertArchive.decode(data).devices[id])
        XCTAssertEqual(restored.pendingDecision(enabledThresholds: all), pending)
        XCTAssertEqual(restored.observe(percentage: 29, enabledThresholds: all)?.percentage, 29)
        XCTAssertTrue(restored.markDelivered(pending))
        XCTAssertNil(restored.observe(percentage: 29, enabledThresholds: all))
    }

    func testNewerMilestoneIsNotConsumedByOlderDeliveryAcknowledgment() throws {
        var state = BatteryAlertDeviceState()
        state.observe(percentage: 80, enabledThresholds: all)
        let fifty = try XCTUnwrap(state.observe(percentage: 50, enabledThresholds: all))
        state.observe(percentage: 20, enabledThresholds: all)
        XCTAssertTrue(state.markDelivered(fifty))
        let newer = try XCTUnwrap(state.pendingDecision(enabledThresholds: all))
        XCTAssertEqual(newer.threshold, .twenty)
        XCTAssertEqual(newer.coveredThresholds, [.thirty, .twenty])
    }

    func testPendingDropDoesNotResurrectOlderMilestonesWhileRecharging() throws {
        var state = BatteryAlertDeviceState()
        state.observe(percentage: 80, enabledThresholds: all)
        state.observe(percentage: 9, enabledThresholds: all)
        XCTAssertNil(state.observe(percentage: 35, enabledThresholds: all))
        XCTAssertTrue(state.pendingThresholds.isEmpty)
        XCTAssertEqual(state.observe(percentage: 30, enabledThresholds: all)?.threshold, .thirty)

        var jitter = BatteryAlertDeviceState()
        jitter.observe(percentage: 80, enabledThresholds: all)
        jitter.observe(percentage: 20, enabledThresholds: all)
        XCTAssertNil(jitter.observe(percentage: 21, enabledThresholds: all))
        let retry = try XCTUnwrap(jitter.observe(percentage: 20, enabledThresholds: all))
        XCTAssertEqual(retry.threshold, .twenty)
        XCTAssertEqual(retry.coveredThresholds, [.twenty])
    }

    func testRechargeInvalidatesStaleDeliveryAndDisabledMilestonesStayQuiet() throws {
        var state = BatteryAlertDeviceState()
        state.observe(percentage: 80, enabledThresholds: all)
        let old = try XCTUnwrap(state.observe(percentage: 30, enabledThresholds: all))
        state.observe(percentage: 70, enabledThresholds: all)
        XCTAssertFalse(state.markDelivered(old))
        XCTAssertNil(state.pendingDecision(enabledThresholds: all))
        XCTAssertNil(state.observe(percentage: 30, enabledThresholds: [.low]))
        XCTAssertNil(state.observe(percentage: 29, enabledThresholds: all))
        XCTAssertEqual(state.observe(percentage: 20, enabledThresholds: all)?.threshold, .twenty)
    }

    func testInvalidReadingsCannotCreateOrRearmAlerts() throws {
        var state = BatteryAlertDeviceState()
        let original = state
        XCTAssertNil(state.observe(percentage: -1, enabledThresholds: all))
        XCTAssertNil(state.observe(percentage: 101, enabledThresholds: all))
        XCTAssertEqual(state, original)
        XCTAssertNil(state.lastPercentage)
        XCTAssertEqual(state.observe(percentage: 0, enabledThresholds: [.low])?.percentage, 0)
    }

    func testTwoDeviceHistoriesRemainIndependentAfterRelaunch() throws {
        let first = UUID().uuidString, second = UUID().uuidString
        var left = BatteryAlertDeviceState(), right = BatteryAlertDeviceState()
        left.observe(percentage: 80, enabledThresholds: all)
        right.observe(percentage: 80, enabledThresholds: all)
        let leftAlert = try XCTUnwrap(left.observe(percentage: 20, enabledThresholds: all))
        XCTAssertTrue(left.markDelivered(leftAlert))
        let archive = try BatteryAlertArchive.decode(BatteryAlertArchive(devices: [first: left, second: right]).encoded())
        var restoredLeft = try XCTUnwrap(archive.devices[first]), restoredRight = try XCTUnwrap(archive.devices[second])
        XCTAssertNil(restoredLeft.observe(percentage: 20, enabledThresholds: all))
        XCTAssertEqual(restoredRight.observe(percentage: 20, enabledThresholds: all)?.threshold, .twenty)
    }

    func testArchiveRejectsUnknownVersionsInvalidUUIDsAndOversizedData() throws {
        XCTAssertThrowsError(try BatteryAlertArchive(devices: ["not-a-uuid": .init()]).encoded())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: BatteryAlertArchive().encoded()) as? [String: Any])
        json["version"] = 99
        XCTAssertThrowsError(try BatteryAlertArchive.decode(JSONSerialization.data(withJSONObject: json)))
        XCTAssertThrowsError(try BatteryAlertArchive.decode(Data(repeating: 32, count: 131_073)))
        XCTAssertThrowsError(try BatteryAlertArchive.decode(Data("malformed".utf8)))
    }
}
