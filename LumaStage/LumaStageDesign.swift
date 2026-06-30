import SwiftUI

enum LumaStageDesign {
    static let cornerRadius: CGFloat = 16
    static let surfaceRadius: CGFloat = 20
    static let panelRadius: CGFloat = 32
    static let panelPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    /// visionOS minimum reliable gaze (eye-tracking) target — larger than iOS's 44pt. Apply via
    /// `lumaGazeTarget()` to icon-only / compact controls so look-and-pinch can hit them reliably.
    static let minGazeTarget: CGFloat = 60

    // Brand accent tints. Used sparingly *over* the native system glass — never as opaque fills.
    static let coolBlue = Color(red: 0.275, green: 0.595, blue: 0.950)
    static let deepBlue = Color(red: 0.095, green: 0.205, blue: 0.660)
    static let warmAmber = Color(red: 1.000, green: 0.610, blue: 0.275)
    static let softGreen = Color(red: 0.410, green: 0.680, blue: 0.520)
    static let magenta = Color(red: 0.740, green: 0.315, blue: 0.900)

    // Dark tokens retained only for self-contained preview art (SceneKit fixtures, the project
    // template thumbnails) that paints its own surfaces — not for chrome.
    static let nightBlack = Color(red: 0.025, green: 0.027, blue: 0.033)
    static let graphite = Color(red: 0.105, green: 0.112, blue: 0.126)
    static let graphiteElevated = Color(red: 0.145, green: 0.153, blue: 0.170)

    // Semantic text colors so vibrancy adapts to the native glass automatically, instead of
    // hardcoded white opacities that fight the system material.
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let hairline = Color.primary.opacity(0.08)
}

extension View {
    /// The canonical floating-panel material for top-level visionOS surfaces (the AI composer,
    /// the project picker). Uses the system glass backing — which supplies its own specular edge,
    /// depth, and shadow — so callers must *not* add manual fills, strokes, or drop shadows.
    @ViewBuilder
    func lumaFloatingPanel(cornerRadius: CGFloat = LumaStageDesign.panelRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
#if os(visionOS)
        self.glassBackgroundEffect(in: shape)
#else
        self
            .background(.ultraThinMaterial, in: shape)
            .background(LumaStageDesign.graphite.opacity(0.42), in: shape)
#endif
    }

    /// A nested vibrant surface that layers *on top* of a floating panel — chips, inline sections,
    /// template rows. Uses the system material (not the unified `glassEffect`, which is unavailable
    /// on visionOS) so glass-on-glass reads cleanly with one frosted layer plus an optional tint.
    @ViewBuilder
    func lumaNativeGlass(
        tint: Color = .clear,
        radius: CGFloat = LumaStageDesign.surfaceRadius,
        interactive: Bool = false,
        fallbackOpacity: Double = 0.42
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
#if os(visionOS)
        self
            .background(tint, in: shape)
            .background(.regularMaterial, in: shape)
#else
        self
            .background(.ultraThinMaterial, in: shape)
            .background(LumaStageDesign.graphite.opacity(fallbackOpacity), in: shape)
#endif
    }

    /// Native button styling. `.bordered` / `.borderedProminent` already render as Liquid Glass
    /// capsules on visionOS, so callers get the system look; pair with `.tint(_:)` for accents.
    @ViewBuilder
    func lumaGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Enforces the visionOS 60pt minimum gaze target (eye tracking is imprecise; iOS's 44pt is too
    /// small). Apply to icon-only / compact buttons so look-and-pinch selects them reliably.
    func lumaGazeTarget(_ size: CGFloat = LumaStageDesign.minGazeTarget) -> some View {
        frame(minWidth: size, minHeight: size)
    }
}

/// A nested glass capsule used for top-level floating panels' inner content blocks.
struct LumaPanel: ViewModifier {
    var padding: CGFloat = LumaStageDesign.panelPadding
    var cornerRadius: CGFloat = LumaStageDesign.panelRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .lumaFloatingPanel(cornerRadius: cornerRadius)
    }
}

extension View {
    func lumaPanel(
        padding: CGFloat = LumaStageDesign.panelPadding,
        cornerRadius: CGFloat = LumaStageDesign.panelRadius
    ) -> some View {
        modifier(LumaPanel(padding: padding, cornerRadius: cornerRadius))
    }
}

struct LumaSectionHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.coolBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)
                    .textCase(.uppercase)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }
}

struct LumaStatusChip: View {
    let title: String
    var tint: Color = LumaStageDesign.coolBlue

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(LumaStageDesign.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .lumaNativeGlass(tint: tint.opacity(0.22), radius: 14, fallbackOpacity: 0.24)
    }
}

struct LumaMetricRow: View {
    let title: String
    let value: String
    var tint: Color = LumaStageDesign.textSecondary

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(LumaStageDesign.textSecondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct LumaControlSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumaSectionHeader(title: title, subtitle: subtitle, systemImage: systemImage)
            content
        }
        .padding(16)
        .lumaNativeGlass(radius: LumaStageDesign.surfaceRadius, fallbackOpacity: 0.34)
    }
}
