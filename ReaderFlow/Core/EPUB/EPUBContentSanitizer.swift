import Foundation

struct EPUBContentSanitizer {
    private let dangerousElementPatterns = [
        #"<\s*script\b[^>]*>[\s\S]*?<\s*/\s*script\s*>"#,
        #"<\s*iframe\b[^>]*>[\s\S]*?<\s*/\s*iframe\s*>"#,
        #"<\s*object\b[^>]*>[\s\S]*?<\s*/\s*object\s*>"#,
        #"<\s*embed\b[^>]*>"#,
        #"<\s*form\b[^>]*>[\s\S]*?<\s*/\s*form\s*>"#,
    ]

    func sanitizeHTML(_ html: String) -> String {
        var sanitized = html
        for pattern in dangerousElementPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        sanitized = sanitized.replacingOccurrences(
            of: #"\s+on[a-zA-Z]+\s*=\s*(['"]).*?\1"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"\s+(href|src|poster)\s*=\s*(['"])\s*javascript:[\s\S]*?\2"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"\s+(href|src|poster)\s*=\s*(['"])\s*https?://[\s\S]*?\2"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"url\(\s*(['"]?)\s*https?://[\s\S]*?\1\s*\)"#,
            with: "url()",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = sanitized.replacingOccurrences(
            of: #"@import\s+(['"])\s*https?://[\s\S]*?\1\s*;"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return sanitized
    }
}
