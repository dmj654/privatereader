import Foundation

/// 决定"从这一页开始听，第一句该是哪一句"。
///
/// 单独的纯函数而不是塞在 ViewModel 里，是因为这里有三个很容易错的边界：
/// 1. 章标题排在正文前面，但它不是正文——朗读不该从"第三章 XXX"开始念。
/// 2. 分页可能把一句话切成两半，页首位置落在句子中间，要找到**包含**它的那句。
/// 3. 页首位置可能正好在某句结束之后、下一句开始之前（空白），要落到下一句。
///
/// 之前的问题是 1：新章第一页的位置是 0，匹配到第一句（章标题）就停下，
/// 用户听到的是标题，体感就是"正文第一句没读"。
public enum SpeechStartLocator {

    /// - Parameters:
    ///   - sentences: 整章的句子（按位置升序）
    ///   - pageLocation: 当前页第一个字符在整章文本里的 UTF-16 偏移
    ///   - titleLength: 章标题的 UTF-16 长度；标题在整章文本的最前面
    ///   - skipTitle: 是否跳过章标题。只在从章首开始听时为 true
    /// - Returns: 应当开始朗读的句子下标
    public static func startIndex(sentences: [SpeechSentence],
                                  pageLocation: Int,
                                  titleLength: Int,
                                  skipTitle: Bool = true) -> Int {
        guard !sentences.isEmpty else { return 0 }

        var index = locate(sentences: sentences, pageLocation: pageLocation)

        if skipTitle, titleLength > 0 {
            // 标题占据 [0, titleLength)，后面紧跟换行。任何起点落在这一段里的句子
            // 都属于标题（标题里可能带句号、被切成多句），全部跳过。
            while index < sentences.count, sentences[index].location < titleLength {
                index += 1
            }
            if index >= sentences.count { index = sentences.count - 1 }
        }
        return index
    }

    private static func locate(sentences: [SpeechSentence], pageLocation: Int) -> Int {
        if let hit = sentences.firstIndex(where: { NSLocationInRange(pageLocation, $0.range) }) {
            return hit
        }
        // 页首落在空白里（上一句结尾与下一句开头之间）：取下一句。
        if let next = sentences.firstIndex(where: { $0.location > pageLocation }) {
            return next
        }
        return sentences.count - 1
    }
}
