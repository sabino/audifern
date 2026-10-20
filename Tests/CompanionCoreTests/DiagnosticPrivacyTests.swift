import Foundation
import Testing
@testable import CompanionCore

@Test func shareableDiagnosticsRemoveIdentifiersAndRawAuthenticationData() {
    let privateValue = "SYNTHETIC-DEVICE-ONLY"
    let source = ["uuid": privateValue, "payload_hex": "01020304", "auth_proof": "test-only",
                  "characteristic": OticonRemoteProtocol.mainVolume, "scope": "read-only", "name": "Example aid"]
    let output = DiagnosticPrivacy.shareableDetails(source, identifiers: [privateValue])
    #expect(output == ["characteristic": OticonRemoteProtocol.mainVolume, "scope": "read-only"])
    let message = DiagnosticPrivacy.redact("Connected SYNTHETIC-DEVICE-ONLY; local@example.invalid; 192.0.2.8; AA:BB:CC:DD:EE:FF", identifiers: [privateValue])
    #expect(!message.contains(privateValue) && !message.contains("@") && !message.contains("192.0.2.8") && !message.contains("AA:BB"))
}

@Test func diagnosticsRetainPublicProtocolInformationAndRedactLongestValueFirst() {
    let input = "Example Device extended · " + OticonRemoteProtocol.mainVolume
    let output = DiagnosticPrivacy.redact(input, identifiers: ["Example Device", "Example Device extended"])
    #expect(output == "[private] · " + OticonRemoteProtocol.mainVolume)
    #expect(DiagnosticPrivacy.redact("Interactive consumer command") == "Interactive consumer command")
}
