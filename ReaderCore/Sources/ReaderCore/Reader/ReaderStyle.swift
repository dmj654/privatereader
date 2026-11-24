import Foundation
import CoreText

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 排版参数 → 富文本属性。用 CTFont 而非 UIFont，保持跨平台可测。
public struct ReaderStyle: Equatable, Sendable {
    public var fontSize: Double
    public var lineHeightMultiple: Double
    public var paragraphSpacing: Double
    public var firstLineIndent: Double
    public var fontName: String?

    public init(fontSize: Double = 17.5,
                lineHeightMultiple: Double = 2.05,
                paragraphSpacing: Double = 10,
                firstLineIndent: Double = 34,
                fontName: String? = nil) {
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.paragraphSpacing = paragraphSpacing
        self.firstLineIndent = firstLineIndent
        self.fontName = fontName
    }

    public static let `default` = ReaderStyle()

    public func attributes(color: CGColor) -> [NSAttributedString.Key: Any] {
        let font: CTFont
        if let fontName, !fontName.isEmpty {
            font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        } else {
            font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
                ?? CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.firstLineHeadIndent = firstLineIndent
        paragraphStyle.headIndent = 0

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
    }

    /// 正文按段落重组：把连续换行压成一个，段首加全角缩进。
    public static func normalizedBody(_ body: String) -> String {
        let lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.map { "　　" + $0 }.joined(separator: "\n")
    }
}
