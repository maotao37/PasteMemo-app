import SwiftUI

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
