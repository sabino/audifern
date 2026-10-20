import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case system, english = "en", portugueseBrazil = "pt-BR", spanish = "es"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: L("Use system language")
        case .english: "English"
        case .portugueseBrazil: "Português (Brasil)"
        case .spanish: "Español"
        }
    }
    var locale: Locale {
        switch self {
        case .system: .current
        case .english: Locale(identifier: "en_US")
        case .portugueseBrazil: Locale(identifier: "pt_BR")
        case .spanish: Locale(identifier: "es_ES")
        }
    }

    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for language in preferredLanguages {
            switch language.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first {
            case "en": return .english
            case "pt": return .portugueseBrazil
            case "es": return .spanish
            default: continue
            }
        }
        return .english
    }
}

/// Runtime language selection is independent of backend/SwiftUI actor isolation.
/// The only mutable field is protected by the lock; bundles are immutable reads.
/// AppPreferences owns persistence and publishes selection changes to the UI.
final class Localization: @unchecked Sendable {
    typealias Language = AppLanguage
    static let shared = Localization()
    private let lock = NSLock()
    private var selection: AppLanguage
    private let preferredLanguagesOverride: [String]?
    private let systemLocaleOverride: Locale?

    init(language: AppLanguage = .system, preferredLanguages: [String]? = nil, systemLocale: Locale? = nil) {
        selection = language; preferredLanguagesOverride = preferredLanguages; systemLocaleOverride = systemLocale
    }

    var language: AppLanguage {
        get { lock.withLock { selection } }
        set { lock.withLock { selection = newValue } }
    }
    func setLanguage(_ language: AppLanguage) { self.language = language }
    var effectiveLanguage: AppLanguage {
        let selected = language
        return selected == .system ? .resolve(preferredLanguages: preferredLanguagesOverride ?? Locale.preferredLanguages) : selected
    }
    var formattingLocale: Locale {
        let selected = language
        return selected == .system ? systemLocaleOverride ?? .current : selected.locale
    }

    func string(_ key: String, arguments: [any CVarArg] = []) -> String {
        let selected = language
        let effective = selected == .system ? AppLanguage.resolve(preferredLanguages: preferredLanguagesOverride ?? Locale.preferredLanguages) : selected
        let locale = selected == .system ? systemLocaleOverride ?? .current : selected.locale
        let english = Self.translation(key, language: .english) ?? key
        let translated = Self.translation(key, language: effective) ?? english
        guard !arguments.isEmpty else { return translated }
        // Catalogs may reorder positional arguments, but cannot change their
        // types. Invalid/missing arguments never reach printf's unsafe varargs.
        guard let expected = LocalizedFormat.signature(english), expected.accepts(arguments) else { return english }
        let format = LocalizedFormat.signature(translated) == expected ? translated : english
        return String(format: format, locale: locale, arguments: arguments)
    }

    /// Integer-count messages for the initial English/pt-BR/Spanish languages.
    /// Both keys are normal catalog entries; user/device values remain arguments.
    /// pt-BR uses the CLDR one category for integer zero and one. The plural key
    /// also supplies these languages' other/many forms (same noun inflection).
    func plural(_ singular: String, _ plural: String, count: Int) -> String {
        let isOne = effectiveLanguage == .portugueseBrazil ? count.magnitude <= 1 : count.magnitude == 1
        let key = isOne ? singular : plural
        return string(key, arguments: LocalizedFormat.signature(key)?.maximumIndex == 0 ? [] : [count])
    }

    static func bundle(for language: AppLanguage) -> Bundle? {
        guard language != .system,
              let url = AppResources.bundle.url(forResource: language.rawValue, withExtension: "lproj") else { return nil }
        return Bundle(url: url)
    }
    private static func translation(_ key: String, language: AppLanguage) -> String? {
        let sentinel = "__AUDIFERN_MISSING_LOCALIZATION__"
        let value = bundle(for: language)?.localizedString(forKey: key, value: sentinel, table: "Localizable")
        return value == sentinel ? nil : value
    }
}

func L(_ key: String, _ arguments: any CVarArg...) -> String {
    Localization.shared.string(key, arguments: arguments)
}

func LP(_ singular: String, _ plural: String, count: Int) -> String {
    Localization.shared.plural(singular, plural, count: count)
}

/// The printf subset used by interface text. Refuses pointer/write conversions,
/// dynamic widths, mixed positional arguments and incompatible runtime types.
enum LocalizedFormat {
    struct Signature: Equatable {
        let arguments: [Int: String]
        var maximumIndex: Int { arguments.keys.max() ?? 0 }
        func accepts(_ values: [any CVarArg]) -> Bool {
            guard values.count == maximumIndex else { return false }
            for (position, conversion) in arguments {
                let value = values[position - 1]
                let type = Swift.type(of: value)
                guard let specifier = conversion.last else { return false }
                switch specifier {
                case "@": guard type == String.self || type is AnyClass else { return false }
                case "d", "i", "u", "o", "x", "X", "c", "C":
                    guard type == Int.self || type == Int8.self || type == Int16.self || type == Int32.self || type == Int64.self
                        || type == UInt.self || type == UInt8.self || type == UInt16.self || type == UInt32.self || type == UInt64.self
                        || type == Bool.self else { return false }
                case "f", "F", "e", "E", "g", "G", "a", "A":
                    guard type == Double.self || type == Float.self || type == CGFloat.self else { return false }
                default: return false
                }
            }
            return true
        }
    }

    static func signature(_ format: String) -> Signature? {
        let bytes = Array(format.utf8)
        var index = 0, nextArgument = 1, positional: Bool?
        var arguments: [Int: String] = [:]
        func digit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
        while index < bytes.count {
            guard bytes[index] == 37 else { index += 1; continue }
            index += 1
            guard index < bytes.count else { return nil }
            if bytes[index] == 37 { index += 1; continue }
            let start = index
            while index < bytes.count && digit(bytes[index]) { index += 1 }
            let hasPosition = index < bytes.count && bytes[index] == 36
            let position: Int
            if hasPosition {
                guard let value = Int(String(decoding: bytes[start..<index], as: UTF8.self)), (1...64).contains(value) else { return nil }
                position = value; index += 1
            } else { position = nextArgument; nextArgument += 1; index = start }
            if let positional, positional != hasPosition { return nil }
            positional = hasPosition
            while index < bytes.count && [UInt8(45), 43, 32, 35, 48, 39].contains(bytes[index]) { index += 1 }
            let widthStart = index
            while index < bytes.count && digit(bytes[index]) { index += 1 }
            if index > widthStart, (Int(String(decoding: bytes[widthStart..<index], as: UTF8.self)) ?? Int.max) > 1_000 { return nil }
            if index < bytes.count && bytes[index] == 46 {
                index += 1
                let precisionStart = index
                while index < bytes.count && digit(bytes[index]) { index += 1 }
                if index > precisionStart, (Int(String(decoding: bytes[precisionStart..<index], as: UTF8.self)) ?? Int.max) > 12 { return nil }
            }
            let lengthStart = index
            if index < bytes.count && [UInt8(104), 108, 106, 122, 116].contains(bytes[index]) {
                let first = bytes[index]; index += 1
                if index < bytes.count && bytes[index] == first && [UInt8(104), 108].contains(first) { index += 1 }
            }
            guard index < bytes.count && Array("@diuoxXcCfFeEgGaA".utf8).contains(bytes[index]) else { return nil }
            let length = String(decoding: bytes[lengthStart..<index], as: UTF8.self)
            if bytes[index] == 64 && !length.isEmpty { return nil }
            if Array("fFeEgGaA".utf8).contains(bytes[index]) && !["", "l"].contains(length) { return nil }
            if Array("cC".utf8).contains(bytes[index]) && !length.isEmpty { return nil }
            let conversion = String(decoding: bytes[lengthStart...index], as: UTF8.self)
            guard arguments[position] == nil || arguments[position] == conversion else { return nil }
            arguments[position] = conversion
            index += 1
        }
        // POSIX positional formats may not leave gaps between arguments.
        if let maximum = arguments.keys.max(), Set(arguments.keys) != Set(1...maximum) { return nil }
        return Signature(arguments: arguments)
    }
}
