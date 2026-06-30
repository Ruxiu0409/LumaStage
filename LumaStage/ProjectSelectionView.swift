import SwiftUI

struct ProjectSelectionView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showsFixtureIntro = false
    @State private var showsProjectTemplatePicker = false

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
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer()

            Button("新增專案", systemImage: "plus") {
                showsProjectTemplatePicker = true
            }
            .font(.callout.weight(.semibold))
            .lumaGlassButton(prominent: true)
            .lumaGazeTarget()
            .tint(LumaStageDesign.coolBlue)
            .accessibilityHint("選擇範本以建立新的舞台專案")
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
        }
        .lumaNativeGlass(radius: LumaStageDesign.cornerRadius, fallbackOpacity: 0.34)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.callout.weight(.semibold))
                .accessibilityHidden(true)

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
            .accessibilityHint("開啟燈具指南，認識常見的舞台燈具")

            LumaStatusChip(title: "標準夜景", tint: LumaStageDesign.softGreen)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("環境光：標準夜景")
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
                .accessibilityAddTraits(.isHeader)

            Text("建立一個附有預設燈光與專案細節的學生活動舞台，再用 AI 微調整體效果。")
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
                    .frame(height: 150)

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: template.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.coolBlue)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.08))
                        )
                        .accessibilityHidden(true)

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
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lumaNativeGlass(radius: LumaStageDesign.cornerRadius, interactive: true, fallbackOpacity: 0.32)
        // One VoiceOver element per template card: the preview art is decorative (hidden inside the
        // preview view), and the title/type/subtitle/intro fold into the label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(template.title)，\(template.eventType)，\(template.subtitle)，\(template.introduction)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("點兩下以此範本建立專案")
    }
}

private struct ProjectTemplatePreviewImage: View {
    let template: ProjectCreationTemplate

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                background

                StageSilhouette(width: size.width * 0.66, height: size.height * 0.28)
                    .fill(Color.black.opacity(template.visualStyle == .emptyStage ? 0.75 : 0.88))
                    .overlay {
                        StageSilhouette(width: size.width * 0.66, height: size.height * 0.28)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .position(x: size.width * 0.50, y: size.height * 0.72)

                truss(width: size.width * 0.70, height: size.height * 0.42)
                    .stroke(Color.white.opacity(0.48), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .position(x: size.width * 0.50, y: size.height * 0.43)

                beamLayer(size: size)

                performerGroup(size: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
        // Purely decorative stage illustration — the enclosing template card carries the real
        // label, so hide this from VoiceOver to avoid a redundant element.
        .accessibilityHidden(true)
    }

    private var background: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var backgroundColors: [Color] {
        switch template.visualStyle {
        case .emptyStage:
            return [
                Color(red: 0.08, green: 0.09, blue: 0.105),
                Color(red: 0.14, green: 0.15, blue: 0.17)
            ]
        case .warmConcert:
            return [
                Color(red: 0.12, green: 0.07, blue: 0.10),
                Color(red: 0.27, green: 0.13, blue: 0.08)
            ]
        case .coolShowcase:
            return [
                Color(red: 0.04, green: 0.08, blue: 0.16),
                Color(red: 0.07, green: 0.18, blue: 0.30)
            ]
        case .partyFinale:
            return [
                Color(red: 0.11, green: 0.06, blue: 0.18),
                Color(red: 0.28, green: 0.10, blue: 0.24)
            ]
        }
    }

    @ViewBuilder
    private func beamLayer(size: CGSize) -> some View {
        switch template.visualStyle {
        case .emptyStage:
            EmptyView()
        case .warmConcert:
            ProjectLightBeam(color: LumaStageDesign.warmAmber.opacity(0.42), rotation: -14)
                .frame(width: size.width * 0.24, height: size.height * 0.70)
                .position(x: size.width * 0.38, y: size.height * 0.50)
            ProjectLightBeam(color: LumaStageDesign.coolBlue.opacity(0.32), rotation: 14)
                .frame(width: size.width * 0.24, height: size.height * 0.70)
                .position(x: size.width * 0.62, y: size.height * 0.50)
        case .coolShowcase:
            ForEach(0..<4, id: \.self) { index in
                ProjectLightBeam(color: LumaStageDesign.coolBlue.opacity(0.34), rotation: Double(index - 2) * 7)
                    .frame(width: size.width * 0.15, height: size.height * 0.62)
                    .position(x: size.width * (0.32 + CGFloat(index) * 0.12), y: size.height * 0.50)
            }
        case .partyFinale:
            ProjectLightBeam(color: LumaStageDesign.warmAmber.opacity(0.40), rotation: -18)
                .frame(width: size.width * 0.20, height: size.height * 0.68)
                .position(x: size.width * 0.34, y: size.height * 0.49)
            ProjectLightBeam(color: LumaStageDesign.magenta.opacity(0.38), rotation: 0)
                .frame(width: size.width * 0.20, height: size.height * 0.68)
                .position(x: size.width * 0.50, y: size.height * 0.48)
            ProjectLightBeam(color: LumaStageDesign.coolBlue.opacity(0.34), rotation: 18)
                .frame(width: size.width * 0.20, height: size.height * 0.68)
                .position(x: size.width * 0.66, y: size.height * 0.49)
        }
    }

    @ViewBuilder
    private func performerGroup(size: CGSize) -> some View {
        switch template.visualStyle {
        case .emptyStage:
            EmptyView()
        case .warmConcert:
            ForEach(0..<3, id: \.self) { index in
                performer
                    .frame(width: 18, height: 42)
                    .position(x: size.width * (0.43 + CGFloat(index) * 0.07), y: size.height * 0.68)
            }
        case .coolShowcase:
            ForEach(0..<5, id: \.self) { index in
                performer
                    .frame(width: 15, height: 36)
                    .position(x: size.width * (0.36 + CGFloat(index) * 0.07), y: size.height * 0.69)
            }
        case .partyFinale:
            ForEach(0..<4, id: \.self) { index in
                performer
                    .frame(width: 17, height: 40)
                    .position(x: size.width * (0.39 + CGFloat(index) * 0.075), y: size.height * 0.68)
            }
        }
    }

    private var performer: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color.white.opacity(0.86))
                .frame(width: 8, height: 8)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.78))
        }
        .shadow(color: Color.white.opacity(0.18), radius: 6)
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

private struct ProjectLightBeam: View {
    let color: Color
    let rotation: Double

    var body: some View {
        ProjectBeamShape()
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.08),
                        color,
                        color.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blur(radius: 3)
            .rotationEffect(.degrees(rotation))
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
                .accessibilityHidden(true)

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
                    .accessibilityHint("開啟燈具指南，認識常見的舞台燈具")

                Button("建立專案", systemImage: "plus", action: createAction)
                    .font(.callout.weight(.semibold))
                    .lumaGlassButton(prominent: true)
                    .lumaGazeTarget()
                    .tint(LumaStageDesign.coolBlue)
                    .accessibilityHint("選擇範本以建立新的舞台專案")
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
                    .accessibilityHidden(true)

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
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Collapse the row's five text fragments + decorative icons into one VoiceOver element so
        // the project reads as a single item, with all its metadata folded into the label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(project.name)，\(project.venueDescription)，\(project.eventType)，\(project.lastEditedDescription)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("點兩下開啟此專案")
    }
}

#Preview {
    ProjectSelectionView()
        .environment(AppModel())
}
