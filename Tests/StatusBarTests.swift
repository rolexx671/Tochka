import AppKit

@main
struct StatusBarTests {
    static func main() {
        _ = NSApplication.shared
        precondition(!StatusBarInteraction.opensMenu(type: .leftMouseUp, modifiers: []))
        precondition(StatusBarInteraction.opensMenu(type: .rightMouseUp, modifiers: []))
        precondition(StatusBarInteraction.opensMenu(type: .leftMouseUp, modifiers: .control))
        precondition(StatusBarInteraction.opensMenu(type: .leftMouseUp, modifiers: [.control, .shift]))
        precondition(!StatusBarInteraction.opensMenu(type: nil, modifiers: []))
        let source = NSImage(contentsOfFile: "assets/AppIcon.icns")!
        source.size = NSSize(width: 20, height: 20)
        let gray = StatusBarAppearance.grayscale(source)!
        precondition(gray.size == source.size && !gray.isTemplate)
        let original = NSBitmapImageRep(cgImage: source.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let output = NSBitmapImageRep(cgImage: gray.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        precondition(output.pixelsWide == original.pixelsWide && output.pixelsHigh == original.pixelsHigh)
        var colored = 0
        var transparent = 0
        for y in 0..<output.pixelsHigh {
            for x in 0..<output.pixelsWide {
                let before = original.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let after = output.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                precondition(abs(before.alphaComponent - after.alphaComponent) < 0.01)
                if after.alphaComponent < 0.01 { transparent += 1; continue }
                precondition(abs(after.redComponent - after.greenComponent) < 0.015)
                precondition(abs(after.greenComponent - after.blueComponent) < 0.015)
                if abs(before.redComponent - before.greenComponent) > 0.1 { colored += 1 }
            }
        }
        precondition(colored > 0 && transparent > 0)
        try! gray.tiffRepresentation!.write(to: URL(fileURLWithPath: "build/verification/disabled-icon.tiff"))
        print("PASS: left/right/Ctrl clicks; grayscale icon has neutral RGB and unchanged transparency")
    }
}
