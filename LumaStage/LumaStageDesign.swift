import SwiftUI

enum LumaStageDesign {
    static let cornerRadius: CGFloat = 8
    static let surfaceRadius: CGFloat = 18
    static let panelPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 14

    static let nightBlack = Color(red: 0.025, green: 0.027, blue: 0.033)
    static let graphite = Color(red: 0.105, green: 0.112, blue: 0.126)
    static let graphiteElevated = Color(red: 0.145, green: 0.153, blue: 0.170)
    static let coolBlue = Color(red: 0.275, green: 0.595, blue: 0.950)
    static let deepBlue = Color(red: 0.095, green: 0.205, blue: 0.660)
    static let warmAmber = Color(red: 1.000, green: 0.610, blue: 0.275)
    static let softGreen = Color(red: 0.410, green: 0.680, blue: 0.520)
    static let magenta = Color(red: 0.740, green: 0.315, blue: 0.900)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.62)
    static let hairline = Color.white.opacity(0.12)
    static let adoptsIOS26NativePanelStyle = true

    static var usesNativeLiquidGlassSurfaces: Bool {
#if os(iOS)
        if #available(iOS 26.0, *) {
            return true
        }
#endif
        return false
    }
}

struct LumaPanel: ViewModifier {
    var padding: CGFloat = LumaStageDesign.panelPadding
    var tint: Color = LumaStageDesign.nightBlack.opacity(0.22)
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LumaStageDesign.surfaceRadius, style: .continuous)

        return content
            .padding(padding)
            .lumaNativeGlass(
                tint: tint,
                radius: LumaStageDesign.surfaceRadius,
                interactive: interactive,
                fallbackOpacity: 0.42
            )
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func lumaPanel(
        padding: CGFloat = LumaStageDesign.panelPadding,
        tint: Color = LumaStageDesign.nightBlack.opacity(0.22),
        interactive: Bool = false
    ) -> some View {
        modifier(LumaPanel(padding: padding, tint: tint, interactive: interactive))
    }

    @ViewBuilder
    func lumaNativeGlass(
        tint: Color = .white.opacity(0.04),
        radius: CGFloat = LumaStageDesign.surfaceRadius,
        interactive: Bool = false,
        fallbackOpacity: Double = 0.42
    ) -> some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            self
                .background(Color.white.opacity(0.001), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .glassEffect(
                    .regular.tint(tint).interactive(interactive),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(LumaStageDesign.graphite.opacity(fallbackOpacity), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
#else
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(LumaStageDesign.graphite.opacity(fallbackOpacity), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
#endif
    }

    @ViewBuilder
    func lumaGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else if let tint {
                self.buttonStyle(.glass(.regular.tint(tint).interactive(true)))
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
#else
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
#endif
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
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .lumaNativeGlass(tint: tint.opacity(0.18), radius: 14, interactive: false, fallbackOpacity: 0.24)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        }
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
        .padding(14)
        .lumaNativeGlass(tint: .white.opacity(0.03), radius: 14, interactive: false, fallbackOpacity: 0.34)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
    }
}
