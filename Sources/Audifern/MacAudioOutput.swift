import CoreAudio
import Foundation

struct MacAudioOutput: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor protocol MacAudioOutputClient: AnyObject {
    func outputs() -> [MacAudioOutput]
    func currentOutput() -> String?
    func selectOutput(_ uid: String) -> Bool
}

@MainActor final class PreviewMacAudioOutput: MacAudioOutputClient {
    private var current = "preview-speakers"
    func outputs() -> [MacAudioOutput] {
        [.init(id: "preview-speakers", name: L("Preview speakers")), .init(id: "preview-aids", name: L("Preview hearing aids"))]
    }
    func currentOutput() -> String? { current }
    func selectOutput(_ uid: String) -> Bool {
        guard outputs().contains(where: { $0.id == uid }) else { return false }
        current = uid; return true
    }
}

/// Public Core Audio routing only. This does not pair, disconnect a Bluetooth
/// audio profile, or make an output held by another host appear on this Mac.
@MainActor final class SystemMacAudioOutput: MacAudioOutputClient {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private func devices() -> [AudioDeviceID] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioDeviceID>.size, size % UInt32(MemoryLayout<AudioDeviceID>.size) == 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &property, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? ids : []
    }
    private func text(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &result) == noErr else { return nil }
        return result?.takeRetainedValue() as String?
    }
    func outputs() -> [MacAudioOutput] {
        devices().compactMap { device in
            var property = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr, size > 0,
                  let uid = text(device, kAudioDevicePropertyDeviceUID), let name = text(device, kAudioObjectPropertyName) else { return nil }
            return MacAudioOutput(id: uid, name: name)
        }
    }
    func currentOutput() -> String? {
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &device) == noErr else { return nil }
        return text(device, kAudioDevicePropertyDeviceUID)
    }
    func selectOutput(_ uid: String) -> Bool {
        guard outputs().contains(where: { $0.id == uid }),
              var device = devices().first(where: { text($0, kAudioDevicePropertyDeviceUID) == uid }) else { return false }
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectSetPropertyData(system, &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr else { return false }
        return currentOutput() == uid
    }
}
