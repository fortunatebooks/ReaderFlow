import Foundation
import SwiftData

@Model
final class ReaderSettingsEntity {
    @Attribute(.unique) var id: UUID
    var theme: String
    var fontFamily: String
    var textSize: Double
    var lineHeight: Double
    var marginScale: Double
    var autoscrollSpeed: Double
    var autoCopyHighlights: Bool
    var hapticsEnabled: Bool
    var exportDetailLevel: String
    var schemaVersion: Int

    init(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
        theme: ReaderTheme = .system,
        fontFamily: ReaderFontFamily = .systemSerif,
        textSize: Double = 18,
        lineHeight: Double = 1.55,
        marginScale: Double = 1,
        autoscrollSpeed: Double = 25,
        autoCopyHighlights: Bool = false,
        hapticsEnabled: Bool = true,
        exportDetailLevel: ExportDetailLevel = .detailed,
        schemaVersion: Int = 1
    ) {
        self.id = id
        self.theme = theme.rawValue
        self.fontFamily = fontFamily.rawValue
        self.textSize = textSize
        self.lineHeight = lineHeight
        self.marginScale = marginScale
        self.autoscrollSpeed = autoscrollSpeed
        self.autoCopyHighlights = autoCopyHighlights
        self.hapticsEnabled = hapticsEnabled
        self.exportDetailLevel = exportDetailLevel.rawValue
        self.schemaVersion = schemaVersion
    }
}

enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }
}

enum ReaderFontFamily: String, Codable, CaseIterable, Identifiable {
    case systemSerif
    case systemSans
    case atkinsonHyperlegible
    case literata
    case sourceSerif4
    case georgia
    case palatino
    case avenirNext
    case monospaced

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .systemSerif: "System Serif"
        case .systemSans: "System Sans"
        case .atkinsonHyperlegible: "Atkinson Hyperlegible"
        case .literata: "Literata"
        case .sourceSerif4: "Source Serif 4"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .avenirNext: "Avenir Next"
        case .monospaced: "Monospaced"
        }
    }
}

enum ExportDetailLevel: String, Codable, CaseIterable, Identifiable {
    case simple
    case detailed

    var id: String {
        rawValue
    }
}
