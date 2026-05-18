import SwiftUI

/// A count rendered at least two digits wide: the leading zero
/// needed to reach two digits is faded (same hue, dimmed via
/// opacity) so the tens column stays reserved and the layout stops
/// jumping when the count crosses 1↔2 digits. ≥100 just grows.
/// Monospaced digits keep every digit equal width. Inherits the
/// caller's font/color (apply `.font`/`.foregroundStyle` on the
/// `PaddedCount` itself); the pad dims relative to that.
struct PaddedCount: View {
    private let value: Int
    init(_ value: Int) { self.value = value }

    var body: some View {
        let digits = String(Swift.max(0, value))
        let pad = String(
            repeating: "0",
            count: Swift.max(0, 2 - digits.count))
        HStack(spacing: 0) {
            if !pad.isEmpty {
                Text(pad).opacity(0.35)
            }
            Text(digits)
        }
        .monospacedDigit()
    }
}
