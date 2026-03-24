import SwiftUI

// MARK: - Hex Color Init

extension Color {
    /// Initialize a Color from a hex string like "#1a1a1a" or "10b981".
    init(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean = String(clean.dropFirst()) }

        var rgb: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Pomodare Design System Colors

extension Color {
    static let pomAccent  = Color(red: 0.91,  green: 0.365, blue: 0.016) // #e85d04
    static let pomSuccess = Color(red: 0.063, green: 0.725, blue: 0.506) // #10b981
    static let pomSurface = Color(red: 0.141, green: 0.141, blue: 0.141) // #242424
    static let pomBorder  = Color(red: 0.18,  green: 0.18,  blue: 0.18)  // #2e2e2e
    static let pomMuted   = Color(red: 0.533, green: 0.533, blue: 0.533) // #888888
    static let pomWarning = Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
}
