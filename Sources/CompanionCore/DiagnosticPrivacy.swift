import Foundation

/// A deliberately small shareable diagnostic surface: protocol descriptors may
/// remain, while raw payloads, names, identities and authentication data do not.
public enum DiagnosticPrivacy {
    public static func redact(_ text: String, identifiers: [String] = []) -> String {
        var result = text
        for identifier in Set(identifiers).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: identifier, with: "[private]", options: .caseInsensitive)
        }
        for pattern in [
            #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            #"(?:/Users/|/home/)[^/\s]+"#,
            #"\b(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}\b"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[private]")
            }
        }
        return result
    }

    public static func shareableDetails(_ details: [String: String], identifiers: [String] = []) -> [String: String] {
        let allowed: Set<String> = ["characteristic", "service", "properties", "count", "duration_seconds",
                                    "services_count", "characteristics_count", "stage", "status", "opcode", "scope"]
        return details.filter { allowed.contains($0.key) }.mapValues { redact($0, identifiers: identifiers) }
    }
}
