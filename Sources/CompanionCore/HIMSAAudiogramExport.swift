import Foundation

/// Export of entered exam values in HIMSA Audiogram 502 XML, not a Noah patient database,
/// fitting prescription, manufacturer module, or assertion of Noah validation.
/// Element order and enums were checked against the official Audiogram 502 revision6 XSD.
public enum HIMSAAudiogramExport {
    public enum Signal: String, CaseIterable, Sendable {
        case unknown = "Unknown", pureTone = "PureTone", warble = "Warble"
        public var label: String {
            switch self { case .unknown: "Unknown"; case .pureTone: "Pure tone"; case .warble: "Warble tone" }
        }
    }

    public enum AirTransducer: String, CaseIterable, Sendable {
        case headphones, insertPhones
        public var label: String { self == .headphones ? "Headphones" : "Insert earphones" }
    }

    public enum ExportError: Error, LocalizedError, Equatable {
        case noMeasurements, missingMaskingLevels, missingAirTransducer, precisionNotSupported

        public var errorDescription: String? {
            switch self {
            case .noMeasurements: "Enter at least one exam value before exporting."
            case .missingMaskingLevels: "HIMSA export needs the actual masking levels, which are not stored in this record. Use JSON to preserve masked measurements."
            case .missingAirTransducer: "Select the air-conduction transducer recorded in your exam before exporting to HIMSA."
            case .precisionNotSupported: "HIMSA 502 accepts at most one decimal place. JSON preserves this exam's full precision."
            }
        }
    }

    public static func xml(for exam: Audiogram, signal: Signal = .unknown,
                           airTransducer: AirTransducer? = nil) throws -> Data {
        _ = try exam.validated()
        guard !exam.thresholds.isEmpty else { throw ExportError.noMeasurements }
        guard !exam.thresholds.contains(where: { $0.key.masked }) else { throw ExportError.missingMaskingLevels }
        guard airTransducer != nil || !exam.thresholds.contains(where: { $0.key.conduction == .air }) else {
            throw ExportError.missingAirTransducer
        }
        guard exam.thresholds.allSatisfy({ abs($0.levelDBHL * 10 - ($0.levelDBHL * 10).rounded()) < 0.0000001 }) else {
            throw ExportError.precisionNotSupported
        }
        var lines = [#"<?xml version="1.0" encoding="UTF-8"?>"#,
                     #"<HIMSAAudiometricStandard xmlns="http://www.himsa.com/Measurement/Audiogram/502" Version="502">"#]
        for ear in AudiogramEar.allCases {
            for conduction in AudiogramConduction.allCases {
                let entries = exam.thresholds.filter { $0.key.ear == ear && $0.key.conduction == conduction }
                    .sorted { $0.key.frequencyHz < $1.key.frequencyHz }
                guard !entries.isEmpty else { continue }
                let output: String
                switch conduction {
                case .air: output = airTransducer == .insertPhones ? "InsertPhone" : "AirConductor"
                case .bone: output = "BoneConductor"
                }
                lines += ["  <ToneThresholdAudiogram>", "    <AudMeasurementConditions>",
                          "      <StimulusSignalType>\(signal.rawValue)</StimulusSignalType>",
                          "      <MaskingSignalType>NoSignalApplied</MaskingSignalType>",
                          "      <StimulusSignalOutput>\(output)\(ear.label)</StimulusSignalOutput>",
                          "      <MaskingSignalOutput>NoSignalOutput</MaskingSignalOutput>",
                          "      <StimulusdBWeighting>HL</StimulusdBWeighting>",
                          "      <MaskingdBWeighting>NodBWeighting</MaskingdBWeighting>",
                          "    </AudMeasurementConditions>"]
                for entry in entries {
                    let level = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), entry.levelDBHL)
                    lines += ["    <TonePoints>",
                              "      <StimulusFrequency>\(entry.key.frequencyHz)</StimulusFrequency>",
                              "      <StimulusLevel>\(level)</StimulusLevel>",
                              "      <TonePointStatus>\(entry.noResponse ? "NoResponse" : "Normal")</TonePointStatus>",
                              "    </TonePoints>"]
                }
                lines.append("  </ToneThresholdAudiogram>")
            }
        }
        lines.append("</HIMSAAudiometricStandard>")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
