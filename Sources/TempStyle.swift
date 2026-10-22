import AppKit
import SwiftUI

// Color levels for the temperature number (thresholds are CPU °C).
enum TempLevel {
    case low, normal, high

    static let lowBelow = 45.0   // blue below this (idle)
    static let highFrom = 85.0   // red from this up (Apple Silicon throttles around 100°C)

    init(celsius c: Double) {
        if c < Self.lowBelow { self = .low } else if c >= Self.highFrom { self = .high } else { self = .normal }
    }

    /// nil means "use the normal text color".
    var nsColor: NSColor? {
        switch self {
        case .low: return .systemBlue
        case .normal: return nil
        case .high: return .systemRed
        }
    }

    var color: Color? { nsColor.map(Color.init(nsColor:)) }
}

enum MenuBarLabel {
    /// Menu bar labels are drawn as monochrome templates, so a colored number
    /// has to be drawn into a non-template image for the color to show.
    static func image(_ text: String, color: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { rect in
            string.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }
}
