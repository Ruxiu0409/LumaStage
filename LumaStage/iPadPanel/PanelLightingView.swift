#if os(iOS)
import Foundation
import SwiftUI

/// **Lighting tab** — the control desk. The overview is a compact grid of fixture cards (one per
/// addressable light, Light 1…N), each showing its color, type, and intensity at a glance; tapping a
/// card pushes a focused editor for that one fixture. This replaced a single long `List` that stacked
/// every fixture's full controls — unusably tall once a look has many fixtures.
struct PanelLightingView: View {
    let model: LumaPanelModel

    var body: some View {
        NavigationStack {
            Group {
                if let look = model.lighting, let cue = model.selectedCue {
                    LightingOverview(model: model, look: look, cue: cue)
                } else {
                    unavailable
                }
            }
            .navigationTitle("燈光")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { PanelConnectionToolbar(model: model) }
            .navigationDestination(for: String.self) { fixtureId in
                FixtureDetailView(model: model, fixtureId: fixtureId)
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            model.isConnected ? "等待燈光效果…" : "未連線",
            systemImage: model.isConnected ? "lightbulb" : "wifi.slash",
            description: Text(model.isConnected
                ? "Vision Pro 尚未傳送燈光效果。"
                : "在同一個 Wi-Fi 下的 Apple Vision Pro 上開啟 LumaStage 以建立連線。")
        )
    }
}

// MARK: - Overview (cue picker + fixture grid)

/// The short, scannable top level: pick the live cue, then see every fixture as a compact card.
private struct LightingOverview: View {
    let model: LumaPanelModel
    let look: LightingLook
    let cue: LightingCue

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cueControl

                if !look.mood.isEmpty {
                    Text(look.mood)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(cue.fixtureGroups.enumerated()), id: \.element.id) { index, fixture in
                        NavigationLink(value: fixture.id) {
                            FixtureCard(number: index + 1, fixture: fixture)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(role: .destructive) {
                    model.send(.resetSelectedCue)
                } label: {
                    Label("將場景重置為生成的燈光", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.isConnected)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    /// The cue stack: scrollable chips (tap to select, long-press to delete), a "+" to append, and a GO
    /// button to advance the show — the iPad mirror of the in-headset cue strip and a console's cue list.
    @ViewBuilder private var cueControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("場景串").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(selectedCueNumber)/\(look.cues.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(look.cues.enumerated()), id: \.element.id) { index, c in
                            Button {
                                model.send(.selectCue(id: c.id))
                            } label: {
                                Text("\(index + 1) · \(c.localizedDisplayName)")
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(c.id == look.selectedCueId ? .orange : nil)
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.send(.removeCue(id: c.id))
                                } label: {
                                    Label("刪除場景", systemImage: "trash")
                                }
                                .disabled(look.cues.count <= 1)
                            }
                        }

                        Button {
                            model.send(.appendCue)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("新增場景")
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    model.send(.goToNextCue)
                } label: {
                    Label("GO", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.green)
                .disabled(look.cues.count <= 1)
                .accessibilityLabel("GO，前往下一個場景")
            }
        }
        .disabled(!model.isConnected)
    }

    private var selectedCueNumber: Int {
        (look.cues.firstIndex(where: { $0.id == look.selectedCueId }) ?? 0) + 1
    }
}

/// One compact tile in the overview grid: a color chip, the light number, its fixture type, and an
/// intensity bar — the state an operator scans for before drilling in.
private struct FixtureCard: View {
    let number: Int
    let fixture: FixtureGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color(hex: fixture.color.value) ?? .gray)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                Spacer()
                Text("\(Int((fixture.intensity * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(StageLightLabel.displayName(number: number))
                    .font(.headline)
                Text(LightingFixtureCatalog.item(for: fixture.renderModel)?.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: fixture.intensity.clamped01)
                .tint(Color(hex: fixture.color.value) ?? .accentColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if !fixture.enabled {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Detail (one fixture's full controls)

/// A focused editor for a single light, pushed from its card. Looks the fixture up live by id from the
/// selected cue, so edits (and cue switches) keep it current. Intensity / color / beam are editable;
/// the rest of the fixture record is shown read-only.
private struct FixtureDetailView: View {
    let model: LumaPanelModel
    let fixtureId: String

    var body: some View {
        Group {
            if let fixture = currentFixture {
                Form {
                    intensitySection(fixture)
                    colorSection(fixture)
                    beamSection(fixture)
                    technicalSection(fixture)
                }
            } else {
                ContentUnavailableView("找不到燈具", systemImage: "lightbulb.slash")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentFixture: FixtureGroup? {
        model.selectedCue?.fixtureGroups.first { $0.id == fixtureId }
    }

    private var title: String {
        guard let index = model.selectedCue?.fixtureGroups.firstIndex(where: { $0.id == fixtureId }) else {
            return "燈具"
        }
        return StageLightLabel.displayName(number: index + 1)
    }

    private func intensitySection(_ fixture: FixtureGroup) -> some View {
        Section("強度") {
            HStack {
                Slider(value: intensityBinding(fixture), in: 0...1)
                    .disabled(!model.isConnected)
                Text("\(Int((fixture.intensity * 100).rounded()))%")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    private func colorSection(_ fixture: FixtureGroup) -> some View {
        Section("顏色") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lightingPalette, id: \.hex) { swatch in
                        Button {
                            model.send(.setFixtureColor(fixtureId: fixture.id, hex: swatch.hex))
                        } label: {
                            Circle()
                                .fill(Color(hex: swatch.hex) ?? .gray)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle().strokeBorder(
                                        isSelected(swatch.hex, fixture.color.value) ? Color.primary : Color.black.opacity(0.15),
                                        lineWidth: isSelected(swatch.hex, fixture.color.value) ? 3 : 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .disabled(!model.isConnected)
        }
    }

    private func beamSection(_ fixture: FixtureGroup) -> some View {
        Section("光束角度") {
            HStack {
                Slider(value: beamBinding(fixture), in: 5...120)
                    .disabled(!model.isConnected)
                Text("\(Int(fixture.effectiveFineControl.beamAngleDegrees.rounded()))°")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    private func technicalSection(_ fixture: FixtureGroup) -> some View {
        let fineControl = fixture.effectiveFineControl
        return Section("技術參數") {
            detailRow("型號", LightingFixtureCatalog.item(for: fixture.renderModel)?.displayName ?? "—")
            detailRow("目標", fixture.target?.displayName ?? "—")
            detailRow("位置", String(format: "X %.1f · Y %.1f · Z %.1f", fineControl.position.x, fineControl.position.y, fineControl.position.z))
            detailRow("朝向", String(format: "Pan %.0f° · Tilt %.0f°", fineControl.panDegrees, fineControl.tiltDegrees))
            detailRow("DMX", dmxSummary(fixture.dmx))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
        }
    }

    private func dmxSummary(_ dmx: DMXPatch?) -> String {
        guard let dmx else { return "未指定" }
        return "U\(dmx.universe) · A\(dmx.address) · 通道 \(dmx.channels.dimmer)/\(dmx.channels.red)/\(dmx.channels.green)/\(dmx.channels.blue)"
    }

    private func isSelected(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    private func intensityBinding(_ fixture: FixtureGroup) -> Binding<Double> {
        Binding(
            get: { fixture.intensity },
            set: { model.send(.setFixtureIntensity(fixtureId: fixture.id, intensity: $0)) }
        )
    }

    /// Sends the whole `FixtureFineControl` with the new beam angle — the renderer drives the spotlight
    /// cone from `beamAngleDegrees`, so the AVP relights live. Reads `effectiveFineControl` so a fixture
    /// with no explicit fine control starts from its role/zone default.
    private func beamBinding(_ fixture: FixtureGroup) -> Binding<Double> {
        Binding(
            get: { fixture.effectiveFineControl.beamAngleDegrees },
            set: { newValue in
                var control = fixture.effectiveFineControl
                control.beamAngleDegrees = newValue
                model.send(.setFixtureFineControl(fixtureId: fixture.id, control: control))
            }
        )
    }
}

// MARK: - Shared

/// Preset color swatches — a control-desk palette, so no hex typing or `Color`→hex conversion.
private let lightingPalette: [(name: String, hex: String)] = [
    ("White", "#FFFFFF"),
    ("Amber", "#FF8A2C"),
    ("Gold", "#FFC83D"),
    ("Green", "#33E07A"),
    ("Cyan", "#27D7E0"),
    ("Blue", "#3FB6FF"),
    ("Deep Blue", "#1E54FF"),
    ("Purple", "#A24BFF"),
    ("Magenta", "#FF2D9E"),
    ("Red", "#FF3B3B")
]

private extension Double {
    /// `ProgressView` clamps internally, but keep the value in range so a stray out-of-bounds intensity
    /// never trips a runtime assert.
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}

private extension Color {
    /// Builds a SwiftUI `Color` from a `#RRGGBB` string for the swatch fills.
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview {
    PanelLightingView(model: .mockPreview())
}
#endif
