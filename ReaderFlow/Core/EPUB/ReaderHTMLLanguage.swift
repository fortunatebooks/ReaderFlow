import Foundation

enum ReaderHTMLLanguage {
    static func attributeValue(for languageCode: String?) -> String {
        let fallback = "und"
        guard let languageCode else {
            return fallback
        }
        let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !trimmed.isEmpty else {
            return fallback
        }
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        let isSafe = trimmed.unicodeScalars.allSatisfy { scalar in
            allowedCharacters.contains(scalar)
        }
        return isSafe ? trimmed.htmlEscaped : fallback
    }
}
