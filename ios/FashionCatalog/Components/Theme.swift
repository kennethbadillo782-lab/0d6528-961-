import SwiftUI

enum Theme {
    static let background = Color.black
    static let card = Color(hex: 0x1B1F24)
    static let search = Color(hex: 0x20242A)
    static let chip = Color(hex: 0x24282D)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xA0A5AD)
    static let blue = Color(hex: 0x287BFF)
    static let heart = Color(hex: 0xF04C79)
    static let border = Color(hex: 0x30343A)
    static let green = Color(hex: 0x3CCB7F)
    static let red = Color(hex: 0xE5484D)
    static let accent = Color(hex: 0x8B7CF6)
    static let star = Color(hex: 0xF5C451)

    static let hPadding: CGFloat = 16
    static let cardRadius: CGFloat = 12
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum DateText {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let withTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PR")
        f.dateFormat = "d MMM yyyy, h:mm a"
        return f
    }()

    static func short(_ date: Date) -> String {
        formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func long(_ date: Date) -> String {
        withTime.string(from: date).replacingOccurrences(of: ".", with: "")
    }
}
