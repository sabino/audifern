import Foundation
import Testing
@testable import CompanionCore

private func batteryService(_ major: UInt8 = 2, _ minor: UInt8 = 0,
                            id: UInt32 = OticonBattery.serviceID, status: UInt8 = 0xFF) -> UTLProtocol.Service {
    .init(id: id, handle: 7, major: major, minor: minor, status: status)
}

@Test func batteryV1AndV2DecodeVersionedTelemetry() throws {
    // 50%, charge 12,000, draw 1,000, not low, discharging => 12 hours.
    // Independent wire fixture: three BE32 scalars, then MSB-first flags.
    let payload = Data([0, 0, 0, 50, 0, 0, 0x2E, 0xE0, 0, 0, 0x03, 0xE8, 0x40])
    for version in [(UInt8(1), UInt8(0)), (1, 1), (2, 0)] {
        let state = try OticonBattery.fastState(payload, service: batteryService(version.0, version.1))
        #expect(state.percentage == 50)
        #expect(state.remainingCharge == 12_000)
        #expect(state.currentDraw == 1_000)
        #expect(state.batteryLow == false)
        #expect(state.isDischarging == true)
        #expect(state.isCharging == false)
        #expect(state.chargingDone == (version.0 == 2 ? false : nil))
        #expect(state.estimatedTimeLeftSeconds == 43_200)
    }
}

@Test func batteryV2AcceptsObservedUninterpretedTailWithoutChangingScalarOrBitLayout() throws {
    // Synthetic values preserve an observed Battery 2.0 response's shape.
    // The shipped schema consumes only 13 bytes; its nonzero tail has no
    // recovered meaning and is not an additional Boolean field.
    let observed = Data([0, 0, 0, 42, 0, 0, 0x2E, 0xE0, 0, 0, 0x03, 0xE8,
                         0x40, 0x12, 0x34, 0x56])
    let state = try OticonBattery.fastState(observed, service: batteryService())
    #expect(state == (try OticonBattery.fastState(Data(observed.prefix(13)), service: batteryService())))
    #expect(state.percentage == 42)
    #expect(state.remainingCharge == 12_000)
    #expect(state.currentDraw == 1_000)
    #expect(state.batteryLow == false)
    #expect(state.isDischarging == true)
    #expect(state.chargingDone == false)
    #expect(state.estimatedTimeLeftSeconds == 43_200)

    // The unknown tail is ignored, not validated as zero padding. This does not
    // broaden other service versions or accept arbitrary extra/truncated data.
    let otherTail = Data(observed.prefix(13)) + Data([0xFF, 0xA5, 0xC0])
    #expect(state == (try OticonBattery.fastState(otherTail, service: batteryService())))
    for version in [UInt8(0), 1] {
        #expect(throws: OticonBattery.DecodeError.malformed) {
            try OticonBattery.fastState(observed, service: batteryService(1, version))
        }
    }
    for count in [12, 14, 15, 17] {
        let wrongLength = count <= observed.count ? Data(observed.prefix(count)) : observed + Data([0])
        #expect(throws: OticonBattery.DecodeError.malformed) {
            try OticonBattery.fastState(wrongLength, service: batteryService())
        }
    }
}

@Test func batteryRemainingTimeUsesTelemetryNotPercentage() throws {
    let slow = try OticonBattery.fastState(Data([0, 0, 0, 50, 0, 0, 0x2E, 0xE0, 0, 0, 0x03, 0xE8, 0x40]), service: batteryService())
    let fast = try OticonBattery.fastState(Data([0, 0, 0, 50, 0, 0, 0x2E, 0xE0, 0, 0, 0x07, 0xD0, 0x40]), service: batteryService())
    #expect(slow.percentage == fast.percentage)
    #expect(slow.estimatedTimeLeftSeconds == 43_200)
    #expect(fast.estimatedTimeLeftSeconds == 21_600)
    #expect(try OticonBattery.standardState(Data([50])).estimatedTimeLeftSeconds == nil)
}

@Test func batteryUnknownInvalidAndChargingTelemetryNeverInventsRuntime() throws {
    let samples = [
        Data([0, 0, 0, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0x40]), // zero/zero: shipped corruption check
        Data([0, 0, 0, 50, 0, 0, 0, 10, 0, 0, 0, 0, 0x40]), // no current draw
        Data([0, 0, 0, 50, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 1, 0x40]), // signed charge -1
        Data([0, 0, 0, 50, 0, 0, 0, 10, 0, 0, 0, 1, 0]), // explicitly charging
        Data([0, 0, 0, 50, 0, 0, 0, 10, 0, 0, 0, 1, 0x60]), // charge complete
        Data([0, 0, 0, 50, 0, 0, 0, 10, 0xFF, 0xFF, 0xFF, 0xFF, 0x40])
    ]
    for sample in samples {
        #expect(try OticonBattery.fastState(sample, service: batteryService()).estimatedTimeLeftSeconds == nil)
    }
    let zero = try OticonBattery.fastState(samples[0], service: batteryService())
    #expect(zero.hasCorruptZeroTelemetry)
    #expect(try OticonBattery.standardState(Data([255])).percentage == nil)
    #expect(try OticonBattery.standardState(Data([101])).percentage == nil)
    #expect(try OticonBattery.standardState(Data([0])).percentage == 0)
    #expect(try OticonBattery.standardState(Data([100])).percentage == 100)
    // A real zero charge with a positive draw reports zero time, not unavailable.
    #expect(try OticonBattery.fastState(Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0xC0]), service: batteryService()).estimatedTimeLeftSeconds == 0)
}

@Test func batteryHealthAndLegacyLifespanAreNotRuntime() throws {
    let healthPayload = Data([0, 0, 0, 90, 0, 0, 0, 60, 0, 0, 0x03, 0xE8, 0, 0, 0x4E, 0x20])
    let health = try OticonBattery.slowHealth(healthPayload, service: batteryService())
    #expect(health.lifespan == 90)
    #expect(health.lifespanThreshold == 60)
    #expect(health.slowAverageCurrentDraw == 1_000)
    #expect(health.fullChargeCapacity == 20_000)
    let negativeCapacity = try OticonBattery.slowHealth(Data([0, 0, 0, 90, 0, 0, 0, 60, 0, 0, 0x03, 0xE8, 0xFF, 0xFF, 0xFF, 0xFF]), service: batteryService(1))
    #expect(negativeCapacity.fullChargeCapacity == -1)
    #expect(throws: OticonBattery.DecodeError.malformed) { try OticonBattery.slowHealth(Data(healthPayload.dropLast()), service: batteryService()) }
    let legacy = try OticonBattery.legacyInfo(Data([50, 90, 60]))
    #expect(legacy.percentage == 50 && legacy.lifespan == 90 && legacy.threshold == 60)
    #expect(try OticonBattery.legacyInfo(Data([255, 0, 0])).percentage == nil)
    #expect(throws: OticonBattery.DecodeError.malformed) { try OticonBattery.legacyInfo(Data([50])) }
}

@Test func batteryDecoderRejectsUnknownVersionsLengthsAndUsesMSBFlags() throws {
    let valid = Data([0, 0, 0, 50, 0, 0, 0, 10, 0, 0, 0, 1, 0x40])
    for service in [batteryService(1, 2), batteryService(2, 1), batteryService(3, 0), batteryService(id: 1), batteryService(status: 0)] {
        #expect(!OticonBattery.supports(service))
        #expect(throws: OticonBattery.DecodeError.unsupportedVersion) { try OticonBattery.fastState(valid, service: service) }
    }
    for data in [Data(), Data(valid.dropLast()), valid + Data([0]),
                 Data([0x18, 50, 10, 1, 0xF4, 0xF5, 0xF4])] { // CBOR is a different carrier
        #expect(throws: OticonBattery.DecodeError.malformed) { try OticonBattery.fastState(data, service: batteryService()) }
    }
    for flags in UInt8.min...UInt8.max {
        let payload = Data(valid.dropLast()) + Data([flags])
        let v2 = try OticonBattery.fastState(payload, service: batteryService())
        let v1 = try OticonBattery.fastState(payload, service: batteryService(1))
        #expect(v2.batteryLow == (flags & 0x80 != 0))
        #expect(v2.isDischarging == (flags & 0x40 != 0))
        #expect(v2.chargingDone == (flags & 0x20 != 0))
        #expect(v1.chargingDone == nil) // all other bits are ignored by these contracts
    }
    let unknownLevel = Data([0xFF, 0xFF, 0xFF, 0xFF]) + Data(valid.dropFirst(4))
    #expect(try OticonBattery.fastState(unknownLevel, service: batteryService()).percentage == nil)
}

@Test func batteryEventsUseDynamicHandleAndExactEventCodes() throws {
    let payload = Data([0, 0, 0, 50, 0, 0, 0, 10, 0, 0, 0, 1, 0x40])
    for code in [UInt8(1), 2] {
        let event = UTLProtocol.ServiceMessage(messageType: .event, identifier: 0, serviceHandle: 7, code: code, payload: payload)
        #expect(try OticonBattery.eventState(event, service: batteryService())?.percentage == 50)
        let extended = UTLProtocol.ServiceMessage(messageType: .event, identifier: 0, serviceHandle: 7,
                                                 code: code, payload: payload + Data([1, 2, 3]))
        #expect(try OticonBattery.eventState(extended, service: batteryService())
                == OticonBattery.eventState(event, service: batteryService()))
    }
    for (type, handle, code) in [(UTLProtocol.MessagePart.MessageType.response, UInt8(7), UInt8(1)), (.event, 8, 1), (.event, 7, 3)] {
        let unrelated = UTLProtocol.ServiceMessage(messageType: type, identifier: 0, serviceHandle: handle, code: code, payload: Data())
        #expect(try OticonBattery.eventState(unrelated, service: batteryService()) == nil)
    }
}

@Test func batterySettlingDelayMatchesPositivePairingTimerRule() throws {
    #expect(try OticonBattery.settlingDelaySeconds(pairingTimerSeconds: 25, service: batteryService(1)) == 85)
    #expect(try OticonBattery.settlingDelaySeconds(pairingTimerSeconds: 25, service: batteryService()) == 325)
    #expect(try OticonBattery.settlingDelaySeconds(pairingTimerSeconds: 0, service: batteryService()) == 0)
    #expect(try OticonBattery.settlingDelaySeconds(pairingTimerSeconds: nil, service: batteryService()) == 0)
    #expect(try OticonBattery.settlingDelaySeconds(pairingTimerSeconds: .max, service: batteryService()) == Double(UInt32.max) + 300)
    #expect(OticonBattery.pollingIntervalSeconds == 300)
}
