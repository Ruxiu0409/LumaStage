import Foundation

// MARK: - OpenAI-primary, FM-secondary composer

/// Composes two `LightingLookGenerating` backends into an "OpenAI first, fall back to
/// on-device Foundation Models" generator (SPEC 10). It is a pure composer: it only ever
/// calls into the two injected services, so it stays **Foundation-only** and never imports
/// FoundationModels — both `primary` (OpenAI) and `secondary` (FM) hide behind the same
/// `any LightingLookGenerating` seam, the same injectable boundary as `LoopbackSyncTransport`.
///
/// `result.source` naturally reflects whichever backend actually produced the look (OpenAI
/// success → `.openAI`; fell back → `.foundationModels`), so `AppModel.generationStatus`,
/// the iPad panel, etc. show the correct engine with no extra plumbing.
struct FallbackLightingService: LightingLookGenerating {
    let primary: any LightingLookGenerating
    let secondary: any LightingLookGenerating

    init(primary: any LightingLookGenerating, secondary: any LightingLookGenerating) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Available when **either** backend is available. When both are unavailable, the reason
    /// combines the two — leading with the secondary's (the device-side floor) as the main
    /// cause, then appending the primary's so the user sees why the cloud path is out too.
    var availability: LightingModelAvailability {
        if primary.availability.isAvailable || secondary.availability.isAvailable {
            return .available
        }

        let secondaryReason = secondary.availability.unavailableReason
        let primaryReason = primary.availability.unavailableReason

        switch (secondaryReason, primaryReason) {
        case let (secondary?, primary?):
            return .unavailable(reason: "\(secondary)（\(primary)）")
        case let (secondary?, nil):
            return .unavailable(reason: secondary)
        case let (nil, primary?):
            return .unavailable(reason: primary)
        case (nil, nil):
            return .unavailable(reason: "目前無法生成燈光效果。")
        }
    }

    /// Decides whether a `primary` failure should fall back to `secondary`.
    ///
    /// Default (demo resilience): fall back on **any** error except `.emptyPrompt` — both
    /// backends would reject an empty prompt, so there's nothing to gain from retrying it.
    /// An implementer who does NOT want content refusals / validation failures to silently
    /// swap engines can narrow this to transport/availability errors only (e.g. `URLError`,
    /// HTTP 401/403/429/5xx, missing key) by inspecting the `.generationFailed` message or by
    /// matching on a richer error type — keep that decision centralized here.
    private func shouldFallback(on error: any Error) -> Bool {
        if case LightingGenerationError.emptyPrompt = error {
            return false
        }
        return true
    }

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        if primary.availability.isAvailable {
            let primaryError: any Error
            do {
                return try await primary.generateLook(from: prompt)
            } catch {
                primaryError = error
            }

            // Primary failed. Fall back to secondary only when the failure is worth retrying
            // on the other engine AND the secondary can actually run.
            guard shouldFallback(on: primaryError), secondary.availability.isAvailable else {
                throw primaryError
            }
            do {
                return try await secondary.generateLook(from: prompt)
            } catch {
                // Both failed — rethrow the PRIMARY error: the user configured OpenAI, so
                // OpenAI's failure message is the more actionable one to surface.
                throw primaryError
            }
        }

        // Primary not available up front — use the secondary if it can run, otherwise surface
        // the primary's own failure by asking it to generate (it will throw its reason).
        if secondary.availability.isAvailable {
            return try await secondary.generateLook(from: prompt)
        }
        return try await primary.generateLook(from: prompt)
    }
}
