import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// On-device lighting generation backed by Apple's Foundation Models framework.
///
/// Uses `LanguageModelSession` with compile-time structured output (`@Generable`) in TWO staged passes
/// (SPEC 14) so each model call's OUTPUT stays bounded — the on-device model shares one ~4096-token
/// window across input + output, and a single-shot "whole show" output (fixtures × cues states) blows it
/// for larger rigs / longer shows (`contextSizeExceeded`).
///
/// - **Pass 1 — rig plan**: one call yields `GeneratedRigPlan` (name, mood, the ordered cue LABELS, and
///   the WHOLE rig as `{name,type,zone}` fixtures — no colours/intensities). Output ≈ N fixtures.
/// - **Pass 2..(M+1) — per-cue design**: for each cue, a FRESH `LanguageModelSession` yields a
///   `GeneratedCueDesign` (one `GeneratedFixtureState` per fixture, in rig order). Output ≈ N states.
///
/// Each pass's output is ≈ N and decoupled from M, so more cues just means more (bounded) calls. The
/// results are joined + validated by the Foundation-only `LightingLookDraft.makeValidatedStagedLook(…)`.
/// No network, no API key.
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

        // Randomized (nucleus) sampling with NO fixed seed so each generation differs — choosing a
        // lighting look is a creative act, not extraction. `.greedy` made every run byte-identical for a
        // given prompt (and ignores `temperature` entirely), which read as "the output is always the
        // same". The `@Generable` schemas still pin the structure (2–6 cues, a 4–12 fixture rig, one state
        // per fixture per cue), so randomness only varies the cue count, fixture mix, colors, intensities,
        // mood and wording within those bounds. Reused across both passes. Pass a `seed:` here only if you
        // need reproducible output for debugging.
        let options = GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9), temperature: 0.9)

        #if DEBUG
        // Diagnostic only (SPEC 11 work item D): the on-device model's context window is shared by input +
        // output, so log the budget (`contextSize`) against the INPUT token cost of Pass 1 (rig-plan
        // instructions + the user prompt) to see how much room is left for the structured output. Staged
        // generation keeps EACH pass's output bounded (≈ N), so Pass 1 is the representative budget check.
        // Best-effort, never gates generation. `tokenCount(...)` excludes the @Generable schema text since
        // we pass `includeSchemaInPrompt: false`.
        do {
            let contextSize = model.contextSize
            let instructionTokens = try await model.tokenCount(for: Instructions(Self.rigPlanInstructions))
            let promptTokens = try await model.tokenCount(for: Prompt(trimmedPrompt))
            print("[LumaStage FM] staged pass1 contextSize=\(contextSize) inputTokens=\(instructionTokens + promptTokens) (instructions=\(instructionTokens), prompt=\(promptTokens))")
        } catch {
            print("[LumaStage FM] token diagnostic unavailable: \(error)")
        }
        #endif

        do {
            // ── Pass 1: rig plan (one call, small output) ──────────────────────────────────────────────
            let planSession = LanguageModelSession(
                model: model,
                instructions: Instructions(Self.rigPlanInstructions)
            )
            let plan = try await planSession.respond(
                to: Prompt(trimmedPrompt),
                generating: GeneratedRigPlan.self,
                // Constrained decoding still enforces the structure, so omit the (large) schema text from
                // the prompt to reclaim context — same as SPEC 11's single-shot path.
                includeSchemaInPrompt: false,
                options: options
            ).content

            let rig = plan.fixtures.enumerated().map { index, fixture -> LightingLookDraft.RigFixture in
                let model = fixture.type.visualModel
                let name = fixture.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "燈具 \(index + 1)"
                    : fixture.name
                return LightingLookDraft.RigFixture(
                    id: "fixture_\(index)",
                    name: name,
                    role: model.derivedRole,
                    zone: fixture.zone.stageZone,
                    model: model
                )
            }
            let cueNames = plan.cues.map(\.name)

            // ── Pass 2..(M+1): per-cue design (one FRESH session per cue, sequential) ───────────────────
            // Sequential `await`s (naturally cancellable). A fresh session per cue keeps the growing
            // transcript from feeding back into the shared context window — each cue's output stays ≈ N.
            var cueStates: [[LightingLookDraft.StagedState]] = []
            cueStates.reserveCapacity(cueNames.count)
            for cueIndex in cueNames.indices {
                let cueSession = LanguageModelSession(
                    model: model,
                    instructions: Instructions(Self.cueDesignInstructions)
                )
                let cuePrompt = Self.cueDesignPrompt(
                    request: trimmedPrompt,
                    rig: rig,
                    cueNames: cueNames,
                    cueIndex: cueIndex
                )
                let design = try await cueSession.respond(
                    to: Prompt(cuePrompt),
                    generating: GeneratedCueDesign.self,
                    includeSchemaInPrompt: false,
                    options: options
                ).content
                cueStates.append(design.states.map(\.stagedState))
            }

            let look = try LightingLookDraft.makeValidatedStagedLook(
                lookName: plan.lookName,
                mood: plan.mood,
                rig: rig,
                cueNames: cueNames,
                cueStates: cueStates,
                explanationTerm: plan.explanation.term,
                explanationPlainText: plan.explanation.plainText,
                explanationActionSummary: plan.explanation.actionSummary,
                explanationRationale: plan.explanation.rationale
            )
            return LightingGenerationResult(look: look, source: .foundationModels)
        } catch let error as LightingGenerationError {
            throw error
        } catch {
            throw LightingGenerationError.generationFailed(Self.describe(generationError: error))
        }
    }

    // MARK: - Staged prompts / instructions (English — the on-device model wants an English environment)

    // Kept deliberately SHORT: the on-device model has a small context window, and a long instructions
    // block plus the structured-output schema can exceed it (contextSizeExceeded). The fixture-type and
    // zone vocabularies are enforced by the @Generable enums, so they don't need re-listing here.
    //
    // Pass 1 — rig plan ONLY: name the show, name the cue arc, and design the rig (types/zones). Do NOT
    // pick colours or intensities here (those come per-cue in Pass 2).
    private static let rigPlanInstructions = """
    You plan a stage lighting rig and show structure for a night outdoor student event. Match the request's event and mood.

    Design the RIG once. FIRST choose HOW MANY fixtures (4 to 12) from the event's scale and energy — do NOT default
    to the minimum. Use 10 to 12 for a big or energetic show (dance showcase, concert, festival, or when the request
    says "large rig" / "lots of lights" / "big"); 6 to 9 for a typical event; only 4 to 5 for a small, intimate set
    (a quiet talk, an acoustic solo). When unsure, lean toward a fuller rig. Prefer an EVEN count so left/right
    fixtures pair up symmetrically. Mix fixture types and zones to suit — energetic shows lean on moving beams, a
    strobe and a laser; talks use a few gentle front fresnels and washes. Give each fixture a short name, a type, and
    a mount zone. Do NOT choose colours or intensities here.

    Name the SHOW as an ordered list of cues telling a short arc: use 4 to 6 cues for a show with a real build
    (e.g. Opening → Build → Chorus → Finale), 2 to 3 only for a simple look. Give only each cue's short label. Also
    teach one beginner lighting term with a one-sentence rationale. Prompts may mix Chinese and English.
    """

    // Pass 2 — design ONE cue's states for the already-fixed rig. Only the per-cue look (on/off, brightness,
    // colour) is chosen here; the rig is fixed and must not be re-listed by the model.
    private static let cueDesignInstructions = """
    The lighting rig is already fixed. For the ONE cue named in the prompt, set each fixture's state: whether it is
    on (enabled), its brightness (intensity 0.0–1.0), and its colour as an RGB hex of exactly six digits like
    #FFD1A3 (no trailing text). Give exactly one state per fixture, IN THE LISTED FIXTURE ORDER.

    Make it look designed: contrast a warm front wash against a cooler or more saturated background; some fixtures
    may be OFF in some cues. Follow the cue's place in the arc — earlier cues are softer, later cues escalate.
    """

    /// Builds the compact English prompt for designing cue `cueIndex`: the original request, the fixed rig
    /// (numbered, human-readable `type (zone)` lines the model must design in order), the full cue arc for
    /// narrative context, and the instruction to design just this cue. Kept small — it restates the rig
    /// (≤12 lines) rather than accumulating a transcript, which is the point of a fresh session per cue.
    static func cueDesignPrompt(
        request: String,
        rig: [LightingLookDraft.RigFixture],
        cueNames: [String],
        cueIndex: Int
    ) -> String {
        let rigLines = rig.enumerated().map { index, fixture in
            "\(index + 1). \(fixture.name) (\(Self.promptLabel(for: fixture.zone)))"
        }.joined(separator: "; ")

        let arc = cueNames.enumerated().map { index, name in
            let label = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cue \(index + 1)" : name
            return "\(index + 1) \(label)"
        }.joined(separator: ", ")

        let thisCueRaw = cueIndex < cueNames.count ? cueNames[cueIndex] : ""
        let thisCue = thisCueRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Cue \(cueIndex + 1)"
            : thisCueRaw

        return """
        Request: \(request)
        Rig (\(rig.count) fixtures, design in this order): \(rigLines)
        Cues: \(arc)
        Now design cue \(cueIndex + 1) "\(thisCue)": give one state per fixture, in order.
        """
    }

    /// Human-readable mount-zone name for the compact per-cue prompt's rig listing (e.g. "front of house").
    private static func promptLabel(for zone: StageZone) -> String {
        switch zone {
        case .stageFront: return "front of house"
        case .stageBack: return "upstage truss"
        case .stageLeft: return "stage left"
        case .stageRight: return "stage right"
        case .fullStage: return "floor"
        }
    }

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

// MARK: - Structured output schemas (staged generation)

/// Pass 1 output: the SHOW SKELETON. Names the look, the mood, the ordered cue LABELS, and the WHOLE rig
/// (each fixture's name/type/zone — NO per-cue colour/intensity), plus one teaching explanation. Small,
/// bounded output that decouples the rig/cue structure from the per-cue design, so a large rig or a long
/// show never blows the on-device context window in one shot. Per-cue states come from `GeneratedCueDesign`
/// (Pass 2), and the two are joined by `LightingLookDraft.makeValidatedStagedLook(…)`.
@Generable
struct GeneratedRigPlan {
    @Guide(description: "Human-friendly name for this lighting look, e.g. 'Dance Crew Showcase'")
    var lookName: String

    @Guide(description: "Short mood summary, e.g. 'high-energy, colorful, dance crew finale'")
    var mood: String

    @Guide(description: "The ordered cue list (2 to 6) telling a short arc — use 4–6 cues for a show with a real build (Opening → Build → … → Finale), 2–3 only for a simple look. The first is the establishing look; later cues escalate or change energy. Give only each cue's short label.", .count(2...6))
    var cues: [GeneratedCueLabel]

    @Guide(description: "The whole lighting rig — CHOOSE HOW MANY fixtures (4 to 12) from the event's scale, do not default to the minimum: 10–12 for a big/energetic show or when the request asks for a large rig or lots of lights, 6–9 for a typical event, 4–5 only for a small intimate one; prefer an even count so left/right pair up. Mix fixture types and zones — e.g. moving heads + a strobe + a laser + colored washes for a dance showcase; a few gentle front fresnels and washes for a talk.", .count(4...12))
    var fixtures: [GeneratedRigFixture]

    @Guide(description: "One short teaching note about an industry lighting term used in this look")
    var explanation: GeneratedExplanation

    /// One cue in the ordered show — just its display label. Its per-fixture states are designed in a
    /// separate Pass 2 call (`GeneratedCueDesign`), aligned to this cue's index.
    @Generable
    struct GeneratedCueLabel {
        @Guide(description: "Short human label for this cue, e.g. 'Opening', 'Build', 'Chorus', 'Finale'")
        var name: String
    }

    /// One fixture in the rig: just its label, type, and mount zone (NO per-cue state — that's Pass 2).
    @Generable
    struct GeneratedRigFixture {
        @Guide(description: "Short label, e.g. 'Front Fresnel L' or 'Upstage Moving Head 2'")
        var name: String

        @Guide(description: "Fixture type")
        var type: GeneratedFixtureType

        @Guide(description: "Where the fixture is mounted on the stage")
        var zone: GeneratedZone
    }
}

/// Pass 2 output: ONE cue's design over the already-fixed rig — exactly one `GeneratedFixtureState` per
/// fixture, IN THE LISTED FIXTURE ORDER. Generated in its own fresh session per cue so the output stays
/// bounded by the fixture count (≈ N), never the show length (M).
@Generable
struct GeneratedCueDesign {
    @Guide(description: "One state per fixture, IN THE LISTED FIXTURE ORDER. Provide exactly one per fixture.", .count(1...12))
    var states: [GeneratedFixtureState]
}

/// One short teaching note carried through to `LightingExplanation`. Reused by Pass 1's `GeneratedRigPlan`.
@Generable
struct GeneratedExplanation {
    @Guide(description: "Industry term being taught, e.g. 'Wash', 'Gobo', 'Key Light', or 'Color Temperature'")
    var term: String

    @Guide(description: "ONE short beginner-friendly sentence explaining the term")
    var plainText: String

    @Guide(description: "One sentence summarizing what this look does")
    var actionSummary: String

    @Guide(description: "ONE short sentence of design rationale a beginner can learn from (e.g. why the front is warm or how contrast builds mood)")
    var rationale: String
}

/// One fixture's per-cue state. Reused by Pass 2's `GeneratedCueDesign`.
@Generable
struct GeneratedFixtureState {
    @Guide(description: "Whether this fixture is on in this cue")
    var enabled: Bool

    @Guide(description: "Brightness from 0.0 (off) to 1.0 (full)", .range(0.0...1.0))
    var intensity: Double

    @Guide(description: "RGB hex color as exactly six hex digits like #FFD1A3 — no trailing comma or extra characters")
    var colorHex: String
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

extension GeneratedFixtureState {
    /// Foundation-only mirror for `LightingLookDraft.makeValidatedStagedLook`. `colorHex` is self-healed
    /// there (`normalizedHex(...) ?? "#FFFFFF"`), so it passes the raw model string through unchanged.
    var stagedState: LightingLookDraft.StagedState {
        LightingLookDraft.StagedState(enabled: enabled, intensity: intensity, colorHex: colorHex)
    }
}

extension GeneratedFixtureType {
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

extension GeneratedZone {
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

#endif
