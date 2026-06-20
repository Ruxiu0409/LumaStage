import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// On-device lighting generation backed by Apple's Foundation Models framework.
///
/// Uses `LanguageModelSession` with compile-time structured output (`@Generable`) so the
/// model fills in a constrained `GeneratedLightingLook`, which is then assembled and
/// validated by `LightingLookDraft.makeValidatedLook()`. No network, no API key.
struct FoundationModelsLightingService: LightingLookGenerating {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel? = nil) {
        // Use the permissive content-transformation guardrails instead of `.default`.
        // LumaStage only ever turns a benign lighting request into a lighting look, but the
        // default guardrails run a sensitive-content analysis pass that false-positives on
        // harmless prompts like "add a blue light" — and in the Simulator that pass fails
        // outright as `com.apple.SensitiveContentAnalysisML error 15`. Permissive mode is the
        // intended setting for this kind of user-content transformation and skips that check.
        self.model = model ?? SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    var availability: LightingModelAvailability {
        switch model.availability {
        case .available:
            // `availability` reports `.available` even when the device's language config keeps the
            // model (and its guardrail safety model) from working, so also gate on the locale.
            // Without this, generation fails late with a cryptic SensitiveContentAnalysisML error.
            guard model.supportsLocale(.current) else {
                return .unavailable(reason: Self.unsupportedLocaleReason)
            }
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: Self.describe(reason))
        @unknown default:
            return .unavailable(reason: "Apple Intelligence is currently unavailable.")
        }
    }

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LightingGenerationError.emptyPrompt
        }

        guard case .available = model.availability else {
            throw LightingGenerationError.modelUnavailable(availability.unavailableReason ?? "Apple Intelligence is unavailable.")
        }

        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions)
        )

        // Low temperature + greedy sampling: this is structured extraction, not creative writing.
        let options = GenerationOptions(samplingMode: .greedy, temperature: 0.2)

        do {
            let generated = try await session.respond(
                to: Prompt(trimmedPrompt),
                generating: GeneratedLightingLook.self,
                options: options
            ).content

            let look = try generated.draft.makeValidatedLook()
            return LightingGenerationResult(look: look, source: .foundationModels)
        } catch let error as LightingGenerationError {
            throw error
        } catch {
            throw LightingGenerationError.generationFailed(Self.describe(generationError: error))
        }
    }

    private static let instructions = """
    You generate MVP stage lighting looks for LumaStage.
    The scene is a fixed standardNight outdoor student-event stage.
    Produce content for exactly two cues: an Opening (softer, establishing) and a Highlight (brighter, more focused).
    For each cue, return two or more fixture groups. Use only the fixture roles wash, spot, frontLight, and backgroundWash.
    Intensity is 0.0 to 1.0. Colors are RGB hex like #FFD1A3.
    A fixture may optionally project a gobo pattern (breakup, stripes, stars, or grid); default to none and only choose a pattern when the request clearly calls for one (e.g. "dappled forest floor", "starry backdrop", "window light").
    The explanation must teach one industry lighting term in language a beginner can understand,
    and relate to what this look actually changed.
    Voice prompts may mix Chinese and English; interpret lighting vocabulary in either language.
    """

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled in Settings."
        case .modelNotReady:
            return "The on-device model is still downloading or preparing."
        @unknown default:
            return "Apple Intelligence is currently unavailable."
        }
    }

    private static let unsupportedLocaleReason =
        "Apple Intelligence isn't ready for this device language. Set the system & Siri language to a supported one (e.g. English (US)), then let Apple Intelligence finish downloading."

    /// `SensitiveContentAnalysisML error 15` means the guardrail safety-model assets aren't
    /// provisioned (an environment/asset issue, not a content block) — common when the system
    /// language is unsupported or in the Simulator. It can arrive raw or wrapped in another error.
    private static func isSafetyModelAssetError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "com.apple.SensitiveContentAnalysisML" { return true }
        if nsError.underlyingErrors.contains(where: { ($0 as NSError).domain == "com.apple.SensitiveContentAnalysisML" }) { return true }
        return nsError.localizedDescription.contains("SensitiveContentAnalysisML")
    }

    private static func describe(generationError error: Error) -> String {
        if isSafetyModelAssetError(error) {
            return "Apple Intelligence's safety model isn't ready here. Use a supported language (e.g. English (US)) and let assets download, or run on a real Vision Pro — the Simulator often can't run this check."
        }

        // OS 27 surfaces generation failures through the top-level `LanguageModelError`
        // (the older `LanguageModelSession.GenerationError` is deprecated in 27.0).
        switch error {
        case let modelError as LanguageModelError:
            switch modelError {
            case .contextSizeExceeded:
                return "The request was too long for the on-device model. Try a shorter prompt."
            case .guardrailViolation:
                return "The request was blocked by the safety system."
            case .rateLimited:
                return "Too many requests. Try again in a moment."
            case .unsupportedLanguageOrLocale:
                return "This language is not supported by Apple Intelligence."
            case .refusal:
                return "The model declined to generate a lighting look. Try rephrasing."
            case .timeout:
                return "The request timed out. Try again."
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide:
                return "This request used a capability Apple Intelligence does not support here."
            @unknown default:
                return modelError.errorDescription ?? "Apple Intelligence could not complete the request."
            }
        case let validationError as ValidationError:
            return validationError.errorDescription ?? "The generated lighting look was invalid."
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Structured output schema

/// Compile-time structured-output schema the model fills in. Cue identity (ids/names) is
/// fixed by `LightingLookDraft`, so the model only supplies fixture content, mood, name,
/// and the teaching explanation.
@Generable
struct GeneratedLightingLook {
    @Guide(description: "Human-friendly name for this lighting look, e.g. 'Warm Opening Lighting'")
    var lookName: String

    @Guide(description: "Short mood summary, e.g. 'warm, welcoming, student showcase'")
    var mood: String

    @Guide(description: "Opening cue: softer establishing lighting that keeps performers visible")
    var openingCue: GeneratedCue

    @Guide(description: "Highlight cue: brighter, more focused lighting for the main moment")
    var highlightCue: GeneratedCue

    @Guide(description: "One short teaching note about an industry lighting term used in this look")
    var explanation: GeneratedExplanation

    @Generable
    struct GeneratedExplanation {
        @Guide(description: "Industry term being taught, e.g. 'Intensity' or 'Background Wash'")
        var term: String

        @Guide(description: "Beginner-friendly plain-language explanation of the term")
        var plainText: String

        @Guide(description: "One sentence summarizing what this look changed")
        var actionSummary: String
    }

    @Generable
    struct GeneratedCue {
        @Guide(description: "Two to four fixture groups lighting the stage for this cue", .count(2...4))
        var fixtureGroups: [GeneratedFixture]
    }

    @Generable
    struct GeneratedFixture {
        @Guide(description: "Stable lowercase identifier, e.g. 'front_wash' or 'background_wash'")
        var id: String

        @Guide(description: "Display name, e.g. 'Front Wash'")
        var name: String

        @Guide(description: "Fixture role: wash, spot, frontLight (performer-facing), or backgroundWash")
        var role: GeneratedRole

        @Guide(description: "Stage zone the fixture covers: stageFront, stageBack, stageLeft, stageRight, or fullStage")
        var zone: GeneratedZone

        @Guide(description: "Whether this fixture group is on for this cue")
        var enabled: Bool

        @Guide(description: "Brightness from 0.0 (off) to 1.0 (full)", .range(0.0...1.0))
        var intensity: Double

        @Guide(description: "RGB hex color string like #FFD1A3")
        var colorHex: String

        @Guide(description: "Optional projected light pattern (gobo) for this fixture: none for a plain beam, breakup (dappled foliage), stripes (slats), stars (starfield), or grid (window). Use none unless the request clearly asks for a pattern.")
        var gobo: GeneratedGobo
    }

    @Generable
    enum GeneratedRole {
        case wash
        case spot
        case frontLight
        case backgroundWash
    }

    @Generable
    enum GeneratedGobo {
        case none
        case breakup
        case stripes
        case stars
        case grid
    }

    @Generable
    enum GeneratedZone {
        case stageFront
        case stageBack
        case stageLeft
        case stageRight
        case fullStage
    }
}

extension GeneratedLightingLook {
    /// Maps the constrained model output into the testable Foundation-only draft.
    var draft: LightingLookDraft {
        LightingLookDraft(
            lookName: lookName,
            mood: mood,
            openingFixtures: openingCue.fixtureGroups.map { $0.draftFixture },
            highlightFixtures: highlightCue.fixtureGroups.map { $0.draftFixture },
            explanationTerm: explanation.term,
            explanationPlainText: explanation.plainText,
            explanationActionSummary: explanation.actionSummary
        )
    }
}

private extension GeneratedLightingLook.GeneratedFixture {
    var draftFixture: LightingLookDraft.Fixture {
        LightingLookDraft.Fixture(
            id: id,
            name: name,
            role: role.fixtureRole,
            zone: zone.stageZone,
            enabled: enabled,
            intensity: intensity,
            colorHex: colorHex,
            gobo: gobo.goboPattern
        )
    }
}

private extension GeneratedLightingLook.GeneratedGobo {
    /// Maps the model's gobo choice into the domain pattern; `.none` means a plain beam (`nil`).
    var goboPattern: GoboPattern? {
        switch self {
        case .none: return nil
        case .breakup: return .breakup
        case .stripes: return .stripes
        case .stars: return .stars
        case .grid: return .grid
        }
    }
}

private extension GeneratedLightingLook.GeneratedRole {
    var fixtureRole: FixtureRole {
        switch self {
        case .wash: return .wash
        case .spot: return .spot
        case .frontLight: return .frontLight
        case .backgroundWash: return .backgroundWash
        }
    }
}

private extension GeneratedLightingLook.GeneratedZone {
    var stageZone: StageZone {
        switch self {
        case .stageFront: return .stageFront
        case .stageBack: return .stageBack
        case .stageLeft: return .stageLeft
        case .stageRight: return .stageRight
        case .fullStage: return .fullStage
        }
    }
}
#endif
