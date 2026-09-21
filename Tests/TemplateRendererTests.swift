import Foundation
import Testing
@testable import PasteMemo

@Suite("Template renderer")
struct TemplateRendererTests {
    /// 2024-01-02 03:04:05 UTC — pinned so formatted output is stable across machines.
    private let fixedDate = Date(timeIntervalSince1970: 1_704_164_645)
    private let posixLocale = Locale(identifier: "en_US_POSIX")
    private var utcContext: TemplateContext {
        TemplateContext(date: fixedDate, timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test("expands profile, project, clipboard, and date variables")
    func expandsSupportedVariables() {
        let result = TemplateRenderer.render(
            "{{name}}|{{project}}|{{clipboard}}|{{date}}|{{time}}|{{datetime}}",
            context: TemplateContext(date: fixedDate, name: "Taylor", project: "Apollo", clipboard: "payload"),
            locale: posixLocale
        )

        #expect(result.contains("Taylor|Apollo|payload|"))
        #expect(!result.contains("{{date}}"))
        #expect(!result.contains("{{time}}"))
        #expect(!result.contains("{{datetime}}"))
    }

    @Test("repeated variables render every occurrence")
    func repeatedVariables() {
        let result = TemplateRenderer.render(
            "{{name}}/{{name}}",
            context: TemplateContext(name: "A")
        )
        #expect(result == "A/A")
    }

    @Test("custom ICU format overrides the default date style")
    func customDateFormat() {
        let result = TemplateRenderer.render(
            "{{date:yyyy-MM-dd}} {{time:HH:mm}}",
            context: utcContext,
            locale: posixLocale
        )
        #expect(result == "2024-01-02 03:04")
    }

    @Test("non-ASCII literals such as 年月日 are valid pattern text")
    func nonAsciiLiteralsInFormat() {
        let result = TemplateRenderer.render(
            "{{date:yyyy年M月d日}}",
            context: utcContext,
            locale: posixLocale
        )
        #expect(result == "2024年1月2日")
    }

    @Test("invalid format falls back to the default style")
    func invalidFormatFallsBack() {
        // Unterminated quote → invalid → default medium style for en_US.
        let result = TemplateRenderer.render(
            "{{date:yy'y}}",
            context: utcContext,
            locale: posixLocale
        )
        #expect(result == "Jan 2, 2024")
    }

    @Test("unknown variables render empty and accept fill values")
    func fillInVariables() {
        let template = "Hi {{who}}, about {{what}} ({{what}} again)"
        let empty = TemplateRenderer.render(template, context: TemplateContext())
        #expect(empty == "Hi , about  ( again)")

        let filled = TemplateRenderer.render(
            template,
            context: TemplateContext(),
            fills: ["who": "Taylor", "what": "Apollo"]
        )
        #expect(filled == "Hi Taylor, about Apollo (Apollo again)")
    }

    @Test("placeholder names are non-builtin, ordered, and deduplicated")
    func placeholderExtraction() {
        let names = TemplateRenderer.placeholderNames(in: "Hi {{who}} {{date}} — {{what}} then {{who}}")
        #expect(names == ["who", "what"])
        #expect(TemplateRenderer.placeholderNames(in: "{{name}} {{clipboard}}") .isEmpty)
    }
}
