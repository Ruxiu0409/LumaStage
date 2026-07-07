import Foundation

// MARK: - Generation contract

/// Anything that can turn a natural-language prompt into a validated `LightingLook`.
///
/// The concrete implementation is `OpenAILightingService` (cloud OpenAI Responses API).
/// This protocol and the supporting value types stay Foundation-only on purpose so the
/// headless smoke tests can exercise the AI → domain boundary without a live network call.
protocol LightingLookGenerating {
    /// Whether the underlying model can currently produce a look.
    var availability: LightingModelAvailability { get }

    /// Generate a fully validated `LightingLook` from a user prompt.
    func generateLook(from prompt: String) async throws -> LightingGenerationResult
}

/// Injectable network boundary for cloud backends (e.g. `OpenAILightingService`).
///
/// Mirrors `URLSession.data(for:)` so the default production wiring is a thin closure over
/// `URLSession.shared`, while the headless smoke tests can inject a stub that returns a fixed
/// `(Data, URLResponse)`. Kept Foundation-only here — same injectable-boundary pattern as
/// `LightingLookGenerating` / `LumaSyncTransport` — so cloud services stay in the smoke compile set.
typealias HTTPSend = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Foundation-only mirror of `SystemLanguageModel.Availability` so views and `AppModel`
/// can render the "Apple Intelligence unavailable" state without importing FoundationModels.
enum LightingModelAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    /// User-facing reason when generation is blocked, otherwise `nil`.
    var unavailableReason: String? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}

enum LightingGenerationSource: String, Equatable {
    case foundationModels
    case openAI

    var displayName: String {
        switch self {
        case .foundationModels:
            return "Apple Foundation Models"
        case .openAI:
            return "OpenAI（雲端）"
        }
    }
}

struct LightingGenerationResult: Equatable {
    var look: LightingLook
    var source: LightingGenerationSource
}

enum LightingGenerationError: Error, LocalizedError, Equatable {
    case modelUnavailable(String)
    case emptyPrompt
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return "Apple Intelligence 無法使用：\(reason)"
        case .emptyPrompt:
            return "請先輸入燈光需求。"
        case .generationFailed(let message):
            return message
        }
    }
}

// MARK: - AI → domain assembler

/// Plain, testable representation of a model-generated look.
///
/// The `@Generable` type the model fills in (see `FoundationModelsLightingService`) maps
/// into this draft, which then assembles a `LightingLook` and runs the same
/// `LightingLook.validate()` invariants the rest of the app relies on. Keeping the
/// assembly here (Foundation-only) is what lets the smoke tests cover it headlessly.
struct LightingLookDraft: Equatable {
    struct Fixture: Equatable {
        var id: String
        var name: String
        var role: FixtureRole
        var zone: StageZone
        var enabled: Bool
        var intensity: Double
        var colorHex: String
        var gobo: GoboPattern? = nil
        /// The physical fixture type (dynamic rig). Optional + back-compat: nil falls back to a model
        /// derived from `role` when assembled. `beamAngleDegrees` likewise carries the per-fixture beam.
        var model: LightingFixtureVisualModel? = nil
        var beamAngleDegrees: Double? = nil
        /// An AI-authored dynamic movement for this fixture in this cue (sweep/circle/strobe/chase).
        /// Optional + back-compat: nil means "no authored movement", so the renderer falls back to the
        /// per-type deterministic default in `LightEffectPlan`.
        var effect: LightEffect? = nil
    }

    var lookName: String
    var mood: String
    var openingFixtures: [Fixture]
    var highlightFixtures: [Fixture]
    var explanationTerm: String
    var explanationPlainText: String
    var explanationActionSummary: String
    /// A short teaching rationale carried through to `LightingExplanation.rationale`. Additive +
    /// back-compat: defaults to "" so existing `LightingLookDraft(...)` construction sites stay valid.
    var explanationRationale: String = ""

    /// Builds a `LightingLook` with the fixed MVP cue identity (`cue_opening` / `cue_highlight`),
    /// `standardNight` ambient baseline, and default transitions, then validates it.
    /// Cue ids and names are assigned here — not taken from the model — so the required-cue
    /// invariant always holds; only fixture content, mood, name, and explanation come from the model.
    func makeValidatedLook() throws -> LightingLook {
        let look = LightingLook(
            schemaVersion: "1.0",
            intent: .generateLook,
            lookName: lookName,
            mood: mood,
            ambient: AmbientState(preset: .standardNight, level: 0.35, colorTemperature: 4200),
            selectedCueId: "cue_opening",
            cues: [
                LightingCue(
                    id: "cue_opening",
                    name: "Opening",
                    transition: .mvpDefault,
                    fixtureGroups: openingFixtures.map(Self.fixtureGroup(from:))
                ),
                LightingCue(
                    id: "cue_highlight",
                    name: "Highlight",
                    transition: .mvpDefault,
                    fixtureGroups: highlightFixtures.map(Self.fixtureGroup(from:))
                )
            ],
            explanation: LightingExplanation(
                term: explanationTerm,
                plainText: explanationPlainText,
                actionSummary: explanationActionSummary,
                rationale: explanationRationale
            )
        )

        // 規定：雷射只能掛在上舞台桁架上。所有生成路徑（on-device staged、cloud DTO、fallback）都經過
        // 這個組裝器，所以在此把每盞雷射的 zone 正規化為 .stageBack（idempotent；demo/music show 已合規）。
        let normalized = look.enforcingTrussMountedLasers()
        try normalized.validate()
        return normalized
    }

    /// One named cue in a multi-cue show: an id, a display name, and the rig's per-cue fixture states.
    /// (The fixtures across a look's cues share ids/order — rig identity — so the same physical light is
    /// addressable in every cue.)
    struct Cue: Equatable {
        var id: String
        var name: String
        var fixtures: [Fixture]
    }

    /// Builds a multi-cue `LightingLook` from an ordered cue list — the AI's "describe the whole show →
    /// a sequence of cues" path (and the manual cue-stack editor). The first cue is selected; ambient
    /// baseline + transitions are pinned here, cue ids/names come from the caller, and `validate()` runs
    /// the same invariants. Foundation-only so the smoke tests pin the multi-cue assembly without the
    /// on-device model. The two-cue `makeValidatedLook()` above still backs templates and legacy looks.
    static func makeValidatedLook(
        lookName: String,
        mood: String,
        cues: [Cue],
        explanationTerm: String,
        explanationPlainText: String,
        explanationActionSummary: String,
        explanationRationale: String = ""
    ) throws -> LightingLook {
        let lightingCues = cues.map { cue in
            LightingCue(
                id: cue.id,
                name: cue.name,
                transition: .mvpDefault,
                fixtureGroups: cue.fixtures.map(Self.fixtureGroup(from:))
            )
        }

        let look = LightingLook(
            schemaVersion: "1.0",
            intent: .generateLook,
            lookName: lookName,
            mood: mood,
            ambient: AmbientState(preset: .standardNight, level: 0.35, colorTemperature: 4200),
            selectedCueId: lightingCues.first?.id ?? "cue_opening",
            cues: lightingCues,
            explanation: LightingExplanation(
                term: explanationTerm,
                plainText: explanationPlainText,
                actionSummary: explanationActionSummary,
                rationale: explanationRationale
            )
        )

        // 規定：雷射只能掛在上舞台桁架上。所有生成路徑（on-device staged、cloud DTO、fallback）都經過
        // 這個組裝器，所以在此把每盞雷射的 zone 正規化為 .stageBack（idempotent；demo/music show 已合規）。
        let normalized = look.enforcingTrussMountedLasers()
        try normalized.validate()
        return normalized
    }

    // MARK: - Staged (define-once rig + per-cue state matrix) assembly

    /// One fixture in a define-once rig, carrying NO per-cue state. Its `id` is assigned by the
    /// staged assembler and reused verbatim in every cue, so the same physical light stays
    /// addressable across the whole show (rig identity).
    struct RigFixture: Equatable {
        var id: String
        var name: String
        var role: FixtureRole
        var zone: StageZone
        /// nil → the fixture's `renderModel` is derived from `role`/`zone` (the existing fallback).
        var model: LightingFixtureVisualModel? = nil
    }

    /// One fixture's state in a single cue (the Foundation-only mirror of the model's per-cue
    /// `GeneratedFixtureState`: whether it's on, how bright, and its RGB hex colour).
    struct StagedState: Equatable {
        var enabled: Bool
        var intensity: Double
        var colorHex: String
    }

    /// Assembles a multi-cue `LightingLook` from a rig defined ONCE plus a per-cue state matrix.
    ///
    /// This is the staged-generation path (SPEC 14): the on-device model designs the rig skeleton in one
    /// pass and each cue's states in a separate bounded pass, so the assembly here re-joins them. The rig
    /// is the single source of fixture identity — `rig[j]`'s `id/name/role/zone/model` is reused in EVERY
    /// cue — while `cueStates[c][j]` supplies fixture `j`'s state in cue `c`. Cue ids are pinned to
    /// `cue_0`, `cue_1`, … here (never taken from the model), then the existing
    /// `makeValidatedLook(lookName:mood:cues:…)` runs the same `validate()` invariants.
    ///
    /// Count drift is reconciled defensively, mirroring `makeValidatedLook`'s tolerance so a
    /// slightly-off-count generation still assembles a valid show and a degenerate input never crashes:
    /// - A state row shorter than the rig reuses its LAST entry for the missing fixtures; an EMPTY row
    ///   makes that whole cue dark (every fixture `enabled: false`).
    /// - A state row longer than the rig ignores the extra entries.
    /// - Fewer `cueStates` rows than `cueNames` treats the missing cues as empty rows (all off); extra
    ///   `cueStates` rows are ignored.
    /// Every `colorHex` self-heals through `FixtureColor.normalizedHex(...) ?? "#FFFFFF"` at this boundary,
    /// so one un-normalizable colour dims a single light rather than failing the whole look.
    static func makeValidatedStagedLook(
        lookName: String,
        mood: String,
        rig: [RigFixture],
        cueNames: [String],
        cueStates: [[StagedState]],
        explanationTerm: String,
        explanationPlainText: String,
        explanationActionSummary: String,
        explanationRationale: String
    ) throws -> LightingLook {
        // Always build at least one cue so `makeValidatedLook`'s `selectedCueId` resolves; an empty
        // `rig` yields cues with no fixtures, which `validate()` accepts (no fixture-count minimum).
        let cueCount = max(cueNames.count, 1)

        let draftCues: [Cue] = (0..<cueCount).map { cueIndex in
            let rawName = cueIndex < cueNames.count ? cueNames[cueIndex] : ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Cue \(cueIndex + 1)"
                : rawName

            // The state row for this cue (missing rows / rows past the end are treated as empty → all off).
            let row = cueIndex < cueStates.count ? cueStates[cueIndex] : []

            let fixtures: [Fixture] = rig.enumerated().map { fixtureIndex, rigFixture in
                let state = Self.resolvedStagedState(for: fixtureIndex, in: row)
                return Fixture(
                    id: rigFixture.id,
                    name: rigFixture.name,
                    role: rigFixture.role,
                    zone: rigFixture.zone,
                    enabled: state.enabled,
                    intensity: state.intensity,
                    colorHex: FixtureColor.normalizedHex(state.colorHex) ?? "#FFFFFF",
                    model: rigFixture.model
                )
            }

            return Cue(id: "cue_\(cueIndex)", name: name, fixtures: fixtures)
        }

        return try Self.makeValidatedLook(
            lookName: lookName,
            mood: mood,
            cues: draftCues,
            explanationTerm: explanationTerm,
            explanationPlainText: explanationPlainText,
            explanationActionSummary: explanationActionSummary,
            explanationRationale: explanationRationale
        )
    }

    /// Picks fixture `fixtureIndex`'s state from a single cue's state `row`, reconciling count drift:
    /// an empty row means the fixture is off; a short row reuses its last entry; a long row's extras are
    /// unreachable (only indices `< rig.count` are ever requested). `colorHex` is self-healed later.
    private static func resolvedStagedState(for fixtureIndex: Int, in row: [StagedState]) -> StagedState {
        guard let last = row.last else {
            // Empty row → whole cue dark for this fixture.
            return StagedState(enabled: false, intensity: 0, colorHex: "#000000")
        }
        if fixtureIndex < row.count {
            return row[fixtureIndex]
        }
        // Short row → reuse the last supplied entry for the trailing fixtures.
        return last
    }

    private static func fixtureGroup(from fixture: Fixture) -> FixtureGroup {
        // Carry the per-fixture beam angle when the model supplied one (dynamic rig); otherwise the
        // role/zone default applies. Every rig fixture renders now, so the gobo is kept regardless.
        // Values are NOT clamped here — `LightingLook.validate()` stays the single gate that rejects
        // out-of-range intensity/beam (the @Generable `.range` guides keep the model in bounds).
        var fineControl = FixtureFineControl.default(role: fixture.role, zone: fixture.zone)
        if let beam = fixture.beamAngleDegrees {
            fineControl.beamAngleDegrees = beam
        }

        return FixtureGroup(
            id: fixture.id,
            name: fixture.name,
            role: fixture.role,
            zone: fixture.zone,
            enabled: fixture.enabled,
            // The renderer is intensity-driven and never reads `enabled`, so a per-cue state the model
            // emits as {enabled:false, intensity:0.7} would otherwise come up lit. Make `enabled`
            // authoritative here: a disabled fixture assembles dark.
            intensity: fixture.enabled ? fixture.intensity : 0,
            color: FixtureColor(
                mode: .rgb,
                value: FixtureColor.normalizedHex(fixture.colorHex) ?? fixture.colorHex
            ),
            fineControl: fineControl,
            gobo: fixture.gobo,
            model: fixture.model,
            effect: fixture.effect
        )
    }
}

// MARK: - Renderable draft assembly

extension LightingLookDraft {
    /// One cue's worth of a performer-facing front light + a backdrop wash. NOTE: the renderer no longer
    /// gates on role — `ImmersiveView.syncRig`/`apply` build and relight a spotlight for EVERY fixture in
    /// the cue regardless of role. This two-beam `RenderableCue` path now backs only templates / mvpDemo /
    /// legacy looks; on-device generation builds a dynamic 4–12 fixture rig via
    /// `GeneratedLightingLook.makeValidatedLook`, not this.
    struct RenderableCue: Equatable {
        var frontLightIntensity: Double
        var frontLightHex: String
        var frontLightGobo: GoboPattern?
        var backgroundWashIntensity: Double
        var backgroundWashHex: String
        var backgroundWashGobo: GoboPattern?
    }

    /// Assembles a draft whose every cue carries a `.frontLight` and a `.backgroundWash` fixture with
    /// fixed ids/zones. Forcing the two rendered roles here — in Foundation, where the smoke tests can
    /// pin it — rather than trusting the model is what guarantees a generated look changes the stage.
    init(
        lookName: String,
        mood: String,
        opening: RenderableCue,
        highlight: RenderableCue,
        explanationTerm: String,
        explanationPlainText: String,
        explanationActionSummary: String
    ) {
        self.init(
            lookName: lookName,
            mood: mood,
            openingFixtures: Self.renderableFixtures(from: opening),
            highlightFixtures: Self.renderableFixtures(from: highlight),
            explanationTerm: explanationTerm,
            explanationPlainText: explanationPlainText,
            explanationActionSummary: explanationActionSummary
        )
    }

    private static func renderableFixtures(from cue: RenderableCue) -> [Fixture] {
        [
            Fixture(
                id: "front_light",
                name: "前光",
                role: .frontLight,
                zone: .stageFront,
                enabled: true,
                intensity: cue.frontLightIntensity,
                colorHex: cue.frontLightHex,
                gobo: cue.frontLightGobo
            ),
            Fixture(
                id: "background_wash",
                name: "背景泛光",
                role: .backgroundWash,
                zone: .stageBack,
                enabled: true,
                intensity: cue.backgroundWashIntensity,
                colorHex: cue.backgroundWashHex,
                gobo: cue.backgroundWashGobo
            )
        ]
    }
}

// MARK: - Unavailable placeholder

/// Generator used when FoundationModels cannot be linked (e.g. headless tooling, previews
/// on hosts without Apple Intelligence). Always reports unavailable and refuses to generate.
struct UnavailableLightingLookService: LightingLookGenerating {
    let reason: String

    init(reason: String = "此環境中無法使用 Apple Intelligence。") {
        self.reason = reason
    }

    var availability: LightingModelAvailability {
        .unavailable(reason: reason)
    }

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        throw LightingGenerationError.modelUnavailable(reason)
    }
}
