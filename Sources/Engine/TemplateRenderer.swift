import Foundation

struct TemplateContext: Equatable {
    var date: Date = Date()
    var name = ""
    var project = ""
    var clipboard = ""
    /// Pinned per render so the same context always produces the same text.
    var timeZone: TimeZone = .current
}

enum TemplateRenderer {
    static let builtinVariables = ["date", "time", "datetime", "name", "project", "clipboard"]

    /// Kept for existing callers; the editor UI groups variables by kind instead.
    static let supportedVariables = builtinVariables

    /// `{{variable}}` or `{{variable:format}}`. Whitespace inside the braces is
    /// part of the name, matching the exact-match semantics of the original renderer.
    private static let variableRegex = try! NSRegularExpression(pattern: #"\{\{([^:}]+)(?::([^}]*))?\}\}"#)

    /// ICU reserved pattern letters. An unquoted ASCII letter outside this set
    /// (or an unterminated quote) is treated as an invalid format and falls back
    /// to the default style — malformed patterns must never crash the formatter.
    private static let dateFormatLetters: Set<Character> = [
        "G", "y", "Y", "u", "U", "Q", "q", "M", "L", "l", "w", "W", "d", "D", "F",
        "E", "e", "c", "a", "b", "B", "H", "h", "K", "k", "m", "s", "S", "A",
        "z", "Z", "v", "V", "x", "X",
    ]

    static func render(
        _ template: String,
        context: TemplateContext,
        fills: [String: String] = [:],
        locale: Locale = .current
    ) -> String {
        let ns = template as NSString
        let matches = variableRegex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return template }

        var output = ""
        var cursor = 0
        for match in matches {
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = ns.substring(with: nameRange)
            let format = match.range(at: 2).location == NSNotFound
                ? nil
                : ns.substring(with: match.range(at: 2))
            output += resolvedValue(name: name, format: format, context: context, fills: fills, locale: locale)
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    /// Non-builtin `{{names}}` in order of first appearance, deduplicated.
    static func placeholderNames(in template: String) -> [String] {
        let ns = template as NSString
        var seen = Set<String>()
        var names: [String] = []
        for match in variableRegex.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            let nameRange = match.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }
            let name = ns.substring(with: nameRange)
            if !builtinVariables.contains(name), seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    private static func resolvedValue(
        name: String,
        format: String?,
        context: TemplateContext,
        fills: [String: String],
        locale: Locale
    ) -> String {
        switch name {
        case "date":
            return dateString(context.date, format: format, dateStyle: .medium, timeStyle: .none, locale: locale, timeZone: context.timeZone)
        case "time":
            return dateString(context.date, format: format, dateStyle: .none, timeStyle: .short, locale: locale, timeZone: context.timeZone)
        case "datetime":
            return dateString(context.date, format: format, dateStyle: .medium, timeStyle: .short, locale: locale, timeZone: context.timeZone)
        case "name":
            return context.name
        case "project":
            return context.project
        case "clipboard":
            return context.clipboard
        default:
            return fills[name] ?? ""
        }
    }

    private static func dateString(
        _ date: Date,
        format: String?,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if let format, isValidDateFormat(format) {
            formatter.dateFormat = format
        } else {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
        }
        return formatter.string(from: date)
    }

    private static func isValidDateFormat(_ pattern: String) -> Bool {
        guard !pattern.isEmpty, pattern.count <= 64 else { return false }
        var inQuote = false
        for char in pattern {
            if char == "'" { inQuote.toggle(); continue }
            if inQuote { continue }
            if char.isASCII, char.isLetter, !dateFormatLetters.contains(char) { return false }
        }
        // An unterminated quote leaves the tail of the pattern as literal text
        // in ICU, which never matches user intent — treat it as invalid.
        return !inQuote
    }
}
