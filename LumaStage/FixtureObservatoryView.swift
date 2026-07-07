import SwiftUI

#if os(visionOS)
import RealityKit

/// The volumetric window of the fixture observatory: the 3D model, floating and fully manipulable
/// (drag to move, pinch to scale, twist to rotate). It shares paging state with the separate
/// info-card window via `appModel.fixtureCarousel`, so the two are independent, separately movable
/// objects rather than one fused panel.
///
/// Manipulation rides on a stable container entity (`fixture_stage`) carrying an
/// `InputTargetComponent` + `CollisionComponent`, so the targeted gestures keep working across page
/// swaps (only the visual model child is swapped). The transform resets to default on page change so
/// each fixture is presented centered.
struct FixtureObservatoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var stage = Entity()

    var body: some View {
        // Eagerly read the shown model so `body` re-evaluates when paging swaps the fixture — this
        // both drives the RealityView `update:` (same Observation footgun as elsewhere) and keeps the
        // accessibility label below in sync with the current fixture.
        let model = appModel.fixtureCarousel.current
        let fixtureName = LightingFixtureCatalog.item(for: model)?.displayName ?? "燈具"

        return RealityView { content in
            stage.name = "fixture_stage"
            content.add(stage)
            sync(stage)
        } update: { _ in
            sync(stage)
        }
        // The 3D model isn't a SwiftUI element, so VoiceOver/Voice Control have nothing to announce
        // without an explicit label. Name the current fixture and describe the manipulation gesture.
        .accessibilityElement()
        .accessibilityLabel(fixtureName)
        .accessibilityValue("3D 燈具模型")
        .accessibilityHint("用雙手可旋轉與縮放")
        // Each fixture is re-presented centered: drop any move/scale/rotate from the previous one.
        .onChange(of: appModel.fixtureCarousel.index) {
            stage.transform = Transform()
        }
        .onAppear {
            // Dismiss the launch/project window while inspecting; it's otherwise left behind as
            // nothing but its empty, draggable system bar. Reopened at the teardown sites below.
            dismissWindow(id: AppModel.mainWindowID)
            // Open the info card now that THIS volumetric window is on screen and registered in the
            // scene's window list, so the card's `.defaultWindowPlacement` finds it and seats the card
            // trailing (side by side) instead of stacking on top of the model. (Opening both windows
            // together from the Fixture Guide raced this lookup and overlapped them.)
            openWindow(id: AppModel.fixtureInfoCardWindowID)
        }
        .onDisappear {
            // Closing the model window (via system chrome) tears down the whole observatory.
            if appModel.isInspectingFixture {
                appModel.endFixtureInspection()
                dismissWindow(id: AppModel.fixtureInfoCardWindowID)
                openWindow(id: AppModel.mainWindowID)
            }
        }
    }

    /// Swaps the displayed model only when the shared model changes; the entity name encodes the
    /// visual model so repeated `update:` passes are cheap no-ops. After each swap the container is
    /// (re)configured for the system manipulation gesture, its collision shape refit to the new model
    /// so the whole fixture is grabbable.
    private func sync(_ stage: Entity) {
        let visualModel = appModel.fixtureCarousel.current
        let wantName = "fixture_model_\(visualModel.rawValue)"
        guard !stage.children.contains(where: { $0.name == wantName }) else {
            return
        }
        stage.children.forEach { $0.removeFromParent() }
        let model = FixtureRealityModel.makeEntity(for: visualModel)
        model.name = wantName
        stage.addChild(model)

        // Drive translate / scale / rotate through RealityKit's system manipulation gesture rather
        // than three competing SwiftUI gestures — the two pinch-based ones (scale and rotate) fought
        // each other so only one ever took effect. `configureEntity` adds the input target, a hover
        // highlight, the `ManipulationComponent`, and a collision refit to this model's bounds (so the
        // whole fixture is grabbable). `.stay` leaves the fixture where the user releases it instead of
        // snapping back — paging to another fixture re-centers it via the `onChange` above.
        let bounds = model.visualBounds(relativeTo: stage)
        let shape = ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
        ManipulationComponent.configureEntity(stage, collisionShapes: [shape])
        if var manipulation = stage.components[ManipulationComponent.self] {
            manipulation.releaseBehavior = .stay
            // Observatory behaves like a turntable: keep rotate + pinch-to-scale, but LOCK translation so
            // the fixture can't be dragged off-centre / out of reach — it only spins and resizes in place.
            manipulation.dynamics.translationBehavior = .none
            // Explicitly enable scaling. Leaving `scalingBehavior` at the component default had
            // pinch-to-zoom silently doing nothing on device while one-hand rotation still worked, so
            // the fixture could be spun but never enlarged. Rotation is left at its (working) default.
            manipulation.dynamics.scalingBehavior = .unconstrained
            stage.components.set(manipulation)
        }
    }
}

/// The plain, separately movable info-card window: teaching copy plus the paging and back controls.
/// Paging mutates the shared `appModel.fixtureCarousel`, which the volumetric model window observes.
struct FixtureInfoCardWindow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FixtureInfoCard(
            item: appModel.fixtureCarousel.currentItem,
            index: appModel.fixtureCarousel.index,
            count: appModel.fixtureCarousel.models.count,
            onBack: close,
            onPrevious: { page(by: -1) },
            onNext: { page(by: 1) }
        )
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .gesture(pageGesture)
        .onDisappear {
            // Closing the card window (via system chrome) tears down the whole observatory.
            if appModel.isInspectingFixture {
                appModel.endFixtureInspection()
                dismissWindow(id: AppModel.fixtureObservatoryWindowID)
                openWindow(id: AppModel.mainWindowID)
            }
        }
    }

    private func page(by direction: Int) {
        withAnimation(reduceMotion ? nil : .snappy) {
            appModel.pageFixture(by: direction)
        }
    }

    private func close() {
        appModel.endFixtureInspection()
        dismissWindow(id: AppModel.fixtureObservatoryWindowID)
        openWindow(id: AppModel.mainWindowID)
        dismiss()
    }

    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                if value.translation.width < -44 {
                    page(by: 1)
                } else if value.translation.width > 44 {
                    page(by: -1)
                }
            }
    }
}

private struct FixtureInfoCard: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let item: LightingFixtureCatalogItem?
    let index: Int
    let count: Int
    let onBack: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    /// The current fixture's name, spoken as the paging buttons' value so VoiceOver/Voice Control
    /// users hear which fixture they're on without relying on the colour-only dot indicator.
    private var currentName: String { item?.displayName ?? "燈具" }

    /// 1-based position read alongside the fixture name, e.g. "第 2 個，共 10 個".
    private var positionLabel: String { "第 \(index + 1) 個，共 \(max(count, 1)) 個" }

    /// VoiceOver value for both pager buttons: the current fixture plus its position in the carousel.
    private var pagerValue: String { "\(currentName)，\(positionLabel)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            backRow
            header
            if let item {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.shortDescription)
                        .font(.callout)
                        .foregroundStyle(LumaStageDesign.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.useCase)
                        .font(.caption)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label {
                        Text(item.beginnerPromptHint)
                    } icon: {
                        // Decorative — the prompt text below already reads as a sample prompt.
                        Image(systemName: "quote.bubble")
                            .accessibilityHidden(true)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LumaStageDesign.warmAmber)
                    .fixedSize(horizontal: false, vertical: true)
                }
                // Read the description, use case, and sample prompt as one continuous element so
                // VoiceOver doesn't stop between every short paragraph.
                .accessibilityElement(children: .combine)
            }
            pager
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lumaNativeGlass(tint: LumaStageDesign.coolBlue.opacity(0.08), radius: LumaStageDesign.surfaceRadius, fallbackOpacity: 0.36)
        .overlay {
            // Strengthen the card edge when Increase Contrast is on so the brand-tinted glass card
            // separates from whatever's behind it; the standard hairline stays subtle otherwise.
            RoundedRectangle(cornerRadius: LumaStageDesign.surfaceRadius, style: .continuous)
                .stroke(
                    colorSchemeContrast == .increased ? Color.primary.opacity(0.45) : LumaStageDesign.hairline,
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
        .foregroundStyle(LumaStageDesign.textPrimary)
    }

    private var backRow: some View {
        HStack {
            Button(action: onBack) {
                Label("返回專案", systemImage: "chevron.backward")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            // Closing inspection reopens the main window onto the project list (the Fixture Guide sheet
            // was dismissed when inspection began), so the label says 返回專案, not 返回燈具清單. Visible
            // text is the label, so VoiceOver and Voice Control "點按返回專案" stay in sync — no separate
            // `.accessibilityLabel`.
            .accessibilityHint("結束燈具預覽並回到專案列表")
            .lumaGazeTarget()

            Spacer()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item?.displayName ?? "燈具")
                .font(.title2.weight(.bold))

            Spacer()

            if let englishName = item?.englishName {
                Text(englishName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.coolBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        // Read the Chinese name + its English reference term as one element (a header), instead of two
        // separate fragments. Treat the whole title as the screen's heading for rotor navigation.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var pager: some View {
        HStack(spacing: 16) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .lumaGazeTarget()
            .accessibilityLabel("上一個燈具")
            .accessibilityValue(pagerValue)
            .accessibilityHint("切換到清單中的上一個燈具")

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<max(count, 1), id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? LumaStageDesign.coolBlue : LumaStageDesign.textSecondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                }
            }
            // Colour-only position dots — the position is spoken via each pager button's value, so the
            // dots are decoration for VoiceOver.
            .accessibilityHidden(true)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .lumaGazeTarget()
            .accessibilityLabel("下一個燈具")
            .accessibilityValue(pagerValue)
            .accessibilityHint("切換到清單中的下一個燈具")
        }
        .padding(.top, 2)
    }
}
#endif
