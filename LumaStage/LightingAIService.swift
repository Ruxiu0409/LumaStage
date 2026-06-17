import Foundation

// MARK: - Generation contract

/// Anything that can turn a natural-language prompt into a validated `LightingLook`.
///
/// The concrete on-device implementation lives in `FoundationModelsLightingService`
/// (guarded by `#if canImport(FoundationModels)`). This protocol and the supporting
/// value types stay Foundation-only on purpose so the headless smoke tests can exercise
/// the AI → domain boundary without linking FoundationModels or running a model.
protocol LightingLookGenerating {
    /// Whether the underlying model can currently produce a look.
    var availability: LightingModelAvailability { get }

    /// Generate a fully validated `LightingLook` from a user prompt.
    func generateLook(from prompt: String) async throws -> LightingGenerationResult
}

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

    var displayName: String {
        switch self {
        case .foundationModels:
            return "Apple Foundation Models"
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
            return "Apple Intelligence is unavailable: \(reason)"
        case .emptyPrompt:
            return "Enter a lighting request first."
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
    }

    var lookName: String
    var mood: String
    var openingFixtures: [Fixture]
    var highlightFixtures: [Fixture]
    var explanationTerm: String
    var explanationPlainText: String
    var explanationActionSummary: String

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
                actionSummary: explanationActionSummary
            )
        )

        try look.validate()
        return look
    }

    private static func fixtureGroup(from fixture: Fixture) -> FixtureGroup {
        FixtureGroup(
            id: fixture.id,
            name: fixture.name,
            role: fixture.role,
            zone: fixture.zone,
            enabled: fixture.enabled,
            intensity: fixture.intensity,
            color: FixtureColor(
                mode: .rgb,
                value: FixtureColor.normalizedHex(fixture.colorHex) ?? fixture.colorHex
            ),
            // Drop gobos on roles the renderer can't project, so stored state matches what shows.
            gobo: fixture.role.rendersProjectedGobo ? fixture.gobo : nil
        )
    }
}

// MARK: - Unavailable placeholder

/// Generator used when FoundationModels cannot be linked (e.g. headless tooling, previews
/// on hosts without Apple Intelligence). Always reports unavailable and refuses to generate.
struct UnavailableLightingLookService: LightingLookGenerating {
    let reason: String

    init(reason: String = "Apple Intelligence is not available in this environment.") {
        self.reason = reason
    }

    var availability: LightingModelAvailability {
        .unavailable(reason: reason)
    }

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        throw LightingGenerationError.modelUnavailable(reason)
    }
}
