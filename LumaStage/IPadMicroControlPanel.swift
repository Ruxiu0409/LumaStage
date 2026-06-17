import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct IPadMicroControlPanel: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedFixtureId: String?
    var usesInternalScroll = true

    private let colorSwatches = [
        WashSwatch(name: "Warm", hex: "#FFD1A3"),
        WashSwatch(name: "Sky Blue", hex: "#4FA8FF"),
        WashSwatch(name: "Deep Blue", hex: "#2F6BFF"),
        WashSwatch(name: "Magenta", hex: "#D65CFF"),
        WashSwatch(name: "Cool White", hex: "#EAF4FF")
    ]

    private var selectedFixture: FixtureGroup? {
        if let fixture = appModel.selectedFixture(id: selectedFixtureId) {
            return fixture
        }

        return appModel.selectedCueFixtures.first
    }

    var body: some View {
        Group {
            if usesInternalScroll {
                ScrollView {
                    panelContent
                }
                .scrollIndicators(.visible)
            } else {
                panelContent
            }
        }
        .lumaPanel()
        .onAppear(perform: ensureSelectedFixture)
        .onChange(of: appModel.selectedCueId) { _, _ in
            ensureSelectedFixture()
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: LumaStageDesign.sectionSpacing) {
            header
            sceneSegmentSelector
            fixtureSelector

            if let selectedFixture {
                intensityControl(for: selectedFixture)
                colorControl(for: selectedFixture)
                angleControls(for: selectedFixture)
                positionControls(for: selectedFixture)
                patchReadout(for: selectedFixture)
            } else {
                emptyFixtureState
            }
        }
        .padding(.bottom, 2)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("iPad Fine Control", systemImage: "slider.horizontal.3")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)

                Text("Select a cue and fixture to fine-tune color, intensity, position, and angle")
                    .font(.caption)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                appModel.resetSelectedCue()
                ensureSelectedFixture()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.headline)
            }
            .lumaGlassButton()
            .help("Reset Current Cue")
        }
    }

    private var sceneSegmentSelector: some View {
        LumaControlSection(
            title: "Cue",
            subtitle: "Choose the cue to fine-tune",
            systemImage: "film.stack"
        ) {
            Picker(
                "Cue",
                selection: Binding(
                    get: { appModel.selectedCueId },
                    set: { appModel.selectCue(id: $0) }
                )
            ) {
                ForEach(appModel.lightingLook.cues) { cue in
                    Text(cue.localizedDisplayName).tag(cue.id)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var fixtureSelector: some View {
        LumaControlSection(
            title: "Fixture",
            subtitle: "Select one fixture group for Fine Control",
            systemImage: "lightbulb.2"
        ) {
            VStack(spacing: 10) {
                ForEach(appModel.selectedCueFixtures) { fixture in
                    fixtureButton(fixture)
                }
            }
        }
    }

    private func fixtureButton(_ fixture: FixtureGroup) -> some View {
        let isSelected = selectedFixture?.id == fixture.id

        return Button {
            selectedFixtureId = fixture.id
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color(for: fixture.color.value))
                    .frame(width: 38, height: 30)
                    .overlay {
                        Image(systemName: icon(for: fixture.role))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(fixture.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.textPrimary)

                    Text("\(roleName(fixture.role)) · \(zoneName(fixture.zone))")
                        .font(.caption2)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                }

                Spacer()

                Text("\(Int(round(fixture.intensity * 100)))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? LumaStageDesign.coolBlue : LumaStageDesign.textSecondary)
            }
            .padding(10)
            .lumaNativeGlass(
                tint: isSelected ? LumaStageDesign.coolBlue.opacity(0.16) : .white.opacity(0.02),
                radius: LumaStageDesign.cornerRadius,
                interactive: true,
                fallbackOpacity: isSelected ? 0.50 : 0.28
            )
            .overlay {
                RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius, style: .continuous)
                    .stroke(isSelected ? LumaStageDesign.coolBlue.opacity(0.78) : LumaStageDesign.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func intensityControl(for fixture: FixtureGroup) -> some View {
        LumaControlSection(
            title: "Intensity",
            subtitle: "Slider and numeric input update the selected fixture",
            systemImage: "sun.max"
        ) {
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { fixture.intensity },
                        set: { appModel.setFixtureIntensity(id: fixture.id, value: clamped($0, in: 0...1)) }
                    ),
                    in: 0...1,
                    step: 0.01
                )
                .tint(LumaStageDesign.warmAmber)

                LumaNumberInput(
                    value: Binding(
                        get: { fixture.intensity * 100 },
                        set: { appModel.setFixtureIntensity(id: fixture.id, value: clamped($0 / 100, in: 0...1)) }
                    ),
                    range: 0...100,
                    unit: "%"
                )
                .frame(width: 104)
            }
        }
    }

    private func colorControl(for fixture: FixtureGroup) -> some View {
        LumaControlSection(
            title: "Color",
            subtitle: "Use swatches for quick changes or open the native color picker",
            systemImage: "paintpalette"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(colorSwatches) { swatch in
                        Button {
                            appModel.setFixtureColor(id: fixture.id, hexColor: swatch.hex)
                        } label: {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            fixture.color.value == swatch.hex ? Color.white : LumaStageDesign.hairline,
                                            lineWidth: fixture.color.value == swatch.hex ? 3 : 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .help(swatch.name)
                    }
                }

                ColorPicker(
                    "Custom Color",
                    selection: Binding(
                        get: { color(for: fixture.color.value) },
                        set: { newColor in
                            if let hex = newColor.hexRGB {
                                appModel.setFixtureColor(id: fixture.id, hexColor: hex)
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(LumaStageDesign.textPrimary)
            }
        }
    }

    private func angleControls(for fixture: FixtureGroup) -> some View {
        let control = fixture.effectiveFineControl

        return LumaControlSection(
            title: "Angle and Beam",
            subtitle: "Pan / Tilt / Roll control direction, while Beam controls spread",
            systemImage: "scope"
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    LumaAngleControl(
                        title: "Pan",
                        value: fineControlBinding(for: fixture, get: \.panDegrees) { $0.panDegrees = $1 },
                        range: -180...180,
                        tint: LumaStageDesign.coolBlue
                    )

                    LumaAngleControl(
                        title: "Tilt",
                        value: fineControlBinding(for: fixture, get: \.tiltDegrees) { $0.tiltDegrees = $1 },
                        range: -90...90,
                        tint: LumaStageDesign.warmAmber
                    )
                }

                HStack(spacing: 12) {
                    LumaFineSlider(
                        title: "Roll",
                        value: fineControlBinding(for: fixture, get: \.rollDegrees) { $0.rollDegrees = $1 },
                        range: -180...180,
                        unit: "deg",
                        tint: LumaStageDesign.magenta
                    )

                    LumaFineSlider(
                        title: "Beam",
                        value: fineControlBinding(for: fixture, get: \.beamAngleDegrees) { $0.beamAngleDegrees = $1 },
                        range: 5...120,
                        unit: "deg",
                        tint: LumaStageDesign.softGreen
                    )
                }

                Text("Current: Pan \(Int(round(control.panDegrees)))deg · Tilt \(Int(round(control.tiltDegrees)))deg · Beam \(Int(round(control.beamAngleDegrees)))deg")
                    .font(.caption2)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private func positionControls(for fixture: FixtureGroup) -> some View {
        LumaControlSection(
            title: "Position",
            subtitle: "Fine-tune fixture position in stage coordinates, measured in meters",
            systemImage: "move.3d"
        ) {
            HStack(spacing: 10) {
                LumaNumberInput(
                    label: "X",
                    value: positionBinding(for: fixture, axis: .x),
                    range: -5...5,
                    unit: "m"
                )

                LumaNumberInput(
                    label: "Y",
                    value: positionBinding(for: fixture, axis: .y),
                    range: 0...6,
                    unit: "m"
                )

                LumaNumberInput(
                    label: "Z",
                    value: positionBinding(for: fixture, axis: .z),
                    range: -5...5,
                    unit: "m"
                )
            }
        }
    }

    private func patchReadout(for fixture: FixtureGroup) -> some View {
        let control = fixture.effectiveFineControl

        return VStack(alignment: .leading, spacing: 10) {
            LumaSectionHeader(title: "Live Readout", subtitle: "Applied to \(appModel.selectedCue?.localizedDisplayName ?? "Current Cue") / \(fixture.name)", systemImage: "waveform.path.ecg")

            LumaMetricRow(title: "Intensity", value: "\(Int(round(fixture.intensity * 100)))%", tint: LumaStageDesign.warmAmber)
            LumaMetricRow(title: "Color", value: fixture.color.value, tint: color(for: fixture.color.value))
            LumaMetricRow(title: "Position", value: String(format: "X %.2f  Y %.2f  Z %.2f", control.position.x, control.position.y, control.position.z), tint: LumaStageDesign.coolBlue)
            LumaMetricRow(title: "Angle", value: String(format: "P %.0f  T %.0f  R %.0f", control.panDegrees, control.tiltDegrees, control.rollDegrees), tint: LumaStageDesign.magenta)
        }
        .padding(14)
        .lumaNativeGlass(tint: .white.opacity(0.03), radius: 14, interactive: false, fallbackOpacity: 0.34)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
    }

    private var emptyFixtureState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb.slash")
                .font(.title2.weight(.semibold))
                .foregroundStyle(LumaStageDesign.textSecondary)

            Text("No adjustable fixtures in the current cue")
                .font(.callout.weight(.semibold))
                .foregroundStyle(LumaStageDesign.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func ensureSelectedFixture() {
        guard !appModel.selectedCueFixtures.isEmpty else {
            selectedFixtureId = nil
            return
        }

        if let selectedFixtureId,
           appModel.selectedCueFixtures.contains(where: { $0.id == selectedFixtureId }) {
            return
        }

        selectedFixtureId = appModel.selectedCueFixtures.first?.id
    }

    private func fineControlBinding(
        for fixture: FixtureGroup,
        get keyPath: KeyPath<FixtureFineControl, Double>,
        set mutation: @escaping (inout FixtureFineControl, Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { selectedFixture?.effectiveFineControl[keyPath: keyPath] ?? fixture.effectiveFineControl[keyPath: keyPath] },
            set: { newValue in
                updateFineControl(fixtureId: fixture.id) { control in
                    mutation(&control, newValue)
                }
            }
        )
    }

    private func positionBinding(for fixture: FixtureGroup, axis: PositionAxis) -> Binding<Double> {
        Binding(
            get: {
                let control = selectedFixture?.effectiveFineControl ?? fixture.effectiveFineControl
                switch axis {
                case .x: return control.position.x
                case .y: return control.position.y
                case .z: return control.position.z
                }
            },
            set: { newValue in
                updateFineControl(fixtureId: fixture.id) { control in
                    switch axis {
                    case .x:
                        control.position.x = newValue
                    case .y:
                        control.position.y = newValue
                    case .z:
                        control.position.z = newValue
                    }
                }
            }
        )
    }

    private func updateFineControl(fixtureId: String, mutation: (inout FixtureFineControl) -> Void) {
        guard let fixture = appModel.selectedFixture(id: fixtureId) else {
            return
        }

        var control = fixture.effectiveFineControl
        mutation(&control)
        appModel.setFixtureFineControl(id: fixture.id, control: control)
    }

    private func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func color(for hex: String) -> Color {
        let rgb = RGBComponents(hex: hex) ?? .white
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func icon(for role: FixtureRole) -> String {
        switch role {
        case .frontLight:
            return "person.crop.rectangle.badge.plus"
        case .backgroundWash:
            return "rectangle.on.rectangle"
        case .wash:
            return "lightswitch.on"
        case .spot:
            return "scope"
        }
    }

    private func roleName(_ role: FixtureRole) -> String {
        switch role {
        case .wash:
            return "Wash Light"
        case .spot:
            return "Spot"
        case .frontLight:
            return "Front Light"
        case .backgroundWash:
            return "Background Wash"
        }
    }

    private func zoneName(_ zone: StageZone) -> String {
        switch zone {
        case .stageFront:
            return "Stage Front"
        case .stageBack:
            return "Stage Back"
        case .stageLeft:
            return "Stage Left"
        case .stageRight:
            return "Stage Right"
        case .fullStage:
            return "Full Stage"
        }
    }
}

private enum PositionAxis {
    case x
    case y
    case z
}

private struct LumaAngleControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)

                Spacer()

                Text("\(Int(round(value)))deg")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

                ZStack {
                    Circle()
                        .stroke(LumaStageDesign.hairline, lineWidth: 1)

                    Circle()
                        .fill(tint.opacity(0.14))

                    Rectangle()
                        .fill(tint)
                        .frame(width: 3, height: size * 0.36)
                        .offset(y: -size * 0.18)
                        .rotationEffect(.degrees(value))

                    Circle()
                        .fill(tint)
                        .frame(width: 9, height: 9)
                }
                .frame(width: size, height: size)
                .position(center)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            value = clamped(angle(for: gesture.location, center: center), in: range)
                        }
                )
            }
            .frame(height: 92)

            LumaNumberInput(value: $value, range: range, unit: "deg")
        }
        .padding(12)
        .lumaNativeGlass(tint: tint.opacity(0.08), radius: LumaStageDesign.cornerRadius, fallbackOpacity: 0.26)
    }

    private func angle(for location: CGPoint, center: CGPoint) -> Double {
        let dx = location.x - center.x
        let dy = location.y - center.y
        return atan2(dx, -dy) * 180 / .pi
    }

    private func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct LumaFineSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LumaMetricRow(title: title, value: "\(Int(round(value))) \(unit)", tint: tint)

            Slider(value: $value, in: range, step: 1)
                .tint(tint)

            LumaNumberInput(value: $value, range: range, unit: unit)
        }
        .padding(12)
        .lumaNativeGlass(tint: tint.opacity(0.08), radius: LumaStageDesign.cornerRadius, fallbackOpacity: 0.26)
    }
}

private struct LumaNumberInput: View {
    var label: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack(spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .frame(width: 12, alignment: .leading)
            }

            TextField(
                "",
                value: Binding(
                    get: { value },
                    set: { value = min(max($0, range.lowerBound), range.upperBound) }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .font(.caption.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.trailing)
#if os(iOS)
            .keyboardType(.decimalPad)
#endif
            .textFieldStyle(.roundedBorder)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(LumaStageDesign.textSecondary)
                .frame(width: 24, alignment: .leading)
        }
    }
}

private struct WashSwatch: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }

    var color: Color {
        let rgb = RGBComponents(hex: hex) ?? .white
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

private extension Color {
    var hexRGB: String? {
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
#else
        return nil
#endif
    }
}

#Preview {
    IPadMicroControlPanel()
        .environment(AppModel())
}
