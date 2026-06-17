import SwiftUI

struct StageLookPreview: View {
    let cue: LightingCue?

    private var frontLight: FixtureGroup? {
        cue?.fixtureGroups.first(where: { $0.role == .frontLight })
    }

    private var backgroundWash: FixtureGroup? {
        cue?.fixtureGroups.first(where: { $0.role == .backgroundWash })
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let stageRect = CGRect(
                x: size.width * 0.07,
                y: size.height * 0.11,
                width: size.width * 0.86,
                height: size.height * 0.76
            )

            ZStack {
                nightEnvironment
                backDrape(in: stageRect)
                floorDeck(in: stageRect)
                backgroundWashLayer(in: stageRect)
                frontBeamLayer(in: stageRect)
                truss(in: stageRect)
                performer(in: stageRect)
                previewReadout(in: stageRect)
            }
        }
        .animation(.easeInOut(duration: cue?.transition.duration ?? 1.2), value: cue)
    }

    private var nightEnvironment: some View {
        ZStack {
            LumaStageDesign.nightBlack

            LinearGradient(
                colors: [
                    LumaStageDesign.deepBlue.opacity(0.18),
                    .clear,
                    LumaStageDesign.warmAmber.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func backDrape(in rect: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.052, green: 0.056, blue: 0.070),
                            Color(red: 0.025, green: 0.027, blue: 0.033)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            HStack(spacing: rect.width / 18) {
                ForEach(0..<12, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.045) : Color.black.opacity(0.16))
                        .frame(width: 2)
                }
            }
            .padding(.horizontal, 30)
        }
        .frame(width: rect.width, height: rect.height * 0.54)
        .position(x: rect.midX, y: rect.minY + rect.height * 0.28)
        .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
    }

    private func backgroundWashLayer(in rect: CGRect) -> some View {
        let washColor = color(for: backgroundWash)
        let intensity = backgroundWash?.intensity ?? 0

        return ZStack {
            LinearGradient(
                colors: [
                    washColor.opacity(0.18 + intensity * 0.22),
                    washColor.opacity(0.42 + intensity * 0.38),
                    washColor.opacity(0.10 + intensity * 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: rect.width * 0.045) {
                ForEach(0..<6, id: \.self) { _ in
                    Capsule()
                        .fill(washColor.opacity(0.32 + intensity * 0.42))
                        .frame(width: rect.width * 0.035)
                        .blur(radius: 4)
                }
            }
            .padding(.top, rect.height * 0.08)
        }
        .frame(width: rect.width * 0.74, height: rect.height * 0.39)
        .position(x: rect.midX, y: rect.minY + rect.height * 0.33)
        .blendMode(.screen)
    }

    private func floorDeck(in rect: CGRect) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.30))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.30))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.170, green: 0.150, blue: 0.130),
                        Color(red: 0.070, green: 0.064, blue: 0.060)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            ForEach(0..<7, id: \.self) { index in
                Path { path in
                    let fraction = CGFloat(index) / 6
                    let topX = rect.minX + rect.width * (0.15 + fraction * 0.70)
                    let bottomX = rect.minX + rect.width * (0.04 + fraction * 0.92)
                    path.move(to: CGPoint(x: topX, y: rect.maxY - rect.height * 0.30))
                    path.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
                }
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
            }
        }
    }

    private func frontBeamLayer(in rect: CGRect) -> some View {
        let beamColor = color(for: frontLight)
        let intensity = frontLight?.intensity ?? 0
        let opacity = 0.18 + intensity * 0.38

        return ZStack {
            beam(color: beamColor, rect: rect, anchorX: 0.28, floorX: 0.42, opacity: opacity)
            beam(color: beamColor, rect: rect, anchorX: 0.72, floorX: 0.58, opacity: opacity)

            Ellipse()
                .fill(beamColor.opacity(0.34 + intensity * 0.28))
                .frame(width: rect.width * 0.30, height: rect.height * 0.11)
                .blur(radius: 9)
                .position(x: rect.midX, y: rect.maxY - rect.height * 0.18)
        }
        .blendMode(.screen)
    }

    private func beam(color: Color, rect: CGRect, anchorX: CGFloat, floorX: CGFloat, opacity: Double) -> some View {
        Path { path in
            let top = CGPoint(x: rect.minX + rect.width * anchorX, y: rect.minY + rect.height * 0.08)
            let floor = CGPoint(x: rect.minX + rect.width * floorX, y: rect.maxY - rect.height * 0.13)
            path.move(to: top)
            path.addLine(to: CGPoint(x: floor.x - rect.width * 0.12, y: floor.y))
            path.addLine(to: CGPoint(x: floor.x + rect.width * 0.12, y: floor.y))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [
                    color.opacity(opacity * 0.20),
                    color.opacity(opacity),
                    color.opacity(opacity * 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .blur(radius: 7)
    }

    private func truss(in rect: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.22))
                .frame(width: rect.width * 0.86, height: 8)
                .position(x: rect.midX, y: rect.minY + rect.height * 0.07)

            ForEach(0..<7, id: \.self) { index in
                let x = rect.minX + rect.width * (0.13 + CGFloat(index) * 0.123)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 3, height: 28)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? 26 : -26))
                    .position(x: x, y: rect.minY + rect.height * 0.07)
            }

            ForEach([CGFloat(0.24), CGFloat(0.40), CGFloat(0.60), CGFloat(0.76)], id: \.self) { position in
                fixtureHousing(in: rect, at: position)
            }
        }
    }

    private func fixtureHousing(in rect: CGRect, at position: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(
                LinearGradient(
                    colors: [
                        LumaStageDesign.graphiteElevated,
                        Color.black.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: rect.width * 0.065, height: rect.height * 0.045)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(LumaStageDesign.warmAmber.opacity(0.36))
                    .frame(width: rect.width * 0.034, height: 3)
                    .padding(.bottom, 3)
            }
            .position(x: rect.minX + rect.width * position, y: rect.minY + rect.height * 0.105)
    }

    private func performer(in rect: CGRect) -> some View {
        let beamColor = color(for: frontLight)
        let intensity = frontLight?.intensity ?? 0

        return VStack(spacing: 0) {
            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: rect.width * 0.052, height: rect.width * 0.052)

            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.78))
                .frame(width: rect.width * 0.070, height: rect.height * 0.155)
        }
        .shadow(color: beamColor.opacity(0.38 + intensity * 0.38), radius: 24)
        .position(x: rect.midX, y: rect.maxY - rect.height * 0.27)
    }

    private func previewReadout(in rect: CGRect) -> some View {
        HStack(spacing: 8) {
            LumaStatusChip(title: cue?.localizedDisplayName ?? "No Cue Selected", tint: LumaStageDesign.warmAmber)
            LumaStatusChip(
                title: "\(Int(round((frontLight?.intensity ?? 0) * 100)))% Front",
                tint: color(for: frontLight)
            )
            LumaStatusChip(
                title: "\(Int(round((backgroundWash?.intensity ?? 0) * 100)))% Background",
                tint: color(for: backgroundWash)
            )
        }
        .position(x: rect.midX, y: rect.maxY - 26)
    }

    private func color(for fixture: FixtureGroup?) -> Color {
        let rgb = fixture?.color.rgbComponents ?? .white
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview {
    StageLookPreview(cue: try? LightingLook.mvpDemo().requireCue(id: "cue_opening"))
}
