// SPDX-License-Identifier: GPL-3.0-only
// Export exactly one selected Developer ID identity; never export the Keychain.
import CryptoKit
import Foundation
import Security

enum ExportFailure: Error { case message(String) }

func exportIdentity() throws {
    guard CommandLine.arguments.count == 3,
          let password = ProcessInfo.processInfo.environment["AUDIFERN_EXPORT_PASSWORD"],
          password.count >= 32 else {
        throw ExportFailure.message("Provide the certificate SHA-1, output path and a strong password through AUDIFERN_EXPORT_PASSWORD.")
    }
    let fingerprint = CommandLine.arguments[1].uppercased()
    guard fingerprint.range(of: "^[A-F0-9]{40}$", options: .regularExpression) != nil else {
        throw ExportFailure.message("The selected identity must be a certificate SHA-1 fingerprint.")
    }
    let destination = URL(fileURLWithPath: CommandLine.arguments[2])
    guard !FileManager.default.fileExists(atPath: destination.path) else {
        throw ExportFailure.message("Refusing to replace an existing export.")
    }
    var results: CFTypeRef?
    let status = SecItemCopyMatching([
        kSecClass: kSecClassIdentity,
        kSecReturnRef: true,
        kSecMatchLimit: kSecMatchLimitAll
    ] as CFDictionary, &results)
    guard status == errSecSuccess, let identities = results as? [SecIdentity] else {
        throw ExportFailure.message("Could not read local signing identities.")
    }
    var selected: SecIdentity?
    for identity in identities {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { continue }
        let data = SecCertificateCopyData(certificate) as Data
        let actual = Insecure.SHA1.hash(data: data).map { String(format: "%02X", $0) }.joined()
        guard actual == fingerprint else { continue }
        let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
        guard summary.hasPrefix("Developer ID Application:") else {
            throw ExportFailure.message("The selected identity is not Developer ID Application.")
        }
        guard selected == nil else { throw ExportFailure.message("More than one identity matches the fingerprint.") }
        selected = identity
    }
    guard let selected else { throw ExportFailure.message("The selected Developer ID private key is not in the local Keychain.") }
    var parameters = SecItemImportExportKeyParameters()
    parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
    let passphrase = password as CFString
    parameters.passphrase = Unmanaged.passUnretained(passphrase)
    var exported: CFData?
    let exportedStatus = withExtendedLifetime(passphrase) {
        SecItemExport(selected, .formatPKCS12, [], &parameters, &exported)
    }
    guard exportedStatus == errSecSuccess, let exported else {
        throw ExportFailure.message("Export was not authorized or failed (OSStatus \(exportedStatus)). Use the macOS Keychain prompt; no login password belongs in this tool.")
    }
    try (exported as Data).write(to: destination, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    print("Exported only the selected Developer ID identity to a password-protected PKCS#12 file.")
}

do {
    try exportIdentity()
} catch ExportFailure.message(let message) {
    fputs(message + "\n", stderr)
    exit(1)
} catch {
    fputs("The selected identity could not be exported securely.\n", stderr)
    exit(1)
}
