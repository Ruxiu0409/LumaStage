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

    /// Roles the visionOS renderer currently realizes as real spotlights (and can therefore
    /// project a gobo through). The other roles aren't rendered yet, so a gobo on them would be
    /// a silent no-op — `LightingLookDraft` clears gobos on non-rendering roles so persisted
    /// state never claims a projection that won't appear.
    var rendersProjectedGobo: Bool {
        self == .frontLight || self == .backgroundWash
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
/// Mirrored by `GeneratedLightingLook.GeneratedGobo` in the on-device `@Generable` schema and
/// rendered via `SpotLightComponent.ProjectiveTexture` in `ImmersiveView`.
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

    static let mvpDefault = CueTransition(duration: 1.2, easing: "easeInOut")
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7, trimmed.first == "#" else {
            return nil
        }

        let hex = String(trimmed.dropFirst())
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hex.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
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

    var effectiveFineControl: FixtureFineControl {
        fineControl ?? .default(role: role, zone: zone)
    }
}

struct LightingCue: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var transition: CueTransition
    var fixtureGroups: [FixtureGroup]

    var localizedDisplayName: String {
        switch name {
        case "Opening":
            return "Opening"
        case "Highlight":
            return "Highlight"
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
}

struct LightingExplanation: Codable, Equatable {
    var term: String
    var plainText: String
    var actionSummary: String
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
            lookName: "Warm Opening Lighting",
            mood: "Warm, welcoming, student showcase",
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
                            name: "Front Wash",
                            role: .frontLight,
                            zone: .stageFront,
                            enabled: true,
                            intensity: 0.6,
                            color: FixtureColor(mode: .rgb, value: "#FFD1A3")
                        ),
                        FixtureGroup(
                            id: "background_wash",
                            name: "Background Wash",
                            role: .backgroundWash,
                            zone: .stageBack,
                            enabled: true,
                            intensity: 0.75,
                            color: FixtureColor(mode: .rgb, value: "#4FA8FF")
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
                            name: "Front Wash",
                            role: .frontLight,
                            zone: .stageFront,
                            enabled: true,
                            intensity: 0.75,
                            color: FixtureColor(mode: .rgb, value: "#FFE0B8")
                        ),
                        FixtureGroup(
                            id: "background_wash",
                            name: "Background Wash",
                            role: .backgroundWash,
                            zone: .stageBack,
                            enabled: true,
                            intensity: 0.9,
                            color: FixtureColor(mode: .rgb, value: "#2F6BFF")
                        )
                    ]
                )
            ],
            explanation: LightingExplanation(
                term: "Intensity",
                plainText: "Intensity describes how strong the light output is. A 60% front light keeps performers visible without overpowering the background wash.",
                actionSummary: "Generated Opening and Highlight cues with warm front light and cool background wash contrast."
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

        let cueIds = Set(cues.map(\.id))
        guard cueIds.contains("cue_opening"), cueIds.contains("cue_highlight") else {
            throw ValidationError.missingRequiredCue
        }

        guard cueIds.contains(selectedCueId) else {
            throw ValidationError.missingCue(selectedCueId)
        }

        for cue in cues {
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

    static func defaultProjects() -> [LumaStageProject] {
        []
    }

    static func demoProjects() -> [LumaStageProject] {
        [
            LumaStageProject(
                id: "project_campus_music_night",
                name: "Campus Music Night",
                venueDescription: "Outdoor student stage",
                eventType: "Student Performance",
                lastEditedDescription: "Demo Project",
                stageLayout: .defaultStudentOutdoor(),
                lightingLook: look(
                    name: "Warm Opening Lighting",
                    mood: "Warm, welcoming, student showcase"
                )
            ),
            LumaStageProject(
                id: "project_club_showcase",
                name: "Club Showcase",
                venueDescription: "Outdoor truss stage",
                eventType: "Club Presentation",
                lastEditedDescription: "Ready to Preview",
                stageLayout: .defaultStudentOutdoor(),
                lightingLook: look(
                    name: "Cool Showcase Lighting",
                    mood: "Cool, focused, student showcase"
                )
            ),
            LumaStageProject(
                id: "project_graduation_party",
                name: "Graduation Party",
                venueDescription: "Night outdoor stage",
                eventType: "Celebration",
                lastEditedDescription: "Draft Lighting",
                stageLayout: .defaultStudentOutdoor(),
                lightingLook: look(
                    name: "Party Highlight Lighting",
                    mood: "Bright, celebratory, outdoor event"
                )
            )
        ]
    }

    static func newProject(index: Int) -> LumaStageProject {
        newProject(index: index, template: .blank)
    }

    static func newProject(index: Int, template: ProjectCreationTemplate.Kind) -> LumaStageProject {
        let template = ProjectCreationTemplate.template(for: template)

        return LumaStageProject(
            id: "project_custom_\(UUID().uuidString)",
            name: "\(template.projectName) \(index)",
            venueDescription: template.venueDescription,
            eventType: template.eventType,
            lastEditedDescription: "New Project",
            stageLayout: .defaultStudentOutdoor(),
            lightingLook: look(name: template.lookName, mood: template.mood)
        )
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
        case blank
        case campusMusic
        case clubShowcase
        case graduationParty
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

    static let allTemplates: [ProjectCreationTemplate] = [
        ProjectCreationTemplate(
            kind: .blank,
            title: "Blank Project",
            subtitle: "Start with a basic outdoor stage, then adjust stage and lighting manually.",
            introduction: "Best when you already know what you want to build. LumaStage prepares only the stage base and basic truss, so fixtures, cues, and mood can be configured inside the project.",
            systemImage: "square.dashed",
            visualStyle: .emptyStage,
            projectName: "Untitled Project",
            venueDescription: "Outdoor student stage",
            eventType: "Student Showcase",
            lookName: "Opening Lighting",
            mood: "To be designed, fully adjustable"
        ),
        ProjectCreationTemplate(
            kind: .campusMusic,
            title: "Campus Music Night",
            subtitle: "For bands, vocals, and club nights, with a warm opening and performer focus.",
            introduction: "Designed for an outdoor evening performance. Front light keeps performers clear, while warm and blue background layers suit student bands, singing contests, and small concerts.",
            systemImage: "music.mic",
            visualStyle: .warmConcert,
            projectName: "Campus Music Night",
            venueDescription: "Outdoor student stage",
            eventType: "Student Performance",
            lookName: "Warm Opening Lighting",
            mood: "Warm, welcoming, student showcase"
        ),
        ProjectCreationTemplate(
            kind: .clubShowcase,
            title: "Club Showcase",
            subtitle: "For multi-act programs, with clear front light and a cool background.",
            introduction: "Built for dance, theater, and club presentation programs with multiple segments. The template keeps front light stable so performers remain readable between scenes.",
            systemImage: "person.3.sequence",
            visualStyle: .coolShowcase,
            projectName: "Club Showcase",
            venueDescription: "Outdoor truss stage",
            eventType: "Club Presentation",
            lookName: "Cool Showcase Lighting",
            mood: "Cool, focused, student showcase"
        ),
        ProjectCreationTemplate(
            kind: .graduationParty,
            title: "Graduation Party",
            subtitle: "For post-ceremony moments and party sections, with bright celebratory cues.",
            introduction: "Designed for post-ceremony highlights, raffles, performances, and group photos. Higher intensity and celebratory colors make the stage feel like a finale.",
            systemImage: "sparkles",
            visualStyle: .partyFinale,
            projectName: "Graduation Party",
            venueDescription: "Night outdoor stage",
            eventType: "Celebration",
            lookName: "Party Highlight Lighting",
            mood: "Bright, celebratory, outdoor event"
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
                term: "Intensity",
                plainText: "Intensity is the industry term for how strong a fixture output is. Setting front light to \(Int(round(intensity * 100)))% makes the performer-facing light use that output level.",
                actionSummary: "Adjusted the front light intensity for the current cue."
            )

        case .backgroundWashColor(let hexColor):
            guard let normalizedHex = FixtureColor.normalizedHex(hexColor) else {
                throw ValidationError.invalidHexColor(hexColor)
            }

            try mutateFixture(role: .backgroundWash, inCueAt: cueIndex) { fixture in
                fixture.color.value = normalizedHex
            }
            lightingLook.explanation = LightingExplanation(
                term: "Background Wash",
                plainText: "A background wash is a broad area of colored light placed behind the stage or on the backdrop. Changing its color directly shifts the stage mood.",
                actionSummary: "Adjusted the background wash color for the current cue."
            )

        case .fixtureIntensity(let fixtureId, let intensity):
            guard (0.0...1.0).contains(intensity) else {
                throw ValidationError.invalidIntensity(intensity)
            }

            try mutateFixture(id: fixtureId, inCueAt: cueIndex) { fixture in
                fixture.intensity = intensity
            }
            lightingLook.explanation = LightingExplanation(
                term: "Fixture Intensity",
                plainText: "Fine Control directly edits the selected fixture in the current cue, without changing matching fixtures in other cues.",
                actionSummary: "Adjusted the selected fixture intensity."
            )

        case .fixtureColor(let fixtureId, let hexColor):
            guard let normalizedHex = FixtureColor.normalizedHex(hexColor) else {
                throw ValidationError.invalidHexColor(hexColor)
            }

            try mutateFixture(id: fixtureId, inCueAt: cueIndex) { fixture in
                fixture.color.value = normalizedHex
            }
            lightingLook.explanation = LightingExplanation(
                term: "Fixture Color",
                plainText: "The color picker applies an RGB hex value to the selected fixture in the current cue, making single-source visual tweaks precise.",
                actionSummary: "Adjusted the selected fixture color."
            )

        case .fixtureFineControl(let fixtureId, let control):
            try control.validate()
            try mutateFixture(id: fixtureId, inCueAt: cueIndex) { fixture in
                fixture.fineControl = control
            }
            lightingLook.explanation = LightingExplanation(
                term: "Fixture Angle and Position",
                plainText: "Position, pan, tilt, roll, and beam angle are stored on the selected fixture in the current cue for synchronized MR fine control.",
                actionSummary: "Updated the selected fixture position, rotation, and beam angle."
            )
        }

        try lightingLook.validate()
    }

    mutating func resetSelectedCue() throws {
        let selectedCueId = selectedCueId
        let baselineCue = try baselineLook.requireCue(id: selectedCueId)
        guard let cueIndex = lightingLook.cues.firstIndex(where: { $0.id == selectedCueId }) else {
            throw ValidationError.missingCue(selectedCueId)
        }

        lightingLook.cues[cueIndex] = baselineCue
        lightingLook.explanation = LightingExplanation(
            term: "Cue Baseline",
            plainText: "Reset only returns the current cue to the AI-generated baseline and does not affect the other cue.",
            actionSummary: "Reset the current cue to its generated baseline."
        )

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
}

enum ValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(String)
    case unsupportedAmbientPreset(String)
    case unsupportedColorMode(String)
    case missingRequiredCue
    case missingCue(String)
    case missingFixture(String)
    case invalidIntensity(Double)
    case invalidHexColor(String)
    case invalidFineControlValue(String, Double)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported schema version: \(version)"
        case .unsupportedAmbientPreset(let preset):
            return "Unsupported ambient preset: \(preset)"
        case .unsupportedColorMode(let mode):
            return "Unsupported color mode: \(mode)"
        case .missingRequiredCue:
            return "Opening and Highlight cues are required."
        case .missingCue(let id):
            return "Cue not found: \(id)"
        case .missingFixture(let role):
            return "Fixture role not found: \(role)"
        case .invalidIntensity(let intensity):
            return "Intensity must be between 0.0 and 1.0. Current value: \(intensity)."
        case .invalidHexColor(let value):
            return "Invalid RGB hex color: \(value)"
        case .invalidFineControlValue(let field, let value):
            return "Invalid Fine Control parameter: \(field)=\(value)."
        }
    }
}
