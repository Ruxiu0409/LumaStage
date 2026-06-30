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
        // LumaStage only ever turns a benign lighting request into a lighting look, and permissive
        // mode is the intended setting for that — it reduces `.default`'s `guardrailViolation`
        // false-positives on harmless prompts like "add a blue light".
        //
        // It does NOT, however, remove the output safety pass: that pass depends on a SEPARATE
        // safety-model asset (`com.apple.fm.language.instruct_300m.safety`) which downloads
        // independently of the base model and is frequently missing in the Simulator. When it's
        // absent, `respond(...)` throws `com.apple.SensitiveContentAnalysisML error 15` regardless
        // of guardrail mode — an asset/environment condition (test on a real device with a matching
        // system + Siri locale), NOT something this setting can fix. See `isSafetyModelAssetError`.
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
            return .unavailable(reason: "Apple Intelligence 目前無法使用。")
        }
    }

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LightingGenerationError.emptyPrompt
        }

        guard case .available = model.availability else {
            throw LightingGenerationError.modelUnavailable(availability.unavailableReason ?? "Apple Intelligence 無法使用。")
        }

        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions)
        )

        // Randomized (nucleus) sampling with NO fixed seed so each generation differs — choosing a
        // lighting look is a creative act, not extraction. `.greedy` made every run byte-identical
        // for a given prompt (and ignores `temperature` entirely), which read as "the output is
        // always the same". The `@Generable` schema still pins the overall shape (2–5 cues, a 4–12
        // fixture rig, one state per cue), so randomness varies the cue count, fixture mix, colors,
        // intensities, mood and wording within those bounds. Pass a `seed:` here only if you need
        // reproducible output for debugging.
        let options = GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9), temperature: 0.9)

        do {
            let generated = try await session.respond(
                to: Prompt(trimmedPrompt),
                generating: GeneratedLightingLook.self,
                options: options
            ).content

            let look = try generated.makeValidatedLook()
            return LightingGenerationResult(look: look, source: .foundationModels)
        } catch let error as LightingGenerationError {
            throw error
        } catch {
            throw LightingGenerationError.generationFailed(Self.describe(generationError: error))
        }
    }

    private static let instructions = """
    You are a lighting designer for LumaStage, designing a full lighting rig for a night outdoor
    student-event stage. From the user's request, design the WHOLE scene.

    Treat the user's request as the primary driver: match the event and mood. A dance-crew showcase
    ("熱舞社成發") wants an energetic, colorful rig — several moving head beams, a strobe, and one or two
    lasers up on the truss, bold saturated colors, maybe gobos; a talk or award wants a few gentle front
    fresnels and soft washes, warm and even. Pick a fixture count that fits: a big showcase uses 8–12
    fixtures, a simple event 4–6.

    Available fixture types: frontFresnel, ledFresnel (soft performer front light); spotBarrel (tight
    focused spot); movingHeadBeam (punchy moving beam for effects); washBar, backgroundBatten, ledPar
    (broad color washes); ledStrobeBar (strobe/flash accents); audienceBlinder (big bright blinders
    facing the crowd); laser (razor-thin saturated aerial beams — the most eye-catching effect, ideal
    for drops, choruses and high-energy peaks; reach for it on energetic events, especially dance/EDM,
    and prefer punchy saturated colors like green, red or blue for it).
    Mounting zones: frontOfHouse (out front, lights performers), upstageTruss (behind, washes the
    backdrop / beam effects), sideStageLeft, sideStageRight (side accents), floor (uplight from the deck).

    Design a SHOW: an ordered list of 2 to 5 cues the operator steps through with a GO button, telling a
    short arc. A simple event can be just two cues (Opening, Highlight); a dance showcase or song wants
    more — e.g. Opening → Build → Chorus → Finale, or Intro → Verse → Drop → Bows. Name each cue with a
    short, human label in the order it plays. The first cue is the softer establishing look; later cues
    should escalate or change energy so the sequence clearly progresses (not five near-identical cues).

    Define the rig ONCE as a list of fixtures. For EVERY fixture provide a `states` array with exactly one
    entry per cue, IN THE SAME ORDER as the cue list — so states[0] is that fixture in the first cue,
    states[1] in the second, and so on. Each state sets: enabled, intensity (0.0–1.0), an RGB hex color of
    exactly six hex digits such as #FFD1A3 (no trailing comma or other text), beam spread in degrees
    (5 tight … 120 wide), and an optional gobo. Give fixtures roles that contrast — warm front vs.
    cool/colored backlight, for instance — so the stage looks designed, not flat. A fixture can be off
    (enabled false / intensity 0) in some cues and on in others to build the arc.
    Only use a gobo when the request calls for a texture (e.g. "starry backdrop", "dappled forest").

    The explanation teaches one industry lighting term a beginner can understand, tied to this look.
    Voice prompts may mix Chinese and English; interpret lighting vocabulary in either language.
    """

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "此裝置不支援 Apple Intelligence。"
        case .appleIntelligenceNotEnabled:
            return "尚未在「設定」中啟用 Apple Intelligence。"
        case .modelNotReady:
            return "裝置端模型仍在下載或準備中。"
        @unknown default:
            return "Apple Intelligence 目前無法使用。"
        }
    }

    private static let unsupportedLocaleReason =
        "Apple Intelligence 尚未支援此裝置語言。請將系統與 Siri 語言設為支援的語言（例如英文（美國）），再讓 Apple Intelligence 完成下載。"

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
            return "Apple Intelligence 的安全模型在此尚未就緒。請使用支援的語言（例如英文（美國））並讓資產下載完成，或改在實體 Vision Pro 上執行 — 模擬器通常無法執行此項檢查。"
        }

        // OS 27 surfaces generation failures through the top-level `LanguageModelError`
        // (the older `LanguageModelSession.GenerationError` is deprecated in 27.0).
        switch error {
        case let modelError as LanguageModelError:
            switch modelError {
            case .contextSizeExceeded:
                return "此請求對裝置端模型來說太長了。請改用較短的提示。"
            case .guardrailViolation:
                return "此請求被安全系統封鎖。"
            case .rateLimited:
                return "請求過於頻繁。請稍候再試一次。"
            case .unsupportedLanguageOrLocale:
                return "Apple Intelligence 不支援此語言。"
            case .refusal:
                return "模型拒絕生成燈光效果。請嘗試換個說法。"
            case .timeout:
                return "請求逾時。請再試一次。"
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide:
                return "此請求使用了 Apple Intelligence 在此不支援的功能。"
            @unknown default:
                return modelError.errorDescription ?? "Apple Intelligence 無法完成此請求。"
            }
        case let validationError as ValidationError:
            return validationError.errorDescription ?? "生成的燈光效果無效。"
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Structured output schema (dynamic rig)

/// Compile-time structured-output schema the model fills in. The model designs a SHOW: an ordered list
/// of cues plus the WHOLE rig — a variable list of fixtures, each with a type, a stage zone, and a
/// `states` array carrying its state in EACH cue (aligned by index to the cue list). Defining the rig
/// once and giving each fixture one state per cue keeps rig identity stable across the whole sequence.
/// Cue ids are fixed downstream (`cue_0`, `cue_1`, …) in `makeValidatedLook()`.
@Generable
struct GeneratedLightingLook {
    @Guide(description: "Human-friendly name for this lighting look, e.g. 'Dance Crew Showcase'")
    var lookName: String

    @Guide(description: "Short mood summary, e.g. 'high-energy, colorful, dance crew finale'")
    var mood: String

    @Guide(description: "The ordered cue list — 2 to 5 cues the operator steps through with GO, telling a short arc (e.g. Opening, Build, Chorus, Finale). The first is the establishing look; later cues escalate or change energy.", .count(2...5))
    var cues: [GeneratedCue]

    @Guide(description: "The whole lighting rig: the fixtures that together light this event. Pick a count and a mix of fixture types and zones that genuinely suit the request — e.g. several moving heads + strobes + colored washes for a dance showcase; a few gentle front fresnels and washes for a talk or award.", .count(4...12))
    var fixtures: [GeneratedFixture]

    @Guide(description: "One short teaching note about an industry lighting term used in this look")
    var explanation: GeneratedExplanation

    @Generable
    struct GeneratedExplanation {
        @Guide(description: "Industry term being taught, e.g. 'Wash', 'Gobo', 'Key Light', or 'Color Temperature'")
        var term: String

        @Guide(description: "Beginner-friendly plain-language explanation of the term")
        var plainText: String

        @Guide(description: "One sentence summarizing what this look does")
        var actionSummary: String
    }

    /// One cue in the ordered show — just its display label (its fixture states live on each fixture's
    /// `states` array at the matching index).
    @Generable
    struct GeneratedCue {
        @Guide(description: "Short human label for this cue, e.g. 'Opening', 'Build', 'Chorus', 'Finale'")
        var name: String
    }

    /// One fixture in the rig: its type and mounting zone, plus a `states` array with one entry per cue
    /// (same order as the cue list).
    @Generable
    struct GeneratedFixture {
        @Guide(description: "Short label, e.g. 'Front Fresnel L' or 'Upstage Moving Head 2'")
        var name: String

        @Guide(description: "Fixture type")
        var type: GeneratedFixtureType

        @Guide(description: "Where the fixture is mounted on the stage")
        var zone: GeneratedZone

        @Guide(description: "This fixture's state in each cue, IN THE SAME ORDER as the cue list: states[0] is the first cue, states[1] the second, and so on. Provide exactly one state per cue.", .count(2...5))
        var states: [GeneratedFixtureState]
    }

    @Generable
    struct GeneratedFixtureState {
        @Guide(description: "Whether this fixture is on in this cue")
        var enabled: Bool

        @Guide(description: "Brightness from 0.0 (off) to 1.0 (full)", .range(0.0...1.0))
        var intensity: Double

        @Guide(description: "RGB hex color as exactly six hex digits like #FFD1A3 — no trailing comma or extra characters")
        var colorHex: String

        @Guide(description: "Beam spread in degrees: 5 (tight beam) to 120 (wide flood)", .range(5.0...120.0))
        var beamAngleDegrees: Double

        @Guide(description: "Optional projected pattern (gobo): none for a plain beam, breakup (dappled foliage), stripes (slats), stars (starfield), or grid (window). Use none unless the request clearly calls for a pattern.")
        var gobo: GeneratedGobo
    }

    @Generable
    enum GeneratedFixtureType {
        case frontFresnel
        case ledFresnel
        case spotBarrel
        case washBar
        case backgroundBatten
        case movingHeadBeam
        case ledStrobeBar
        case ledPar
        case audienceBlinder
        case laser
    }

    @Generable
    enum GeneratedZone {
        case frontOfHouse
        case upstageTruss
        case sideStageLeft
        case sideStageRight
        case floor
    }

    @Generable
    enum GeneratedGobo {
        case none
        case breakup
        case stripes
        case stars
        case grid
    }
}

extension GeneratedLightingLook {
    /// Maps the dynamic model output into a validated multi-cue `LightingLook`. The rig is defined once;
    /// for each cue (in playback order) every fixture contributes its state at the matching index, so the
    /// same physical fixture (stable `fixture_<i>` id) stays addressable across the whole show. Counts are
    /// reconciled defensively — a fixture that supplied fewer states than there are cues reuses its last
    /// state; extra states are ignored — so a slightly off-count generation still assembles a valid show.
    func makeValidatedLook() throws -> LightingLook {
        let cueCount = max(cues.count, 1)
        let draftCues: [LightingLookDraft.Cue] = (0..<cueCount).map { cueIndex in
            let rawName = cueIndex < cues.count ? cues[cueIndex].name : ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Cue \(cueIndex + 1)"
                : rawName
            let cueFixtures = fixtures.enumerated().map { index, fixture in
                fixture.draftFixture(index: index, cueIndex: cueIndex)
            }
            return LightingLookDraft.Cue(id: "cue_\(cueIndex)", name: name, fixtures: cueFixtures)
        }

        return try LightingLookDraft.makeValidatedLook(
            lookName: lookName,
            mood: mood,
            cues: draftCues,
            explanationTerm: explanation.term,
            explanationPlainText: explanation.plainText,
            explanationActionSummary: explanation.actionSummary
        )
    }
}

private extension GeneratedLightingLook.GeneratedFixture {
    /// This fixture's draft entry for `cueIndex`, picking the matching `states` entry (clamped: a short
    /// `states` array reuses its last entry). Guards an empty `states` (impossible under the
    /// `.count(2...5)` guide, but a degenerate decode must never crash) with an off state.
    func draftFixture(index: Int, cueIndex: Int) -> LightingLookDraft.Fixture {
        let model = type.visualModel
        let resolvedName = name.isEmpty ? "燈具 \(index + 1)" : name

        guard !states.isEmpty else {
            return LightingLookDraft.Fixture(
                id: "fixture_\(index)", name: resolvedName, role: model.derivedRole,
                zone: zone.stageZone, enabled: false, intensity: 0, colorHex: "#000000", model: model
            )
        }

        let state = states[min(max(cueIndex, 0), states.count - 1)]
        return LightingLookDraft.Fixture(
            id: "fixture_\(index)",
            name: resolvedName,
            role: model.derivedRole,
            zone: zone.stageZone,
            enabled: state.enabled,
            intensity: state.intensity,
            colorHex: state.colorHex,
            gobo: state.gobo.goboPattern,
            model: model,
            beamAngleDegrees: state.beamAngleDegrees
        )
    }
}

private extension GeneratedLightingLook.GeneratedFixtureType {
    var visualModel: LightingFixtureVisualModel {
        switch self {
        case .frontFresnel: return .frontFresnel
        case .ledFresnel: return .ledFresnel
        case .spotBarrel: return .spotBarrel
        case .washBar: return .washBar
        case .backgroundBatten: return .backgroundBatten
        case .movingHeadBeam: return .movingHeadBeam
        case .ledStrobeBar: return .ledStrobeBar
        case .ledPar: return .ledPar
        case .audienceBlinder: return .audienceBlinder
        case .laser: return .laser
        }
    }
}

private extension GeneratedLightingLook.GeneratedZone {
    var stageZone: StageZone {
        switch self {
        case .frontOfHouse: return .stageFront
        case .upstageTruss: return .stageBack
        case .sideStageLeft: return .stageLeft
        case .sideStageRight: return .stageRight
        case .floor: return .fullStage
        }
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

#endif
