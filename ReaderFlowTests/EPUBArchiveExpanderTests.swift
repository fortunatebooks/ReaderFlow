import Foundation
@testable import ReaderFlow
import Testing

struct EPUBArchiveExpanderTests {
    @Test func rejectsUnsafeArchivePaths() {
        #expect(EPUBArchiveExpander.isSafeArchivePath("OPS/chapter1.xhtml"))
        #expect(EPUBArchiveExpander.isSafeArchivePath("META-INF/container.xml"))
        #expect(!EPUBArchiveExpander.isSafeArchivePath("/absolute/path.xhtml"))
        #expect(!EPUBArchiveExpander.isSafeArchivePath("../secret.txt"))
        #expect(!EPUBArchiveExpander.isSafeArchivePath("OPS/../secret.txt"))
        #expect(!EPUBArchiveExpander.isSafeArchivePath("%2e%2e/secret.txt"))
        #expect(!EPUBArchiveExpander.isSafeArchivePath(""))
    }

    @Test func expandedArchiveKnowsContainerURL() {
        let archive = ExpandedEPUBArchive(rootURL: URL(filePath: "/tmp/book"))

        #expect(archive.containerURL.path == "/tmp/book/META-INF/container.xml")
    }
}
