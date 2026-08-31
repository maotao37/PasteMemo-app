import Foundation

struct TemplateContext: Equatable {
    var date: Date = Date()
    var name = ""
    var project = ""
    var clipboard = ""
}

enum TemplateRenderer {
    static let supportedVariables = ["date", "time", "datetime", "name", "project", "clipboard"]

    static func render(_ template: String, context: TemplateContext, locale: Locale = .current) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = locale
        dateTimeFormatter.dateStyle = .medium
        dateTimeFormatter.timeStyle = .short

        let values = [
            "date": dateFormatter.string(from: context.date),
            "time": timeFormatter.string(from: context.date),
            "datetime": dateTimeFormatter.string(from: context.date),
            "name": context.name,
            "project": context.project,
            "clipboard": context.clipboard,
        ]

        return values.reduce(template) { result, entry in
            result.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value)
        }
    }
}
