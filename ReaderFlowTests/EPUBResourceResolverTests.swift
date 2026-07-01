import Foundation
@testable import ReaderFlow
import Testing

struct EPUBResourceResolverTests {
    @Test func normalizesSafeRelativePaths() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("images/cover.jpg", relativeTo: "chapter1.xhtml"))

        #expect(path == "OPS/images/cover.jpg")
    }

    @Test func rejectsTraversalOutsidePackage() {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        #expect(resolver.normalizedResourcePath("../../secret.txt", relativeTo: "chapter1.xhtml") == nil)
        #expect(resolver.normalizedResourcePath("../secret.txt", relativeTo: "chapter1.xhtml") == nil)
        #expect(resolver.normalizedResourcePath("%2e%2e/secret.txt", relativeTo: "chapter1.xhtml") == nil)
    }

    @Test func resolvesNestedBasePathsInsidePackageRoot() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("../images/cover.jpg", relativeTo: "Text/chapter1.xhtml"))

        #expect(path == "OPS/images/cover.jpg")
    }

    @Test func doesNotDuplicatePackageRootWhenBasePathIncludesIt() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("../images/cover.jpg", relativeTo: "OPS/Text/chapter1.xhtml"))

        #expect(path == "OPS/images/cover.jpg")
    }

    @Test func preservesFragments() throws {
        let resolver = EPUBResourceResolver(packageRoot: "OPS")

        let path = try #require(resolver.normalizedResourcePath("chapter2.xhtml#note", relativeTo: "chapter1.xhtml"))

        #expect(path == "OPS/chapter2.xhtml#note")
    }
}
