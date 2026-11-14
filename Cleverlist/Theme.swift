import SwiftUI

enum Theme: String, Codable, CaseIterable, Identifiable {
    case summer, winter, christmas, halloween, autumn, spring
    var id: String { rawValue }
    var artwork: String { "season-" + rawValue }
    var accent: Color { Color(hex: palette.0) }
    var secondary: Color { Color(hex: palette.1) }
    var background: Color { Color(hex: palette.2) }
    private var palette: (String, String, String) {
        switch self {
        case .summer: ("186648", "F1B31C", "E7F3C8")
        case .winter: ("1E50A0", "61B2E4", "DCEFFA")
        case .christmas: ("9D1833", "E65C64", "F8DFE1")
        case .halloween: ("623A84", "F4AA41", "EBDCF4")
        case .autumn: ("6A462F", "E27022", "F6E3C4")
        case .spring: ("674481", "B1CC33", "EEDFF1")
        }
    }
    func name(_ language: Language) -> String {
        let names: [Theme: [String]] = [
            .summer: ["Summer", "Sommar", "Sommer"],
            .winter: ["Winter", "Vinter", "Winter"],
            .christmas: ["Christmas", "Jul", "Weihnachten"],
            .halloween: ["Halloween", "Halloween", "Halloween"],
            .autumn: ["Autumn", "Höst", "Herbst"],
            .spring: ["Spring", "Vår", "Frühling"]
        ]
        return names[self]?[language == .en ? 0 : language == .sv ? 1 : 2] ?? rawValue
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0x167D65
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255, opacity: 1)
    }
}
