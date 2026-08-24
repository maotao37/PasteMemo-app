import Foundation
import Testing
@testable import PasteMemo

@Suite("Type colors and image preview layout")
struct TypeColorAndPreviewLayoutTests {
    @Test("every configurable content type has a valid default color")
    func defaultColorsAreValid() {
        for type in ClipContentType.colorConfigurableCases {
            #expect(ClipTypeColorStore.normalizedHex(type.defaultColorHex) != nil)
        }
    }

    @Test("legacy contact types use the text color category")
    func legacyTypesUseTextColor() {
        #expect(ClipContentType.email.colorConfigurationType == .text)
        #expect(ClipContentType.phone.colorConfigurationType == .text)
    }

    @Test("custom colors persist and reset to defaults")
    @MainActor
    func colorOverridesPersistAndReset() throws {
        let suiteName = "TypeColorAndPreviewLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ClipTypeColorStore(defaults: defaults)
        store.setHex("#123abc", for: .image)
        #expect(store.hex(for: .image) == "#123ABC")

        let reloaded = ClipTypeColorStore(defaults: defaults)
        #expect(reloaded.hex(for: .image) == "#123ABC")
        reloaded.resetAll()
        #expect(reloaded.hex(for: .image) == ClipContentType.image.defaultColorHex)
    }

    @Test("fit layout scales images up and down while preserving aspect ratio")
    func fittedImageSize() {
        let enlarged = PreviewImageLayout.fittedSize(
            imageSize: CGSize(width: 100, height: 50),
            viewportSize: CGSize(width: 500, height: 300)
        )
        #expect(enlarged == CGSize(width: 500, height: 250))

        let reduced = PreviewImageLayout.fittedSize(
            imageSize: CGSize(width: 2400, height: 1200),
            viewportSize: CGSize(width: 600, height: 500)
        )
        #expect(reduced == CGSize(width: 600, height: 300))
    }
}
