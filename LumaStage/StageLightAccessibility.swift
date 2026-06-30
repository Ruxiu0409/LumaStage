import Foundation

/// VoiceOver phrasing for the on-stage lights, as pure Foundation-only logic so it can be smoke-tested
/// without a view (the project convention: decidable copy → Foundation file + smoke test; views stay
/// thin). `ImmersiveView` sets these strings as the `AccessibilityComponent` label/value on each light's
/// `lightpick_<n>` pick proxy so VoiceOver announces "第 3 盞燈，搖頭光束燈 — 藍色，亮度 60%" instead of
/// a hex code, and "已關閉" for a dark fixture.
///
/// All user-facing strings are Traditional Chinese (繁體中文) per the project's language convention; the
/// full-width Chinese comma "，" is the field separator.
enum StageLightAccessibility {
    /// Field separator for the composed VoiceOver strings — the full-width Chinese comma.
    private static let separator = "，"

    /// Coarse human 繁中 colour name for a `#RRGGBB` hex, bucketed by chroma + hue + lightness so
    /// VoiceOver says "藍色"/"暖白" instead of a hex code. Falls back to "白色" on unparseable input.
    ///
    /// "Colourfulness" is keyed off **chroma** (`C = maxChannel − minChannel`, the raw RGB spread),
    /// *not* HSL saturation — HSL saturation balloons toward 1.0 for light pastels, which would
    /// misread a desaturated incandescent tint like `#FFE9C8` as a vivid orange. Chroma stays low for
    /// near-whites/greys (the channels are close) and high for vivid hues.
    ///
    /// Bucketing (H in degrees 0...360, L = lightness 0...1, C = chroma 0...1):
    ///   - L ≤ 0.08                                  → 黑色   (near-black, regardless of hue)
    ///   - C ≤ 0.25 (low-chroma neutral / tinted-white band):
    ///       · L ≥ 0.6 and hue in the warm amber band (20°..<70°) → 暖白 (incandescent, e.g. #FFE9C8, C≈0.22)
    ///       · L ≥ 0.78                               → 白色   (near-white)
    ///       · otherwise                              → 灰色   (desaturated mid/low lightness)
    ///   - otherwise (chromatic) bucket by hue:
    ///       · 紅色 [345...360] ∪ [0...15)   · 橙色 [15...45)    · 黃色 [45...70)
    ///       · 綠色 [70...165)               · 青色 [165...195)  · 藍色 [195...255)
    ///       · 紫色 [255...290)              · 粉紅色 [290...345)
    static func colorName(forHex hex: String) -> String {
        guard let rgb = rgbComponents(fromHex: hex) else { return "白色" }
        let (h, chroma, l) = hueChromaLightness(r: rgb.r, g: rgb.g, b: rgb.b)

        // Near-black first (a dark tint of any hue still reads as black).
        if l <= 0.08 { return "黑色" }

        // Low-chroma neutral / tinted-white band.
        if chroma <= 0.25 {
            // A bright warm amber tint (incandescent) reads as 暖白.
            if l >= 0.6, h >= 20, h < 70 { return "暖白" }
            if l >= 0.78 { return "白色" }
            return "灰色"
        }

        // Chromatic colours: bucket by hue.
        switch h {
        case ..<15, 345...360: return "紅色"
        case 15..<45: return "橙色"
        case 45..<70: return "黃色"
        case 70..<165: return "綠色"
        case 165..<195: return "青色"
        case 195..<255: return "藍色"
        case 255..<290: return "紫色"
        default: return "粉紅色" // 290..<345
        }
    }

    /// Static identity for the Nth light (1-based) of a given type, e.g.
    /// `(3, .movingHeadBeam)` → "第 3 盞燈，搖頭光束燈". The 繁中 type name comes from the fixture
    /// catalog (`LightingFixtureCatalog.item(for:)?.displayName`), falling back to "燈具".
    static func identityLabel(number: Int, model: LightingFixtureVisualModel) -> String {
        let typeName = LightingFixtureCatalog.item(for: model)?.displayName ?? "燈具"
        return "第 \(number) 盞燈\(separator)\(typeName)"
    }

    /// Live state string for VoiceOver's accessibility value, e.g.
    /// `("#2E6BFF", 0.6, isOff: false)` → "藍色，亮度 60%". When `isOff` is true the fixture is dark, so
    /// intensity and colour are ignored and the value is "已關閉".
    static func stateValue(colorHex: String, intensity: Double, isOff: Bool) -> String {
        if isOff { return "已關閉" }
        let percent = Int((intensity * 100).rounded())
        return "\(colorName(forHex: colorHex))\(separator)亮度 \(percent)%"
    }

    // MARK: - Colour parsing

    /// Parses a `#RRGGBB` hex into normalized 0...1 RGB, tolerating a missing leading `#` and any case.
    /// Returns nil for anything that is not exactly six hex digits.
    private static func rgbComponents(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    /// Converts normalized RGB to hue (degrees 0...360), chroma (max−min channel spread, 0...1), and
    /// lightness ((max+min)/2, 0...1). Chroma — not HSL saturation — is the colourfulness metric used by
    /// `colorName`, so it stays low for near-whites/greys and high only for genuinely vivid hues.
    private static func hueChromaLightness(r: Double, g: Double, b: Double) -> (h: Double, chroma: Double, l: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let chroma = maxC - minC
        let l = (maxC + minC) / 2

        guard chroma > 0 else { return (0, 0, l) } // achromatic (pure grey/white/black)

        var h: Double
        if maxC == r {
            h = (g - b) / chroma + (g < b ? 6 : 0)
        } else if maxC == g {
            h = (b - r) / chroma + 2
        } else {
            h = (r - g) / chroma + 4
        }
        h *= 60
        return (h, chroma, l)
    }
}
