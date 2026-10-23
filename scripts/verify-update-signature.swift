// SPDX-License-Identifier: GPL-3.0-only
import CryptoKit
import Foundation

do {
    let args = CommandLine.arguments
    guard args.count >= 4, let rawKey = Data(base64Encoded: args[2]), rawKey.count == 32 else {
        throw NSError(domain: "Audifern.UpdateVerification", code: 1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    let content: Data
    let signature: Data
    if args[1] == "feed" {
        let prefix = Data("<!-- sparkle-signatures:\n".utf8)
        guard let boundary = data.range(of: prefix, options: .backwards),
              let suffix = data.range(of: Data("-->".utf8), in: boundary.upperBound..<data.endIndex),
              String(decoding: data[suffix.upperBound...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "Audifern.UpdateVerification", code: 2)
        }
        content = data.subdata(in: data.startIndex..<boundary.lowerBound)
        let lines = String(decoding: data[boundary.upperBound..<suffix.lowerBound], as: UTF8.self).split(separator: "\n")
        guard lines.count == 2,
              let encoded = lines.first(where: { $0.hasPrefix("edSignature:") })?.dropFirst("edSignature:".count),
              let length = lines.first(where: { $0.hasPrefix("length:") })?.dropFirst("length:".count),
              Int(length.trimmingCharacters(in: .whitespaces)) == content.count,
              let decoded = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespaces)), decoded.count == 64 else {
            throw NSError(domain: "Audifern.UpdateVerification", code: 3)
        }
        signature = decoded
    } else if args[1] == "archive", args.count == 5, let decoded = Data(base64Encoded: args[4]), decoded.count == 64 {
        content = data; signature = decoded
    } else { throw NSError(domain: "Audifern.UpdateVerification", code: 4) }
    guard key.isValidSignature(signature, for: content) else { throw NSError(domain: "Audifern.UpdateVerification", code: 5) }
    print("Verified Ed25519 update signature.")
} catch {
    fputs("Update signature verification failed.\n", stderr)
    exit(1)
}
