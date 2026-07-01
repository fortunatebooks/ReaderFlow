import Foundation

struct EPUBPreflightResult: Codable, Hashable {
    var compressedSizeBytes: Int64
    var expandedSizeBytes: Int64
    var xhtmlSizeBytes: Int64
    var spineItemCount: Int
    var estimatedDomNodeCount: Int
    var imageCount: Int

    static let empty = EPUBPreflightResult(
        compressedSizeBytes: 0,
        expandedSizeBytes: 0,
        xhtmlSizeBytes: 0,
        spineItemCount: 0,
        estimatedDomNodeCount: 0,
        imageCount: 0
    )
}

struct EPUBPreflightLimits {
    var maximumCompressedSizeBytes: Int64 = 150 * 1024 * 1024
    var maximumExpandedSizeBytes: Int64 = 300 * 1024 * 1024
    var maximumXHTMLSizeBytes: Int64 = 8 * 1024 * 1024
    var maximumSpineItemCount: Int = 400
    var maximumImageCount: Int = 1000

    func allows(_ result: EPUBPreflightResult) -> Bool {
        result.compressedSizeBytes <= maximumCompressedSizeBytes &&
            result.expandedSizeBytes <= maximumExpandedSizeBytes &&
            result.xhtmlSizeBytes <= maximumXHTMLSizeBytes &&
            result.spineItemCount <= maximumSpineItemCount &&
            result.imageCount <= maximumImageCount
    }
}
