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
    ///
    /// 选句规则：**取这一页上开始的第一个完整句子**，而不是"包含页首的句子"。
    ///
    /// 后者在字号、行距变化后最容易出问题：分页会把一句话切成两半，
    /// 页首落在句子中间，于是"这一页的第一句"其实是上一页那半句。
    /// 朗读从上一页的内容开口，高亮也只亮在上一页——听感和视觉都错位。
    /// 宁可漏掉页首那半句，也不要读了半天还停在上一页。
    public static func startIndex(sentences: [SpeechSentence],
                                  pageLocation: Int,
                                  titleLength: Int,
                                  skipTitle: Bool = true) -> Int {
        guard !sentences.isEmpty else { return 0 }

        var index = firstStartingAtOrAfter(sentences, location: pageLocation)
        if index == nil {
            // 整页都在一句话中间，页面上没有任何句子从头开始：
            // 只能退回包含页首的那句，否则这一页没得读。
            index = containing(sentences, location: pageLocation)
        }
        var start = index ?? 0

        if skipTitle, titleLength > 0 {
            // 标题占据 [0, titleLength)，后面紧跟换行。任何起点落在这一段里的句子
            // 都属于标题（标题里可能带句号、被切成多句），全部跳过。
            while start < sentences.count, sentences[start].location < titleLength {
                start += 1
            }
            if start >= sentences.count { start = sentences.count - 1 }
        }
        return start
    }

    /// 页首之后（含正好等于页首）开始的第一句。
    private static func firstStartingAtOrAfter(_ sentences: [SpeechSentence], location: Int) -> Int? {
        sentences.firstIndex { $0.location >= location }
    }

    private static func containing(_ sentences: [SpeechSentence], location: Int) -> Int {
        if let hit = sentences.firstIndex(where: { NSLocationInRange(location, $0.range) }) {
            return hit
        }
        // 页首落在空白里（上一句结尾与下一句开头之间）：取下一句。
        if let next = sentences.firstIndex(where: { $0.location > location }) {
            return next
        }
        return sentences.count - 1
    }
}
