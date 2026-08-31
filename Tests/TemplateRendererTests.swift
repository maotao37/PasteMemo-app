import Foundation
import Testing
@testable import PasteMemo

@Suite("Template renderer")
struct TemplateRendererTests {
    @Test("expands profile, project, clipboard, and date variables")
    func expandsSupportedVariables() {
        let date = Date(timeIntervalSince1970: 1_704_164_645)
        let locale = Locale(identifier: "en_US_POSIX")
        let result = TemplateRenderer.render(
            "{{name}}|{{project}}|{{clipboard}}|{{date}}|{{time}}|{{datetime}}",
            context: TemplateContext(date: date, name: "Taylor", project: "Apollo", clipboard: "payload"),
            locale: locale
        )

        #expect(result.contains("Taylor|Apollo|payload|"))
        #expect(!result.contains("{{date}}"))
        #expect(!result.contains("{{time}}"))
        #expect(!result.contains("{{datetime}}"))
    }

    @Test("keeps unknown variables and supports repeated variables")
    func repeatedAndUnknownVariables() {
        let result = TemplateRenderer.render(
            "{{name}}/{{name}}/{{unknown}}",
            context: TemplateContext(name: "A")
        )
        #expect(result == "A/A/{{unknown}}")
    }
}
