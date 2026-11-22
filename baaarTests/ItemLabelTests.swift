import Testing

@Suite struct ItemLabelTests {
    /// Reads answered in order, one per call, as Accessibility would answer them over time.
    final class Reads {
        private var answers: [String: [String?]]
        private(set) var count = 0

        init(_ answers: [String: [String?]]) {
            self.answers = answers
        }

        func read(_ attribute: String) -> String? {
            count += 1
            guard var queue = answers[attribute], !queue.isEmpty else { return nil }
            let answer = queue.removeFirst()
            answers[attribute] = queue
            return answer
        }
    }

    @Test func aTitleThatGoesEmptyAfterTheFirstReadIsKept() {
        let reads = Reads(["AXTitle": ["caffeinated", nil]])
        #expect(ItemLabel.first(of: ["AXTitle", "AXDescription"], read: reads.read) == "caffeinated")
        #expect(reads.count == 1)
    }

    @Test func anEmptyTitleFallsBackToTheDescription() {
        let reads = Reads(["AXTitle": [""], "AXDescription": ["battery"]])
        #expect(ItemLabel.first(of: ["AXTitle", "AXDescription"], read: reads.read) == "battery")
        #expect(reads.count == 2)
    }

    @Test func onlyTheFirstLineIsTheLabel() {
        let reads = Reads(["AXTitle": ["wi-fi\nconnected"]])
        #expect(ItemLabel.first(of: ["AXTitle"], read: reads.read) == "wi-fi")
    }

    @Test func noTextIsNoLabel() {
        let reads = Reads([:])
        #expect(ItemLabel.first(of: ["AXTitle", "AXDescription"], read: reads.read) == nil)
        #expect(reads.count == 2)
    }
}
