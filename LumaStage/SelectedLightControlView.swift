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
        VStack(alignment: .leading, spacing: 18) {
            header(number: number)
            onOffRow(number: number)
            dimmerRow(number: number)
            colorRow(number: number)
            followCueButton(number: number)
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
            .accessibilityLabel("關閉單燈控制")
        }
    }

    /// The manual blackout / restore for one fixture. Uses a filled-vs-slash SF Symbol so the on/off
    /// state isn't conveyed by colour alone.
    private func onOffRow(number: Int) -> some View {
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
        .accessibilityLabel(isOff ? "開啟第 \(number) 盞燈" : "關閉第 \(number) 盞燈")
        .accessibilityAddTraits(isOff ? [] : [.isSelected])
    }

    /// The dimmer. A continuous `Slider` is the primary control (fine 0–100% trim); the five fade-bumps
    /// stay below as quick console shortcuts. The preset nearest the light's current resolved intensity is
    /// highlighted (a checkmark + bold, not colour alone) so the user sees where the level currently sits.
    private func dimmerRow(number: Int) -> some View {
        let resolved = appModel.selectedLightResolved
        // When the light is off its effective intensity is 0, so the "關" bump reads as current — that
        // matches what the user sees on stage.
        let currentIntensity = resolved?.intensity ?? 0
        let percentText = "\(Int((currentIntensity * 100).rounded()))%"
        let nearest = Self.nearestPresetIndex(to: currentIntensity)

        return VStack(alignment: .leading, spacing: 8) {
            LumaSectionHeader(title: "亮度", systemImage: "sun.max")
            // Primary continuous dimmer with the live percentage beside it. The binding reads/writes the
            // same `setManualIntensity` override the preset shortcuts use, so slider + bumps stay coherent.
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { appModel.selectedLightResolved?.intensity ?? 0 },
                        set: { newValue in appModel.setManualIntensity(light: number, newValue) }
                    ),
                    in: 0...1
                )
                .tint(LumaStageDesign.coolBlue)
                .accessibilityLabel("亮度")
                .accessibilityValue(Text(percentText))
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
                    dimmerButton(number: number, label: preset.label, value: preset.value, isCurrent: index == nearest)
                }
            }
        }
    }

    private func dimmerButton(number: Int, label: String, value: Double, isCurrent: Bool) -> some View {
        Button {
            appModel.setManualIntensity(light: number, value)
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
        .accessibilityLabel("亮度 \(label)")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// The colour swatches. The active manual colour is ringed + checkmarked (non-colour marks so the
    /// selection reads under low colour vision); `nil` override = following the cue, so no swatch is
    /// marked unless the override's hex matches a palette entry.
    private func colorRow(number: Int) -> some View {
        let activeHex = appModel.selectedLightOverride?.colorHex.map { FixtureColor.normalizedHex($0) ?? $0 }

        return VStack(alignment: .leading, spacing: 8) {
            LumaSectionHeader(title: "顏色", systemImage: "paintpalette")
            // Two rows of five — the 360pt card is too narrow for ten swatches in a line.
            VStack(spacing: 8) {
                ForEach(Array(Self.colorSwatches.chunked(into: 5).enumerated()), id: \.offset) { _, group in
                    HStack(spacing: 8) {
                        ForEach(group, id: \.hex) { swatch in
                            colorSwatch(number: number, swatch: swatch, activeHex: activeHex)
                        }
                    }
                }
            }
        }
    }

    private func colorSwatch(
        number: Int,
        swatch: (name: String, chinese: String, hex: String),
        activeHex: String?
    ) -> some View {
        let rgb = RGBComponents(hex: swatch.hex) ?? .white
        let isSelected = activeHex == (FixtureColor.normalizedHex(swatch.hex) ?? swatch.hex)

        return Button {
            appModel.setManualColor(light: number, hex: swatch.hex)
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
        .accessibilityLabel(swatch.chinese)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Drops the manual override so the light follows the AI cue again.
    private func followCueButton(number: Int) -> some View {
        Button("跟隨場景", systemImage: "arrow.uturn.backward") {
            appModel.clearManualOverride(light: number)
        }
        .font(.callout.weight(.semibold))
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .lumaGazeTarget()
        // Dimmed when there's nothing to clear, so the affordance reflects whether an override exists.
        .disabled(appModel.selectedLightOverride == nil)
        .accessibilityLabel("第 \(number) 盞燈跟隨場景")
        .accessibilityHint("清除此燈的手動調整，回到 AI 生成的燈光")
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
