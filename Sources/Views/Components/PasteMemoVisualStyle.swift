import SwiftUI

@MainActor
@Observable
final class ClipTypeColorStore {
    static let shared = ClipTypeColorStore()
    static let storageKey = "clipTypeColorOverrides"

    private let defaults: UserDefaults
    private var overrides: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.overrides = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    func hex(for type: ClipContentType) -> String {
        let canonical = type.colorConfigurationType
        return Self.normalizedHex(overrides[canonical.rawValue]) ?? canonical.defaultColorHex
    }

    func color(for type: ClipContentType) -> Color {
        Color.pasteMemo(hex: hex(for: type)) ?? .secondary
    }

    func setColor(_ color: Color, for type: ClipContentType) {
        guard let hex = color.pasteMemoHex else { return }
        setHex(hex, for: type)
    }

    func setHex(_ hex: String, for type: ClipContentType) {
        guard let hex = Self.normalizedHex(hex) else { return }
        let canonical = type.colorConfigurationType
        overrides[canonical.rawValue] = hex
        defaults.set(overrides, forKey: Self.storageKey)
    }

    func resetAll() {
        overrides.removeAll()
        defaults.removeObject(forKey: Self.storageKey)
    }

    nonisolated static func normalizedHex(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted),
              raw.count == 6,
              UInt64(raw, radix: 16) != nil else { return nil }
        return "#" + raw.uppercased()
    }
}

/// Shared semantic palette for operational states. Window chrome and content
/// surfaces stay neutral; color is reserved for selection and meaning.
enum PasteMemoVisualStyle {
    static let ai = Color(nsColor: .systemPurple)
    static let otp = Color(nsColor: .systemGreen)
    static let pinned = Color(nsColor: .systemOrange)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)

    static let subtleFill = Color.primary.opacity(0.055)
    static let subtleStroke = Color.primary.opacity(0.08)
    static let selectedFill = Color.accentColor.opacity(0.14)
    static let selectedStroke = Color.accentColor.opacity(0.28)
}

extension Color {
    static func pasteMemo(hex: String?) -> Color? {
        guard let raw = hex?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted),
              raw.count == 6,
              let value = UInt64(raw, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    @MainActor
    var pasteMemoHex: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
