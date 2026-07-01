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

    @Test func detectsCommonRightsManagementMetadataPaths() {
        #expect(EPUBArchiveExpander.isRightsManagementPath("META-INF/rights.xml"))
        #expect(EPUBArchiveExpander.isRightsManagementPath("META-INF/license.lcpl"))
        #expect(EPUBArchiveExpander.isRightsManagementPath("META-INF/license.status"))
        #expect(EPUBArchiveExpander.isRightsManagementPath("meta-inf/RIGHTS.XML"))
        #expect(!EPUBArchiveExpander.isRightsManagementPath("META-INF/encryption.xml"))
        #expect(!EPUBArchiveExpander.isRightsManagementPath("OPS/Text/chapter.xhtml"))
    }

    @Test func distinguishesFontObfuscationFromProtectedEncryptionMetadata() {
        let fontObfuscation = """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
          </EncryptedData>
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://ns.adobe.com/pdf/enc#RC"/>
          </EncryptedData>
        </encryption>
        """
        let protectedEncryption = """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://readium.org/2014/01/lcp"/>
          </EncryptedData>
        </encryption>
        """
        let missingAlgorithm = """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"/>
        </encryption>
        """

        #expect(!EPUBUnsupportedPublicationDetector.hasProtectedEncryptionMetadata(Data(fontObfuscation.utf8)))
        #expect(EPUBUnsupportedPublicationDetector.hasProtectedEncryptionMetadata(Data(protectedEncryption.utf8)))
        #expect(EPUBUnsupportedPublicationDetector.hasProtectedEncryptionMetadata(Data(missingAlgorithm.utf8)))
    }

    @Test func detectsAppleFixedLayoutDisplayOptions() {
        let fixedLayout = """
        <display_options>
          <platform name="*">
            <option name="fixed-layout">true</option>
          </platform>
        </display_options>
        """
        let reflowable = """
        <display_options>
          <platform name="*">
            <option name="fixed-layout">false</option>
          </platform>
        </display_options>
        """

        #expect(EPUBUnsupportedPublicationDetector.hasAppleFixedLayoutDisplayOptions(Data(fixedLayout.utf8)))
        #expect(!EPUBUnsupportedPublicationDetector.hasAppleFixedLayoutDisplayOptions(Data(reflowable.utf8)))
    }
}
