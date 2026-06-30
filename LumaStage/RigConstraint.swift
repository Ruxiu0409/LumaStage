import Foundation

// MARK: - Rig constraint / 鎖定燈具 (SPEC 05 P1, owner A2 — Foundation-only, smoke-tested)
//
// A "locked rig": when the user already knows what gear they have, every generated look is clamped to
// that inventory. A constraint bounds the rig size (`fixtureCount`) and/or the allowed fixture models
// (`allowedModels`). `enforce(on:)` rewrites a `LightingLook` so each cue obeys it — remapping any
// out-of-inventory fixture model to the nearest allowed model by role, and trimming over-count rigs from
// the tail in rig order — while keeping every cue's fixtureId set consistent (rig identity preserved).
// Pure logic so the smoke tests pin it without a simulator; `AppModel` applies it after generation.

struct RigConstraint: Codable, Equatable {
    /// Maximum number of fixtures in the rig; nil = no count limit.
    var fixtureCount: Int?
    /// Allowed fixture models; empty = no model restriction.
    var allowedModels: [LightingFixtureVisualModel]

    /// True when the constraint imposes nothing — `enforce` returns the look unchanged in this case.
    var isUnconstrained: Bool { fixtureCount == nil && allowedModels.isEmpty }

    /// Clamps a look to this constraint. Idempotent: a compliant look is returned unchanged.
    /// - Model rewrite: any fixture whose `renderModel` is not in `allowedModels` is remapped to the
    ///   allowed model whose derived role matches (else the first allowed model). The `model` field is set
    ///   so the rewrite is explicit and the renderer instantiates the right geometry.
    /// - Count clamp: when the rig exceeds `fixtureCount`, fixtures are dropped from the tail in rig order;
    ///   a short rig is NOT padded (the generator is responsible for supplying enough).
    /// - Rig identity: the same set of fixture ids is kept across every cue, so the kept-fixture decision is
    ///   made once (from the first cue's order) and applied to all cues.
    func enforce(on look: LightingLook) -> LightingLook {
        guard !isUnconstrained else { return look }

        var result = look

        // Decide which fixture ids survive the count clamp, using the first cue's order as rig order.
        let keptIds: Set<String>?
        if let limit = fixtureCount, let firstCue = look.cues.first, firstCue.fixtureGroups.count > limit {
            let bounded = max(0, limit)
            keptIds = Set(firstCue.fixtureGroups.prefix(bounded).map(\.id))
        } else {
            keptIds = nil
        }

        result.cues = look.cues.map { cue in
            var newCue = cue
            var groups = cue.fixtureGroups
            if let keptIds {
                groups = groups.filter { keptIds.contains($0.id) }
            }
            newCue.fixtureGroups = groups.map { remapModelIfNeeded($0) }
            return newCue
        }

        return result
    }

    /// Rewrites a fixture's model to a whitelist member when its current model isn't allowed.
    private func remapModelIfNeeded(_ fixture: FixtureGroup) -> FixtureGroup {
        guard !allowedModels.isEmpty else { return fixture }

        let current = fixture.renderModel
        guard !allowedModels.contains(current) else {
            // Already allowed: make the model explicit so a later re-enforce is a no-op (idempotence).
            var explicit = fixture
            explicit.model = current
            return explicit
        }

        // Nearest allowed by derived role, else the first allowed model.
        let targetRole = current.derivedRole
        let replacement = allowedModels.first(where: { $0.derivedRole == targetRole }) ?? allowedModels[0]

        var rewritten = fixture
        rewritten.model = replacement
        return rewritten
    }
}
