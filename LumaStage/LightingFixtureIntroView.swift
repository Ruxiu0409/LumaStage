import SwiftUI

#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit
#endif

struct LightingFixtureIntroView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var appModel

    let fixtures = LightingFixtureCatalog.allFixtures

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introHeader

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        ForEach(fixtures) { fixture in
                            Button {
                                appModel.startFixtureInspection(model: fixture.visualModel)
                                // Open ONLY the model window here; it opens the info card from its own
                                // onAppear (see `FixtureObservatoryView`). Opening both back-to-back here
                                // raced the card's `.trailing(observatory)` placement before the model
                                // window was registered, so the card fell back to the default spot and
                                // stacked on top of the model — you saw only the card. Deferring the card
                                // open until the model window is on screen fixes the side-by-side layout.
                                openWindow(id: AppModel.fixtureObservatoryWindowID)
                                dismiss()
                            } label: {
                                LightingFixtureIntroCard(fixture: fixture)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(22)
            }
            .foregroundStyle(LumaStageDesign.textPrimary)
            .navigationTitle("燈具指南")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var introHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("認識可控制的燈具", systemImage: "lightbulb.2")
                .font(.title2.weight(.bold))

            Text("點擊任一燈具即可在 3D 中檢視，然後左右滑動瀏覽整個目錄。先了解每種燈具的作用，再進入專案做出更清楚的燈光決策。")
                .font(.callout)
                .foregroundStyle(LumaStageDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .lumaNativeGlass(tint: LumaStageDesign.coolBlue.opacity(0.10), radius: LumaStageDesign.surfaceRadius, fallbackOpacity: 0.34)
        .overlay {
            RoundedRectangle(cornerRadius: LumaStageDesign.surfaceRadius, style: .continuous)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
    }
}

private struct LightingFixtureIntroCard: View {
    let fixture: LightingFixtureCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            LightingFixtureModelPreview(model: fixture.visualModel)
                .frame(height: 104)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fixture.displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(LumaStageDesign.textPrimary)

                    Spacer()

                    Text(fixture.englishName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.coolBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }

                Text(fixture.shortDescription)
                    .font(.caption)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label("點擊以 3D 檢視", systemImage: "hand.tap")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.warmAmber)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .lumaNativeGlass(tint: .white.opacity(0.035), radius: LumaStageDesign.surfaceRadius, interactive: false, fallbackOpacity: 0.34)
        .overlay {
            RoundedRectangle(cornerRadius: LumaStageDesign.surfaceRadius, style: .continuous)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
    }
}

struct LightingFixtureModelPreview: View {
    let model: LightingFixtureVisualModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.06, blue: 0.075),
                            Color(red: 0.11, green: 0.12, blue: 0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

#if canImport(SceneKit) && canImport(UIKit)
            SceneKitFixtureModelView(model: model)
                .padding(4)
#else
            Text("3D 模型預覽")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LumaStageDesign.textSecondary)
#endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
    }
}

#if canImport(SceneKit) && canImport(UIKit)
private struct SceneKitFixtureModelView: UIViewRepresentable {
    let model: LightingFixtureVisualModel

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = false
        view.scene = LightingFixtureSceneFactory.scene(for: model)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.scene = LightingFixtureSceneFactory.scene(for: model)
    }
}

private enum LightingFixtureSceneFactory {
    static func scene(for model: LightingFixtureVisualModel) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let root = SCNNode()
        root.eulerAngles = SCNVector3(-0.12, -0.44, 0)
        scene.rootNode.addChildNode(root)

        addLighting(to: scene)
        addFloor(to: scene)

        switch model {
        case .ledStrobeBar:
            addLedStrobeBar(to: root)
        case .movingHeadBeam:
            addMovingHeadBeam(to: root)
        case .ledPar:
            addLedPar(to: root)
        case .audienceBlinder:
            addAudienceBlinder(to: root)
        case .ledFresnel:
            addLedFresnel(to: root)
        case .laser:
            addLaser(to: root)
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.position = SCNVector3(0, 0.55, 4.2)
        camera.look(at: SCNVector3(0, 0.05, 0))
        scene.rootNode.addChildNode(camera)

        return scene
    }

    private static func addLighting(to scene: SCNScene) {
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.8, 0.35, 0.2)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 260
        fill.position = SCNVector3(-1.8, 1.4, 2.0)
        scene.rootNode.addChildNode(fill)
    }

    private static func addFloor(to scene: SCNScene) {
        let floor = SCNFloor()
        floor.reflectivity = 0.07
        floor.firstMaterial = material(color: UIColor(red: 0.08, green: 0.085, blue: 0.095, alpha: 1), roughness: 0.75)
        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(0, -0.92, 0)
        scene.rootNode.addChildNode(node)
    }

    // MARK: - Real-world product fixtures

    private static func addLedStrobeBar(to root: SCNNode) {
        // Long pixel/strobe bar, horizontal along X, standing on small end feet.
        let housing = box(width: 1.84, height: 0.20, length: 0.20, color: .blackBody, metalness: 0.6)
        housing.position = SCNVector3(0, 0.42, 0)
        root.addChildNode(housing)

        let facePlate = box(width: 1.78, height: 0.13, length: 0.05, color: .graphite, metalness: 0.5)
        facePlate.position = SCNVector3(0, 0.42, 0.11)
        root.addChildNode(facePlate)

        // Rainbow LED pixel row across the front.
        let rainbow: [FixtureUIColor] = [.redLens, .yellowLens, .greenLens, .cyanLens, .blueLens, .magentaLens]
        let pixelCount = 16
        for index in 0..<pixelCount {
            let x = -0.80 + Float(index) * (1.60 / Float(pixelCount - 1))
            let cup = box(width: 0.07, height: 0.10, length: 0.02, color: .blackBody, metalness: 0.55)
            cup.position = SCNVector3(x, 0.42, 0.135)
            root.addChildNode(cup)

            let lens = box(width: 0.052, height: 0.082, length: 0.02, color: rainbow[index % rainbow.count], metalness: 0.05, transparency: 0.9)
            lens.position = SCNVector3(x, 0.42, 0.15)
            root.addChildNode(lens)
        }

        // A few bright white strobe cells along the bottom edge.
        for x in [-0.55, 0.0, 0.55] as [Float] {
            let strobe = box(width: 0.12, height: 0.05, length: 0.02, color: .coolWhite, metalness: 0.04, transparency: 0.95)
            strobe.position = SCNVector3(x, 0.32, 0.135)
            root.addChildNode(strobe)
        }

        // End brackets + small feet so it reads as standing on the deck.
        for x in [-0.92, 0.92] as [Float] {
            let bracket = box(width: 0.08, height: 0.30, length: 0.24, color: .darkMetal, metalness: 0.66)
            bracket.position = SCNVector3(x, 0.40, 0)
            root.addChildNode(bracket)

            let foot = box(width: 0.22, height: 0.04, length: 0.34, color: .darkMetal, metalness: 0.7)
            foot.position = SCNVector3(x, 0.245, 0)
            root.addChildNode(foot)

            addYokeKnob(to: root, x: x, y: 0.40, z: 0.0)
        }

        addCoolingSlots(to: root, originX: -0.7, y: 0.50, z: -0.105, count: 9, vertical: true)
        addCable(to: root, fromX: 0.86, y: 0.30, z: -0.10)
    }

    private static func addMovingHeadBeam(to root: SCNNode) {
        // Heavy base — the moving head stands on it, no separate stand.
        let base = box(width: 0.66, height: 0.20, length: 0.60, color: .blackBody, metalness: 0.6)
        base.position = SCNVector3(0, -0.18, 0)
        root.addChildNode(base)

        let baseTop = box(width: 0.56, height: 0.08, length: 0.52, color: .graphite, metalness: 0.5)
        baseTop.position = SCNVector3(0, -0.04, 0)
        root.addChildNode(baseTop)

        let display = box(width: 0.18, height: 0.07, length: 0.02, color: .cyanLens, metalness: 0.05, transparency: 0.92)
        display.position = SCNVector3(-0.18, -0.04, 0.27)
        root.addChildNode(display)

        // Two yoke arms.
        for x in [-0.34, 0.34] as [Float] {
            let arm = box(width: 0.12, height: 0.62, length: 0.26, color: .darkMetal, metalness: 0.62)
            arm.position = SCNVector3(x, 0.22, 0)
            root.addChildNode(arm)
        }
        addYokeKnob(to: root, x: -0.30, y: 0.40, z: 0)
        addYokeKnob(to: root, x: 0.30, y: 0.40, z: 0)

        // Head — a cylinder whose axis points along Z so the lens faces forward (+Z).
        let head = cylinder(radius: 0.26, height: 0.56, color: .blackBody, metalness: 0.62)
        head.eulerAngles.x = .pi / 2
        head.position = SCNVector3(0, 0.46, 0.02)
        root.addChildNode(head)

        let rim = cylinder(radius: 0.275, height: 0.07, color: .darkMetal, metalness: 0.7)
        rim.eulerAngles.x = .pi / 2
        rim.position = SCNVector3(0, 0.46, 0.27)
        root.addChildNode(rim)

        let lens = cylinder(radius: 0.205, height: 0.04, color: .coolWhite, metalness: 0.05, transparency: 0.82)
        lens.eulerAngles.x = .pi / 2
        lens.position = SCNVector3(0, 0.46, 0.30)
        root.addChildNode(lens)
        addLensRing(to: root, radius: 0.225, x: 0, y: 0.46, z: 0.31, axis: .z)

        let rearCap = cylinder(radius: 0.245, height: 0.07, color: .graphite, metalness: 0.66)
        rearCap.eulerAngles.x = .pi / 2
        rearCap.position = SCNVector3(0, 0.46, -0.26)
        root.addChildNode(rearCap)

        addCoolingSlots(to: root, originX: -0.13, y: 0.62, z: -0.05, count: 5, vertical: false)
    }

    private static func addLedPar(to root: SCNNode) {
        addStand(to: root)

        let yoke = box(width: 0.86, height: 0.07, length: 0.12, color: .blackBody, metalness: 0.65)
        yoke.position = SCNVector3(0, 0.54, 0)
        root.addChildNode(yoke)

        for x in [-0.40, 0.40] as [Float] {
            let arm = box(width: 0.07, height: 0.50, length: 0.08, color: .blackBody, metalness: 0.65)
            arm.position = SCNVector3(x, 0.28, 0)
            root.addChildNode(arm)
        }
        addYokeKnob(to: root, x: -0.44, y: 0.30, z: 0)
        addYokeKnob(to: root, x: 0.44, y: 0.30, z: 0)

        // Round PAR can — axis along Z so the lens face points forward.
        let can = cylinder(radius: 0.34, height: 0.30, color: .blackBody, metalness: 0.6)
        can.eulerAngles.x = .pi / 2
        can.position = SCNVector3(0, 0.22, 0)
        root.addChildNode(can)

        let rearFins = cylinder(radius: 0.345, height: 0.10, color: .graphite, metalness: 0.66)
        rearFins.eulerAngles.x = .pi / 2
        rearFins.position = SCNVector3(0, 0.22, -0.16)
        root.addChildNode(rearFins)

        let bezel = cylinder(radius: 0.34, height: 0.03, color: .darkMetal, metalness: 0.6)
        bezel.eulerAngles.x = .pi / 2
        bezel.position = SCNVector3(0, 0.22, 0.155)
        root.addChildNode(bezel)
        addLensRing(to: root, radius: 0.32, x: 0, y: 0.22, z: 0.17, axis: .z)

        // Dense grid of small LED cells filling the circular face.
        let ledColors: [FixtureUIColor] = [.coolWhite, .coolWhite, .coolWhite, .redLens, .greenLens, .blueLens]
        var colorIndex = 0
        let step: Float = 0.088
        var gridY: Float = -0.26
        while gridY <= 0.26 {
            var gridX: Float = -0.26
            while gridX <= 0.26 {
                if (gridX * gridX + gridY * gridY).squareRoot() <= 0.27 {
                    let led = cylinder(radius: 0.032, height: 0.02, color: ledColors[colorIndex % ledColors.count], metalness: 0.05, transparency: 0.9)
                    led.eulerAngles.x = .pi / 2
                    led.position = SCNVector3(gridX, 0.22 + gridY, 0.175)
                    root.addChildNode(led)
                    colorIndex += 1
                }
                gridX += step
            }
            gridY += step
        }
    }

    private static func addAudienceBlinder(to root: SCNNode) {
        addStand(to: root)

        let yoke = box(width: 1.02, height: 0.08, length: 0.12, color: .blackBody, metalness: 0.65)
        yoke.position = SCNVector3(0, 0.66, 0)
        root.addChildNode(yoke)

        for x in [-0.50, 0.50] as [Float] {
            let arm = box(width: 0.08, height: 0.60, length: 0.08, color: .blackBody, metalness: 0.65)
            arm.position = SCNVector3(x, 0.32, 0)
            root.addChildNode(arm)
        }
        addYokeKnob(to: root, x: -0.54, y: 0.34, z: 0)
        addYokeKnob(to: root, x: 0.54, y: 0.34, z: 0)

        // Square panel housing.
        let panel = box(width: 0.86, height: 0.86, length: 0.22, color: .blackBody, metalness: 0.55)
        panel.position = SCNVector3(0, 0.30, 0)
        root.addChildNode(panel)

        // 2x2 grid of large warm-white COB cells.
        for row in 0..<2 {
            for column in 0..<2 {
                let cellX = -0.20 + Float(column) * 0.40
                let cellY = 0.10 + Float(row) * 0.40
                let cell = box(width: 0.36, height: 0.36, length: 0.05, color: .graphite, metalness: 0.5)
                cell.position = SCNVector3(cellX, cellY, 0.12)
                root.addChildNode(cell)

                let lens = cylinder(radius: 0.15, height: 0.03, color: .warmWhite, metalness: 0.04, transparency: 0.92)
                lens.eulerAngles.x = .pi / 2
                lens.position = SCNVector3(cellX, cellY, 0.155)
                root.addChildNode(lens)
                addLensRing(to: root, radius: 0.16, x: cellX, y: cellY, z: 0.165, axis: .z)
            }
        }

        addCoolingSlots(to: root, originX: -0.5, y: 0.30, z: -0.12, count: 8, vertical: false)
        addCable(to: root, fromX: 0.40, y: 0.10, z: -0.10)
    }

    private static func addLedFresnel(to root: SCNNode) {
        addStand(to: root)

        let body = box(width: 0.64, height: 0.58, length: 0.44, color: .darkMetal, metalness: 0.62)
        body.position = SCNVector3(0, 0.20, 0)
        root.addChildNode(body)

        let yoke = box(width: 0.92, height: 0.08, length: 0.08, color: .blackBody, metalness: 0.65)
        yoke.position = SCNVector3(0, 0.56, 0)
        root.addChildNode(yoke)

        for x in [-0.40, 0.40] as [Float] {
            let arm = box(width: 0.07, height: 0.56, length: 0.08, color: .blackBody, metalness: 0.65)
            arm.position = SCNVector3(x, 0.27, 0)
            root.addChildNode(arm)
        }
        addYokeKnob(to: root, x: -0.45, y: 0.29, z: 0)
        addYokeKnob(to: root, x: 0.45, y: 0.29, z: 0)

        // Fresnel lens with concentric rings.
        let lens = cylinder(radius: 0.26, height: 0.06, color: .coolWhite, metalness: 0.05, transparency: 0.84)
        lens.eulerAngles.x = .pi / 2
        lens.position = SCNVector3(0, 0.20, 0.25)
        root.addChildNode(lens)

        for radius in [0.10, 0.17, 0.24] as [CGFloat] {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: radius, pipeRadius: 0.008))
            ring.geometry?.firstMaterial = material(color: FixtureUIColor.silverMetal.uiColor, metalness: 0.7)
            ring.eulerAngles.x = .pi / 2
            ring.position = SCNVector3(0, 0.20, 0.285)
            root.addChildNode(ring)
        }

        // Three LED emitters visible behind the lens (matches the product's triple-LED face).
        for emitter in [SCNVector3(0, 0.31, 0.205), SCNVector3(-0.10, 0.135, 0.205), SCNVector3(0.10, 0.135, 0.205)] {
            let led = sphere(radius: 0.05, color: .coolWhite, metalness: 0.04)
            led.position = emitter
            root.addChildNode(led)
        }

        // Square lens-holder frame standing proud of the lens.
        let frameEdges: [(CGFloat, CGFloat, Float, Float)] = [
            (0.54, 0.04, 0.0, 0.47),
            (0.54, 0.04, 0.0, -0.07),
            (0.04, 0.54, -0.27, 0.20),
            (0.04, 0.54, 0.27, 0.20)
        ]
        for (width, height, edgeX, edgeY) in frameEdges {
            let edge = box(width: width, height: height, length: 0.05, color: .blackBody, metalness: 0.55)
            edge.position = SCNVector3(edgeX, edgeY, 0.33)
            root.addChildNode(edge)
        }

        addCoolingSlots(to: root, originX: -0.16, y: 0.20, z: -0.235, count: 5, vertical: true)
        addScrew(to: root, x: -0.27, y: 0.47, z: 0.30)
        addScrew(to: root, x: 0.27, y: -0.07, z: 0.30)
    }

    private static func addLaser(to root: SCNNode) {
        // Truss-mounted laser scanner with an RGB emitter face and the signature fan of thin, glowing
        // aerial beams (constant-shaded + additive so they read as light, not solid rods).
        addHangingClamp(to: root, y: 0.74)

        let housing = box(width: 0.92, height: 0.42, length: 0.5, color: .blackBody, metalness: 0.6)
        housing.position = SCNVector3(0, 0.2, 0)
        root.addChildNode(housing)

        let facePlate = box(width: 0.8, height: 0.3, length: 0.05, color: .graphite, metalness: 0.5)
        facePlate.position = SCNVector3(0, 0.2, 0.25)
        root.addChildNode(facePlate)

        for x in [-0.5, 0.5] as [Float] {
            let cheek = box(width: 0.08, height: 0.5, length: 0.5, color: .darkMetal, metalness: 0.66)
            cheek.position = SCNVector3(x, 0.2, 0)
            root.addChildNode(cheek)
        }

        let emitterColors: [FixtureUIColor] = [.redLens, .greenLens, .blueLens, .cyanLens, .magentaLens]
        for (index, x) in ([-0.28, -0.14, 0.0, 0.14, 0.28] as [Float]).enumerated() {
            let cup = cylinder(radius: 0.05, height: 0.04, color: .blackBody, metalness: 0.6)
            cup.eulerAngles.x = .pi / 2
            cup.position = SCNVector3(x, 0.2, 0.265)
            root.addChildNode(cup)

            let dot = sphere(radius: 0.03, color: emitterColors[index % emitterColors.count], metalness: 0.05)
            dot.position = SCNVector3(x, 0.2, 0.285)
            root.addChildNode(dot)
        }

        addCoolingSlots(to: root, originX: -0.34, y: 0.42, z: -0.255, count: 7, vertical: true)

        // A small fan of bright green beams shooting forward. Each beam hangs off a yaw pivot at the
        // emitter, laid along +Z and pushed out by half its length, so the fan spreads cleanly.
        let beamLength: CGFloat = 0.62
        for yawDegrees in [-16.0, 0.0, 16.0] as [Float] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0, 0.2, 0.30)
            pivot.eulerAngles.y = yawDegrees * .pi / 180

            let beamGeometry = SCNCylinder(radius: 0.012, height: beamLength)
            beamGeometry.radialSegmentCount = 12
            beamGeometry.firstMaterial = material(color: FixtureUIColor.greenLens.uiColor, metalness: 0, transparency: 0.9, lightingModel: .constant)
            let beam = SCNNode(geometry: beamGeometry)
            beam.eulerAngles.x = .pi / 2
            beam.position = SCNVector3(0, 0, Float(beamLength / 2))
            pivot.addChildNode(beam)
            root.addChildNode(pivot)
        }
    }

    private static func addStand(to root: SCNNode) {
        let pole = cylinder(radius: 0.025, height: 0.72, color: .silverMetal, metalness: 0.8)
        pole.position = SCNVector3(0, -0.36, 0)
        root.addChildNode(pole)

        let foot = cylinder(radius: 0.34, height: 0.035, color: .darkMetal, metalness: 0.7)
        foot.position = SCNVector3(0, -0.74, 0)
        root.addChildNode(foot)
    }

    private static func addHangingClamp(to root: SCNNode, y: Float) {
        let rail = cylinder(radius: 0.035, height: 1.2, color: .silverMetal, metalness: 0.82)
        rail.eulerAngles.z = .pi / 2
        rail.position = SCNVector3(0, y, -0.04)
        root.addChildNode(rail)

        let clamp = box(width: 0.18, height: 0.14, length: 0.18, color: .darkMetal, metalness: 0.72)
        clamp.position = SCNVector3(0, y - 0.13, -0.04)
        root.addChildNode(clamp)

        let hook = SCNNode(geometry: SCNTorus(ringRadius: 0.10, pipeRadius: 0.014))
        hook.geometry?.firstMaterial = material(color: FixtureUIColor.silverMetal.uiColor, metalness: 0.82)
        hook.eulerAngles.x = .pi / 2
        hook.position = SCNVector3(0, y - 0.06, -0.04)
        root.addChildNode(hook)
    }

    private static func addLensRing(to root: SCNNode, radius: CGFloat, x: Float, y: Float, z: Float, axis: Axis3D) {
        let ring = SCNNode(geometry: SCNTorus(ringRadius: radius, pipeRadius: 0.007))
        ring.geometry?.firstMaterial = material(color: FixtureUIColor.silverMetal.uiColor, metalness: 0.72)
        if axis == .z {
            ring.eulerAngles.x = .pi / 2
        } else {
            ring.eulerAngles.z = .pi / 2
        }
        ring.position = SCNVector3(x, y, z)
        root.addChildNode(ring)
    }

    private static func addScrew(to root: SCNNode, x: Float, y: Float, z: Float) {
        let screw = cylinder(radius: 0.018, height: 0.010, color: .silverMetal, metalness: 0.88)
        screw.eulerAngles.x = .pi / 2
        screw.position = SCNVector3(x, y, z)
        root.addChildNode(screw)
    }

    private static func addYokeKnob(to root: SCNNode, x: Float, y: Float, z: Float) {
        let knob = cylinder(radius: 0.075, height: 0.040, color: .rubberBlack, metalness: 0.12)
        knob.eulerAngles.x = .pi / 2
        knob.position = SCNVector3(x, y, z + 0.06)
        root.addChildNode(knob)

        let cap = cylinder(radius: 0.040, height: 0.012, color: .silverMetal, metalness: 0.80)
        cap.eulerAngles.x = .pi / 2
        cap.position = SCNVector3(x, y, z + 0.09)
        root.addChildNode(cap)
    }

    private static func addCoolingSlots(to root: SCNNode, originX: Float, y: Float, z: Float, count: Int, vertical: Bool) {
        for index in 0..<count {
            let offset = Float(index) * 0.055
            let slot = box(
                width: vertical ? 0.018 : 0.040,
                height: vertical ? 0.14 : 0.014,
                length: 0.010,
                color: .rubberBlack,
                metalness: 0.08
            )
            slot.position = SCNVector3(originX + offset, y, z)
            root.addChildNode(slot)
        }
    }

    private static func addBarnDoor(to root: SCNNode, x: Float, y: Float, z: Float, angle: Float) {
        let panel = box(width: 0.44, height: 0.055, length: 0.20, color: .blackBody, metalness: 0.50)
        panel.eulerAngles.x = angle
        panel.position = SCNVector3(x, y, z)
        root.addChildNode(panel)
    }

    private static func addCable(to root: SCNNode, fromX: Float, y: Float, z: Float) {
        let cable = cylinder(radius: 0.014, height: 0.42, color: .rubberBlack, metalness: 0.04)
        cable.eulerAngles.x = .pi / 2
        cable.eulerAngles.z = 0.28
        cable.position = SCNVector3(fromX + 0.12, y - 0.04, z - 0.16)
        root.addChildNode(cable)
    }

    private static func box(width: CGFloat, height: CGFloat, length: CGFloat, color: FixtureUIColor, metalness: CGFloat, transparency: CGFloat = 1) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.025)
        geometry.firstMaterial = material(color: color.uiColor, metalness: metalness, transparency: transparency)
        return SCNNode(geometry: geometry)
    }

    private static func cylinder(radius: CGFloat, height: CGFloat, color: FixtureUIColor, metalness: CGFloat, transparency: CGFloat = 1) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.radialSegmentCount = 32
        geometry.firstMaterial = material(color: color.uiColor, metalness: metalness, transparency: transparency)
        return SCNNode(geometry: geometry)
    }

    private static func sphere(radius: CGFloat, color: FixtureUIColor, metalness: CGFloat) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 32
        geometry.firstMaterial = material(color: color.uiColor, metalness: metalness)
        return SCNNode(geometry: geometry)
    }

    private static func cone(topRadius: CGFloat, bottomRadius: CGFloat, height: CGFloat, color: FixtureUIColor, transparency: CGFloat) -> SCNNode {
        let geometry = SCNCone(topRadius: topRadius, bottomRadius: bottomRadius, height: height)
        geometry.radialSegmentCount = 48
        geometry.firstMaterial = material(color: color.uiColor, metalness: 0, transparency: transparency, lightingModel: .constant)
        return SCNNode(geometry: geometry)
    }

    private static func material(
        color: UIColor,
        metalness: CGFloat = 0,
        transparency: CGFloat = 1,
        lightingModel: SCNMaterial.LightingModel = .physicallyBased,
        roughness: CGFloat = 0.38
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.metalness.contents = metalness
        material.roughness.contents = roughness
        material.transparency = transparency
        material.lightingModel = lightingModel
        material.blendMode = transparency < 1 ? .add : .alpha
        material.isDoubleSided = transparency < 1
        return material
    }
}

private enum Axis3D {
    case x
    case z
}

private enum FixtureUIColor {
    case blackBody
    case darkMetal
    case graphite
    case silverMetal
    case blueLens
    case deepBlueLens
    case amberLens
    case warmLens
    case redLens
    case greenLens
    case yellowLens
    case magentaLens
    case cyanLens
    case coolWhite
    case warmWhite
    case blueBeam
    case amberBeam
    case warmBeam
    case rubberBlack

    var uiColor: UIColor {
        switch self {
        case .blackBody:
            return UIColor(red: 0.03, green: 0.035, blue: 0.045, alpha: 1)
        case .darkMetal:
            return UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
        case .graphite:
            return UIColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1)
        case .silverMetal:
            return UIColor(red: 0.70, green: 0.72, blue: 0.72, alpha: 1)
        case .blueLens:
            return UIColor(red: 0.19, green: 0.55, blue: 1.0, alpha: 1)
        case .deepBlueLens:
            return UIColor(red: 0.08, green: 0.18, blue: 0.82, alpha: 1)
        case .amberLens:
            return UIColor(red: 1.0, green: 0.53, blue: 0.16, alpha: 1)
        case .warmLens:
            return UIColor(red: 1.0, green: 0.72, blue: 0.44, alpha: 1)
        case .redLens:
            return UIColor(red: 1.0, green: 0.16, blue: 0.18, alpha: 1)
        case .greenLens:
            return UIColor(red: 0.20, green: 0.92, blue: 0.34, alpha: 1)
        case .yellowLens:
            return UIColor(red: 1.0, green: 0.85, blue: 0.16, alpha: 1)
        case .magentaLens:
            return UIColor(red: 0.96, green: 0.20, blue: 0.78, alpha: 1)
        case .cyanLens:
            return UIColor(red: 0.16, green: 0.86, blue: 0.96, alpha: 1)
        case .coolWhite:
            return UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
        case .warmWhite:
            return UIColor(red: 1.0, green: 0.93, blue: 0.78, alpha: 1)
        case .blueBeam:
            return UIColor(red: 0.22, green: 0.58, blue: 1.0, alpha: 1)
        case .amberBeam:
            return UIColor(red: 1.0, green: 0.60, blue: 0.20, alpha: 1)
        case .warmBeam:
            return UIColor(red: 1.0, green: 0.78, blue: 0.52, alpha: 1)
        case .rubberBlack:
            return UIColor(red: 0.006, green: 0.007, blue: 0.009, alpha: 1)
        }
    }
}
#endif

#Preview {
    LightingFixtureIntroView()
        .environment(AppModel())
}
