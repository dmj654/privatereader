import XCTest
@testable import ReaderCore

final class SentenceSplitterTests: XCTestCase {
    func testSplitsOnChinesePunctuation() {
        let sentences = SentenceSplitter.split("第一句。第二句！第三句？")
        XCTAssertEqual(sentences.count, 3)
        XCTAssertEqual(sentences[0].text, "第一句。")
        XCTAssertEqual(sentences[1].text, "第二句！")
        XCTAssertEqual(sentences[2].text, "第三句？")
    }

    func testLocationsAreContiguousAndInOrder() {
        let text = "　　第一句。第二句！第三句？"
        let sentences = SentenceSplitter.split(text)

        // 段首两个全角空格不该进第一句
        XCTAssertEqual(sentences[0].location, 2)
        XCTAssertEqual(sentences[0].length, 4)

        for pair in zip(sentences, sentences.dropFirst()) {
            XCTAssertLessThan(pair.0.location, pair.1.location, "句子的位置必须递增")
        }

        let ns = text as NSString
        for sentence in sentences {
            let sliced = ns.substring(with: sentence.range)
            XCTAssertEqual(sliced, sentence.text, "偏移必须能切回原句")
        }
    }

    func testClosingQuoteBelongsToTheSentence() {
        let sentences = SentenceSplitter.split("他说：“走吧。”然后离开。")
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].text, "他说：“走吧。”")
        XCTAssertEqual(sentences[1].text, "然后离开。")
    }

    func testNewlineEndsSentence() {
        let sentences = SentenceSplitter.split("第一行\n第二行")
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].text, "第一行")
        XCTAssertEqual(sentences[1].text, "第二行")
    }

    func testNoPunctuationStillReturnsOneSentence() {
        let sentences = SentenceSplitter.split("这句话没有任何标点")
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences[0].text, "这句话没有任何标点")
    }

    func testEmptyInputReturnsNothing() {
        XCTAssertTrue(SentenceSplitter.split("").isEmpty)
        XCTAssertTrue(SentenceSplitter.split("　　\n  \n").isEmpty)
    }

    func testVeryLongSentenceIsSplitAtComma() {
        let clause = String(repeating: "很长的一段话，", count: 40)
        let sentences = SentenceSplitter.split(clause, maxLength: 60)

        XCTAssertGreaterThan(sentences.count, 1, "长句必须被切开，不能一口气念半分钟")
        for sentence in sentences {
            XCTAssertLessThanOrEqual(sentence.length, 80, "切完的句子不该还是超长")
        }
    }

    func testSplitPreservesAllVisibleCharacters() {
        let text = "　　他抬头看了看天。天很蓝，云很白。风停了。"
        let sentences = SentenceSplitter.split(text)
        let joined = sentences.map(\.text).joined()
        XCTAssertEqual(joined, text.trimmingCharacters(in: .whitespacesAndNewlines),
                       "切分不能丢字，否则念出来会跳句")
    }
}

final class SpeechQueueTests: XCTestCase {
    private func makeQueue(_ texts: [String]) -> SpeechQueue {
        var sentences: [SpeechSentence] = []
        var location = 0
        for text in texts {
            sentences.append(SpeechSentence(text: text, location: location, length: (text as NSString).length))
            location += (text as NSString).length
        }
        return SpeechQueue(sentences: sentences)
    }

    func testAdvanceThroughChapter() {
        var queue = makeQueue(["一。", "二。", "三。"])
        XCTAssertEqual(queue.current?.text, "一。")
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.text, "二。")
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.text, "三。")
        XCTAssertFalse(queue.advance(), "最后一句再前进应当报告到头")
        XCTAssertEqual(queue.current?.text, "三。", "到头后不能越界")
    }

    func testIsAtEnd() {
        var queue = makeQueue(["一。", "二。"])
        XCTAssertFalse(queue.isAtEnd)
        _ = queue.advance()
        XCTAssertTrue(queue.isAtEnd)
    }

    func testRewindStopsAtFirst() {
        var queue = makeQueue(["一。", "二。"])
        XCTAssertFalse(queue.rewind())
        _ = queue.advance()
        XCTAssertTrue(queue.rewind())
        XCTAssertEqual(queue.current?.text, "一。")
    }

    func testJumpClampsIntoRange() {
        var queue = makeQueue(["一。", "二。", "三。"])
        queue.jump(to: 99)
        XCTAssertEqual(queue.index, 2)
        queue.jump(to: -5)
        XCTAssertEqual(queue.index, 0)
    }

    func testIndexContainingLocation() {
        // "一。"=2, "二。"=4, "三。"=6
        let queue = makeQueue(["一。", "二。", "三。"])
        XCTAssertEqual(queue.index(containing: 0), 0)
        XCTAssertEqual(queue.index(containing: 2), 1)
        XCTAssertEqual(queue.index(containing: 5), 2)
        // 落在空白处时，回退到前面最近的一句
        XCTAssertEqual(queue.index(containing: 3), 1)
    }

    func testEmptyQueueIsSafe() {
        let queue = SpeechQueue(sentences: [])
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isAtEnd)
        var mutable = queue
        XCTAssertFalse(mutable.advance())
        mutable.jump(to: 3)
        XCTAssertNil(mutable.current)
    }
}
