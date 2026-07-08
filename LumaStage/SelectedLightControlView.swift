import SwiftUI

#if os(visionOS)
/// The floating per-light control card — the "channel control / programmer" surfaced in the headset.
/// The user looks at a fixture and pinches it in `ImmersiveView` (which selects it and shows this card
/// as a RealityView attachment); the card then drives the deterministic `LightOverride` layer that sits
/// ON TOP of the AI cue: open/close one light, dim it to a console fade-bump preset, or recolour it.
/// All edits route through `AppModel` (never the look/cue directly) and persist until "跟隨場景" clears
/// them. Hidden whenever no light is selected — the renderer also disables the attachment, but rendering
/// `EmptyView()` keeps the card from claiming layout / hit-testing while detached.
struct SelectedLightControlView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The dimmer fade-bumps offered as buttons (a continuous slider would lag the cue's ~2.5s relight
    /// fade, so discrete presets read as console level-bumps). `nil` value → the full-blackout "關" bump.
    private static let intensityPresets: [(label: String, value: Double)] = [
        ("關", 0.0), ("25%", 0.25), ("50%", 0.5), ("75%", 0.75), ("全亮", 1.0)
    ]

    /// The colour palette tapped onto the selected light. English names mirror the console / gel-frame
    /// vocabulary (`#RRGGBB`, matching `setManualColor`'s contract); the Chinese label is the gaze hint.
    private static let colorSwatches: [(name: String, chinese: String, hex: String)] = [
        ("White", "白", "#FFFFFF"),
        ("Amber", "琥珀", "#FF8A2C"),
        ("Gold", "金", "#FFC83D"),
        ("Green", "綠", "#33E07A"),
        ("Cyan", "青", "#27D7E0"),
        ("Blue", "藍", "#3FB6FF"),
        ("Deep Blue", "深藍", "#1E54FF"),
        ("Purple", "紫", "#A24BFF"),
        ("Magenta", "洋紅", "#FF2D9E"),
        ("Red", "紅", "#FF3B3B")
    ]

    var body: some View {
        // Eagerly read the selection so `body` re-evaluates when the renderer's pinch changes it — the
        // card's existence and every row below resolve off this number. Guard it onto the live rig so a
        // stale selection (e.g. after the cue's fixture count shrinks) collapses the card instead of
        // indexing a missing fixture; the renderer hides the attachment in the same case.
        if let number = appModel.selectedLightNumber, number >= 1, number <= appModel.lightCount {
            card(number: number)
        } else {
            EmptyView()
        }
    }

    private func card(number: Int) -> some View {
        // SPEC 20 WI-9: on the 編程 page the card edits the RECORDED cue (layer 1) — colour/intensity via
        // `CuePatch` (`setFixtureColor`/`setFixtureIntensity`), angle via rig-identity `rotateFixture`. On the
        // 播放 page the edit controls are read-only (`editable == false`); tap-to-inspect stays.
        let editable = WorkflowPhasePolicy.allowsCueEditing(in: appModel.workflowPhase)
        return VStack(alignment: .leading, spacing: 18) {
            header(number: number)
            onOffRow(number: number, editable: editable)
            dimmerRow(number: number, editable: editable)
            colorRow(number: number, editable: editable)
            angleRow(number: number, editable: editable)
            followCueButton(number: number, editable: editable)
            if !editable {
                Text("播放中僅供檢視，切換到「調控」階段即可編輯。")
                    .font(.caption2)
                    .foregroundStyle(LumaStageDesign.textSecondary)
            }
        }
        .padding(24)
        // A fixed width keeps this attachment's content size definite (the rows use `Spacer()` /
        // `maxWidth: .infinity` internally); height stays content-driven.
        .frame(width: 360, alignment: .leading)
        .lumaFloatingPanel()
    }

    /// "第 N 盞燈 · <fixture name>" plus the close (X) button that clears the selection.
    private func header(number: Int) -> some View {
        // The cue fixture's authored name (e.g. "前光", "背景洗") if it exists — a friendlier handle than
        // the bare number when the rig mixes roles.
        let fixtureName = appModel.selectedCue?.fixtureGroups[safe: number - 1]?.name

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(number) 盞燈")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(LumaStageDesign.textPrimary)
                if let fixtureName, !fixtureName.isEmpty {
                    Text(fixtureName)
                        .font(.caption)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button("關閉控制", systemImage: "xmark") {
                appModel.selectLight(number: nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
        }
    }

    /// The manual blackout / restore for one fixture. Uses a filled-vs-slash SF Symbol so the on/off
    /// state isn't conveyed by colour alone. This is a transient overlay (layer 2); disabled while read-only.
    private func onOffRow(number: Int, editable: Bool) -> some View {
        let isOff = appModel.selectedLightResolved?.isOff ?? false
        return Button {
            appModel.toggleManualOff(light: number)
        } label: {
            Label(
                isOff ? "開啟" : "關閉",
                systemImage: isOff ? "lightbulb.slash.fill" : "lightbulb.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .lumaGazeTarget()
        .tint(isOff ? LumaStageDesign.warmAmber : LumaStageDesign.softGreen)
        .disabled(!editable)
    }

    /// The dimmer. A continuous `Slider` is the primary control (fine 0–100% trim); the five fade-bumps
    /// stay below as quick console shortcuts. The preset nearest the light's current resolved intensity is
    /// highlighted (a checkmark + bold, not colour alone) so the user sees where the level currently sits.
    private func dimmerRow(number: Int, editable: Bool) -> some View {
        // On the 編程 page the card reflects (and writes) the SELECTED cue's recorded intensity, not the
        // transient override — so switching cues shows each cue's authored value.
        let recorded = recordedFixture(number: number)
        let currentIntensity = recorded?.intensity ?? 0
        let fixtureId = appModel.selectedCue?.fixtureId(forLightNumber: number)
        let percentText = "\(Int((currentIntensity * 100).rounded()))%"
        let nearest = Self.nearestPresetIndex(to: currentIntensity)

        return VStack(alignment: .leading, spacing: 8) {
            LumaSectionHeader(title: "亮度", systemImage: "sun.max")
            // Primary continuous dimmer with the live percentage beside it. The binding reads/writes the
            // recorded cue intensity (`setFixtureIntensity` → CuePatch, per-cue, persisted).
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { recordedFixture(number: number)?.intensity ?? 0 },
                        set: { newValue in
                            guard editable, let fixtureId else { return }
                            appModel.setFixtureIntensity(id: fixtureId, value: newValue)
                        }
                    ),
                    in: 0...1
                )
                .tint(LumaStageDesign.coolBlue)
                Text(percentText)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .frame(minWidth: 48, alignment: .trailing)
            }
            // Keep the slider row a comfortable look-and-pinch gaze target.
            .frame(minHeight: LumaStageDesign.minGazeTarget)
            // Quick fade-bump shortcuts kept alongside the slider.
            HStack(spacing: 8) {
                ForEach(Array(Self.intensityPresets.enumerated()), id: \.offset) { index, preset in
                    dimmerButton(number: number, fixtureId: fixtureId, label: preset.label, value: preset.value, isCurrent: index == nearest, editable: editable)
                }
            }
        }
        .disabled(!editable)
    }

    private func dimmerButton(number: Int, fixtureId: String?, label: String, value: Double, isCurrent: Bool, editable: Bool) -> some View {
        Button {
            guard editable, let fixtureId else { return }
            appModel.setFixtureIntensity(id: fixtureId, value: value)
        } label: {
            HStack(spacing: 4) {
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(label)
                    .font(.callout.weight(isCurrent ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        // Height-only gaze constraint: the row's `maxWidth: .infinity` labels already share the width
        // evenly, so pinning min*width* too (as `lumaGazeTarget`'s 48 did) would push 5×60 past the card.
        .frame(minHeight: LumaStageDesign.minGazeTarget)
        .tint(isCurrent ? LumaStageDesign.coolBlue : nil)
    }

    /// The colour swatches. The active manual colour is ringed + checkmarked (non-colour marks so the
    /// selection reads under low colour vision); `nil` override = following the cue, so no swatch is
    /// marked unless the override's hex matches a palette entry.
    private func colorRow(number: Int, editable: Bool) -> some View {
        // Reflect the SELECTED cue's recorded colour (layer 1), so the ring/checkmark tracks the authored
        // value of the cue currently being programmed.
        let recordedHex = recordedFixture(number: number)?.color.value
        let activeHex = recordedHex.map { FixtureColor.normalizedHex($0) ?? $0 }
        let fixtureId = appModel.selectedCue?.fixtureId(forLightNumber: number)

        return VStack(alignment: .leading, spacing: 8) {
            LumaSectionHeader(title: "顏色", systemImage: "paintpalette")
            // Two rows of five — the 360pt card is too narrow for ten swatches in a line.
            VStack(spacing: 8) {
                ForEach(Array(Self.colorSwatches.chunked(into: 5).enumerated()), id: \.offset) { _, group in
                    HStack(spacing: 8) {
                        ForEach(group, id: \.hex) { swatch in
                            colorSwatch(number: number, fixtureId: fixtureId, swatch: swatch, activeHex: activeHex, editable: editable)
                        }
                    }
                }
            }
        }
        .disabled(!editable)
    }

    private func colorSwatch(
        number: Int,
        fixtureId: String?,
        swatch: (name: String, chinese: String, hex: String),
        activeHex: String?,
        editable: Bool
    ) -> some View {
        let rgb = RGBComponents(hex: swatch.hex) ?? .white
        let isSelected = activeHex == (FixtureColor.normalizedHex(swatch.hex) ?? swatch.hex)

        return Button {
            guard editable, let fixtureId else { return }
            appModel.setFixtureColor(id: fixtureId, hexColor: swatch.hex)
        } label: {
            Circle()
                .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                .frame(width: 40, height: 40)
                .overlay {
                    // A hairline keeps near-white swatches legible against the glass; the selection ring
                    // + checkmark are the non-colour selection cue.
                    Circle().strokeBorder(LumaStageDesign.hairline, lineWidth: 1)
                    if isSelected {
                        Circle()
                            .strokeBorder(LumaStageDesign.textPrimary, lineWidth: 3)
                            .padding(-3)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.black))
                            // Contrast the tick against the swatch's own brightness.
                            .foregroundStyle(rgb.red + rgb.green + rgb.blue > 1.5 ? .black : .white)
                    }
                }
                // Expand the tappable label to fill the grid cell at the 60pt gaze minimum — a `.plain`
                // button's hit area otherwise collapses to the 40pt circle, too small to look-and-pinch.
                .frame(maxWidth: .infinity, minHeight: LumaStageDesign.minGazeTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// SPEC 20 WI-9 — the aim (angle) row. Pan/tilt step buttons (±5° fine, ±15° coarse) route through
    /// `rotateFixture` (rig identity: the offset applies to this fixture in EVERY cue — hence the hint).
    /// Shows the current `aimOffset`. Read-only outside the 編程 page.
    private func angleRow(number: Int, editable: Bool) -> some View {
        let fixtureId = appModel.selectedCue?.fixtureId(forLightNumber: number)
        let aim = recordedFixture(number: number)?.aimOffset ?? .zero

        return VStack(alignment: .leading, spacing: 8) {
            LumaSectionHeader(title: "角度", systemImage: "dot.scope")
            // Pan (horizontal): −left / +right.
            HStack(spacing: 8) {
                angleStep(fixtureId: fixtureId, label: "向左", systemImage: "arrow.left", pan: -15, editable: editable)
                angleStep(fixtureId: fixtureId, label: "微左", systemImage: "arrow.left", pan: -5, editable: editable)
                angleStep(fixtureId: fixtureId, label: "微右", systemImage: "arrow.right", pan: 5, editable: editable)
                angleStep(fixtureId: fixtureId, label: "向右", systemImage: "arrow.right", pan: 15, editable: editable)
            }
            // Tilt (vertical): +up / −down.
            HStack(spacing: 8) {
                angleStep(fixtureId: fixtureId, label: "上仰", systemImage: "arrow.up", tilt: 15, editable: editable)
                angleStep(fixtureId: fixtureId, label: "微上", systemImage: "arrow.up", tilt: 5, editable: editable)
                angleStep(fixtureId: fixtureId, label: "微下", systemImage: "arrow.down", tilt: -5, editable: editable)
                angleStep(fixtureId: fixtureId, label: "下俯", systemImage: "arrow.down", tilt: -15, editable: editable)
            }
            Text("目前朝向：水平 \(Self.signed(aim.panDegrees))°、俯仰 \(Self.signed(aim.tiltDegrees))°")
                .font(.caption)
                .foregroundStyle(LumaStageDesign.textSecondary)
                .monospacedDigit()
            Text("角度會套用到所有場景（不分場景）。")
                .font(.caption2)
                .foregroundStyle(LumaStageDesign.textSecondary)
        }
        .disabled(!editable)
    }

    private func angleStep(fixtureId: String?, label: String, systemImage: String, pan: Double = 0, tilt: Double = 0, editable: Bool) -> some View {
        Button {
            guard editable, let fixtureId else { return }
            appModel.rotateFixture(id: fixtureId, panDelta: pan, tiltDelta: tilt)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.caption)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        // Height-only gaze constraint (mirrors dimmerButton) so four buttons still fit the 360pt card.
        .frame(minHeight: LumaStageDesign.minGazeTarget)
        .accessibilityLabel("\(label) \(Int(abs(pan != 0 ? pan : tilt)))度")
    }

    /// The selected cue's recorded fixture for this 1-based light number (nil one frame after the rig shrinks).
    private func recordedFixture(number: Int) -> FixtureGroup? {
        appModel.selectedCue?.fixtureGroups[safe: number - 1]
    }

    /// A signed integer string ("+15" / "0" / "−10") for the aim readout, using a real minus sign.
    private static func signed(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 { return "+\(rounded)" }
        if rounded < 0 { return "−\(abs(rounded))" }
        return "0"
    }

    /// Drops the manual override so the light follows the AI cue again.
    private func followCueButton(number: Int, editable: Bool) -> some View {
        Button("跟隨場景", systemImage: "arrow.uturn.backward") {
            appModel.clearManualOverride(light: number)
        }
        .font(.callout.weight(.semibold))
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .lumaGazeTarget()
        // Dimmed when there's nothing to clear, so the affordance reflects whether an override exists.
        .disabled(!editable || appModel.selectedLightOverride == nil)
    }

    /// The index of the preset whose value is closest to `intensity` — drives the highlighted fade-bump.
    private static func nearestPresetIndex(to intensity: Double) -> Int {
        intensityPresets.enumerated().min(by: { lhs, rhs in
            abs(lhs.element.value - intensity) < abs(rhs.element.value - intensity)
        })?.offset ?? 0
    }
}

// MARK: - Local helpers

private extension Array {
    /// Safe subscript so a stale light number (one frame after the rig shrinks) returns nil instead of
    /// trapping on an out-of-bounds fixture lookup.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    /// Splits the swatch palette into fixed-width rows for the two-row colour grid.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}

#Preview {
    SelectedLightControlView()
        .environment(AppModel())
}
#endif
