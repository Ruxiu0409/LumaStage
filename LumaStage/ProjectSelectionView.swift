import SwiftUI

struct ProjectSelectionView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showsFixtureIntro = false
    @State private var showsProjectTemplatePicker = false
    @State private var showsOpenAISettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            projectList
            footer
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lumaFloatingPanel()
        .foregroundStyle(LumaStageDesign.textPrimary)
        .sheet(isPresented: $showsFixtureIntro) {
            LightingFixtureIntroView()
        }
        .sheet(isPresented: $showsProjectTemplatePicker) {
            ProjectTemplateSelectionView { template in
                appModel.createProject(template: template.kind)
            }
        }
        .sheet(isPresented: $showsOpenAISettings) {
            OpenAISettingsView()
                .environment(appModel)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LumaStage")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))

                Text("選擇專案")
                    .font(.headline)
                    .foregroundStyle(LumaStageDesign.textSecondary)
            }
            // Read the app name + screen title as a single header element.

            Spacer()

            Button("設定", systemImage: "gearshape") {
                showsOpenAISettings = true
            }
            .font(.callout.weight(.semibold))
            .labelStyle(.iconOnly)
            .lumaGlassButton()
            .lumaGazeTarget()
            .tint(LumaStageDesign.textSecondary)

            Button("新增專案", systemImage: "plus") {
                showsProjectTemplatePicker = true
            }
            .font(.callout.weight(.semibold))
            .lumaGlassButton(prominent: true)
            .lumaGazeTarget()
            .tint(LumaStageDesign.coolBlue)
        }
    }

    private var projectList: some View {
        Group {
            if appModel.projects.isEmpty {
                EmptyProjectsState(
                    createAction: { showsProjectTemplatePicker = true },
                    introAction: { showsFixtureIntro = true }
                )
            } else {
                // Scroll a long project list instead of letting the content-size window's height hit the
                // visionOS system maximum and compress every row together (the rows are vertically
                // compressible, so an over-tall VStack squeezes their padding to nothing). The order is
                // load-bearing: `.frame(maxHeight:)` THEN `.fixedSize(vertical:)` is the shrink-to-fit-up-
                // to-a-cap idiom — `fixedSize` lets the ScrollView adopt its content's ideal height so a
                // short list keeps the window compact (like the AI composer), while the inner `maxHeight`
                // clamps a tall list and turns on scrolling. `.basedOnSize` suppresses bounce when it fits.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(appModel.projects.enumerated()), id: \.element.id) { index, project in
                            ProjectRow(project: project) {
                                appModel.openProject(id: project.id)
                            }

                            if index < appModel.projects.count - 1 {
                                Divider()
                                    .overlay(LumaStageDesign.hairline)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
                .frame(maxHeight: 460)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .lumaNativeGlass(radius: LumaStageDesign.cornerRadius, fallbackOpacity: 0.34)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.callout.weight(.semibold))

            Text("\(appModel.projects.count) 個專案")
                .font(.callout.weight(.medium))

            Spacer()

            Button("燈具指南", systemImage: "lightbulb.2") {
                showsFixtureIntro = true
            }
            .font(.caption.weight(.semibold))
            .lumaGlassButton()
            .lumaGazeTarget()
            .tint(LumaStageDesign.warmAmber)

            LumaStatusChip(title: "標準夜景", tint: LumaStageDesign.softGreen)
        }
        .foregroundStyle(LumaStageDesign.textSecondary)
    }
}

private struct ProjectTemplateSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let createAction: (ProjectCreationTemplate) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    LazyVStack(spacing: 16) {
                        ForEach(ProjectCreationTemplate.allTemplates) { template in
                            ProjectTemplateRow(template: template) {
                                createAction(template)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(22)
            }
            .foregroundStyle(LumaStageDesign.textPrimary)
            .navigationTitle("新增專案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("新增舞台專案", systemImage: "rectangle.3.group.bubble")
                .font(.title2.weight(.bold))

            Text("選擇範本快速建立舞台專案，或從空白舞台從零開始，再用 AI 微調整體效果。")
                .font(.callout)
                .foregroundStyle(LumaStageDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .lumaNativeGlass(tint: LumaStageDesign.coolBlue.opacity(0.12), radius: LumaStageDesign.surfaceRadius, fallbackOpacity: 0.34)
    }
}

private struct ProjectTemplateRow: View {
    let template: ProjectCreationTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ProjectTemplatePreviewImage(template: template)
                    .frame(height: 164)

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: template.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.coolBlue)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.08))
                        )

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(template.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(LumaStageDesign.textPrimary)

                            Spacer()

                            Text(template.eventType)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LumaStageDesign.coolBlue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Text(template.subtitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(LumaStageDesign.textPrimary.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(template.introduction)
                            .font(.caption)
                            .foregroundStyle(LumaStageDesign.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lumaNativeGlass(radius: LumaStageDesign.cornerRadius, interactive: true, fallbackOpacity: 0.32)
    }
}

private struct ProjectTemplatePreviewImage: View {
    let template: ProjectCreationTemplate

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            // Back-to-front so screen-blended light layers add luminance over the darker scene:
            // backdrop → haze glow → truss + hung fixtures → aerial beams → stage deck → floor pools →
            // lit performers → vignette. Beams terminate at the deck (drawn after them) and read as pools.
            ZStack {
                background
                atmosphere(size: size)
                backdropHalo(size: size)

                truss(width: size.width * 0.66, height: size.height * 0.40)
                    .stroke(Color.white.opacity(0.32), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .position(x: size.width * 0.50, y: size.height * 0.42)

                trussFixtureDots(size: size)
                beamLayer(size: size)
                stage(size: size)
                groundPools(size: size)
                performerGroup(size: size)
                vignette(size: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
    }

    // MARK: Palette

    private var palette: StageArtPalette {
        switch template.visualStyle {
        case .emptyStage:
            return StageArtPalette(
                backgroundTop: Color(red: 0.09, green: 0.10, blue: 0.12),
                backgroundBottom: Color(red: 0.16, green: 0.17, blue: 0.20),
                accent: .white,
                secondary: .white,
                atmosphere: .white
            )
        case .warmConcert:
            return StageArtPalette(
                backgroundTop: Color(red: 0.13, green: 0.08, blue: 0.11),
                backgroundBottom: Color(red: 0.30, green: 0.14, blue: 0.09),
                accent: LumaStageDesign.warmAmber,
                secondary: LumaStageDesign.coolBlue,
                atmosphere: LumaStageDesign.warmAmber
            )
        case .coolShowcase:
            return StageArtPalette(
                backgroundTop: Color(red: 0.04, green: 0.08, blue: 0.16),
                backgroundBottom: Color(red: 0.07, green: 0.18, blue: 0.30),
                accent: LumaStageDesign.coolBlue,
                secondary: LumaStageDesign.softGreen,
                atmosphere: LumaStageDesign.coolBlue
            )
        case .partyFinale:
            return StageArtPalette(
                backgroundTop: Color(red: 0.11, green: 0.06, blue: 0.18),
                backgroundBottom: Color(red: 0.28, green: 0.10, blue: 0.24),
                accent: LumaStageDesign.magenta,
                secondary: LumaStageDesign.coolBlue,
                atmosphere: LumaStageDesign.magenta
            )
        }
    }

    // The blank stage stays deliberately dim/unprogrammed; themed stages glow.
    private var isBlank: Bool { template.visualStyle == .emptyStage }

    // MARK: Layers

    private var background: some View {
        LinearGradient(
            colors: [palette.backgroundTop, palette.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            LinearGradient(
                colors: [Color.black.opacity(0.28), .clear, Color.black.opacity(0.60)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // Soft aerial haze so the beams read as light scattering in air (matching the app's haze/scatter look).
    private func atmosphere(size: CGSize) -> some View {
        RadialGradient(
            colors: [palette.atmosphere.opacity(isBlank ? 0.10 : 0.24), .clear],
            center: .center,
            startRadius: 0,
            endRadius: size.width * 0.6
        )
        .frame(width: size.width * 1.1, height: size.height)
        .position(x: size.width * 0.5, y: size.height * 0.42)
        .blur(radius: 2)
        .blendMode(.screen)
    }

    // A wide glow band on the backdrop behind the truss for depth.
    private func backdropHalo(size: CGSize) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [palette.secondary.opacity(isBlank ? 0.10 : 0.22), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.42
                )
            )
            .frame(width: size.width * 0.9, height: size.height * 0.46)
            .position(x: size.width * 0.5, y: size.height * 0.5)
            .blur(radius: 10)
            .blendMode(.screen)
    }

    // Fixtures hung under the top truss bar. Themed rigs glow in their colours; the blank rig sits dim/unlit.
    private func trussFixtureDots(size: CGSize) -> some View {
        let count = 7
        let barWidth = size.width * 0.60
        let startX = size.width * 0.5 - barWidth / 2
        let y = size.height * 0.255

        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                let t = CGFloat(index) / CGFloat(count - 1)
                let tint = fixtureDotColor(index: index)
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 12, height: 12)
                        .blur(radius: 5)
                        .opacity(isBlank ? 0.0 : 0.9)
                        .blendMode(.screen)
                    Circle()
                        .fill(tint.opacity(isBlank ? 0.45 : 0.95))
                        .frame(width: 4.5, height: 4.5)
                }
                .position(x: startX + barWidth * t, y: y)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func beamLayer(size: CGSize) -> some View {
        switch template.visualStyle {
        case .emptyStage:
            // A single soft, neutral work-light wash — enough to feel lit, but no colour theme (still blank).
            ProjectLightBeam(color: .white, rotation: 0)
                .frame(width: size.width * 0.30, height: size.height * 0.66)
                .position(x: size.width * 0.5, y: size.height * 0.49)
                .opacity(0.5)
        case .warmConcert:
            ProjectLightBeam(color: LumaStageDesign.warmAmber, rotation: -15)
                .frame(width: size.width * 0.22, height: size.height * 0.70)
                .position(x: size.width * 0.38, y: size.height * 0.49)
            ProjectLightBeam(color: LumaStageDesign.coolBlue, rotation: 15)
                .frame(width: size.width * 0.22, height: size.height * 0.70)
                .position(x: size.width * 0.62, y: size.height * 0.49)
        case .coolShowcase:
            ForEach(0..<4, id: \.self) { index in
                ProjectLightBeam(color: LumaStageDesign.coolBlue, rotation: Double(index) * 8 - 12)
                    .frame(width: size.width * 0.14, height: size.height * 0.66)
                    .position(x: size.width * (0.30 + CGFloat(index) * 0.13), y: size.height * 0.49)
            }
        case .partyFinale:
            ProjectLightBeam(color: LumaStageDesign.warmAmber, rotation: -20)
                .frame(width: size.width * 0.18, height: size.height * 0.68)
                .position(x: size.width * 0.32, y: size.height * 0.48)
            ProjectLightBeam(color: LumaStageDesign.magenta, rotation: 0)
                .frame(width: size.width * 0.18, height: size.height * 0.68)
                .position(x: size.width * 0.50, y: size.height * 0.47)
            ProjectLightBeam(color: LumaStageDesign.coolBlue, rotation: 20)
                .frame(width: size.width * 0.18, height: size.height * 0.68)
                .position(x: size.width * 0.68, y: size.height * 0.48)
        }
    }

    private func stage(size: CGSize) -> some View {
        StageSilhouette(width: size.width * 0.66, height: size.height * 0.30)
            .fill(
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                StageSilhouette(width: size.width * 0.66, height: size.height * 0.30)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .position(x: size.width * 0.50, y: size.height * 0.75)
    }

    // Pools of light where the beams land on the deck.
    @ViewBuilder
    private func groundPools(size: CGSize) -> some View {
        let deckY = size.height * 0.655
        switch template.visualStyle {
        case .emptyStage:
            LightPool(color: .white, width: size.width * 0.34, height: size.height * 0.10)
                .opacity(0.5)
                .position(x: size.width * 0.5, y: deckY)
        case .warmConcert:
            LightPool(color: LumaStageDesign.warmAmber, width: size.width * 0.26, height: size.height * 0.09)
                .position(x: size.width * 0.40, y: deckY)
            LightPool(color: LumaStageDesign.coolBlue, width: size.width * 0.26, height: size.height * 0.09)
                .position(x: size.width * 0.60, y: deckY)
        case .coolShowcase:
            ForEach(0..<4, id: \.self) { index in
                LightPool(color: LumaStageDesign.coolBlue, width: size.width * 0.16, height: size.height * 0.07)
                    .position(x: size.width * (0.30 + CGFloat(index) * 0.13), y: deckY)
            }
        case .partyFinale:
            LightPool(color: LumaStageDesign.warmAmber, width: size.width * 0.20, height: size.height * 0.08)
                .position(x: size.width * 0.33, y: deckY)
            LightPool(color: LumaStageDesign.magenta, width: size.width * 0.20, height: size.height * 0.08)
                .position(x: size.width * 0.50, y: deckY)
            LightPool(color: LumaStageDesign.coolBlue, width: size.width * 0.20, height: size.height * 0.08)
                .position(x: size.width * 0.67, y: deckY)
        }
    }

    @ViewBuilder
    private func performerGroup(size: CGSize) -> some View {
        switch template.visualStyle {
        case .emptyStage:
            // No performers — a blank, ready-to-design stage.
            EmptyView()
        case .warmConcert:
            ForEach(0..<3, id: \.self) { index in
                performer
                    .frame(width: 17, height: 40)
                    .position(x: size.width * (0.43 + CGFloat(index) * 0.07), y: size.height * 0.63)
            }
        case .coolShowcase:
            ForEach(0..<5, id: \.self) { index in
                performer
                    .frame(width: 14, height: 34)
                    .position(x: size.width * (0.36 + CGFloat(index) * 0.07), y: size.height * 0.64)
            }
        case .partyFinale:
            ForEach(0..<4, id: \.self) { index in
                performer
                    .frame(width: 16, height: 38)
                    .position(x: size.width * (0.39 + CGFloat(index) * 0.075), y: size.height * 0.63)
            }
        }
    }

    private var performer: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: 8, height: 8)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.8))
        }
        .shadow(color: palette.accent.opacity(0.35), radius: 6)
    }

    // Subtle darkening at the edges to focus the eye on the lit stage.
    private func vignette(size: CGSize) -> some View {
        RadialGradient(
            colors: [.clear, Color.black.opacity(0.35)],
            center: .center,
            startRadius: size.width * 0.22,
            endRadius: size.width * 0.72
        )
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }

    private func fixtureDotColor(index: Int) -> Color {
        switch template.visualStyle {
        case .emptyStage:
            return .white
        case .warmConcert:
            return index.isMultiple(of: 2) ? LumaStageDesign.warmAmber : LumaStageDesign.coolBlue
        case .coolShowcase:
            return index.isMultiple(of: 2) ? LumaStageDesign.coolBlue : LumaStageDesign.softGreen
        case .partyFinale:
            let colors = [LumaStageDesign.warmAmber, LumaStageDesign.magenta, LumaStageDesign.coolBlue]
            return colors[index % colors.count]
        }
    }

    private func truss(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let left = -width / 2
            let right = width / 2
            let top = -height / 2
            let bottom = height / 2

            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: bottom))

            let segments = 8
            for index in 0..<segments {
                let startX = left + CGFloat(index) * width / CGFloat(segments)
                let endX = left + CGFloat(index + 1) * width / CGFloat(segments)
                let startY = index.isMultiple(of: 2) ? top : top + 16
                let endY = index.isMultiple(of: 2) ? top + 16 : top
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }

            for index in 0..<4 {
                let y = bottom - CGFloat(index + 1) * height / 5
                path.move(to: CGPoint(x: left - 5, y: y))
                path.addLine(to: CGPoint(x: left + 13, y: y - 18))
                path.move(to: CGPoint(x: right + 5, y: y))
                path.addLine(to: CGPoint(x: right - 13, y: y - 18))
            }
        }
    }
}

/// A volumetric-looking beam: a soft coloured cone (bright at the fixture, fading to haze at the floor)
/// with a hot near-white core, screen-blended so overlapping beams add luminance like real light.
private struct ProjectLightBeam: View {
    let color: Color
    let rotation: Double

    var body: some View {
        ProjectBeamShape()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.6), color.opacity(0.2), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                ProjectBeamShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.85), color.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(x: 0.36, anchor: .center)
            }
            .blur(radius: 3)
            .rotationEffect(.degrees(rotation))
            .blendMode(.screen)
    }
}

/// The per-template colour palette that drives every art layer (background, haze, backdrop, pools, dots).
private struct StageArtPalette {
    let backgroundTop: Color
    let backgroundBottom: Color
    let accent: Color
    let secondary: Color
    let atmosphere: Color
}

/// A soft elliptical pool of light on the stage deck where a beam lands, screen-blended to add luminance.
private struct LightPool: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.7), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: width / 2
                )
            )
            .frame(width: width, height: height)
            .blur(radius: 4)
            .blendMode(.screen)
    }
}

private struct ProjectBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct StageSilhouette: Shape {
    let width: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            let stage = CGRect(
                x: rect.midX - width / 2,
                y: rect.midY - height / 2,
                width: width,
                height: height
            )
            path.move(to: CGPoint(x: stage.minX + 18, y: stage.minY))
            path.addLine(to: CGPoint(x: stage.maxX - 8, y: stage.minY))
            path.addLine(to: CGPoint(x: stage.maxX, y: stage.maxY - 10))
            path.addLine(to: CGPoint(x: stage.minX, y: stage.maxY))
            path.addLine(to: CGPoint(x: stage.minX + 12, y: stage.minY + 4))
            path.closeSubpath()
        }
    }
}

private struct EmptyProjectsState: View {
    let createAction: () -> Void
    let introAction: () -> Void
    // Scale the hero glyph with Dynamic Type instead of a fixed 42pt size.
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 42

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(LumaStageDesign.coolBlue)

            VStack(spacing: 5) {
                Text("尚無專案")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)

                Text("建立你的第一個舞台專案，接著開始 AI 燈光設計。")
                    .font(.callout)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("先認識燈具", systemImage: "lightbulb.2", action: introAction)
                    .font(.callout.weight(.semibold))
                    .lumaGlassButton()
                    .lumaGazeTarget()
                    .tint(LumaStageDesign.warmAmber)

                Button("建立專案", systemImage: "plus", action: createAction)
                    .font(.callout.weight(.semibold))
                    .lumaGlassButton(prominent: true)
                    .lumaGazeTarget()
                    .tint(LumaStageDesign.coolBlue)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding(28)
    }
}

private struct ProjectRow: View {
    let project: LumaStageProject
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.3.group")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.coolBlue)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.textPrimary)
                        .lineLimit(1)

                    Text(project.venueDescription)
                        .font(.callout)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text(project.eventType)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.textPrimary)
                        .lineLimit(1)

                    Text(project.lastEditedDescription)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LumaStageDesign.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProjectSelectionView()
        .environment(AppModel())
}
