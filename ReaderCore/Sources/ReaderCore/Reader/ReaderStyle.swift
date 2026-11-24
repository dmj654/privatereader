import Foundation
import CoreText

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 字体家族。只放系统里确定存在的三种，避免选了个名字却回退到系统字体还看不出来。
public enum ReaderFontFamily: String, CaseIterable, Codable, Sendable {
    case system
    case songti
    case kaiti

    public var title: String {
        switch self {
        case .system: return "系统"
        case .songti: return "宋体"
        case .kaiti: return "楷体"
        }
    }

    /// PostScript 名。iOS 上宋体是 STSongti-SC-*，楷体是 STKaiti-SC-*。
    var candidates: [String] {
        switch self {
        case .system:
            return []
        case .songti:
            return ["STSongti-SC-Regular", "Songti SC", "STSong"]
        case .kaiti:
            return ["STKaiti-SC-Regular", "Kaiti SC", "STKaiti"]
        }
    }
}

/// 排版参数 → 富文本属性。用 CTFont 而非 UIFont，保持跨平台可测。
public struct ReaderStyle: Hashable, Sendable {
    public var fontSize: Double
    public var lineHeightMultiple: Double
    public var paragraphSpacing: Double
    public var letterSpacing: Double
    public var marginHorizontal: Double
    public var marginTop: Double
    public var fontFamily: ReaderFontFamily
    /// 首行缩进两个字。以前是往正文里塞全角空格，同时又设 paragraphStyle 缩进，结果缩了两次。
    public var indentFirstLine: Bool
    public var justified: Bool

    public init(fontSize: Double = 17.5,
                lineHeightMultiple: Double = 1.95,
                paragraphSpacing: Double = 12,
                letterSpacing: Double = 0,
                marginHorizontal: Double = 22,
                marginTop: Double = 12,
                fontFamily: ReaderFontFamily = .system,
                indentFirstLine: Bool = true,
                justified: Bool = false) {
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.paragraphSpacing = paragraphSpacing
        self.letterSpacing = letterSpacing
        self.marginHorizontal = marginHorizontal
        self.marginTop = marginTop
        self.fontFamily = fontFamily
        self.indentFirstLine = indentFirstLine
        self.justified = justified
    }

    public static let `default` = ReaderStyle()

    /// 首行缩进宽度：两个字。
    public var indentWidth: Double {
        indentFirstLine ? fontSize * 2 : 0
    }

    public func attributes(color: CGColor) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineHeightMultiple
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.firstLineHeadIndent = indentWidth
        paragraphStyle.headIndent = 0
        paragraphStyle.alignment = justified ? .justified : .natural

        var result: [NSAttributedString.Key: Any] = [
            .font: font(),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        if abs(letterSpacing) > 0.01 {
            result[.kern] = letterSpacing
        }
        return result
    }

    /// 按家族解析字体；解析不到就退回系统字体，不会变成方框。
    ///
    /// 刻意分平台：
    /// - iOS 用 `UIFont(name:)`，能正确命中 STSongti / STKaiti 这些中文字体。
    /// - macOS 只走 CoreText，**不碰 AppKit**。CI 是无窗口进程，`NSFont` 的字体匹配
    ///   可能阻塞在系统字体服务上——上次 CI 卡了 29 分钟就是这么来的。
    public func font() -> CTFont {
        #if canImport(UIKit)
        for name in fontFamily.candidates {
            if let font = UIFont(name: name, size: fontSize) {
                return font as CTFont
            }
        }
        #else
        if let first = fontFamily.candidates.first {
            let candidate = CTFontCreateWithName(first as CFString, fontSize, nil)
            let resolved = CTFontCopyPostScriptName(candidate) as String
            if !resolved.isEmpty, resolved != "LastResort" {
                return candidate
            }
        }
        #endif

        return CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    }

    /// 正文按段落重组：把连续空行压成一个。
    /// 缩进交给 paragraphStyle，这里不再往正文里塞全角空格——否则会和首行缩进叠加成四格。
    public static func normalizedBody(_ body: String) -> String {
        let lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }
}
