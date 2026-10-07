import AppKit
import CoreImage

enum StatusBarInteraction {
    static func opensMenu(type: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseUp || modifiers.contains(.control)
    }
}

enum StatusBarAppearance {
    static func grayscale(_ source: NSImage) -> NSImage? {
        guard let bitmap = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: bitmap)
        let output = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        guard let result = CIContext().createCGImage(output, from: input.extent) else { return nil }
        let image = NSImage(cgImage: result, size: source.size)
        image.isTemplate = false
        return image
    }
}
