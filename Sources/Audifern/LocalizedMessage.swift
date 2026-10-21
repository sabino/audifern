import Foundation

/// Presentation only: backend status, state comparisons and log records stay in
/// canonical English. Never call this for a user name, device name or program name.
func M(_ renderedEnglish: String) -> String {
    LocalizedMessage.render(renderedEnglish, using: .shared)
}

enum LocalizedMessage {
    /// An explicit allowlist, not a general attempt to translate arbitrary prose.
    /// Captured names/values are always arguments and never lookup keys.
    static func render(_ english: String, using localization: Localization, depth: Int = 0) -> String {
        guard !english.isEmpty, english.utf8.count <= 16_384 else { return english }
        let sentinel = "__AUDIFERN_ABSENT_MESSAGE__"
        if let exact = Localization.bundle(for: .english)?.localizedString(forKey: english, value: sentinel, table: "Localizable"), exact != sentinel {
            return localization.string(english)
        }
        guard depth < 4 else { return english }
        let whole = NSRange(english.startIndex..<english.endIndex, in: english)
        for template in templates {
            guard let match = template.regex.firstMatch(in: english, range: whole), match.range == whole else { continue }
            var values: [any CVarArg] = []
            for (index, field) in template.fields.enumerated() {
                guard let range = Range(match.range(at: index + 1), in: english) else { return english }
                let value = String(english[range])
                switch field.presentation {
                case .verbatim: values.append(value)
                case .message: values.append(render(value, using: localization, depth: depth + 1))
                case .token: values.append(token(value, using: localization))
                case .control: values.append(control(value, using: localization))
                }
            }
            return localization.string(template.key, arguments: values)
        }
        return english
    }

    private enum Presentation: Sendable { case verbatim, message, token, control }
    private struct Field: Sendable {
        let pattern: String
        let presentation: Presentation
        static let value = Self(pattern: "[^\\r\\n]{1,4096}", presentation: .verbatim)
        static let error = Self(pattern: "[^\\r\\n]{1,4096}", presentation: .message)
        static let count = Self(pattern: "[0-9]{1,4}", presentation: .verbatim)
        static let level = Self(pattern: "[-+−]?[0-9]{1,3}", presentation: .verbatim)
        static let source = Self(pattern: "(?:Tinnitus|Streaming source|tinnitus|streaming source)", presentation: .token)
        static let equalizer = Self(pattern: "(?:Microphone|Streaming)", presentation: .token)
        static let side = Self(pattern: "(?:Left|Right|left|right)", presentation: .token)
        static let setting = Self(pattern: "(?:volume and mute|microphone eq|streaming eq|speechbooster|program)", presentation: .token)
        static let enabled = Self(pattern: "(?:on|off)", presentation: .token)
        static let control = Self(pattern: "(?:(?:Volume|volume) [-+]?[0-9]{1,3}|(?:Program|program) [0-9]{1,3}|Mute|mute|Unmute|unmute|Volume and mute|volume and mute|Microphone EQ|microphone eq|Streaming EQ|streaming eq|SpeechBooster|speechbooster|Program|program)", presentation: .control)
        static let earlier = Self(pattern: "(?: Earlier confirmed changes remain applied\\.)?", presentation: .message)
        static let uncertain = Self(pattern: "(?: The last request may still have reached the aid\\.)?", presentation: .message)
    }

    /// NSRegularExpression is immutable and may be matched concurrently.
    private struct Template: @unchecked Sendable {
        let key: String
        let fields: [Field]
        let regex: NSRegularExpression
        init?(_ key: String, _ fields: [Field]) {
            let literals = key.components(separatedBy: "%@")
            guard literals.count == fields.count + 1 else { return nil }
            var pattern = "\\A" + NSRegularExpression.escapedPattern(for: literals[0])
            for (index, field) in fields.enumerated() {
                pattern += "(" + field.pattern + ")" + NSRegularExpression.escapedPattern(for: literals[index + 1])
            }
            guard let regex = try? NSRegularExpression(pattern: pattern + "\\z") else { return nil }
            self.key = key; self.fields = fields; self.regex = regex
        }
    }

    private static let templates: [Template] = [
        // Concrete control labels/counts, never a standalone arbitrary %@.
        Template("Program %@", [.count]),
        Template("Volume %@", [.level]),
        Template("All %@ sound change confirmed by the hearing aids.", [.count]),
        Template("All %@ sound changes confirmed by the hearing aids.", [.count]),
        Template("Stopped after %@ of %@ confirmed changes.%@%@ %@", [.count, .count, .earlier, .uncertain, .error]),
        Template("Linked change stopped after %@ confirmed aid. %@", [.count, .error]),
        Template("%@ change stopped after %@ confirmed aid. %@", [.source, .count, .error]),
        Template("Connecting to %@", [.value]),
        Template("Reading current %@ controls…", [.source]),
        Template("Both aids confirmed the %@ change.", [.source]),
        Template("%@ change confirmed by hearing aid.", [.source]),
        Template("%@ change not confirmed: %@", [.source, .error]),
        Template("%@: changing %@…", [.side, .setting]),
        Template("%@ EQ confirmed by hearing aid.", [.equalizer]),
        Template("%@ EQ confirmed by hearing aid", [.equalizer]),
        Template("SpeechBooster %@ confirmed by hearing aid.", [.enabled]),
        Template("SpeechBooster %@ confirmed by hearing aid", [.enabled]),
        Template("Sending %@…", [.control]),
        Template("%@ confirmed by hearing aid", [.control]),
        Template("%@ was not confirmed: %@", [.control, .error]),
        Template("%@ failed: %@", [.control, .error]),
        Template("%@ volume is unavailable or outside its reported range.", [.side]),
        Template("%@ EQ limits changed. Reload its advanced controls.", [.side]),
        Template("Load %@ advanced controls first.", [.side]),
        Template("Load %@ SpeechBooster in a supported program first.", [.side]),
        Template("That program is unavailable on the %@ aid.", [.side]),
        Template("No changes sent. %@", [.error]),
        Template("Linked change not confirmed: %@", [.error]),
        Template("Program names: %@", [.error]),
        Template("Device details: %@", [.error]),
        Template("Identification: %@", [.error]),
        Template("Battery health: %@", [.error]),
        Template("Crash-dump counters: %@", [.error]),
        Template("Advanced controls: %@", [.error]),
        Template("Advanced control read stopped: %@", [.error]),
        Template("Battery telemetry: %@", [.error]),
        Template("Device identification: %@", [.error]),
        Template("Speech Booster: %@", [.error]),
        Template("EQ not confirmed: %@", [.error]),
        Template("SpeechBooster not confirmed: %@", [.error]),
        Template("Snapshot unavailable: %@", [.error]),
        Template("Fitting record unavailable: %@", [.error]),
        Template("Fresh consumer controls read. Clinical fitting data is not included.%@", [.error]),
        Template("Preset apply stopped; earlier confirmed settings may already be applied. %@", [.error]),
        Template("Could not read your saved sound presets: %@. The existing file has been preserved.", [.error]),
        Template("Some reported fields could not be decoded: %@.", [.value]),
        Template("Saved %@ on this Mac. Audiogram values are stored for reference; they do not prescribe amplification.", [.value])
    ].compactMap { $0 }

    private static let tokens: [String: String] = [
        "left": "Left", "right": "Right", "microphone": "Microphone", "streaming": "Streaming",
        "tinnitus": "Tinnitus", "streaming source": "Streaming source", "on": "On", "off": "Off",
        "volume and mute": "Volume and mute", "microphone eq": "Microphone EQ", "streaming eq": "Streaming EQ",
        "speechbooster": "SpeechBooster", "program": "Program", "mute": "Mute", "unmute": "Unmute"
    ]
    private static func token(_ value: String, using localization: Localization) -> String {
        guard let key = tokens[value.lowercased()] else { return value }
        let translated = localization.string(key)
        return value.first?.isLowercase == true ? translated.lowercased() : translated
    }
    private static func control(_ value: String, using localization: Localization) -> String {
        let parts = value.split(separator: " ")
        if parts.count == 2, ["volume", "program"].contains(parts[0].lowercased()), Int(parts[1]) != nil {
            let key = parts[0].lowercased() == "volume" ? "Volume %@" : "Program %@"
            let translated = localization.string(key, arguments: [String(parts[1])])
            return value.first?.isLowercase == true ? translated.lowercased() : translated
        }
        return token(value, using: localization)
    }
}
