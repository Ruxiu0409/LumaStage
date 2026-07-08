import Foundation

/// Cloud lighting generation backed by the OpenAI Responses API (strict `json_schema`
/// structured output). Foundation-only on purpose — it uses `URLSession` (through the
/// injectable `HTTPSend` boundary) and never `import FoundationModels`, so it stays in the
/// headless smoke compile set alongside `LightingAIService` / `OpenAIKeychain`.
///
/// It is a sibling of `FoundationModelsLightingService`: both fill a constrained look
/// description (here a plain Foundation DTO instead of an `@Generable` type) and assemble it
/// through the SAME `LightingLookDraft.makeValidatedLook(...)` validator. The validator stays
/// the single authority on count/range/hex — this service only does "network → JSON → draft".
///
/// All OpenAI failures surface as `LightingGenerationError.generationFailed(<繁中>)`. It NEVER
/// uses `.modelUnavailable`, whose `errorDescription` hardcodes the "Apple Intelligence 無法使用："
/// prefix (`LightingAIService.swift`). The only place `.unavailable(reason:)` appears is
/// `availability`, when the API key is missing — surfaced by `AppModel`'s gate without a prefix.
struct OpenAILightingService: LightingLookGenerating {
    /// Injectable network boundary — defaults to `URLSession.shared.data(for:)`. Stubbed in smoke tests.
    var httpSend: HTTPSend
    /// Source of the API key — defaults to the Keychain. Stubbed in smoke tests (Keychain is headless-unreliable).
    var apiKeyProvider: () -> String?
    /// The Responses model id. Injectable so it can be switched without touching the request builder.
    var model: String

    init(
        httpSend: @escaping HTTPSend = { try await URLSession.shared.data(for: $0) },
        apiKeyProvider: @escaping () -> String? = { OpenAIKeychain.load() },
        model: String = "gpt-5.5"
    ) {
        self.httpSend = httpSend
        self.apiKeyProvider = apiKeyProvider
        self.model = model
    }

    // MARK: - Availability

    /// Synchronous, never probes the network (a sync property must not block; an unreachable
    /// endpoint surfaces in `generateLook` as `.generationFailed`). Available iff a non-empty key is set.
    var availability: LightingModelAvailability {
        guard let key = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return .unavailable(reason: Self.missingKeyReason)
        }
        return .available
    }

    // MARK: - Generation

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LightingGenerationError.emptyPrompt
        }

        guard let key = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            // Normal flow has the gate block this first; if we get here, surface a non-prefixed failure
            // (NOT `.modelUnavailable`, which would prepend "Apple Intelligence 無法使用：").
            throw LightingGenerationError.generationFailed(Self.missingKeyReason)
        }

        do {
            let request = try Self.makeRequest(prompt: trimmedPrompt, apiKey: key, model: model)
            let (data, response) = try await httpSend(request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw Self.mapHTTPStatus(http.statusCode)
            }

            let innerJSON = try Self.extractOutputText(from: data)
            guard let innerData = innerJSON.data(using: .utf8) else {
                throw LightingGenerationError.generationFailed(Self.decodeFailureReason)
            }

            let dto = try JSONDecoder().decode(LookDTO.self, from: innerData)
            let look = try dto.makeValidatedLook()
            return LightingGenerationResult(look: look, source: .openAI)
        } catch let error as LightingGenerationError {
            throw error
        } catch let error as ValidationError {
            throw LightingGenerationError.generationFailed(error.errorDescription ?? "生成的燈光效果無效。")
        } catch is DecodingError {
            throw LightingGenerationError.generationFailed(Self.decodeFailureReason)
        } catch let error as URLError {
            throw LightingGenerationError.generationFailed(Self.mapURLError(error))
        } catch {
            throw LightingGenerationError.generationFailed(Self.decodeFailureReason)
        }
    }

    // MARK: - Request building

    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    private static func makeRequest(prompt: String, apiKey: String, model: String) throws -> URLRequest {
        // Responses API flattens name/strict/schema under `text.format` — NOT the Chat Completions
        // `response_format.json_schema` shape (which would 400 here).
        let body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": prompt,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "lighting_look",
                    "strict": true,
                    "schema": jsonSchema
                ]
            ],
            "temperature": 0.9
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    // MARK: - Envelope parsing

    /// Walks the canonical Responses envelope and returns the assistant message's `output_text` string
    /// (which is itself a JSON document). Skips non-`message` output items (e.g. `reasoning`); a `refusal`
    /// content item short-circuits to a refusal failure WITHOUT attempting to decode it as a look.
    private static func extractOutputText(from data: Data) throws -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = root["output"] as? [[String: Any]]
        else {
            throw LightingGenerationError.generationFailed(decodeFailureReason)
        }

        // Find the assistant message item; skip `reasoning` and any other non-message items.
        guard let message = output.first(where: { ($0["type"] as? String) == "message" }),
              let content = message["content"] as? [[String: Any]]
        else {
            throw LightingGenerationError.generationFailed(decodeFailureReason)
        }

        for item in content {
            switch item["type"] as? String {
            case "refusal":
                throw LightingGenerationError.generationFailed(refusalReason)
            case "output_text":
                if let text = item["text"] as? String, !text.isEmpty {
                    return text
                }
            default:
                continue
            }
        }

        throw LightingGenerationError.generationFailed(decodeFailureReason)
    }

    // MARK: - Error mapping (all → .generationFailed; NEVER .modelUnavailable)

    private static func mapHTTPStatus(_ status: Int) -> LightingGenerationError {
        switch status {
        case 401, 403:
            return .generationFailed("OpenAI API 金鑰無效或未授權。")
        case 429:
            return .generationFailed("OpenAI 請求過於頻繁，請稍候再試。")
        case 500...599:
            return .generationFailed("OpenAI 服務暫時無法使用，請稍後再試。")
        default:
            return .generationFailed(decodeFailureReason)
        }
    }

    private static func mapURLError(_ error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "請求逾時，請再試一次。"
        default:
            return "無法連線到 OpenAI（請檢查網路）。"
        }
    }

    private static let missingKeyReason = "尚未設定 OpenAI API 金鑰。請在設定中輸入。"
    private static let refusalReason = "模型拒絕生成燈光效果。請嘗試換個說法。"
    private static let decodeFailureReason = "無法解讀模型回應。請再試一次。"

    // MARK: - System instructions (English — same SHOW the FM schema describes)

    /// English system instructions, mirroring `FoundationModelsLightingService.instructions`: the same
    /// SHOW (2–4 cues, a 4–8 fixture rig, one state per fixture per cue in cue order, six-digit hex,
    /// beam 5–120, optional gobo). OpenAI has a large context window, so this can be a touch fuller than
    /// the deliberately short on-device version. User prompts may mix Chinese and English.
    private static let instructions = """
    You design a full stage lighting look for a night outdoor student event. Match the request's event and mood.

    Design a SHOW: an ordered list of 2 to 4 cues the operator steps through with GO, telling a short arc
    (e.g. Opening → Build → Finale). The first cue is the soft establishing look; later cues escalate so the
    sequence clearly progresses.

    Define the rig ONCE as 4 to 8 fixtures, a mix of types and zones suiting the request — energetic shows
    lean on moving beams, a strobe, and a laser with bold saturated colours; talks use a few gentle front
    washes. For EVERY fixture give a `states` array with exactly one entry per cue, IN THE SAME ORDER as the
    cue list (states[0] is the first cue, states[1] the second, and so on). Each state: enabled, intensity
    0.0–1.0, an RGB hex of exactly six digits like #FFD1A3 (no trailing text), beam 5 (tight) to 120 (wide),
    and a gobo (use none unless a texture is clearly asked for). Contrast warm front light against
    cool or coloured back light so the look reads as designed; a fixture may be off in some cues.

    Ground every look in the McCandless method: always include a matched PAIR of frontOfHouse fixtures that
    cross the stage from roughly 45° to the left and right of the performer. This pair is the base layer —
    it gives stable, even visibility and three-dimensional modelling (light from two front angles reveals
    depth that a single flat front light flattens). Keep the pair lit through the cues as the visibility
    through-line (it may dim for mood but should not go fully dark except a deliberate blackout), and give
    the two sides a gentle warm/cool contrast for depth. Layer the coloured, moving, back-light, and effect
    fixtures ON TOP of this base rather than replacing it.

    The explanation teaches one beginner lighting term tied to this look. Prompts may mix Chinese and English.
    """

    // MARK: - Strict JSON schema (mirrors the FM @Generable structure)

    /// Programmatically built strict `json_schema`. Every object sets `additionalProperties:false` and
    /// lists ALL its keys in `required` (strict mode rejects the request otherwise); the three vocabularies
    /// (type/zone/gobo) are enforced `enum`s. Numeric bounds / array counts are written as hints only —
    /// the shared `validate()` stays the authority, so they're not relied on (see SPEC 10 §jsonSchemaDesign).
    private static let jsonSchema: [String: Any] = {
        func object(properties: [String: Any]) -> [String: Any] {
            [
                "type": "object",
                "additionalProperties": false,
                "properties": properties,
                "required": Array(properties.keys)
            ]
        }

        let cue = object(properties: [
            "name": ["type": "string"]
        ])

        let state = object(properties: [
            "enabled": ["type": "boolean"],
            "intensity": ["type": "number", "minimum": 0.0, "maximum": 1.0],
            "colorHex": ["type": "string"],
            "beamAngleDegrees": ["type": "number", "minimum": 5.0, "maximum": 120.0],
            "gobo": ["type": "string", "enum": ["none", "breakup", "stripes", "stars", "grid"]]
        ])

        let fixture = object(properties: [
            "name": ["type": "string"],
            "type": ["type": "string", "enum": [
                "frontFresnel", "ledFresnel", "spotBarrel", "washBar", "backgroundBatten",
                "movingHeadBeam", "ledStrobeBar", "ledPar", "audienceBlinder", "laser"
            ]],
            "zone": ["type": "string", "enum": [
                "frontOfHouse", "upstageTruss", "sideStageLeft", "sideStageRight", "floor"
            ]],
            "states": ["type": "array", "items": state, "minItems": 2, "maxItems": 4]
        ])

        let explanation = object(properties: [
            "term": ["type": "string"],
            "plainText": ["type": "string"],
            "actionSummary": ["type": "string"]
        ])

        return object(properties: [
            "lookName": ["type": "string"],
            "mood": ["type": "string"],
            "cues": ["type": "array", "items": cue, "minItems": 2, "maxItems": 4],
            "fixtures": ["type": "array", "items": fixture, "minItems": 4, "maxItems": 8],
            "explanation": explanation
        ])
    }()
}

// MARK: - Foundation-only DTO (mirrors @Generable GeneratedLightingLook, NO @Generable)

/// Plain `Decodable` mirror of `FoundationModelsLightingService.GeneratedLightingLook` — the same shape
/// the strict schema constrains, decoded from the model's inner `output_text` JSON string. The enum
/// vocabularies match the FM `@Generable` enums 1:1, and `makeValidatedLook()` reproduces the FM
/// assembly (`FoundationModelsLightingService.swift` `makeValidatedLook` / `draftFixture`) exactly.
private extension OpenAILightingService {
    struct LookDTO: Decodable {
        var lookName: String
        var mood: String
        var cues: [CueDTO]
        var fixtures: [FixtureDTO]
        var explanation: ExplanationDTO

        struct CueDTO: Decodable {
            var name: String
        }

        struct ExplanationDTO: Decodable {
            var term: String
            var plainText: String
            var actionSummary: String
        }

        struct FixtureDTO: Decodable {
            var name: String
            var type: FixtureTypeDTO
            var zone: ZoneDTO
            var states: [StateDTO]
        }

        struct StateDTO: Decodable {
            var enabled: Bool
            var intensity: Double
            var colorHex: String
            var beamAngleDegrees: Double
            var gobo: GoboDTO
        }

        enum FixtureTypeDTO: String, Decodable {
            case frontFresnel, ledFresnel, spotBarrel, washBar, backgroundBatten
            case movingHeadBeam, ledStrobeBar, ledPar, audienceBlinder, laser

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

        enum ZoneDTO: String, Decodable {
            case frontOfHouse, upstageTruss, sideStageLeft, sideStageRight, floor

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

        enum GoboDTO: String, Decodable {
            case none, breakup, stripes, stars, grid

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

        /// Maps the DTO into a validated multi-cue `LightingLook`, reproducing the FM assembly exactly:
        /// the rig is defined once; for each cue (in playback order) every fixture contributes its state at
        /// the matching index (a short `states` array reuses its last entry; an empty one assembles off),
        /// with stable `cue_<i>` / `fixture_<i>` ids. The shared validator runs all count/range/hex checks.
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
}

private extension OpenAILightingService.LookDTO.FixtureDTO {
    /// This fixture's draft entry for `cueIndex`, picking the matching `states` entry (clamped: a short
    /// `states` array reuses its last entry). An empty `states` (impossible under the schema, but a
    /// degenerate decode must never crash) yields an off state.
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
            // Self-heal a bad colour (a colour name, #FFF, RGBA, or prose) to white so one un-normalizable
            // colour dims just this light instead of failing validate() and rejecting the whole look.
            colorHex: FixtureColor.normalizedHex(state.colorHex) ?? "#FFFFFF",
            gobo: state.gobo.goboPattern,
            model: model,
            beamAngleDegrees: state.beamAngleDegrees
        )
    }
}
