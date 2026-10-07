import Carbon
import CoreGraphics

struct Replacement: Equatable {
    let key: CGKeyCode
    let shift: Bool
    let text: String
}

enum Punctuation {
    static let russianID = "com.apple.keylayout.Russian"
    static let blocked: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]

    static func replacement(key: CGKeyCode, flags: CGEventFlags, sourceID: String) -> Replacement? {
        guard sourceID == russianID, flags.intersection(blocked).isEmpty else { return nil }
        let shift = flags.contains(.maskShift)
        switch (key, shift) {
        case (44, false): return Replacement(key: 26, shift: true, text: ".")
        case (44, true): return Replacement(key: 22, shift: true, text: ",")
        case (26, true): return Replacement(key: 44, shift: true, text: "?")
        case (22, true): return Replacement(key: 44, shift: false, text: "/")
        default: return nil
        }
    }

    static func currentSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    static func apply(_ replacement: Replacement, to event: CGEvent) {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(replacement.key))
        // Clear device-specific left/right Shift bits as well as the aggregate bit.
        // This matters when Shift+6 becomes an unshifted slash.
        var flags = event.flags
        flags = CGEventFlags(rawValue: flags.rawValue & ~UInt64(0x00000006))
        if replacement.shift { flags.insert(.maskShift) } else { flags.remove(.maskShift) }
        event.flags = flags
        let units = Array(replacement.text.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
    }
}

final class KeyTransformer {
    // Remember the decision until key-up, including keys that were passed through.
    // Switching layouts or pausing mid-press must not leave an unmatched key-up.
    private var pressed = Set<CGKeyCode>()
    private var replacements: [CGKeyCode: Replacement] = [:]

    func transform(type: CGEventType, event: CGEvent, enabled: Bool, sourceID: () -> String) {
        let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard [44, 26, 22].contains(key) else { return }
        if type == .keyDown {
            if !pressed.contains(key) {
                pressed.insert(key)
                if enabled {
                    replacements[key] = Punctuation.replacement(key: key, flags: event.flags, sourceID: sourceID())
                }
            }
            if let replacement = replacements[key] { Punctuation.apply(replacement, to: event) }
        } else if type == .keyUp {
            if let replacement = replacements.removeValue(forKey: key) { Punctuation.apply(replacement, to: event) }
            pressed.remove(key)
        }
    }

    func reset() { pressed.removeAll(); replacements.removeAll() }
}
