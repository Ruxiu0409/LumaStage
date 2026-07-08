import Foundation

enum LightingIntent: String, Codable, CaseIterable {
    case generateLook
    case localEdit
    case explainOnly
    case resetLook
}

enum AmbientPreset: String, Codable, CaseIterable {
    case standardNight
}

enum FixtureRole: String, Codable, CaseIterable {
    case wash
    case spot
    case frontLight
    case backgroundWash

    /// Roles the visionOS renderer currently realizes as real spotlights. The other roles
    /// (`wash`/`spot`) validate fine but are NOT drawn on stage, so a look made only of them changes
    /// nothing on screen — the relight debug panel flags this via `RelightDebugSnapshot`.
    var isRenderedAsSpotlight: Bool {
        self == .frontLight || self == .backgroundWash
    }

    /// Roles the renderer realizes as real spotlights (and can therefore project a gobo through). The
    /// other roles aren't rendered, so a gobo on them would be a silent no-op — `LightingLookDraft`
    /// clears gobos on non-rendering roles so persisted state never claims a projection that won't appear.
    var rendersProjectedGobo: Bool {
        isRenderedAsSpotlight
    }

    /// User-facing 繁中 name for a role, shown in command feedback (e.g. "已將目前場景的前光改為紅色").
    var displayName: String {
        switch self {
        case .wash: return "泛光"
        case .spot: return "聚光"
        case .frontLight: return "前光"
        case .backgroundWash: return "背景光"
        }
    }
}

enum StageZone: String, Codable, CaseIterable {
    case stageFront
    case stageBack
    case stageLeft
    case stageRight
    case fullStage
}

/// Optional projected light pattern (digital gobo) cast through a fixture's beam — the software
/// equivalent of a metal gobo in a real moving head. A `nil` gobo means a plain, unbroken beam.
/// Data-only on visionOS 26: validated and persisted, but not projected (rendering it needs the
/// visionOS 27 `SpotLightComponent.ProjectiveTexture` API).
enum GoboPattern: String, Codable, CaseIterable {
    case breakup
    case stripes
    case stars
    case grid

    var displayName: String {
        switch self {
        case .breakup: return "Foliage Breakup"
        case .stripes: return "Slats"
        case .stars: return "Starfield"
        case .grid: return "Window"
        }
    }
}

enum ColorMode: String, Codable, CaseIterable {
    case rgb
}

struct AmbientState: Codable, Equatable {
    var preset: AmbientPreset
    var level: Double
    var colorTemperature: Int
}

struct CueTransition: Codable, Equatable {
    var duration: Double
    var easing: String

    // Linear (not eased) over a deliberate 2.5s, so a look change reads as a real stage fade —
    // a steady cross-fade rather than a quick snap. `ImmersiveView.animation(for:)` maps `easing`.
    static let mvpDefault = CueTransition(duration: 2.5, easing: "linear")
}

struct FixtureColor: Codable, Equatable {
    var mode: ColorMode
    var value: String

    var normalized: FixtureColor {
        FixtureColor(mode: mode, value: Self.normalizedHex(value) ?? value)
    }

    var rgbComponents: RGBComponents {
        RGBComponents(hex: value) ?? .white
    }

    static func normalizedHex(_ value: String) -> String? {
        // Be lenient with on-device-model output, which sometimes appends stray punctuation to a colour
        // (observed in the wild: "#FFD1A3," — the model echoed the prompt's example *with* its comma) or
        // wraps the value in prose. Locate the first "#", read the run of hex digits that follows, and
        // accept it only if that run is exactly six (an #RRGGBB triple). Trailing non-hex characters are
        // ignored; genuinely malformed values (no "#", too few or too many digits) still fail so the
        // validators keep their teeth.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hashIndex = trimmed.firstIndex(of: "#") else {
            return nil
        }

        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        var hex = ""
        for scalar in trimmed[trimmed.index(after: hashIndex)...].unicodeScalars {
            guard allowed.contains(scalar) else {
                break   // stop at the first non-hex character (stray comma, space, prose, …)
            }
            hex.unicodeScalars.append(scalar)
            if hex.count > 6 {
                break   // longer than an #RRGGBB run — reject below rather than silently truncating
            }
        }

        guard hex.count == 6 else {
            return nil
        }

        return "#\(hex.uppercased())"
    }
}

struct RGBComponents: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = RGBComponents(red: 1, green: 1, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        guard let normalized = FixtureColor.normalizedHex(hex) else {
            return nil
        }

        let hexValue = String(normalized.dropFirst())
        guard let rawValue = Int(hexValue, radix: 16) else {
            return nil
        }

        red = Double((rawValue >> 16) & 0xFF) / 255.0
        green = Double((rawValue >> 8) & 0xFF) / 255.0
        blue = Double(rawValue & 0xFF) / 255.0
    }

    func dimmed(by intensity: Double) -> RGBComponents {
        RGBComponents(
            red: red * intensity,
            green: green * intensity,
            blue: blue * intensity
        )
    }
}

struct FixturePosition: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

struct FixtureFineControl: Codable, Equatable {
    var position: FixturePosition
    var panDegrees: Double
    var tiltDegrees: Double
    var rollDegrees: Double
    var beamAngleDegrees: Double

    static func `default`(role: FixtureRole, zone: StageZone) -> FixtureFineControl {
        FixtureFineControl(
            position: defaultPosition(role: role, zone: zone),
            panDegrees: 0,
            tiltDegrees: role == .frontLight ? -35 : -18,
            rollDegrees: 0,
            beamAngleDegrees: role == .spot ? 24 : 42
        )
    }

    private static func defaultPosition(role: FixtureRole, zone: StageZone) -> FixturePosition {
        switch role {
        case .frontLight:
            return FixturePosition(x: 0, y: 3, z: 1.1)
        case .backgroundWash:
            return FixturePosition(x: 0, y: 2.4, z: -1.35)
        case .wash:
            return FixturePosition(x: 0, y: 2.8, z: -0.8)
        case .spot:
            return FixturePosition(x: zone == .stageLeft ? -1.2 : 1.2, y: 3.1, z: -0.8)
        }
    }

    func validate() throws {
        guard position.isFinite else {
            throw ValidationError.invalidFineControlValue("position", .nan)
        }

        guard (-180...180).contains(panDegrees) else {
            throw ValidationError.invalidFineControlValue("pan", panDegrees)
        }

        guard (-90...90).contains(tiltDegrees) else {
            throw ValidationError.invalidFineControlValue("tilt", tiltDegrees)
        }

        guard (-180...180).contains(rollDegrees) else {
            throw ValidationError.invalidFineControlValue("roll", rollDegrees)
        }

        guard (5...120).contains(beamAngleDegrees) else {
            throw ValidationError.invalidFineControlValue("beamAngle", beamAngleDegrees)
        }
    }
}

/// A user-authored rotation OFFSET applied on top of a fixture's zone-derived resting aim — how the
/// "Light N turn right/left/up/down M degrees" command re-aims one fixture (pan left/right, tilt
/// up/down), persistently across every cue (rig identity). It is deliberately a NEW additive field
/// (see `FixtureGroup.aimOffset`) rather than a reuse of `FixtureFineControl.pan/tilt`: those default to
/// −35/−18 as dead data the renderer never reads, and the zone aim already points down at the stage, so
/// consuming them would tilt every existing look downward (the "tilt-doubling trap"). A zero offset
/// (`.zero`, the default) leaves the resting aim exactly at the zone-derived direction, so existing / AI
/// looks render identically. The renderer folds it in via `LightEffectSystem.aim(base:panDegrees:tiltDegrees:)`.
struct FixtureAimOffset: Codable, Equatable {
    /// + turns right / − turns left (data convention; the visual left/right is verified on device — see
    /// SPEC 13 Caveats — and if inverted, the sign is flipped in ONE place in the renderer, not here).
    var panDegrees: Double = 0
    /// + tilts up / − tilts down.
    var tiltDegrees: Double = 0

    static let zero = FixtureAimOffset(panDegrees: 0, tiltDegrees: 0)

    /// Same clamps `FixtureFineControl` uses for its pan/tilt: pan −180...180, tilt −90...90.
    func validate() throws {
        guard (-180...180).contains(panDegrees) else {
            throw ValidationError.invalidFineControlValue("aimPan", panDegrees)
        }
        guard (-90...90).contains(tiltDegrees) else {
            throw ValidationError.invalidFineControlValue("aimTilt", tiltDegrees)
        }
    }

    /// Adds a pan/tilt delta and clamps the result to the valid range, returning the new offset — so a
    /// stream of "turn right 60" commands accumulates but can never drive the aim out of range.
    func adding(panDelta: Double, tiltDelta: Double) -> FixtureAimOffset {
        FixtureAimOffset(
            panDegrees: min(max(panDegrees + panDelta, -180), 180),
            tiltDegrees: min(max(tiltDegrees + tiltDelta, -90), 90)
        )
    }
}

/// The area a fixture is aimed at — a controlled vocabulary of stage targets (the JSON `target`
/// field). Encodes as the snake_case string the JSON uses (e.g. `center_stage`).
enum FixtureTarget: String, Codable, CaseIterable {
    case centerStage = "center_stage"
    case upstage
    case downstage
    case stageLeft = "stage_left"
    case stageRight = "stage_right"
    case audience
    case fullStage = "full_stage"

    var displayName: String {
        switch self {
        case .centerStage: return "舞台中央"
        case .upstage: return "舞台後方"
        case .downstage: return "舞台前緣"
        case .stageLeft: return "舞台左側"
        case .stageRight: return "舞台右側"
        case .audience: return "觀眾席"
        case .fullStage: return "整個舞台"
        }
    }
}

/// A fixture's real-world DMX patch (the JSON `dmx` block): the universe + start address a physical
/// console uses, and which channel drives each control parameter. Output/integration only — the
/// virtual digital-twin renderer ignores it. Validated by `validate()`; reused over persistence and
/// the iPad sync via `Codable`.
struct DMXPatch: Codable, Equatable {
    var universe: Int
    var address: Int
    var channels: ChannelMap

    /// One DMX channel per control parameter (matching the JSON `channels` map).
    struct ChannelMap: Codable, Equatable {
        var dimmer: Int
        var red: Int
        var green: Int
        var blue: Int
    }

    func validate() throws {
        guard universe >= 1 else {
            throw ValidationError.invalidDMXValue("universe", universe)
        }
        guard (1...512).contains(address) else {
            throw ValidationError.invalidDMXValue("address", address)
        }
        for (name, channel) in [
            ("dimmer", channels.dimmer), ("red", channels.red),
            ("green", channels.green), ("blue", channels.blue)
        ] where !(1...512).contains(channel) {
            throw ValidationError.invalidDMXValue(name, channel)
        }
    }
}

struct FixtureGroup: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var role: FixtureRole
    var zone: StageZone
    var enabled: Bool
    var intensity: Double
    var color: FixtureColor
    var fineControl: FixtureFineControl? = nil
    var gobo: GoboPattern? = nil
    /// The physical fixture type the renderer instantiates as geometry. Optional + back-compat:
    /// looks saved before dynamic rigs (and the fixed 2-role MVP) decode it as nil and fall back to
    /// `renderModel`, which derives a sensible model from `role`/`zone`.
    var model: LightingFixtureVisualModel? = nil

    /// The area this fixture is aimed at — a human-authored target label (the JSON `target`), distinct
    /// from the numeric `aim` the renderer computes from `zone`. Optional metadata carried through
    /// persistence + the iPad sync; not yet used to drive the on-stage aim.
    var target: FixtureTarget? = nil

    /// Real-world DMX patch (the JSON `dmx` block) — how a physical console addresses this fixture.
    /// Output/integration only: the virtual twin ignores it; it's here so a look can later drive real
    /// fixtures (Art-Net / sACN) or export a patch sheet. Optional + back-compat (old looks decode nil).
    var dmx: DMXPatch? = nil

    /// An AI-authored dynamic movement/flash for this fixture (sweep/circle/strobe/chase). Optional +
    /// back-compat (old looks decode nil). When set, it OVERRIDES the per-type deterministic default in
    /// `LightEffectPlan.effects(for:)`; when nil, the renderer falls back to `LightEffect.suggested(...)`.
    var effect: LightEffect? = nil

    /// A user-authored manual stage position (model metres) that OVERRIDES the zone-derived placement.
    /// Set when the user drags this fixture on the tabletop editor's diorama. Optional + back-compat: old
    /// JSON without the key decodes nil (the synthesized decoder defaults optionals to nil), and nil means
    /// "follow the zone-derived placement" — only a non-nil value counts as a manual placement.
    /// Resolved through `RigPlacement.resolvedPlacement(fixture:slot:count:layout:)` by the renderer and
    /// the tabletop editor; the same `id` carries the same `manualPosition` across every cue (rig identity).
    var manualPosition: FixturePosition? = nil

    /// A user-authored rotation offset applied on top of the zone-derived resting aim (pan left/right,
    /// tilt up/down) — set by the "Light N turn right/left/up/down M degrees" command. Optional +
    /// back-compat: old JSON without the key decodes nil (the synthesized decoder defaults optionals to
    /// nil), and nil means "no offset" (zone aim unchanged). NOT `fineControl.pan/tilt` — that carries
    /// dead −35/−18 defaults the renderer never reads, so reusing it would tilt every existing look down
    /// (see `FixtureAimOffset`). The same `id` carries the same `aimOffset` across every cue (rig identity).
    var aimOffset: FixtureAimOffset? = nil

    var effectiveFineControl: FixtureFineControl {
        fineControl ?? .default(role: role, zone: zone)
    }

    /// The visual model the renderer should build for this fixture — the explicit `model` if set,
    /// otherwise derived from the role/zone so legacy 2-role looks still render real geometry.
    var renderModel: LightingFixtureVisualModel {
        model ?? LightingFixtureVisualModel.derived(role: role, zone: zone)
    }
}

extension FixtureGroup {
    /// 「複製此燈具」用的拷貝：換上新 `id`，其餘視覺/朝向狀態（color/intensity/model/role/zone/enabled/
    /// fineControl/gobo/dmx/target/effect/aimOffset）全數保留；若來源有明確 `manualPosition`，把該位置
    /// 沿 X/Z 位移 (dx,dz) 模型公尺，避免複製體與原件完全重疊。來源 `manualPosition == nil`（zone 推算）
    /// 則維持 nil——靠 zone slot 分散兩者。`name` 維持與來源相同（呼叫端可另行覆寫編號）。
    func duplicated(newId: String, nudgeX dx: Double, nudgeZ dz: Double) -> FixtureGroup {
        var copy = self
        copy.id = newId
        if let pos = manualPosition {
            copy.manualPosition = FixturePosition(x: pos.x + dx, y: pos.y, z: pos.z + dz)
        }
        return copy
    }
}

struct LightingCue: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var transition: CueTransition
    var fixtureGroups: [FixtureGroup]
    /// Follow/hold time in seconds — how long this cue holds before cue-list auto-playback advances to the
    /// next cue (SPEC 16). Additive & optional so old project JSON decodes to `nil` (synthesized Codable uses
    /// `decodeIfPresent` for Optionals); `nil` means "use `CuePlayback.defaultHoldSeconds`". Resolve it via
    /// `CuePlayback.holdDuration(for:)`, which floors/caps the value — never read this raw for scheduling.
    var holdDuration: Double? = nil

    var localizedDisplayName: String {
        switch name {
        case "Opening":
            return "開場"
        case "Highlight":
            return "重點"
        default:
            return name
        }
    }

    func requireFixture(role: FixtureRole) throws -> FixtureGroup {
        guard let fixture = fixtureGroups.first(where: { $0.role == role }) else {
            throw ValidationError.missingFixture(role.rawValue)
        }

        return fixture
    }

    /// SPEC 20 WI-9 — maps a 1-based on-stage light number (fixtures in `fixtureGroups` order, "Light 1…N")
    /// to that fixture's `id`, so the programming page can route a tapped light's cue edits to the right
    /// fixture. Out-of-range → nil.
    func fixtureId(forLightNumber number: Int) -> String? {
        guard number >= 1, number <= fixtureGroups.count else { return nil }
        return fixtureGroups[number - 1].id
    }
}

/// A read-only summary of how the current cue's fixtures map onto the immersive renderer — the data
/// behind the in-app relight debug panel. Pure logic so the panel view stays thin and this stays
/// smoke-tested. `isRendered` flags fixtures whose role the scene does NOT draw (`wash`/`spot`), so an
/// all-non-rendered look reads as "won't show on stage" at a glance.
struct RelightDebugSnapshot: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String { fixtureId }
        /// 1-based addressable light number in cue order — the SAME "Light N" the on-stage floating label,
        /// the voice/deterministic commands, and the iPad panel use, so a debug row can be cross-referenced.
        var number: Int
        var fixtureId: String
        var name: String
        var role: FixtureRole
        /// Effective colour after the manual override + group master resolve — what the spotlight actually shows.
        var hex: String
        /// Effective intensity% after the manual override + group master resolve.
        var intensityPercent: Int
        var beamDegrees: Int
        var gobo: GoboPattern?
        /// The dynamic effect this fixture runs under the current cue's energy (`.none` = steady) — mirrors
        /// what `ImmersiveView`'s LightEffectSystem animates, via the shared `LightEffectPlan`.
        var effectKind: LightEffectKind
        var isRendered: Bool
        /// Whether a manual per-light override is masking this fixture's cue value (so the panel can badge it
        /// as hand-controlled rather than AI-cue-driven — the row's `hex`/`intensityPercent` already resolve it).
        var isOverridden: Bool
        /// Whether the fixture is manually blacked out (intensity resolves to 0 from the override, not the cue).
        var isManuallyOff: Bool
    }

    var cueId: String
    var cueName: String
    /// Whether the cue reads as high-energy, so its rig runs movement/strobe/chase. Shared gate with the
    /// renderer (`LightEffectPlan`), so the in-app readout can't drift from what actually animates.
    var isHighEnergy: Bool
    var rows: [Row]

    /// How many fixtures will actually light the stage (rendered roles).
    var renderedCount: Int { rows.filter(\.isRendered).count }

    /// How many fixtures are running a dynamic effect under the current cue.
    var animatedCount: Int { rows.filter { $0.effectKind != .none }.count }

    /// Builds the debug readout for a cue, resolving each fixture through the SAME manual override +
    /// group-master layers the renderer uses (`ImmersiveView.apply` → `LightOverride.resolved`), so the
    /// panel shows the EFFECTIVE colour/intensity on stage — not the raw cue value. `overrides` and
    /// `groupMasters` are keyed by 1-based light number (cue order), matching `AppModel.lightOverrides`
    /// and `AppModel.groupMasterByLight()`; both default empty so the pure cue mapping stays ergonomic.
    static func make(
        from cue: LightingCue,
        overrides: [Int: LightOverride] = [:],
        groupMasters: [Int: Double] = [:]
    ) -> RelightDebugSnapshot {
        let effects = LightEffectPlan.effects(for: cue)
        return RelightDebugSnapshot(
            cueId: cue.id,
            cueName: cue.localizedDisplayName,
            isHighEnergy: LightEffectPlan.isHighEnergy(cue),
            rows: cue.fixtureGroups.enumerated().map { index, fixture in
                let number = index + 1
                let override = overrides[number] ?? LightOverride()
                let resolved = override.resolved(
                    cueColor: fixture.color.value,
                    cueIntensity: fixture.intensity,
                    groupMaster: groupMasters[number] ?? 1.0
                )
                return Row(
                    number: number,
                    fixtureId: fixture.id,
                    name: fixture.name,
                    role: fixture.role,
                    hex: resolved.color,
                    intensityPercent: Int((resolved.intensity * 100).rounded()),
                    beamDegrees: Int(fixture.effectiveFineControl.beamAngleDegrees.rounded()),
                    gobo: fixture.gobo,
                    effectKind: effects[index].kind,
                    // Every fixture in the dynamic rig is rendered as a real spotlight now.
                    isRendered: true,
                    isOverridden: override.isActive || (groupMasters[number].map { $0 != 1.0 } ?? false),
                    isManuallyOff: override.isOff
                )
            }
        )
    }
}

// MARK: - Deterministic single-light control

/// The displayed name for the Nth addressable light. Lights are numbered 1-based in the order they
/// appear in the cue's `fixtureGroups`, so "Light 3" is the third fixture — dynamic over any rig size.
enum StageLightLabel {
    static func displayName(number: Int) -> String { "Light \(number)" }
    /// 桌面代理／選取狀態用的標籤：可定址編號 + 燈具繁中型號名，例如 "3 · 搖頭光束燈"。
    /// 與 1:1 舞台的 `Light N` 同一編號（cue 順序 index+1）。型號名由呼叫端從 catalog 取後傳入。
    static func tabletopLabel(number: Int, modelName: String) -> String { "\(number) · \(modelName)" }
}

/// A per-light manual override layered ON TOP of the cue's group values — the deterministic control
/// layer (vs. the generative cue). Each field is optional: nil means "follow the cue". Overrides
/// persist across AI generations until explicitly cleared, so manual single-light tweaks stay on top
/// of new looks.
struct LightOverride: Equatable {
    var isOff: Bool = false
    var colorHex: String? = nil
    var intensity: Double? = nil

    /// Whether this override still changes anything (else it can be dropped so the light follows the cue).
    var isActive: Bool { isOff || colorHex != nil || intensity != nil }

    /// Final (color, intensity) for the light given the cue group's values it sits on top of.
    func resolved(cueColor: String, cueIntensity: Double) -> (color: String, intensity: Double) {
        let color = colorHex ?? cueColor
        if isOff { return (color, 0) }
        return (color, intensity ?? cueIntensity)
    }

    /// The override remaining after an authoritative cue-layer edit to the SAME light supersedes one
    /// component. An intensity edit drops the manual level (and any manual blackout) so the light follows
    /// the freshly-set cue level; a colour edit drops the manual colour. Returns nil when nothing manual
    /// remains, so the caller can clear the override entirely and let the light follow the cue. This is
    /// what lets an iPad/console per-fixture edit actually take effect instead of being masked by a stale
    /// override (an in-headset pinch/voice/card tweak) — WITHOUT changing `resolved`'s "override wins" rule.
    func superseded(clearing component: OverrideComponent) -> LightOverride? {
        var copy = self
        switch component {
        case .intensity:
            copy.intensity = nil
            copy.isOff = false
        case .color:
            copy.colorHex = nil
        }
        return copy.isActive ? copy : nil
    }
}

/// Which part of a manual `LightOverride` an authoritative cue-layer edit (iPad panel / direct fixture
/// edit) supersedes, so the new cue value renders instead of the masked override. See `LightOverride.superseded`.
enum OverrideComponent {
    case intensity
    case color
}

/// A deterministic single-light command parsed from a typed/spoken phrase. When `parse` returns a
/// command the app applies it directly (no AI generation) — instant and predictable, the Action
/// Phrase model. A `nil` result falls through to generative AI look design.
enum LightCommand: Equatable {
    case close(Int)
    case open(Int)
    case setColor(Int, hex: String)
    case setIntensity(Int, fraction: Double)
    /// Recolor every fixture of a named role in the SELECTED cue (e.g. "把 Front Light 改成紅色").
    /// A targeted edit — never a full-look regeneration — so naming a role keeps the rig intact.
    case setRoleColor(FixtureRole, hex: String)
    /// Rotate one fixture's aim by a pan/tilt delta ("Light N turn right/left/up/down M degrees"). One
    /// axis is always 0 (a direction word maps to exactly one axis). Persistent across cues (rig identity).
    case rotate(Int, panDeltaDegrees: Double, tiltDeltaDegrees: Double)
    case allOff
    case resetAll

    /// The light number a single-light command targets (nil for the global `allOff`/`resetAll`).
    var targetLightNumber: Int? {
        switch self {
        case .close(let number), .open(let number): return number
        case .setColor(let number, _), .setIntensity(let number, _): return number
        case .rotate(let number, _, _): return number
        case .setRoleColor, .allOff, .resetAll: return nil
        }
    }

    /// Common color names → hex, so "set light 1 to blue" / "把前光改成紅色" resolves without a hex.
    /// English keys match spoken/typed English; CJK keys match Chinese input. The CJK scan in
    /// `colorHex(in:)` does a direct `text.contains(key)` since CJK words don't tokenize as ASCII words.
    static let colorNames: [String: String] = [
        "red": "#FF0000", "green": "#00FF00", "blue": "#0000FF", "yellow": "#FFFF00",
        "orange": "#FF7A00", "purple": "#8A2BE2", "violet": "#8A2BE2", "magenta": "#FF00FF",
        "pink": "#FF6FB5", "cyan": "#00FFFF", "teal": "#1FBFB8", "white": "#FFFFFF",
        "amber": "#FFBF00", "gold": "#FFD700", "lavender": "#B79CED", "warm": "#FFE4C2",
        // CJK colour words (full word before its single-char form, so "紅色" wins over "紅").
        "紅色": "#FF0000", "紅": "#FF0000",
        "藍色": "#0000FF", "藍": "#0000FF",
        "綠色": "#00FF00", "綠": "#00FF00",
        "白色": "#FFFFFF", "白": "#FFFFFF",
        "黃色": "#FFFF00", "黃": "#FFFF00",
        "紫色": "#800080", "紫": "#800080",
        "橙色": "#FFA500", "橙": "#FFA500", "橘": "#FFA500",
        "粉紅": "#FF69B4", "粉色": "#FF69B4",
        "青色": "#00FFFF", "青": "#00FFFF"
    ]

    /// Role-name needles → `FixtureRole`, so "把 Front Light 改成紅色" / "背景光改藍色" targets a role.
    /// Longer/more-specific needles are listed first so `setColor`-style phrases match the right role.
    static let roleNames: [(needle: String, role: FixtureRole)] = [
        ("front light", .frontLight), ("frontlight", .frontLight),
        ("前光", .frontLight), ("主光", .frontLight), ("面光", .frontLight),
        ("background wash", .backgroundWash), ("back wash", .backgroundWash), ("background", .backgroundWash),
        ("背景泛光", .backgroundWash), ("背景光", .backgroundWash), ("背光", .backgroundWash),
        ("wash", .wash), ("泛光", .wash),
        ("spot", .spot), ("聚光", .spot), ("追光", .spot)
    ]

    static func parse(_ raw: String) -> LightCommand? {
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        // Global commands (no specific light number needed).
        if text.contains("blackout") || text.contains("all off") || text.contains("lights off")
            || text.contains("turn off all") || text.contains("kill all") {
            return .allOff
        }
        if text.contains("all on") || text.contains("lights on") || text.contains("turn on all")
            || text.contains("reset lights") || text.contains("reset all") || text.contains("clear lights") {
            return .resetAll
        }

        // Role-name + colour ("把 Front Light 改成紅色", "背景光改藍色") recolors only that role's fixtures
        // in the selected cue — a targeted edit, NOT a full-look regeneration. Gated on a colour actually
        // being present so a role-only phrase ("把前光調暗") doesn't false-match here.
        if let role = roleNeedleMatch(in: text), let hex = colorHex(in: text, words: words) {
            return .setRoleColor(role, hex: hex)
        }

        // Everything else targets one numbered light. The rig size is dynamic, so any number ≥ 1
        // parses here; `AppModel.applyLightCommand` validates it against the current fixture count.
        guard let number = lightNumber(in: text), number >= 1 else {
            return nil
        }

        if let hex = colorHex(in: text, words: words) {
            return .setColor(number, hex: hex)
        }
        if let fraction = intensityFraction(in: text) {
            return .setIntensity(number, fraction: fraction)
        }
        // Rotation ("turn right 60 degrees", "tilt light 3 up 20") is checked here — AFTER intensity so a
        // "% / dim" phrase still wins, and BEFORE close/open. It requires BOTH a rotation verb AND a
        // direction word, so "turn off"/"turn on" (no direction word) fall through to close/open below.
        if let rotation = rotationCommand(number: number, in: text, words: words) {
            return rotation
        }
        if text.contains("turn off") || text.contains("switch off") || text.contains("shut off")
            || words.contains("close") || words.contains("off") || words.contains("kill") {
            return .close(number)
        }
        if text.contains("turn on") || text.contains("switch on")
            || words.contains("open") || words.contains("on") || words.contains("restore") {
            return .open(number)
        }
        return nil
    }

    /// The 1–4 light number that follows the word "light" (digit or word form), e.g. "the light 2".
    private static func lightNumber(in text: String) -> Int? {
        let tokens = text.split(whereSeparator: { $0 == " " }).map(String.init)
        for (index, token) in tokens.enumerated() where token.hasPrefix("light") {
            // "light2" stuck together.
            if token.count > 5, let n = numberToken(String(token.dropFirst(5))) { return n }
            if index + 1 < tokens.count, let n = numberToken(tokens[index + 1]) { return n }
        }
        return nil
    }

    private static func numberToken(_ token: String) -> Int? {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;#"))
        if let n = Int(cleaned) { return n }
        switch cleaned {
        case "one", "first": return 1
        case "two", "second": return 2
        case "three", "third": return 3
        case "four", "fourth": return 4
        default: return nil
        }
    }

    private static func colorHex(in text: String, words: Set<String>) -> String? {
        // Explicit hex like #RRGGBB.
        if let range = text.range(of: "#"), text.distance(from: range.lowerBound, to: text.endIndex) >= 7 {
            let hex = String(text[range.lowerBound...].prefix(7))
            if FixtureColor.normalizedHex(hex) != nil { return hex.uppercased() }
        }
        // "warm white" reads as warm.
        if text.contains("warm white") || text.contains("warm") { return colorNames["warm"] }
        for (name, hex) in colorNames where words.contains(name) {
            return hex
        }
        // CJK colour words ("紅色") don't tokenize into the ASCII `words` set, so scan them directly.
        // Sort longest-key-first so "紅色" wins over its single-char "紅" substring.
        for key in colorNames.keys.sorted(by: { $0.count > $1.count }) where !key.allSatisfy({ $0.isASCII }) {
            if text.contains(key) { return colorNames[key] }
        }
        return nil
    }

    /// The first role whose needle appears in the text (longest/most-specific needles listed first in
    /// `roleNames`), or nil if no role is named.
    private static func roleNeedleMatch(in text: String) -> FixtureRole? {
        for (needle, role) in roleNames where text.contains(needle) {
            return role
        }
        return nil
    }

    /// A brightness percentage, from "...30%", "...30 percent", or "dim/brightness ... 30".
    private static func intensityFraction(in text: String) -> Double? {
        let hasPercentMarker = text.contains("%") || text.contains("percent")
        let mentionsBrightness = text.contains("dim") || text.contains("bright") || text.contains("intensity") || text.contains("level")
        guard hasPercentMarker || mentionsBrightness else { return nil }

        // Pull the first standalone number that isn't the light index right after "light".
        let tokens = text.split(whereSeparator: { !$0.isNumber && $0 != "." }).map(String.init)
        // Reconstruct numbers while skipping the "light N" index.
        var lightIndexValue: Int? = lightNumber(in: text)
        for token in tokens {
            guard let value = Double(token) else { continue }
            if let li = lightIndexValue, Int(value) == li {
                // Likely the light number itself (e.g. the "9" in "light 9") — skip once.
                lightIndexValue = nil
                continue
            }
            let fraction = value > 1 ? value / 100.0 : value
            return min(max(fraction, 0), 1)
        }
        return nil
    }

    /// A single-fixture rotation command, or nil if the text isn't a rotation (so the caller falls
    /// through to close/open). A rotation needs BOTH a rotation verb ({turn, pan, tilt, rotate, aim,
    /// point, spin}) AND a direction word ({right, left, up, down}) — this is what keeps "turn off"/
    /// "turn on" (a verb but no direction word) out of this path. right → pan +M, left → pan −M,
    /// up → tilt +M, down → tilt −M; the magnitude M is the first number after the light index (same
    /// "skip the light number" trick `intensityFraction` uses), defaulting to 45° when none is given.
    private static func rotationCommand(number: Int, in text: String, words: Set<String>) -> LightCommand? {
        let rotationVerbs: Set<String> = ["turn", "pan", "tilt", "rotate", "aim", "point", "spin"]
        guard !rotationVerbs.isDisjoint(with: words) else { return nil }

        // The direction word picks the axis + sign. Only one direction is honored (the first found), so a
        // command names one axis at a time; if none is present this isn't a rotation.
        let panSign: Double
        let tiltSign: Double
        if words.contains("right") {
            panSign = 1; tiltSign = 0
        } else if words.contains("left") {
            panSign = -1; tiltSign = 0
        } else if words.contains("up") {
            panSign = 0; tiltSign = 1
        } else if words.contains("down") {
            panSign = 0; tiltSign = -1
        } else {
            return nil
        }

        let magnitude = rotationMagnitude(in: text, skippingLightNumber: number) ?? 45
        return .rotate(
            number,
            panDeltaDegrees: panSign * magnitude,
            tiltDeltaDegrees: tiltSign * magnitude
        )
    }

    /// The first standalone number in the text that isn't the light index (e.g. the "60" in "light 6 turn
    /// right 60 degrees", skipping the "6"). Mirrors `intensityFraction`'s skip-the-light-number handling.
    private static func rotationMagnitude(in text: String, skippingLightNumber lightNumber: Int) -> Double? {
        let tokens = text.split(whereSeparator: { !$0.isNumber && $0 != "." }).map(String.init)
        var lightIndexValue: Int? = lightNumber
        for token in tokens {
            guard let value = Double(token) else { continue }
            if let li = lightIndexValue, Int(value) == li {
                lightIndexValue = nil   // skip the light number itself once
                continue
            }
            return value
        }
        return nil
    }
}

struct LightingExplanation: Codable, Equatable {
    var term: String
    var plainText: String
    var actionSummary: String
    /// A short teaching rationale ("why the front is warm, what the backlight separates, how contrast is
    /// built") for the AI 燈光導師. Additive + back-compat: defaults to "" so existing construction sites
    /// (mvpDemo/showcaseDemo/StageState patches/AppModel) compile unchanged.
    var rationale: String = ""

    init(
        term: String,
        plainText: String,
        actionSummary: String,
        rationale: String = ""
    ) {
        self.term = term
        self.plainText = plainText
        self.actionSummary = actionSummary
        self.rationale = rationale
    }

    // Custom decoding so old JSON without a `rationale` key decodes to "" — a synthesized memberwise
    // decoder would otherwise reject the missing key even though the property is defaulted.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decode(String.self, forKey: .term)
        plainText = try container.decode(String.self, forKey: .plainText)
        actionSummary = try container.decode(String.self, forKey: .actionSummary)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
    }
}

struct ComposerStatusChipContent: Equatable {
    var projectName: String?
    var cueName: String
    var musicStatusTitle: String?

    var titles: [String] {
        var result: [String] = []
        if let projectName {
            result.append(projectName)
        }
        result.append(cueName)
        if let musicStatusTitle {
            result.append(musicStatusTitle)
        }
        return result
    }
}

enum ComposerStatusChipPolicy {
    static func make(
        projectName: String?,
        cueName: String,
        musicStatusTitle: String?
    ) -> ComposerStatusChipContent {
        ComposerStatusChipContent(
            projectName: sanitizedOptionalTitle(projectName),
            cueName: sanitizedTitle(cueName, fallback: "開場"),
            musicStatusTitle: sanitizedOptionalTitle(musicStatusTitle)
        )
    }

    static func titles(
        projectName: String?,
        cueName: String,
        musicStatusTitle: String?
    ) -> [String] {
        make(
            projectName: projectName,
            cueName: cueName,
            musicStatusTitle: musicStatusTitle
        ).titles
    }

    private static func sanitizedOptionalTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct LightingLook: Codable, Equatable {
    var schemaVersion: String
    var intent: LightingIntent
    var lookName: String
    var mood: String
    var ambient: AmbientState
    var selectedCueId: String
    var cues: [LightingCue]
    var explanation: LightingExplanation

    static func mvpDemo() -> LightingLook {
        LightingLook(
            schemaVersion: "1.0",
            intent: .generateLook,
            lookName: "溫暖開場燈光",
            mood: "溫暖、熱情、學生展演",
            ambient: AmbientState(
                preset: .standardNight,
                level: 0.35,
                colorTemperature: 4200
            ),
            selectedCueId: "cue_opening",
            cues: [
                LightingCue(
                    id: "cue_opening",
                    name: "Opening",
                    transition: .mvpDefault,
                    fixtureGroups: [
                        FixtureGroup(
                            id: "front_wash",
                            name: "前方泛光（左）",
                            role: .frontLight,
                            zone: .stageFront,
                            enabled: true,
                            intensity: 0.6,
                            color: FixtureColor(mode: .rgb, value: "#FFD1A3")
                        ),
                        FixtureGroup(
                            id: "front_wash_right",
                            name: "前方泛光（右）",
                            role: .frontLight,
                            zone: .stageFront,
                            enabled: true,
                            intensity: 0.6,
                            color: FixtureColor(mode: .rgb, value: "#FFD1A3")
                        ),
                        FixtureGroup(
                            id: "background_wash",
                            name: "背景泛光",
                            role: .backgroundWash,
                            zone: .stageBack,
                            enabled: true,
                            intensity: 0.75,
                            color: FixtureColor(mode: .rgb, value: "#4FA8FF")
                        ),
                        FixtureGroup(
                            id: "laser_fan",
                            name: "雷射扇",
                            role: .spot,
                            zone: .stageBack,
                            enabled: true,
                            intensity: 0.7,
                            color: FixtureColor(mode: .rgb, value: "#26FF6A"),
                            model: .laser
                        )
                    ]
                ),
                LightingCue(
                    id: "cue_highlight",
                    name: "Highlight",
                    transition: .mvpDefault,
                    fixtureGroups: [
                        FixtureGroup(
                            id: "front_wash",
                            name: "前方泛光（左）",
                            role: .frontLight,
                            zone: .stageFront,
                            enabled: true,
                            intensity: 0.75,
                            color: FixtureColor(mode: .rgb, value: "#FFE0B8")
                        ),
                        FixtureGroup(
                            id: "front_wash_right",
                            name: "前方泛光（右）",
                            role: .frontLight,
                            zone: .stageFront,
                            enabled: true,
                            intensity: 0.75,
                            color: FixtureColor(mode: .rgb, value: "#FFE0B8")
                        ),
                        FixtureGroup(
                            id: "background_wash",
                            name: "背景泛光",
                            role: .backgroundWash,
                            zone: .stageBack,
                            enabled: true,
                            intensity: 0.9,
                            color: FixtureColor(mode: .rgb, value: "#2F6BFF")
                        ),
                        FixtureGroup(
                            id: "laser_fan",
                            name: "雷射扇",
                            role: .spot,
                            zone: .stageBack,
                            enabled: true,
                            intensity: 0.95,
                            color: FixtureColor(mode: .rgb, value: "#26FF6A"),
                            model: .laser
                        )
                    ]
                )
            ],
            explanation: LightingExplanation(
                term: "亮度",
                plainText: "亮度描述燈光輸出的強度。60% 的前光能讓表演者清晰可見，同時不會壓過背景泛光。",
                actionSummary: "已生成開場與重點場景：溫暖前光、冷色背景泛光，並加入綠色雷射光束在空中點題。"
            )
        )
    }

    /// A neutral "blank canvas" look for the empty-project template: a minimal front-wash + background-wash
    /// rig in plain white at a low level, with no color theme, laser, or accent fixtures. It reads as an
    /// un-designed stage the user fills in with their first AI prompt, while staying a valid two-cue
    /// `LightingLook` (so the cue stack, GO, and the renderer all work immediately). Both cues carry the
    /// same fixture ids (rig identity), differing only by a gentle Opening→Highlight brightness lift.
    static func blankStage() -> LightingLook {
        func fixtures(intensity: Double) -> [FixtureGroup] {
            [
                FixtureGroup(
                    id: "front_wash", name: "前方泛光（左）", role: .frontLight, zone: .stageFront,
                    enabled: true, intensity: intensity, color: FixtureColor(mode: .rgb, value: "#FFFFFF")
                ),
                FixtureGroup(
                    id: "front_wash_right", name: "前方泛光（右）", role: .frontLight, zone: .stageFront,
                    enabled: true, intensity: intensity, color: FixtureColor(mode: .rgb, value: "#FFFFFF")
                ),
                FixtureGroup(
                    id: "background_wash", name: "背景泛光", role: .backgroundWash, zone: .stageBack,
                    enabled: true, intensity: intensity, color: FixtureColor(mode: .rgb, value: "#FFFFFF")
                )
            ]
        }

        return LightingLook(
            schemaVersion: "1.0",
            intent: .generateLook,
            lookName: "空白舞台燈光",
            mood: "中性、待設計",
            ambient: AmbientState(preset: .standardNight, level: 0.30, colorTemperature: 4200),
            selectedCueId: "cue_opening",
            cues: [
                LightingCue(id: "cue_opening", name: "Opening", transition: .mvpDefault, fixtureGroups: fixtures(intensity: 0.4)),
                LightingCue(id: "cue_highlight", name: "Highlight", transition: .mvpDefault, fixtureGroups: fixtures(intensity: 0.6))
            ],
            explanation: LightingExplanation(
                term: "空白舞台",
                plainText: "這是一個中性的空白起點：白色前光與背景泛光，沒有套用任何配色或情緒，等你用 AI 開始設計。",
                actionSummary: "已建立空白舞台：白色前光與背景泛光，尚未套用任何主題。"
            )
        )
    }

    /// A richer multi-fixture demo (key fresnels, moving heads, PARs, a strobe, an audience blinder) for
    /// previews and the iPad panel's offline mock. Exercises the dynamic rig with diverse fixture types,
    /// colors, DMX patches, and aim targets; validates like any generated look. Both cues carry the same
    /// fixture ids in the same order (rig identity), differing only in per-cue state.
    static func showcaseDemo() -> LightingLook {
        struct Spec {
            let id: String
            let name: String
            let model: LightingFixtureVisualModel
            let zone: StageZone
            let target: FixtureTarget
            let openingHex: String
            let highlightHex: String
            let openingIntensity: Double
            let highlightIntensity: Double
            let beam: Double
            let pan: Double
            let tilt: Double
        }

        // A left/right-symmetric rig: every visible fixture has a mirror partner (the lone laser used to
        // sit off to one side and read as awkward), with one centred strobe as the deliberate centrepiece.
        // `syncRig` spreads each zone's fixtures evenly across mirror slots (-1…+1), so listing each zone's
        // members in palindromic order lands the pairs symmetrically — back zone reads
        // laser ¦ moving-head ¦ (centre) strobe ¦ moving-head ¦ laser.
        let specs: [Spec] = [
            // FOH stands: the symmetric key-light pair.
            Spec(id: "key_l", name: "主光柔光燈（左）", model: .frontFresnel, zone: .stageFront, target: .downstage,
                 openingHex: "#FFE6C2", highlightHex: "#FFF1DC", openingIntensity: 0.55, highlightIntensity: 0.80, beam: 40, pan: -8, tilt: -35),
            Spec(id: "key_r", name: "主光柔光燈（右）", model: .frontFresnel, zone: .stageFront, target: .downstage,
                 openingHex: "#FFE6C2", highlightHex: "#FFF1DC", openingIntensity: 0.55, highlightIntensity: 0.80, beam: 40, pan: 8, tilt: -35),
            // Upstage truss, palindromic so the pairs mirror: laser · moving head · centre strobe · moving head · laser.
            Spec(id: "laser_l", name: "雷射燈（左）", model: .laser, zone: .stageBack, target: .fullStage,
                 openingHex: "#22FF6A", highlightHex: "#2BFF88", openingIntensity: 0.0, highlightIntensity: 0.95, beam: 6, pan: -6, tilt: -6),
            Spec(id: "mh_l", name: "搖頭光束燈（左）", model: .movingHeadBeam, zone: .stageBack, target: .centerStage,
                 openingHex: "#2E6BFF", highlightHex: "#1E54FF", openingIntensity: 0.40, highlightIntensity: 0.95, beam: 14, pan: -20, tilt: -18),
            Spec(id: "strobe", name: "LED 頻閃燈條（中）", model: .ledStrobeBar, zone: .stageBack, target: .fullStage,
                 openingHex: "#FFFFFF", highlightHex: "#FFFFFF", openingIntensity: 0.0, highlightIntensity: 0.70, beam: 60, pan: 0, tilt: -10),
            Spec(id: "mh_r", name: "搖頭光束燈（右）", model: .movingHeadBeam, zone: .stageBack, target: .centerStage,
                 openingHex: "#A24BFF", highlightHex: "#FF2D9E", openingIntensity: 0.40, highlightIntensity: 0.95, beam: 14, pan: 20, tilt: -18),
            Spec(id: "laser_r", name: "雷射燈（右）", model: .laser, zone: .stageBack, target: .fullStage,
                 openingHex: "#22FF6A", highlightHex: "#2BFF88", openingIntensity: 0.0, highlightIntensity: 0.95, beam: 6, pan: 6, tilt: -6),
            // Side booms: the symmetric PAR pair on opposite side zones.
            Spec(id: "par_l", name: "LED PAR（左）", model: .ledPar, zone: .stageLeft, target: .stageLeft,
                 openingHex: "#27D7E0", highlightHex: "#33E07A", openingIntensity: 0.50, highlightIntensity: 0.85, beam: 30, pan: 0, tilt: -22),
            Spec(id: "par_r", name: "LED PAR（右）", model: .ledPar, zone: .stageRight, target: .stageRight,
                 openingHex: "#33E07A", highlightHex: "#27D7E0", openingIntensity: 0.50, highlightIntensity: 0.85, beam: 30, pan: 0, tilt: -22)
        ]

        func fixtures(highlight: Bool) -> [FixtureGroup] {
            specs.enumerated().map { index, spec in
                let role = spec.model.derivedRole
                var fineControl = FixtureFineControl.default(role: role, zone: spec.zone)
                fineControl.beamAngleDegrees = spec.beam
                fineControl.panDegrees = spec.pan
                fineControl.tiltDegrees = spec.tilt
                let base = index * 4 + 1   // dimmer + RGB = 4 channels per fixture, all on universe 1
                return FixtureGroup(
                    id: spec.id,
                    name: spec.name,
                    role: role,
                    zone: spec.zone,
                    enabled: true,
                    intensity: highlight ? spec.highlightIntensity : spec.openingIntensity,
                    color: FixtureColor(mode: .rgb, value: highlight ? spec.highlightHex : spec.openingHex),
                    fineControl: fineControl,
                    model: spec.model,
                    target: spec.target,
                    dmx: DMXPatch(universe: 1, address: base,
                                  channels: .init(dimmer: base, red: base + 1, green: base + 2, blue: base + 3))
                )
            }
        }

        return LightingLook(
            schemaVersion: "1.0",
            intent: .generateLook,
            lookName: "舞團演出 Showcase",
            mood: "高能量、彩色、舞團收尾",
            ambient: AmbientState(preset: .standardNight, level: 0.30, colorTemperature: 4200),
            selectedCueId: "cue_highlight",
            cues: [
                LightingCue(id: "cue_opening", name: "Opening", transition: .mvpDefault, fixtureGroups: fixtures(highlight: false)),
                LightingCue(id: "cue_highlight", name: "Highlight", transition: .mvpDefault, fixtureGroups: fixtures(highlight: true))
            ],
            explanation: LightingExplanation(
                term: "Key Light",
                plainText: "主光（Key Light）是打亮表演者的主要光源；其餘燈具左右對稱地圍繞它堆疊顏色與動態，營造層次。",
                actionSummary: "已生成九支燈具、左右對稱的舞團 Showcase：暖色主光、冷暖對比的搖頭光束與 PAR、中央頻閃，兩側對稱的綠色雷射點題。"
            )
        )
    }

    func requireCue(id: String) throws -> LightingCue {
        guard let cue = cues.first(where: { $0.id == id }) else {
            throw ValidationError.missingCue(id)
        }

        return cue
    }

    func validate() throws {
        guard schemaVersion == "1.0" else {
            throw ValidationError.unsupportedSchemaVersion(schemaVersion)
        }

        guard ambient.preset == .standardNight else {
            throw ValidationError.unsupportedAmbientPreset(ambient.preset.rawValue)
        }

        // A lighting look is a cue *stack*: it must carry at least one cue, and the selected cue must
        // resolve. (Earlier the schema hard-pinned exactly `cue_opening` + `cue_highlight`; the rig is
        // now a growable, ordered sequence — templates still ship those two named cues, AI generates a
        // multi-cue show, and the user can add/remove cues — so the invariant is "non-empty + the
        // selection resolves", not two fixed ids. See `StageState`'s cue-stack ops and `goToNextCue`.)
        guard !cues.isEmpty else {
            throw ValidationError.missingRequiredCue
        }

        guard cues.contains(where: { $0.id == selectedCueId }) else {
            throw ValidationError.missingCue(selectedCueId)
        }

        for cue in cues {
            // A cue's follow/hold time (SPEC 16) is an optional playback hint, but when present it must be a
            // sane, finite duration so the auto-playback scheduler can trust it. `CuePlayback.holdDuration`
            // clamps at runtime; validate here keeps malformed data (NaN / negative / absurd) out of a
            // persisted look in the first place.
            if let hold = cue.holdDuration, !(hold.isFinite && (0...CuePlayback.maxHoldSeconds).contains(hold)) {
                throw ValidationError.invalidHoldDuration(hold)
            }
            for fixture in cue.fixtureGroups {
                try validate(fixture)
            }
        }
    }

    private func validate(_ fixture: FixtureGroup) throws {
        guard (0.0...1.0).contains(fixture.intensity) else {
            throw ValidationError.invalidIntensity(fixture.intensity)
        }

        guard fixture.color.mode == .rgb else {
            throw ValidationError.unsupportedColorMode(fixture.color.mode.rawValue)
        }

        guard FixtureColor.normalizedHex(fixture.color.value) != nil else {
            throw ValidationError.invalidHexColor(fixture.color.value)
        }

        if let fineControl = fixture.fineControl {
            try fineControl.validate()
        }

        if let aimOffset = fixture.aimOffset {
            try aimOffset.validate()
        }

        if let dmx = fixture.dmx {
            try dmx.validate()
        }
    }
}

struct LumaStageProject: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var venueDescription: String
    var eventType: String
    var lastEditedDescription: String
    var stageLayout: StageLayout
    var lightingLook: LightingLook
    /// The locked rig (鎖定燈具) generation must obey (SPEC 05). Additive + back-compat: defaults to
    /// unconstrained, and old project JSON without the key decodes to unconstrained via `decodeIfPresent`.
    var rigConstraint: RigConstraint = RigConstraint(fixtureCount: nil, allowedModels: [])

    init(
        id: String,
        name: String,
        venueDescription: String,
        eventType: String,
        lastEditedDescription: String,
        stageLayout: StageLayout,
        lightingLook: LightingLook,
        rigConstraint: RigConstraint = RigConstraint(fixtureCount: nil, allowedModels: [])
    ) {
        self.id = id
        self.name = name
        self.venueDescription = venueDescription
        self.eventType = eventType
        self.lastEditedDescription = lastEditedDescription
        self.stageLayout = stageLayout
        self.lightingLook = lightingLook
        self.rigConstraint = rigConstraint
    }

    // Custom decoding so old project JSON without a `rigConstraint` key decodes to unconstrained — a
    // synthesized memberwise decoder would otherwise reject the missing key even though it's defaulted
    // (same idiom as `LightingExplanation.init(from:)`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        venueDescription = try container.decode(String.self, forKey: .venueDescription)
        eventType = try container.decode(String.self, forKey: .eventType)
        lastEditedDescription = try container.decode(String.self, forKey: .lastEditedDescription)
        stageLayout = try container.decode(StageLayout.self, forKey: .stageLayout)
        lightingLook = try container.decode(LightingLook.self, forKey: .lightingLook)
        rigConstraint = try container.decodeIfPresent(RigConstraint.self, forKey: .rigConstraint)
            ?? RigConstraint(fixtureCount: nil, allowedModels: [])
    }

    static func defaultProjects() -> [LumaStageProject] {
        // Open the app on a complete, ready-to-play design instead of an empty home: the 9-fixture
        // `showcaseDemo` rig (moving heads, PARs, strobe, blinder, laser) carrying an Opening→Highlight
        // energy arc, so the user can GO straight into a real show with no AI generation. Doubles as the
        // demo backup project. Starts on Opening (calm) so GO builds up to the high-energy finale where
        // the dynamic effects ignite.
        var showcaseLook = LightingLook.showcaseDemo()
        showcaseLook.selectedCueId = "cue_opening"
        return [
            LumaStageProject(
                id: "project_dance_showcase",
                name: "舞團演出 Showcase",
                venueDescription: "戶外桁架舞台",
                eventType: "舞團成發",
                lastEditedDescription: "可直接播放的示範秀",
                stageLayout: .defaultStudentOutdoor(),
                lightingLook: showcaseLook
            )
        ]
    }

    static func demoProjects() -> [LumaStageProject] {
        [
            LumaStageProject(
                id: "project_campus_music_night",
                name: "校園音樂之夜",
                venueDescription: "戶外學生舞台",
                eventType: "學生表演",
                lastEditedDescription: "示範專案",
                stageLayout: .defaultStudentOutdoor(),
                lightingLook: look(
                    name: "溫暖開場燈光",
                    mood: "溫暖、熱情、學生展演"
                )
            ),
            LumaStageProject(
                id: "project_club_showcase",
                name: "社團展演",
                venueDescription: "戶外桁架舞台",
                eventType: "社團演出",
                lastEditedDescription: "可預覽",
                stageLayout: .defaultStudentOutdoor(),
                lightingLook: look(
                    name: "冷調展演燈光",
                    mood: "冷調、聚焦、學生展演"
                )
            ),
            LumaStageProject(
                id: "project_graduation_party",
                name: "畢業派對",
                venueDescription: "夜間戶外舞台",
                eventType: "慶祝活動",
                lastEditedDescription: "燈光草稿",
                stageLayout: .defaultStudentOutdoor(),
                lightingLook: look(
                    name: "派對重點燈光",
                    mood: "明亮、歡慶、戶外活動"
                )
            )
        ]
    }

    static func newProject(index: Int) -> LumaStageProject {
        newProject(index: index, template: .campusMusic)
    }

    static func newProject(index: Int, template kind: ProjectCreationTemplate.Kind) -> LumaStageProject {
        let template = ProjectCreationTemplate.template(for: kind)

        return LumaStageProject(
            id: "project_custom_\(UUID().uuidString)",
            name: "\(template.projectName) \(index)",
            venueDescription: template.venueDescription,
            eventType: template.eventType,
            lastEditedDescription: "新專案",
            stageLayout: .defaultStudentOutdoor(),
            lightingLook: baseLook(for: kind, name: template.lookName, mood: template.mood)
        )
    }

    /// The starting look for a newly created project: the blank kind opens on a neutral white canvas,
    /// every themed template carries the `mvpDemo` rig. Both are renamed/re-mooded to match the chosen
    /// template so the look label reflects the picker choice.
    private static func baseLook(for kind: ProjectCreationTemplate.Kind, name: String, mood: String) -> LightingLook {
        switch kind {
        case .emptyStage:
            var look = LightingLook.blankStage()
            look.lookName = name
            look.mood = mood
            return look
        case .campusMusic:
            return look(name: name, mood: mood)
        }
    }

    private static func look(name: String, mood: String) -> LightingLook {
        var look = LightingLook.mvpDemo()
        look.lookName = name
        look.mood = mood
        return look
    }
}

struct ProjectCreationTemplate: Codable, Equatable, Identifiable {
    enum Kind: String, CaseIterable, Codable {
        case campusMusic
        case emptyStage
    }

    enum VisualStyle: String, Codable, Hashable {
        case emptyStage
        case warmConcert
        case coolShowcase
        case partyFinale
    }

    var id: Kind { kind }
    var kind: Kind
    var title: String
    var subtitle: String
    var introduction: String
    var systemImage: String
    var visualStyle: VisualStyle
    var projectName: String
    var venueDescription: String
    var eventType: String
    var lookName: String
    var mood: String

    // Order is UI-facing: the blank stage leads so "從零開始" is the first thing the user sees, then the
    // ready-made scenario template. `projectCreationOffersTemplatesWithBlankOption` pins this order.
    static let allTemplates: [ProjectCreationTemplate] = [
        ProjectCreationTemplate(
            kind: .emptyStage,
            title: "空白舞台",
            subtitle: "從零開始，沒有預設配色或情緒，直接用 AI 打造你的燈光。",
            introduction: "中性的空白起點：白色前光與背景泛光，搭配預設的戶外學生舞台與桁架，沒有套用任何主題。適合想完全自訂、從頭設計的使用者。",
            systemImage: "square.dashed",
            visualStyle: .emptyStage,
            projectName: "空白舞台",
            venueDescription: "戶外桁架舞台",
            eventType: "自訂",
            lookName: "空白舞台燈光",
            mood: "中性、待設計"
        ),
        ProjectCreationTemplate(
            kind: .campusMusic,
            title: "校園音樂之夜",
            subtitle: "適合樂團、歌唱與社團之夜，溫暖開場並聚焦表演者。",
            introduction: "專為戶外夜間演出設計。前光讓表演者清晰可見，溫暖與藍色的背景層次適合學生樂團、歌唱比賽與小型音樂會。",
            systemImage: "music.mic",
            visualStyle: .warmConcert,
            projectName: "校園音樂之夜",
            venueDescription: "戶外學生舞台",
            eventType: "學生表演",
            lookName: "溫暖開場燈光",
            mood: "溫暖、熱情、學生展演"
        )
    ]

    static func template(for kind: Kind) -> ProjectCreationTemplate {
        allTemplates.first(where: { $0.kind == kind }) ?? allTemplates[0]
    }
}

enum CuePatch: Equatable {
    case frontLightDimmer(Double)
    case backgroundWashColor(String)
    case fixtureIntensity(fixtureId: String, intensity: Double)
    case fixtureColor(fixtureId: String, hexColor: String)
    case fixtureFineControl(fixtureId: String, control: FixtureFineControl)
    /// Recolor EVERY fixture of `role` in the selected cue (a role-named voice/typed command).
    case roleColor(role: FixtureRole, hexColor: String)
}

struct StageState: Equatable {
    var lightingLook: LightingLook
    private var baselineLook: LightingLook

    var selectedCueId: String {
        get { lightingLook.selectedCueId }
        set { lightingLook.selectedCueId = newValue }
    }

    init(lightingLook: LightingLook) {
        self.lightingLook = lightingLook
        baselineLook = lightingLook
    }

    func requireSelectedCue() throws -> LightingCue {
        try lightingLook.requireCue(id: selectedCueId)
    }

    mutating func replaceLightingLook(_ look: LightingLook) throws {
        try look.validate()
        lightingLook = look
        baselineLook = look
    }

    mutating func selectCue(id: String) throws {
        _ = try lightingLook.requireCue(id: id)
        lightingLook.selectedCueId = id
    }

    mutating func patchSelectedCue(_ patch: CuePatch) throws {
        let selectedCueId = selectedCueId
        guard let cueIndex = lightingLook.cues.firstIndex(where: { $0.id == selectedCueId }) else {
            throw ValidationError.missingCue(selectedCueId)
        }

        switch patch {
        case .frontLightDimmer(let intensity):
            guard (0.0...1.0).contains(intensity) else {
                throw ValidationError.invalidIntensity(intensity)
            }

            try mutateFixture(role: .frontLight, inCueAt: cueIndex) { fixture in
                fixture.intensity = intensity
            }
            lightingLook.explanation = LightingExplanation(
                term: "亮度",
                plainText: "亮度是業界用來形容燈具輸出強度的術語。將前光設為 \(Int(round(intensity * 100)))% 會讓面向表演者的燈光採用該輸出等級。",
                actionSummary: "已調整目前場景的前光亮度。"
            )

        case .backgroundWashColor(let hexColor):
            guard let normalizedHex = FixtureColor.normalizedHex(hexColor) else {
                throw ValidationError.invalidHexColor(hexColor)
            }

            try mutateFixture(role: .backgroundWash, inCueAt: cueIndex) { fixture in
                fixture.color.value = normalizedHex
            }
            lightingLook.explanation = LightingExplanation(
                term: "背景泛光",
                plainText: "背景泛光是一片放置在舞台後方或背景幕上的大面積彩色燈光。改變其顏色會直接改變舞台氛圍。",
                actionSummary: "已調整目前場景的背景泛光顏色。"
            )

        case .fixtureIntensity(let fixtureId, let intensity):
            guard (0.0...1.0).contains(intensity) else {
                throw ValidationError.invalidIntensity(intensity)
            }

            try mutateFixture(id: fixtureId, inCueAt: cueIndex) { fixture in
                fixture.intensity = intensity
            }
            lightingLook.explanation = LightingExplanation(
                term: "燈具亮度",
                plainText: "精細控制會直接編輯目前場景中所選的燈具，而不會改變其他場景中相符的燈具。",
                actionSummary: "已調整所選燈具的亮度。"
            )

        case .fixtureColor(let fixtureId, let hexColor):
            guard let normalizedHex = FixtureColor.normalizedHex(hexColor) else {
                throw ValidationError.invalidHexColor(hexColor)
            }

            try mutateFixture(id: fixtureId, inCueAt: cueIndex) { fixture in
                fixture.color.value = normalizedHex
            }
            lightingLook.explanation = LightingExplanation(
                term: "燈具顏色",
                plainText: "顏色選擇器會將 RGB 十六進位色值套用到目前場景中所選的燈具，讓單一來源的視覺微調更精準。",
                actionSummary: "已調整所選燈具的顏色。"
            )

        case .fixtureFineControl(let fixtureId, let control):
            try control.validate()
            try mutateFixture(id: fixtureId, inCueAt: cueIndex) { fixture in
                fixture.fineControl = control
            }
            lightingLook.explanation = LightingExplanation(
                term: "燈具角度與位置",
                plainText: "位置、水平旋轉、垂直俯仰、滾轉與光束角度會儲存在目前場景中所選的燈具上，用於同步的 MR 精細控制。",
                actionSummary: "已更新所選燈具的位置、旋轉與光束角度。"
            )

        case .roleColor(let role, let hexColor):
            guard let normalizedHex = FixtureColor.normalizedHex(hexColor) else {
                throw ValidationError.invalidHexColor(hexColor)
            }

            try mutateFixtures(role: role, inCueAt: cueIndex) { fixture in
                fixture.color.value = normalizedHex
            }
            lightingLook.explanation = LightingExplanation(
                term: "\(role.displayName)顏色",
                plainText: "依角色重新著色只會調整目前場景中所有「\(role.displayName)」角色的燈具，不會重新生成整個燈光，也不影響其他場景。",
                actionSummary: "已將目前場景的\(role.displayName)改為 \(normalizedHex)。"
            )
        }

        try lightingLook.validate()
    }

    mutating func resetSelectedCue() throws {
        let selectedCueId = selectedCueId
        guard let baselineCue = try? baselineLook.requireCue(id: selectedCueId) else {
            // A user-added cue (not present in the generation baseline) has nothing to restore to —
            // leave it untouched rather than throwing, so reset stays valid in a grown cue stack.
            return
        }
        guard let cueIndex = lightingLook.cues.firstIndex(where: { $0.id == selectedCueId }) else {
            throw ValidationError.missingCue(selectedCueId)
        }

        lightingLook.cues[cueIndex] = baselineCue
        lightingLook.explanation = LightingExplanation(
            term: "場景基準",
            plainText: "重置只會將目前場景還原為 AI 生成的基準，不會影響其他場景。",
            actionSummary: "已將目前場景重置為其生成基準。"
        )

        try lightingLook.validate()
    }

    // MARK: - Cue stack (multi-cue sequence + GO)
    //
    // A lighting look is an ordered list of cues a designer steps through during a show (grandMA2's
    // Sequence + GO key). These ops grow/shrink/advance that list while keeping `selectedCueId` valid
    // and re-validating. The id is supplied by the caller (AppModel mints a UUID-based id) so the pure
    // logic here stays deterministic for the smoke tests.

    /// The cue ids in playback order.
    var cueOrder: [String] { lightingLook.cues.map(\.id) }

    /// Index of the selected cue in playback order (0 if it can't be found, which `validate()` prevents).
    var selectedCueIndex: Int {
        lightingLook.cues.firstIndex(where: { $0.id == selectedCueId }) ?? 0
    }

    /// Advances the selection to the next cue in order, wrapping at the end — the GO key. Returns the
    /// now-selected cue so the renderer can cross-fade over *its* transition.
    @discardableResult
    mutating func goToNextCue() -> LightingCue {
        advanceSelection(by: 1)
    }

    /// Steps the selection to the previous cue, wrapping at the start (GO back).
    @discardableResult
    mutating func goToPreviousCue() -> LightingCue {
        advanceSelection(by: -1)
    }

    private mutating func advanceSelection(by step: Int) -> LightingCue {
        let cues = lightingLook.cues
        let count = cues.count
        let nextIndex = ((selectedCueIndex + step) % count + count) % count
        lightingLook.selectedCueId = cues[nextIndex].id
        return cues[nextIndex]
    }

    /// Appends a new cue by duplicating the selected cue (so the rig identity — same fixtures, ids and
    /// order — carries over), inserts it right after the selected cue, and selects it. Validates.
    mutating func appendCue(id: String, name: String) throws {
        guard let sourceIndex = lightingLook.cues.firstIndex(where: { $0.id == selectedCueId }) else {
            throw ValidationError.missingCue(selectedCueId)
        }

        var newCue = lightingLook.cues[sourceIndex]
        newCue.id = id
        newCue.name = name
        lightingLook.cues.insert(newCue, at: sourceIndex + 1)
        lightingLook.selectedCueId = id
        try lightingLook.validate()
    }

    /// Removes a cue by id. Refuses to remove the last remaining cue (a look must keep ≥ 1). If the
    /// removed cue was selected, the selection moves to its neighbour. Validates.
    mutating func removeCue(id: String) throws {
        guard lightingLook.cues.count > 1 else {
            throw ValidationError.cannotRemoveLastCue
        }
        guard let index = lightingLook.cues.firstIndex(where: { $0.id == id }) else {
            throw ValidationError.missingCue(id)
        }

        lightingLook.cues.remove(at: index)
        if selectedCueId == id {
            lightingLook.selectedCueId = lightingLook.cues[min(index, lightingLook.cues.count - 1)].id
        }
        try lightingLook.validate()
    }

    /// Renames a cue (e.g. to label a generated show's sections — "Verse", "Chorus", "Bows"). Validates.
    mutating func renameCue(id: String, to name: String) throws {
        guard let index = lightingLook.cues.firstIndex(where: { $0.id == id }) else {
            throw ValidationError.missingCue(id)
        }
        lightingLook.cues[index].name = name
        try lightingLook.validate()
    }

    private mutating func mutateFixture(
        role: FixtureRole,
        inCueAt cueIndex: Int,
        mutation: (inout FixtureGroup) -> Void
    ) throws {
        guard let fixtureIndex = lightingLook.cues[cueIndex].fixtureGroups.firstIndex(where: { $0.role == role }) else {
            throw ValidationError.missingFixture(role.rawValue)
        }

        mutation(&lightingLook.cues[cueIndex].fixtureGroups[fixtureIndex])
    }

    /// Applies `mutation` to EVERY fixture of `role` in the cue (the plural sibling of the single-role
    /// mutator), for role-named commands that recolor a whole role at once. Throws if none match.
    private mutating func mutateFixtures(
        role: FixtureRole,
        inCueAt cueIndex: Int,
        mutation: (inout FixtureGroup) -> Void
    ) throws {
        let indices = lightingLook.cues[cueIndex].fixtureGroups.indices.filter {
            lightingLook.cues[cueIndex].fixtureGroups[$0].role == role
        }
        guard !indices.isEmpty else {
            throw ValidationError.missingFixture(role.rawValue)
        }
        for index in indices {
            mutation(&lightingLook.cues[cueIndex].fixtureGroups[index])
        }
    }

    private mutating func mutateFixture(
        id fixtureId: String,
        inCueAt cueIndex: Int,
        mutation: (inout FixtureGroup) -> Void
    ) throws {
        guard let fixtureIndex = lightingLook.cues[cueIndex].fixtureGroups.firstIndex(where: { $0.id == fixtureId }) else {
            throw ValidationError.missingFixture(fixtureId)
        }

        mutation(&lightingLook.cues[cueIndex].fixtureGroups[fixtureIndex])
    }
}

/// Pure mapping from the domain lighting model (0...1 cue intensity, fixture beam-angle
/// degrees) to RealityKit `SpotLightComponent` units. Kept Foundation-only so the smoke
/// tests can pin it without a simulator; `ImmersiveView` is the only consumer.
///
/// RealityKit spotlights are photometric: `intensity` is in lumens, not the cue model's
/// 0...1 scale — so the renderer must map through here rather than passing intensity raw.
enum SpotLightRenderMath {
    /// Peak luminous output (lumens) a fully-on fixture of each role emits. Tuned for the
    /// 0.46-scaled stage twin; safe to retune from runtime previews without touching tests
    /// that only assert the mapping's shape (clamp/endpoints/monotonicity), not the constants.
    static func maxLumens(role: FixtureRole) -> Double {
        switch role {
        case .frontLight: return 6000
        case .spot: return 7000
        case .wash: return 4500
        case .backgroundWash: return 4000
        }
    }

    /// Maps a 0...1 cue intensity to spotlight lumens for the given role. Clamps intensity
    /// to 0...1; 0 -> 0, 1 -> `maxLumens(role:)`; linear and monotonic in between.
    static func lumens(forIntensity intensity: Double, role: FixtureRole) -> Double {
        let clamped = min(max(intensity, 0), 1)
        return clamped * maxLumens(role: role)
    }

    /// Maps a fixture beam spread (full-cone degrees, validated to 5...120) to a spotlight's
    /// inner/outer cone angles. The full 5...120 range is mapped into a conservative 10°...60°
    /// outer cone that reads well and stays within RealityKit's accepted spotlight range
    /// regardless of whether the SDK treats the angle as full or half; the inner (full-intensity)
    /// cone is 70% of the outer to leave a soft penumbra edge.
    static func coneAngles(beamAngleDegrees: Double) -> (inner: Double, outer: Double) {
        let beam = min(max(beamAngleDegrees, 5), 120)
        let outer = 10 + (beam - 5) / 115 * 50
        let inner = outer * 0.7
        return (inner: inner, outer: outer)
    }

    /// Maps a fixture's beam spread (5...120°) to a `SpotLightComponent.Shadow` light-source size
    /// in meters: a wider beam reads with a larger apparent source and therefore a softer, wider
    /// shadow penumbra. The 0.04...0.40 m range is tuned to stay subtle on the 0.46-scaled stage;
    /// it pairs with shadow quality ≥ medium so the soft edge actually renders.
    static func shadowLightSize(beamAngleDegrees: Double) -> Double {
        let beam = min(max(beamAngleDegrees, 5), 120)
        return 0.04 + (beam - 5) / 115 * 0.36
    }
}

// MARK: - Tabletop preview beam cone (SPEC 21)

/// Deterministic geometry for the tabletop diorama's translucent preview beam cone (SPEC 21): from a
/// fixture's beam spread, throw distance, and 0...1 intensity it derives the cone's length / base radius /
/// alpha. Pure and platform-agnostic (model metres in, model metres out; the view converts to scene units
/// via `sceneLength`). Like `LaserScatterMath`/`SpotLightRenderMath`, the smoke test pins only the *shape*
/// of the mapping (monotonic, clamped, endpoints), not the exact constants — so `maxAlpha`, the half-angle
/// factor, and `minLengthMeters` stay retunable from device previews without touching tests.
enum PreviewBeamCone {
    /// Alpha ceiling at full intensity: bright enough to read as "light in the air", still translucent
    /// enough to see the grey diorama structure behind it. [需實機] tune.
    static let maxAlpha: Double = 0.35
    /// Shortest visible cone length, so a near-zero throw doesn't degenerate into an invisible sliver.
    static let minLengthMeters: Double = 0.4

    /// - length: `max(throwMeters, minLengthMeters)` — a near-zero (or negative) throw floors to a visible
    ///   minimum, otherwise the cone reaches the fixture's aim target.
    /// - baseRadius: `length * tan(coneAngles(beamAngleDegrees:).outer)` — the 1:1 stage's outer cone angle
    ///   reused as the half-spread, so a wider beam widens the base and a longer cone widens with it.
    ///   (`coneAngles` already clamps beamAngle to 5...120.)
    /// - alpha: `clamp(intensity, 0, 1) * maxAlpha` — 0 → 0, 1 → `maxAlpha`, monotonic in between.
    static func dimensions(beamAngleDegrees: Double, throwMeters: Double, intensity: Double)
        -> (length: Double, baseRadius: Double, alpha: Double) {
        let length = max(throwMeters, minLengthMeters)
        let halfAngle = SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees).outer
        let baseRadius = length * tan(halfAngle * .pi / 180)
        let alpha = min(max(intensity, 0), 1) * maxAlpha
        return (length: length, baseRadius: baseRadius, alpha: alpha)
    }
}

// MARK: - Laser volumetric scatter

/// Tunable "look" constants for the volumetric laser beam — the numbers behind the two visible
/// layers (a thin white-hot core and a soft glow sheath). The per-beam haze *particles* were removed
/// (they read as a weird off-axis speckle at 1:1 scale, and RealityKit particles aren't scene-lit);
/// the core+sheath cylinders carry the aerial-beam look on their own. Grouped here so radius, alpha,
/// and colour behaviour can be retuned from device previews in one place; the smoke tests pin the
/// *shape* of the mapping (gate, ordering, monotonicity), not these exact values, so retuning is safe.
/// Consumed by `LaserScatterMath`.
struct LaserScatterConfig: Equatable {
    /// Glow-sheath cylinder radius as a multiple of the beam core radius.
    var sheathRadiusFactor: Double
    /// Base additive alpha of the glow sheath at full intensity.
    var sheathAlpha: Double
    /// How far the core colour lerps toward white (0 = pure hue, 1 = white) for the white-hot centre.
    var coreWhiteness: Double
    /// Core alpha, kept near-opaque so the bright centre reads.
    var coreAlpha: Double

    static let `default` = LaserScatterConfig(
        sheathRadiusFactor: 5.0,
        sheathAlpha: 0.10,
        coreWhiteness: 0.55,
        coreAlpha: 0.95
    )
}

/// Pure mapping from a laser cue's colour (`#RRGGBB`) + 0...1 intensity to the numeric parameters the
/// RealityKit laser renderer needs for its two visible layers (white-hot core + glow sheath).
/// Foundation-only so the smoke tests can pin the look math without a simulator; `ImmersiveView` is the
/// only consumer (it maps `RGBA` -> UIColor and metres -> scene units for the beam cylinders).
///
/// Why two layers: the core is near-white-hot on-axis, and the wider low-alpha sheath bleeds the
/// saturated colour outward to kill the hard cylinder edge, so the beam reads as light in the air rather
/// than a solid rod. (An earlier third layer of additive haze particles was removed — see
/// `LaserScatterConfig`.)
enum LaserScatterMath {
    /// A plain RGBA (0...1 per channel) so the math stays UIKit/RealityKit-free.
    struct RGBA: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    /// A laser is off (all three layers hidden) at or below this cue intensity — shared with the beam
    /// geometry so core/sheath/particles vanish together. Matches the legacy `intensity > 0.03` gate.
    static func beamsVisible(_ intensity: Double) -> Bool { intensity > 0.03 }

    private static func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func components(hex: String) -> RGBComponents { RGBComponents(hex: hex) ?? .white }

    /// The white-hot core colour: the cue hue dimmed by intensity, then lerped toward white by
    /// `coreWhiteness` so the centre of the beam reads as an intense, near-white source.
    static func coreRGBA(hex: String, intensity: Double, config: LaserScatterConfig = .default) -> RGBA {
        let dimmed = components(hex: hex).dimmed(by: clamp01(intensity))
        let w = clamp01(config.coreWhiteness)
        return RGBA(
            red: dimmed.red + (1 - dimmed.red) * w,
            green: dimmed.green + (1 - dimmed.green) * w,
            blue: dimmed.blue + (1 - dimmed.blue) * w,
            alpha: config.coreAlpha
        )
    }

    /// The glow-sheath colour: the fully saturated cue hue at a low, intensity-scaled alpha so the halo
    /// bleeds colour outward without a hard silhouette.
    static func sheathRGBA(hex: String, intensity: Double, config: LaserScatterConfig = .default) -> RGBA {
        let c = components(hex: hex)
        return RGBA(red: c.red, green: c.green, blue: c.blue, alpha: config.sheathAlpha * clamp01(intensity))
    }

    // MARK: Geometry (metres)

    /// Glow-sheath cylinder radius for a given beam core radius.
    static func sheathRadius(coreRadiusMeters: Double, config: LaserScatterConfig = .default) -> Double {
        coreRadiusMeters * config.sheathRadiusFactor
    }
}

// MARK: - Volumetric spotlight beam (haze)

/// Tunable "look" constants for a spotlight's volumetric cone — the two visible layers (core + sheath),
/// modelled on `LaserScatterConfig`. The peak alphas are deliberately much lower than the laser's
/// because a spotlight is a wide cone, not a pencil beam: the same alpha would read as a solid block of
/// fog. The smoke tests pin only the *shape* of the mapping (gate/ordering/monotonicity/range), not
/// these values, so retuning from device previews is safe.
struct SpotBeamScatterConfig: Equatable {
    /// Peak sheath alpha at full intensity and a narrow cone (well below the laser sheath — the cone is
    /// far wider).
    var sheathAlpha: Double
    /// Core alpha (a touch above the sheath so the centre reads, still far below the laser core).
    var coreAlpha: Double
    /// How far the core hue lerps toward white (0 = pure hue, 1 = white).
    var coreWhiteness: Double
    /// Beam-angle alpha falloff: alpha ×= (1 - widthAlphaFalloff · normalizedWidth), where
    /// normalizedWidth = (outer - 10)/50 ∈ 0…1; a wider cone gets fainter so it doesn't read as a fog bank.
    var widthAlphaFalloff: Double
    /// Beam geometry length (model metres) — a fixed throw distance; tune on device to "cone tip → deck".
    var beamLengthMeters: Double

    static let `default` = SpotBeamScatterConfig(
        sheathAlpha: 0.06,
        coreAlpha: 0.10,
        coreWhiteness: 0.40,
        widthAlphaFalloff: 0.6,
        beamLengthMeters: 9.0
    )
}

/// Pure mapping from a spotlight cue's `#RRGGBB` + 0…1 intensity + beam angle → the numbers the
/// volumetric cone renderer needs for its two layers (core cone colour/alpha, sheath cone colour/alpha,
/// and the two cones' base radii). Foundation-only, `ImmersiveView` the only consumer. The layering
/// rationale is the laser's: the core is brighter and whiter, the sheath is wider and fainter so the
/// saturated hue bleeds out and the hard edge dies, letting the cone read as light in the air rather
/// than a solid cone. **No particles** (see root CLAUDE.md "haze particles removed").
enum SpotBeamScatterMath {
    /// A plain RGBA (0...1 per channel) so the math stays UIKit/RealityKit-free. Intentionally a separate
    /// copy of `LaserScatterMath.RGBA` so the two look-maths stay independently tunable.
    struct RGBA: Equatable { var red, green, blue, alpha: Double }

    /// The cone is fully hidden (core + sheath together) at or below this cue intensity, matching the
    /// laser `beamsVisible` gate.
    static func beamVisible(_ intensity: Double) -> Bool { intensity > 0.03 }

    private static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func components(hex: String) -> RGBComponents { RGBComponents(hex: hex) ?? .white }

    /// normalizedWidth ∈ 0…1, linear in the outer cone angle (10°…60°); used for alpha falloff.
    static func normalizedWidth(beamAngleDegrees: Double) -> Double {
        clamp01((SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees).outer - 10) / 50)
    }

    private static func widthScaledAlpha(_ base: Double, beamAngleDegrees: Double, intensity: Double,
                                         config: SpotBeamScatterConfig) -> Double {
        let w = normalizedWidth(beamAngleDegrees: beamAngleDegrees)
        return base * clamp01(intensity) * (1 - clamp01(config.widthAlphaFalloff) * w)
    }

    /// Core cone colour: cue hue dimmed by intensity, then lerped toward white; alpha scales with
    /// intensity and falls off with cone width.
    static func coreRGBA(hex: String, intensity: Double, beamAngleDegrees: Double,
                         config: SpotBeamScatterConfig = .default) -> RGBA {
        let d = components(hex: hex).dimmed(by: clamp01(intensity))
        let w = clamp01(config.coreWhiteness)
        return RGBA(red: d.red + (1 - d.red) * w, green: d.green + (1 - d.green) * w,
                    blue: d.blue + (1 - d.blue) * w,
                    alpha: widthScaledAlpha(config.coreAlpha, beamAngleDegrees: beamAngleDegrees,
                                            intensity: intensity, config: config))
    }

    /// Sheath cone colour: fully saturated cue hue at a low alpha (scaled by intensity and cone width).
    static func sheathRGBA(hex: String, intensity: Double, beamAngleDegrees: Double,
                           config: SpotBeamScatterConfig = .default) -> RGBA {
        let c = components(hex: hex)
        return RGBA(red: c.red, green: c.green, blue: c.blue,
                    alpha: widthScaledAlpha(config.sheathAlpha, beamAngleDegrees: beamAngleDegrees,
                                            intensity: intensity, config: config))
    }

    // MARK: Geometry (metres)

    /// Cone base radius (model metres) = length · tan(half-angle). The half-angle uses `coneAngles`'
    /// inner (core) / outer (sheath) so the visible cone lines up with the actual `SpotLight` cone.
    /// (The outer angle is treated as a half-angle for visual alignment — tune on device, see Caveats.)
    static func baseRadius(lengthMeters: Double, halfAngleDegrees: Double) -> Double {
        lengthMeters * tan(min(max(halfAngleDegrees, 1), 89) * .pi / 180)
    }
    static func coreBaseRadius(lengthMeters: Double, beamAngleDegrees: Double) -> Double {
        baseRadius(lengthMeters: lengthMeters,
                   halfAngleDegrees: SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees).inner)
    }
    static func sheathBaseRadius(lengthMeters: Double, beamAngleDegrees: Double) -> Double {
        baseRadius(lengthMeters: lengthMeters,
                   halfAngleDegrees: SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees).outer)
    }
}

// MARK: - Dynamic rig: fixture-type rendering metadata + zone placement

/// `LightingFixtureVisualModel` lives in the fixture catalog as the visual vocabulary; here it gains
/// the renderer-facing metadata (photometrics, optics, mounting) the dynamic rig needs, plus Codable
/// so it can persist on a `FixtureGroup`.
extension LightingFixtureVisualModel: Codable {}

extension LightingFixtureVisualModel {
    /// A sensible visual model for a legacy/role-only fixture so 2-role MVP looks still render real gear.
    static func derived(role: FixtureRole, zone: StageZone) -> LightingFixtureVisualModel {
        switch role {
        case .frontLight: return .frontFresnel
        case .backgroundWash: return .movingHeadBeam
        case .wash: return .washBar
        case .spot: return .spotBarrel
        }
    }

    /// A reasonable role for a fixture defined only by its visual model (the dynamic-rig direction:
    /// the AI picks a fixture *type*, and role becomes derived metadata used for fine-control defaults
    /// and the debug panel — it no longer gates rendering).
    var derivedRole: FixtureRole {
        switch self {
        case .frontFresnel, .ledFresnel, .audienceBlinder: return .frontLight
        case .spotBarrel, .movingHeadBeam, .laser: return .spot
        case .washBar, .ledStrobeBar, .ledPar: return .wash
        case .backgroundBatten: return .backgroundWash
        }
    }

    /// Peak luminous output (lumens) a fully-on fixture of this type emits. Tuned alongside the
    /// stage twin; only the mapping shape (clamp/endpoints/monotonicity) is pinned by tests.
    var maxLumens: Double {
        switch self {
        case .audienceBlinder: return 8000
        case .spotBarrel: return 7000
        case .frontFresnel: return 6000
        case .laser: return 5500   // intense but thin — the visible beam carries the look; the cone is a colour spill
        case .ledFresnel: return 5200
        case .movingHeadBeam: return 5000
        case .ledStrobeBar: return 5000
        case .washBar: return 4500
        case .ledPar: return 4500
        case .backgroundBatten: return 4000
        }
    }

    /// Front-facing key lights earn higher shadow quality; wash/effect fixtures stay medium.
    var isKeyLight: Bool {
        switch self {
        case .frontFresnel, .ledFresnel, .spotBarrel: return true
        default: return false
        }
    }

    /// Default full-cone beam spread (degrees) when a fixture doesn't carry its own beam angle.
    var defaultBeamDegrees: Double {
        switch self {
        case .laser: return 6     // a laser is a near-collimated pencil beam, the tightest fixture in the rig
        case .spotBarrel: return 18
        case .movingHeadBeam: return 22
        case .frontFresnel: return 35
        case .ledFresnel: return 30
        case .ledPar: return 40
        case .ledStrobeBar: return 55
        case .washBar: return 60
        case .backgroundBatten: return 70
        case .audienceBlinder: return 90
        }
    }

    /// The stage zone this fixture type is typically mounted in — drives `RigPlacement` and gives the
    /// AI a sensible default when it picks a fixture without stating a zone.
    var defaultMountZone: StageZone {
        switch self {
        case .frontFresnel, .ledFresnel, .spotBarrel, .audienceBlinder: return .stageFront
        case .washBar, .backgroundBatten, .movingHeadBeam, .ledStrobeBar, .laser: return .stageBack
        case .ledPar: return .fullStage
        }
    }
}

extension SpotLightRenderMath {
    /// Peak lumens by fixture visual model (the dynamic-rig replacement for the role-based overload).
    static func maxLumens(model: LightingFixtureVisualModel) -> Double { model.maxLumens }

    /// Maps a 0...1 cue intensity to spotlight lumens for a fixture model. Same clamp/shape as the
    /// role-based overload; 0 -> 0, 1 -> the model's peak.
    static func lumens(forIntensity intensity: Double, model: LightingFixtureVisualModel) -> Double {
        min(max(intensity, 0), 1) * model.maxLumens
    }
}

/// Foundation-only placement: where each fixture in a stage zone mounts and what it aims at, in model
/// metres, spreading `count` fixtures evenly across the zone. The renderer converts to scene space.
/// This generalizes the old hardcoded 2 FOH stands + 2 upstage moving heads to any fixture count.
enum RigPlacement {
    static func placement(zone: StageZone, slot: Int, count: Int, layout: StageLayout)
        -> (position: Vector3Meters, aim: Vector3Meters) {
        let stageBase = layout.objects.first { $0.type == .stageBase }
        let size = stageBase?.size ?? StageObjectSize(width: 6, depth: 3, height: 0.8)
        let centerX = stageBase?.position.x ?? 0
        let centerZ = stageBase?.position.z ?? 0
        let topY = (stageBase?.position.y ?? size.height / 2) + size.height / 2
        let upstageZ = layout.objects.flatMap(\.trussEndpoints).map(\.z).min() ?? (centerZ - size.depth / 2)
        let maxTrussY = layout.objects.flatMap(\.trussEndpoints).map(\.y).max() ?? (topY + 2)

        // Even spread fraction in -1...1 across the slots (0 when a single fixture).
        let spread = count <= 1 ? 0.0 : (Double(slot) / Double(count - 1)) * 2.0 - 1.0

        switch zone {
        case .stageFront:
            // Front-of-house stands in the audience area, aimed at the performer zone.
            let position = Vector3Meters(
                x: centerX + spread * size.width * 0.45,
                y: topY + 1.9,
                z: centerZ + size.depth * 0.95 + 0.7
            )
            let aim = Vector3Meters(x: centerX, y: topY + 0.05, z: centerZ + size.depth * 0.12)
            return (position, aim)

        case .stageBack, .fullStage:
            // Hung on the upstage truss, washing the stage / backdrop.
            let position = Vector3Meters(
                x: centerX + spread * size.width * 0.5,
                y: maxTrussY - 0.18,
                z: upstageZ + 0.08
            )
            let aim = Vector3Meters(
                x: centerX,
                y: topY + (maxTrussY - topY) * 0.45,
                z: upstageZ - 0.28
            )
            return (position, aim)

        case .stageLeft, .stageRight:
            // Side booms, spread along stage depth, aimed across the stage.
            let sideX = centerX + (zone == .stageLeft ? -1.0 : 1.0) * size.width * 0.55
            let position = Vector3Meters(
                x: sideX,
                y: topY + 1.2,
                z: centerZ + spread * size.depth * 0.35
            )
            let aim = Vector3Meters(x: centerX, y: topY + 0.4, z: centerZ)
            return (position, aim)
        }
    }

    /// Zone-derived `(position, aim)` for a fixture, with the position replaced by the fixture's
    /// `manualPosition` if it carries one (the aim stays zone-derived). The renderer (`ImmersiveView.syncRig`)
    /// and the tabletop editor both resolve placement through this single entry point so a user-dragged
    /// fixture lands at the same spot on the 1:1 stage and on the diorama.
    static func resolvedPlacement(fixture: FixtureGroup, slot: Int, count: Int, layout: StageLayout)
        -> (position: Vector3Meters, aim: Vector3Meters) {
        // 規定：雷射只能掛在上舞台桁架上。即使資料上被標成別的 zone（舊檔/AI 誤判），也一律用
        // .stageBack 的桁架幾何解析，且手動拖曳的位置會被夾回 truss footprint（見 clampedToTruss）。
        let trussOnly = mountsOnTrussOnly(fixture.renderModel)
        let zone = trussOnly ? .stageBack : fixture.zone
        let zonePlacement = placement(zone: zone, slot: slot, count: count, layout: layout)
        // SPEC 22: front/side key & spot aim nudges partially toward the user-placed performer (opt-in via
        // `layout.performerPosition`). Backlight/laser and a nil performerPosition are a byte-identical no-op,
        // so existing generation/music-show aim is unchanged. Only the aim is affected — never the position.
        let aim = performerNudgedAim(zoneAim: zonePlacement.aim, zone: zone,
                                     model: fixture.renderModel, layout: layout)
        guard let manual = fixture.manualPosition else {
            return (zonePlacement.position, aim)
        }
        var position = Vector3Meters(x: manual.x, y: manual.y, z: manual.z)
        if trussOnly {
            position = clampedToTruss(position, layout: layout)
        }
        return (position, aim)
    }

    /// The stage-centre point (model metres) the tabletop "瞄準舞台中心" button aims a fixture at: the deck
    /// centre lifted to a performer's torso height (matching the side-boom zone aim's `topY + 0.4`), so a
    /// re-aimed light lands on someone standing centre stage rather than on the deck surface.
    static func stageCenterTarget(layout: StageLayout) -> Vector3Meters {
        let stageBase = layout.objects.first { $0.type == .stageBase }
        let size = stageBase?.size ?? StageObjectSize(width: 6, depth: 3, height: 0.8)
        let centerX = stageBase?.position.x ?? 0
        let centerZ = stageBase?.position.z ?? 0
        let topY = (stageBase?.position.y ?? size.height / 2) + size.height / 2
        return Vector3Meters(x: centerX, y: topY + 0.4, z: centerZ)
    }
}

// MARK: - SPEC 22: performer-aware aim nudge (partial blend, opt-in, front/side only)

extension RigPlacement {
    /// 前光/spot aim 朝表演者微調的比例（0＝純 zone aim，1＝完全對準人偶）。初值 0.5，永遠 < 1（微調而非
    /// 接管）；實機微調（見 SPEC 22 Caveats——0.5 是否把 FOH 打歪、側 boom 追蹤是否過頭需實機驗）。
    static let performerAimNudgeFraction = 0.5

    /// 哪些 zone 的 aim 會追蹤表演者：只有「前打/側打的 key/spot」。背景洗（`.stageBack`/`.fullStage`）與
    /// 雷射（truss-only）維持 zone aim，確保既有生成／音樂秀「洗背板」的打光方向完全不變。
    static func aimTracksPerformer(zone: StageZone, model: LightingFixtureVisualModel) -> Bool {
        guard !mountsOnTrussOnly(model) else { return false }   // 雷射不受影響
        switch zone {
        case .stageFront, .stageLeft, .stageRight: return true
        case .stageBack, .fullStage:               return false
        }
    }

    /// 把 zone 推算的 aim 朝 layout 的 `performerPosition` **部分 blend**（lerp fraction），且只對
    /// `aimTracksPerformer` 為真的 fixture。`performerPosition` 為 nil 或非追蹤 zone → **原樣回傳**（byte-identical
    /// no-op）。這是「微調而非接管」：blend 分量固定 < 1，且 opt-in（沒放人偶就完全無作用），既有打光方向不被破壞。
    static func performerNudgedAim(zoneAim: Vector3Meters, zone: StageZone,
                                   model: LightingFixtureVisualModel, layout: StageLayout) -> Vector3Meters {
        guard let target = layout.performerPosition,
              aimTracksPerformer(zone: zone, model: model) else { return zoneAim }
        let f = performerAimNudgeFraction
        return Vector3Meters(
            x: zoneAim.x + (target.x - zoneAim.x) * f,
            y: zoneAim.y + (target.y - zoneAim.y) * f,
            z: zoneAim.z + (target.z - zoneAim.z) * f
        )
    }
}

/// Foundation-only：一盞燈在解析位置上如何被物理支撐，讓場上沒有燈浮空。
/// 位置（model 公尺）水平落在 truss footprint 內、且離地夠高 → 吊掛在 truss；否則 → 從地板長出落地燈架。
enum FixtureSupport: Equatable {
    case hangFromTruss
    /// 從 y = 0 到 `topY`（model 公尺）在燈具的 XZ 立一根落地燈架柱。
    case floorStand(topY: Double)

    var isFloorStand: Bool { if case .floorStand = self { return true }; return false }
}

extension RigPlacement {
    /// 可調常數（實機微調，見 spec Caveats）
    static let trussHangMarginMeters = 0.35   // footprint XZ 外擴；小值避免側台 boom 誤判吊掛
    static let hangMinAboveDeckMeters = 1.0    // 低於此高度即使在 footprint 下也算落地（避免地面燈被判吊掛）
    static let standTopGapMeters = 0.18        // 柱頂距燈底留隙（沿用 FOH columnTopY 的 0.18）

    /// 規定：只能吊掛在桁架上、不可落地的燈具型號。目前只有雷射 — 它是全場唯一有可見光束幾何的燈，
    /// 落地或側台會顯得突兀，且安全上雷射本就該高掛。`resolvedPlacement`/`AppModel` 以此夾住雷射位置。
    static func mountsOnTrussOnly(_ model: LightingFixtureVisualModel) -> Bool {
        model == .laser
    }

    /// 把一個位置（model 公尺）夾進桁架 footprint 的 XZ 範圍內，並吊到桁架頂下方 `standTopGapMeters`，
    /// 使 `support(forPosition:)` 必定回傳 `.hangFromTruss`。無桁架時原樣返回（無處可掛，交給 support 落地）。
    static func clampedToTruss(_ position: Vector3Meters, layout: StageLayout) -> Vector3Meters {
        guard let f = trussFootprint(in: layout) else { return position }
        return Vector3Meters(
            x: min(max(position.x, f.minX), f.maxX),
            y: f.topY - standTopGapMeters,
            z: min(max(position.z, f.minZ), f.maxZ)
        )
    }

    /// 所有 truss 端點的 XZ 包圍盒 + 頂高（model 公尺），無 truss 則 nil。
    static func trussFootprint(in layout: StageLayout)
        -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double, topY: Double)? {
        let pts = layout.objects.flatMap(\.trussEndpoints)
        guard !pts.isEmpty else { return nil }
        return (pts.map(\.x).min()!, pts.map(\.x).max()!,
                pts.map(\.z).min()!, pts.map(\.z).max()!,
                pts.map(\.y).max()!)
    }

    /// 甲板頂面高度（model 公尺），與 `placement`/`support` 用同一套 stageBase 推法。吊掛/落地門檻都以此為基準。
    static func deckTopY(in layout: StageLayout) -> Double {
        let stageBase = layout.objects.first { $0.type == .stageBase }
        let size = stageBase?.size ?? StageObjectSize(width: 6, depth: 3, height: 0.8)
        return (stageBase?.position.y ?? size.height / 2) + size.height / 2
    }

    /// XZ 是否落在 truss footprint±`trussHangMarginMeters` 內（吊掛的水平條件，與 `support` 同一判準）。
    /// 無 truss → false。抽成共用函式，讓 `support` 與 `resolvedDragPosition` 共用同一組門檻常數、不重複一份。
    static func isWithinTrussFootprint(x: Double, z: Double, layout: StageLayout) -> Bool {
        guard let f = trussFootprint(in: layout) else { return false }
        let m = trussHangMarginMeters
        return x >= f.minX - m && x <= f.maxX + m && z >= f.minZ - m && z <= f.maxZ + m
    }

    /// 一盞燈在解析位置的支撐方式。吊掛需同時：XZ 在 footprint±margin 內、且離甲板 >= hangMinAboveDeck。
    static func support(forPosition position: Vector3Meters, layout: StageLayout) -> FixtureSupport {
        let topY = deckTopY(in: layout)
        if isWithinTrussFootprint(x: position.x, z: position.z, layout: layout),
           position.y >= topY + hangMinAboveDeckMeters {
            return .hangFromTruss
        }
        return .floorStand(topY: max(0.3, position.y - standTopGapMeters))
    }

    /// #19 Option A：桌面編輯器把一盞燈拖到某個 XZ 時應提交的 (x, y, z)（model 公尺）——用拖曳落點的 XZ 決定 Y：
    /// - XZ 落在 truss footprint±margin 內 → Y 吸附到桁架吊掛高度（`clampedToTruss` 同款 `topY - standTopGap`），
    ///   使 `support` 對結果回傳 `.hangFromTruss`（真的吊上桁架，不再浮在半空）。
    /// - 否則 → Y 落到落地燈架高度（甲板頂 + `hangMinAboveDeckMeters`），使 `support` 回傳 `.floorStand`。
    /// 只吃 XZ、Y 由 XZ 決定 → idempotent（把結果的 XZ 餵回來得到同一個 Y）。無 truss 時一律落地。
    /// 判定沿用 `support` 的 footprint 測試與門檻常數（`isWithinTrussFootprint` / `trussFootprint` / 那三個
    /// 可調常數），不另立一份 ±0.35／1.0m。
    static func resolvedDragPosition(x: Double, z: Double, layout: StageLayout) -> Vector3Meters {
        if isWithinTrussFootprint(x: x, z: z, layout: layout), let f = trussFootprint(in: layout) {
            return Vector3Meters(x: x, y: f.topY - standTopGapMeters, z: z)
        }
        return Vector3Meters(x: x, y: deckTopY(in: layout) + hangMinAboveDeckMeters, z: z)
    }

    /// Mirrors a fixture across the stage centerline (x=0) for symmetrical rigs.
    /// Flips the manual position X and the pan offset, preserving all other properties.
    static func mirroredAcrossCenterline(_ fixture: FixtureGroup) -> FixtureGroup {
        var copy = fixture
        if let manual = copy.manualPosition {
            copy.manualPosition = FixturePosition(x: -manual.x, y: manual.y, z: manual.z)
        }
        if let aim = copy.aimOffset {
            copy.aimOffset = FixtureAimOffset(panDegrees: -aim.panDegrees, tiltDegrees: aim.tiltDegrees)
        }
        return copy
    }
}

extension LightingLook {
    /// 規定：雷射燈只能吊在上舞台桁架上。把每個 cue 裡雷射燈的 `zone` 正規化為 `.stageBack`，讓 slot 分組
    /// 與 `RigPlacement` 一律把它掛在 truss。與 layout 無關（只改資料上的 zone）——手動拖曳造成的 off-truss
    /// `manualPosition` 由 `RigPlacement.resolvedPlacement`/`AppModel.moveFixture` 夾回 truss。所有生成路徑
    /// 在 `LightingLookDraft.makeValidatedLook` 套用此正規化；`showcaseDemo`/`MusicShowBuilder` 已把雷射放在
    /// `.stageBack`，故此處對它們是 no-op。Idempotent。
    func enforcingTrussMountedLasers() -> LightingLook {
        var result = self
        result.cues = cues.map { cue in
            var newCue = cue
            newCue.fixtureGroups = cue.fixtureGroups.map { fixture in
                guard RigPlacement.mountsOnTrussOnly(fixture.renderModel), fixture.zone != .stageBack else {
                    return fixture
                }
                var moved = fixture
                moved.zone = .stageBack
                return moved
            }
            return newCue
        }
        return result
    }
}

enum ValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(String)
    case unsupportedAmbientPreset(String)
    case unsupportedColorMode(String)
    case missingRequiredCue
    case cannotRemoveLastCue
    case missingCue(String)
    case missingFixture(String)
    case invalidIntensity(Double)
    case invalidHexColor(String)
    case invalidFineControlValue(String, Double)
    case invalidDMXValue(String, Int)
    case invalidHoldDuration(Double)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "不支援的結構描述版本：\(version)"
        case .unsupportedAmbientPreset(let preset):
            return "不支援的環境光預設：\(preset)"
        case .unsupportedColorMode(let mode):
            return "不支援的顏色模式：\(mode)"
        case .missingRequiredCue:
            return "燈光設計至少需要一個場景。"
        case .cannotRemoveLastCue:
            return "至少需要保留一個場景，無法刪除最後一個場景。"
        case .missingCue(let id):
            return "找不到場景：\(id)"
        case .missingFixture(let role):
            return "找不到燈具角色：\(role)"
        case .invalidIntensity(let intensity):
            return "亮度必須介於 0.0 與 1.0 之間。目前值：\(intensity)。"
        case .invalidHexColor(let value):
            return "無效的 RGB 十六進位色值：\(value)"
        case .invalidFineControlValue(let field, let value):
            return "無效的精細控制參數：\(field)=\(value)。"
        case .invalidDMXValue(let field, let value):
            return "無效的 DMX 參數：\(field)=\(value)。"
        case .invalidHoldDuration(let value):
            return "無效的場景停留時間：\(value) 秒。"
        }
    }
}
