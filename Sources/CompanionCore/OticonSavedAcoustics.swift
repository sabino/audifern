import Foundation

/// Names the recorded acoustic categories in the researched HIID 4.5 profile.
/// Wire values are explicit protocol codes, never positions in a filtered UI.
/// This reader does not validate acoustic compatibility or inspect physical parts.
public enum OticonSavedAcoustics {
    public enum DecodeError: Error, Equatable { case unsupportedIdentity }

    public static let limits = "Names describe saved fitting categories. They do not verify the parts currently fitted. Receiver variant, dome size, wire length and acoustic compatibility require additional information."

    public struct Value: Equatable, Sendable {
        public let rawCode: UInt8
        /// The stable HIID 4.5 enumeration symbol, without a UI/resource prefix.
        /// Undefined is an explicit recorded value; an unrecognized code is nil.
        public let identifier: String?
        /// Independently authored English category name, not a vendor UI label.
        public let label: String?
        public var isRecognized: Bool { identifier != nil }
    }

    public struct Labels: Equatable, Sendable {
        public let earpiece: Value
        public let hook: Value
        /// Vent names retain their nominal category, not measured or equivalent
        /// vent diameter. In particular, None and ClosedVent are different values.
        public let vent: Value
        public let tubing: Value
        /// Recorded acoustic fitting level; not a verified receiver identity,
        /// measured output, or a statement of gain in dB.
        public let fittingLevel: Value
        public let fittedSide: Value
    }

    public static func decode(_ fitting: OticonFittedConfiguration.Snapshot) throws -> Labels {
        try decode(fitting.selection, identity: fitting.identity)
    }

    /// Identity must come from the same validated saved record. Missing style,
    /// interface and receiver-module information prevents a full compatibility
    /// check, but does not change these versioned enumeration meanings.
    public static func decode(_ selection: OticonFittedConfiguration.Selection,
                              identity: OticonFittedConfiguration.Identity) throws -> Labels {
        guard identity.isSupported else { throw DecodeError.unsupportedIdentity }
        return Labels(earpiece: value(selection.earPieceCode, earpiece(selection.earPieceCode)),
                      hook: value(selection.hookCode, hook(selection.hookCode)),
                      vent: value(selection.ventCode, vent(selection.ventCode)),
                      tubing: value(selection.tubingCode, tubing(selection.tubingCode)),
                      fittingLevel: value(selection.fittingLevelAcousticsCode, fittingLevel(selection.fittingLevelAcousticsCode)),
                      fittedSide: value(selection.fittedSideCode, fittedSide(selection.fittedSideCode)))
    }

    private typealias Name = (identifier: String, label: String)

    private static func value(_ code: UInt8, _ name: Name?) -> Value {
        Value(rawCode: code, identifier: name?.identifier, label: name?.label)
    }

    private static func earpiece(_ code: UInt8) -> Name? {
        switch code {
        case 0: ("Undefined", "Not specified")
        case 1: ("BassDomeDoubleVented", "Bass dome, double vent")
        case 2: ("BassDomeSingleVented", "Bass dome, single vent")
        case 3: ("CustomEarpieceCIC", "Custom earpiece, CIC")
        case 5: ("LiteTip", "LiteTip")
        case 6: ("MicroMouldLong", "MicroMould, long")
        case 7: ("MicroMouldShort", "MicroMould, short")
        case 8: ("Mould", "Mould")
        case 11: ("PowerDome", "Power dome")
        case 12: ("PowerMould", "Power mould")
        case 14: ("GripTipOpen", "GripTip, open")
        case 15: ("GripTipClosed", "GripTip, closed")
        case 16: ("PowerPlusMould", "Power Plus mould")
        case 17: ("CustomEarpieceIIC", "Custom earpiece, IIC")
        case 18: ("CustomEarpieceITC", "Custom earpiece, ITC")
        case 19: ("CustomEarpieceITE", "Custom earpiece, ITE")
        case 20: ("None", "None")
        case 21: ("PerceivedOpenDome", "Perceived-open dome")
        case 22: ("MicroShellLong", "MicroShell, long")
        case 23: ("MicroShellShort", "MicroShell, short")
        case 24: ("PowerMicroShellLong", "Power MicroShell, long")
        case 25: ("PowerPlusMicroShellLong", "Power Plus MicroShell, long")
        case 26: ("MicroMouldEIE", "MicroMould, EIE")
        default: nil
        }
    }

    private static func hook(_ code: UInt8) -> Name? {
        switch code {
        case 0: ("Undefined", "Not specified")
        case 1: ("None", "None")
        case 2: ("DampedHook", "Damped hook")
        case 3: ("UndampedHook", "Undamped hook")
        case 4: ("ChildDampedHook", "Child hook, damped")
        case 5: ("ChildUndampedHook", "Child hook, undamped")
        case 6: ("CordaHook", "Corda hook")
        case 7: ("Corda2PHook", "Corda 2P hook")
        case 8: ("CordaMiniFitHook", "Corda MiniFit hook")
        case 9: ("CordaPMiniFitHook", "Corda P MiniFit hook")
        default: nil
        }
    }

    private static func vent(_ code: UInt8) -> Name? {
        switch code {
        case 0: ("Undefined", "Not specified")
        case 1: ("ClosedVent", "Closed vent")
        case 2: ("CollectionVent1mm", "Collection vent, nominal 1 mm")
        case 3: ("CollectionVent1Point4mm", "Collection vent, nominal 1.4 mm")
        case 4: ("CollectionVent2Point4mm", "Collection vent, nominal 2.4 mm")
        case 5: ("CollectionVent3mm", "Collection vent, nominal 3 mm")
        case 6: ("LiteTipVent0Point7mm", "LiteTip vent, nominal 0.7 mm")
        case 7: ("LiteTipVent0Point8mm", "LiteTip vent, nominal 0.8 mm")
        case 8: ("LiteTipVent1Point2mm", "LiteTip vent, nominal 1.2 mm")
        case 9: ("LiteTipVent1Point5mm", "LiteTip vent, nominal 1.5 mm")
        case 10: ("MicroMouldVent0Point8mm", "MicroMould vent, nominal 0.8 mm")
        case 11: ("MicroMouldVent0Point8mmLong", "MicroMould vent, long, nominal 0.8 mm")
        case 12: ("MicroMouldVent1Point4mm", "MicroMould vent, nominal 1.4 mm")
        case 13: ("MicroMouldVent1Point4mmLong", "MicroMould vent, long, nominal 1.4 mm")
        case 14: ("MicroMouldVent2Point4mm", "MicroMould vent, nominal 2.4 mm")
        case 15: ("MicroMouldVent2Point4mmLong", "MicroMould vent, long, nominal 2.4 mm")
        case 16: ("MicroMouldVent3mm", "MicroMould vent, nominal 3 mm")
        case 17: ("MicroMouldVent3mmLong", "MicroMould vent, long, nominal 3 mm")
        case 18: ("OpenVent", "Open vent")
        case 19: ("Vent0Point8mm", "Vent, nominal 0.8 mm")
        case 20: ("Vent1Point4mm", "Vent, nominal 1.4 mm")
        case 21: ("Vent1Point8mm", "Vent, nominal 1.8 mm")
        case 22: ("Vent2Point4mm", "Vent, nominal 2.4 mm")
        case 23: ("Vent3mm", "Vent, nominal 3 mm")
        case 24: ("Vent4mm", "Vent, nominal 4 mm")
        case 25: ("PowerDomeVent", "Power-dome vent")
        case 26: ("GripTipOpenVent", "GripTip vent, open")
        case 27: ("GripTipClosedVent", "GripTip vent, closed")
        case 28: ("BassDomeDoubleVent", "Bass-dome vent, double")
        case 29: ("BassDomeSingleVent", "Bass-dome vent, single")
        case 30: ("None", "None")
        case 31: ("CollectionVent1Point2mm", "Collection vent, nominal 1.2 mm")
        case 32: ("CollectionVent1Point6mm", "Collection vent, nominal 1.6 mm")
        case 33: ("CollectionVent1Point8mm", "Collection vent, nominal 1.8 mm")
        case 34: ("CollectionVent2mm", "Collection vent, nominal 2 mm")
        case 35: ("OvalVent10x05", "Oval vent 10×05 category")
        case 36: ("OvalVent10x20", "Oval vent 10×20 category")
        case 37: ("OvalVent17x08", "Oval vent 17×08 category")
        case 38: ("OvalVent17x34", "Oval vent 17×34 category")
        case 39: ("OvalVent21x42", "Oval vent 21×42 category")
        case 40: ("OvalVent28x57", "Oval vent 28×57 category")
        case 41: ("Vent1Point2mm", "Vent, nominal 1.2 mm")
        case 42: ("Vent1Point6mm", "Vent, nominal 1.6 mm")
        case 43: ("Vent2mm", "Vent, nominal 2 mm")
        case 44: ("FreeVentS", "Free vent, small")
        case 45: ("FreeVentM", "Free vent, medium")
        case 46: ("FreeVentL", "Free vent, large")
        case 47: ("FreeVentXL", "Free vent, extra large")
        case 48: ("OvalVent22x11", "Oval vent 22×11 category")
        case 49: ("PerceivedOpenDomeVent", "Perceived-open dome vent")
        case 50: ("MicroShellVent0Point8mm", "MicroShell vent, nominal 0.8 mm")
        case 51: ("MicroShellVent0Point8mmLong", "MicroShell vent, long, nominal 0.8 mm")
        case 52: ("MicroShellVent1Point4mm", "MicroShell vent, nominal 1.4 mm")
        case 53: ("MicroShellVent1Point4mmLong", "MicroShell vent, long, nominal 1.4 mm")
        case 54: ("MicroShellVent1Point8mm", "MicroShell vent, nominal 1.8 mm")
        case 55: ("MicroShellVent1Point8mmLong", "MicroShell vent, long, nominal 1.8 mm")
        case 56: ("MicroShellVent2Point4mm", "MicroShell vent, nominal 2.4 mm")
        case 57: ("MicroShellVent2Point4mmLong", "MicroShell vent, long, nominal 2.4 mm")
        case 58: ("MicroShellVent3mm", "MicroShell vent, nominal 3 mm")
        case 59: ("MicroShellVent3mmLong", "MicroShell vent, long, nominal 3 mm")
        case 60: ("MicroMouldEIEVent0Point8mm", "MicroMould EIE vent, nominal 0.8 mm")
        case 61: ("MicroMouldEIEVent1Point4mm", "MicroMould EIE vent, nominal 1.4 mm")
        case 62: ("MicroMouldEIEVent1Point8mm", "MicroMould EIE vent, nominal 1.8 mm")
        case 63: ("MicroMouldEIEVent2Point4mm", "MicroMould EIE vent, nominal 2.4 mm")
        case 64: ("MicroMouldEIEVent3mm", "MicroMould EIE vent, nominal 3 mm")
        default: nil
        }
    }

    private static func tubing(_ code: UInt8) -> Name? {
        switch code {
        case 0: ("Undefined", "Not specified")
        case 1: ("Bore1mm", "Bore, nominal 1 mm")
        case 2: ("Bore3mm", "Bore, nominal 3 mm")
        case 3: ("Horn", "Horn tubing")
        case 4: ("Insert1Point5mm", "Insert, nominal 1.5 mm")
        case 5: ("Insert2mm", "Insert, nominal 2 mm")
        case 6: ("Tube2mm", "Tube, nominal 2 mm")
        case 7: ("None", "None")
        default: nil
        }
    }

    private static func fittingLevel(_ code: UInt8) -> Name? {
        switch code {
        case 0: ("Undefined", "Not specified")
        case 1: ("Level60", "Level 60")
        case 2: ("Level75", "Level 75")
        case 3: ("Level80", "Level 80")
        case 4: ("Level85", "Level 85")
        case 5: ("Level90", "Level 90")
        case 6: ("Level100", "Level 100")
        case 7: ("Level105", "Level 105")
        case 8: ("Level45", "Level 45")
        case 9: ("Level55", "Level 55")
        case 10: ("Level65", "Level 65")
        case 11: ("Level110", "Level 110")
        case 12: ("Level120", "Level 120")
        case 20: ("None", "None")
        default: nil
        }
    }

    private static func fittedSide(_ code: UInt8) -> Name? {
        switch code {
        case 0: ("None", "Unassigned")
        case 1: ("Left", "Left")
        case 2: ("Right", "Right")
        default: nil
        }
    }
}
