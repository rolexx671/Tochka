import Carbon
import CoreGraphics
import Foundation

@main
struct Tests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        // Search all installed sources, not just enabled ones: CI machines have no Russian layout enabled.
        let russianFilter = [kTISPropertyInputSourceID as String: Punctuation.russianID] as CFDictionary
        let russian = (TISCreateInputSourceList(russianFilter, true).takeRetainedValue() as! [TISInputSource]).first!
        let raw = TISGetInputSourceProperty(russian, kTISPropertyUnicodeKeyLayoutData)!
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
        func translate(_ key: CGKeyCode, _ shift: Bool, _ caps: Bool) -> String {
            var dead: UInt32 = 0; var count = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let mods = (shift ? UInt32(shiftKey) : 0) | (caps ? UInt32(alphaLock) : 0)
            let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), mods >> 8,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 8, &count, &chars)
            check(status == noErr, "UCKeyTranslate failed")
            return String(utf16CodeUnits: chars, count: count)
        }
        // The allowlist must not depend on a second layout being U.S., or on list order.
        let foreignIDs = ["com.apple.keylayout.US", "com.apple.keylayout.ABC",
            "com.apple.keylayout.British", "com.apple.keylayout.French", "com.apple.keylayout.German",
            "com.apple.keylayout.Ukrainian", "com.apple.keylayout.Arabic",
            "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "com.apple.keylayout.RussianWin",
            "com.apple.keylayout.Russian-Phonetic", "example.unknown", ""]
        let installedIDs: [String] = sources.compactMap { source in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        }
        let sourceIDs = Array(Set(foreignIDs + installedIDs + [Punctuation.russianID])).sorted()
        let modifiers: [CGEventFlags] = [.maskShift, .maskAlphaShift, .maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]
        for key: CGKeyCode in 0..<128 {
            for bits in 0..<64 {
                let flags = modifiers.enumerated().reduce(CGEventFlags()) { result, item in
                    bits & (1 << item.offset) == 0 ? result : result.union(item.element)
                }
                for id in sourceIDs {
                    let result = Punctuation.replacement(key: key, flags: flags, sourceID: id)
                    let eligible = id == Punctuation.russianID && flags.intersection(Punctuation.blocked).isEmpty
                    let expected: String? = !eligible ? nil : key == 44 ? (flags.contains(.maskShift) ? "," : ".")
                        : key == 26 && flags.contains(.maskShift) ? "?"
                        : key == 22 && flags.contains(.maskShift) ? "/" : nil
                    check(result?.text == expected, "Unexpected mapping: \(id) \(key) \(bits)")
                    if let result {
                        check(translate(result.key, result.shift, flags.contains(.maskAlphaShift)) == expected,
                            "Actual Russian keyboard output differs")
                        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
                        event.flags = flags
                        Punctuation.apply(result, to: event)
                        var chars = [UniChar](repeating: 0, count: 8); var length = 0
                        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
                        check(String(utf16CodeUnits: chars, count: length) == expected, "Unicode mismatch")
                        check(event.flags.contains(.maskShift) == result.shift, "Shift mismatch")
                    }
                }
            }
        }
        func event(_ key: CGKeyCode, _ down: Bool, _ flags: CGEventFlags = []) -> CGEvent {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
            e.flags = flags; return e
        }
        let transformer = KeyTransformer()
        let down = event(44, true)
        transformer.transform(type: .keyDown, event: down, enabled: true) { Punctuation.russianID }
        check(down.getIntegerValueField(.keyboardEventKeycode) == 26, "Key-down not remapped")
        let repeatEvent = event(44, true)
        repeatEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        transformer.transform(type: .keyDown, event: repeatEvent, enabled: false) { "com.apple.keylayout.US" }
        check(repeatEvent.getIntegerValueField(.keyboardEventKeycode) == 26, "Repeat lost original decision")
        let up = event(44, false)
        transformer.transform(type: .keyUp, event: up, enabled: false) { "com.apple.keylayout.US" }
        check(up.getIntegerValueField(.keyboardEventKeycode) == 26, "Key-up lost original decision")
        let english = event(44, true)
        transformer.transform(type: .keyDown, event: english, enabled: true) { "com.apple.keylayout.US" }
        check(english.getIntegerValueField(.keyboardEventKeycode) == 44, "English modified")
        let englishRepeat = event(44, true)
        transformer.transform(type: .keyDown, event: englishRepeat, enabled: true) { Punctuation.russianID }
        check(englishRepeat.getIntegerValueField(.keyboardEventKeycode) == 44, "English repeat modified after switch")
        transformer.reset()
        let paused = event(22, true, .maskShift)
        transformer.transform(type: .keyDown, event: paused, enabled: false) { Punctuation.russianID }
        check(paused.getIntegerValueField(.keyboardEventKeycode) == 22, "Paused app modified input")
        for id in foreignIDs {
            for key: CGKeyCode in [44, 26, 22] {
                for flags: CGEventFlags in [[], .maskShift, .maskAlphaShift, [.maskShift, .maskAlphaShift]] {
                    transformer.reset()
                    for type in [CGEventType.keyDown, .keyDown, .keyUp] {
                        let original = event(key, type != .keyUp, flags)
                        let before = original.data!
                        transformer.transform(type: type, event: original, enabled: true) { id }
                        check(CFEqual(before, original.data!), "Foreign event modified: \(id) \(key)")
                    }
                }
            }
        }
        for shiftBits: UInt64 in [0x2, 0x4] {
            let e = event(22, true, CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | shiftBits))
            transformer.reset()
            transformer.transform(type: .keyDown, event: e, enabled: true) { Punctuation.russianID }
            check(!e.flags.contains(.maskShift) && e.flags.rawValue & 0x6 == 0, "Physical Shift not cleared")
        }
        transformer.reset()
        let offDown = event(44, true)
        transformer.transform(type: .keyDown, event: offDown, enabled: false) { Punctuation.russianID }
        let onRepeat = event(44, true)
        transformer.transform(type: .keyDown, event: onRepeat, enabled: true) { Punctuation.russianID }
        check(onRepeat.getIntegerValueField(.keyboardEventKeycode) == 44, "Enabling changed a held key")
        let offUp = event(44, false)
        transformer.transform(type: .keyUp, event: offUp, enabled: true) { Punctuation.russianID }
        check(offUp.getIntegerValueField(.keyboardEventKeycode) == 44, "Enabling changed paired key-up")
        print("PASS: \(checks) checks; actual macOS Russian layout, all sampled and installed input sources, keys/modifiers, shortcuts, repeat and key-up.")
    }
}
