@testable import ReaderFlow
import Testing

struct ReaderResourcePathTests {
    @Test func decodesSafeResourcePathParts() {
        #expect(
            ReaderResourcePath.parts(fromPercentEncodedPath: "/fonts/AtkinsonHyperlegible/AtkinsonHyperlegible-Regular.otf") == [
                "fonts",
                "AtkinsonHyperlegible",
                "AtkinsonHyperlegible-Regular.otf",
            ]
        )
        #expect(
            ReaderResourcePath.parts(fromPercentEncodedPath: "/book/123/Text/chapter%201.xhtml") == [
                "book",
                "123",
                "Text",
                "chapter 1.xhtml",
            ]
        )
        #expect(
            ReaderResourcePath.encodedParts(fromPercentEncodedPath: "/book/123/OPS/Images/cover%231.jpg") == [
                "book",
                "123",
                "OPS",
                "Images",
                "cover%231.jpg",
            ]
        )
    }

    @Test func rejectsTraversalAndSeparatorInjection() {
        #expect(ReaderResourcePath.parts(fromPercentEncodedPath: "/fonts/../Info.plist").isEmpty)
        #expect(ReaderResourcePath.parts(fromPercentEncodedPath: "/fonts/AtkinsonHyperlegible%2F..%2F../Info.plist").isEmpty)
        #expect(ReaderResourcePath.parts(fromPercentEncodedPath: "/fonts/AtkinsonHyperlegible%5C..%5CInfo.plist").isEmpty)
        #expect(ReaderResourcePath.parts(fromPercentEncodedPath: "/fonts/AtkinsonHyperlegible%00Regular.otf").isEmpty)
    }
}
