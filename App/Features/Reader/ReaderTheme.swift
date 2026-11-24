import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case day, eyeCare, night, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "日间"
        case .eyeCare: return "护眼"
        case .night: return "夜间"
        case .black: return "纯黑"
        }
    }

    var background: Color {
        switch self {
        case .day: return Color(hex: 0xF8F9FA)
        case .eyeCare: return Color(hex: 0xEDEFE7)
        case .night: return Color(hex: 0x0E1116)
        case .black: return .black
        }
    }

    var textColor: Color {
        switch self {
        case .day, .eyeCare: return Color(hex: 0x2C323A)
        case .night, .black: return Color(hex: 0xC9D2DC)
        }
    }

    var chromeStyle: ColorScheme { self == .night || self == .black ? .dark : .light }

    var isDark: Bool { self == .night || self == .black }
}
