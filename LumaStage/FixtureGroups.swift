//
//  FixtureGroups.swift
//  LumaStage
//
//  SPEC 08 — Group submasters. Foundation-only so the load-resolution invariant is smoke-tested
//  headlessly. A "group" is the fast control unit for live operation (a few submasters the iPad rides),
//  layered into the SAME cue → override resolution the renderer already runs — NOT a second override
//  state. Kept in its own file (not `LightingModels.swift`) so it composes additively without touching
//  the core model file.
//

import Foundation

/// One named group of fixtures the operator can ride with a single submaster fader. Membership is the
/// set of fixture IDs (resolved from the live rig at seed time), so the renderer can look up "which
/// groups is this fixture in" by id. Auto-derived from the rig's role/zone/type — there is no authored
/// grouping schema (and no `@Generable` change); see `StandardFixtureGroup`.
struct FixtureGroupMask: Identifiable, Equatable {
    var id: String
    var name: String
    /// Fixture IDs (matching `FixtureGroup.id`) that belong to this group in the current rig.
    var members: [String]

    /// Auto-derives the standard groups present in a cue's rig. A group with no members in this rig is
    /// omitted (so the panel only ever shows faders that actually control something). Because the dynamic
    /// rig carries stable fixture IDs across cues, seeding from any one cue yields the same membership.
    static func autoSeed(from cue: LightingCue) -> [FixtureGroupMask] {
        StandardFixtureGroup.allCases.compactMap { group in
            let members = cue.fixtureGroups.filter { group.contains($0) }.map(\.id)
            guard !members.isEmpty else { return nil }
            return FixtureGroupMask(id: group.id, name: group.displayName, members: members)
        }
    }

    /// The effective group master for one fixture — the **load invariant's** master term.
    ///
    /// Only groups the operator is actively riding contribute (i.e. groups with an entry in `masters`);
    /// a fixture in several such groups takes the **HTP (highest)** of their levels. A fixture in no
    /// ridden group (or whose ridden groups all sit untouched) defaults to **1.0** — so parking a
    /// submaster doesn't pull a light down, it just stops contributing.
    static func effectiveMaster(
        forFixtureId fixtureId: String,
        groups: [FixtureGroupMask],
        masters: [String: Double]
    ) -> Double {
        let ridden = groups
            .filter { $0.members.contains(fixtureId) }
            .compactMap { masters[$0.id] }
        return ridden.max() ?? 1.0
    }
}

/// The canonical, auto-seeded groups — the only grouping the app exposes (no arbitrary user schema).
/// Membership is derived from each fixture's existing role / zone / render model, so a freshly generated
/// rig is grouped with zero authoring. IDs and display names are the single shared vocabulary for the
/// host (`AppModel` seeding), the wire (`LumaControlCommand`), and the iPad fader bank.
enum StandardFixtureGroup: String, CaseIterable {
    case front          // 前光 — performer key/front light
    case backgroundWash // 背景洗 — backdrop colour wash
    case upstage        // 上舞台 — everything hung on the upstage truss
    case movers         // 動態 — moving heads / lasers / strobes (the effect fixtures)
    case all            // 全部 — the whole rig

    var id: String { "group_\(rawValue)" }

    /// User-facing (繁體中文) fader label.
    var displayName: String {
        switch self {
        case .front: return "前光"
        case .backgroundWash: return "背景洗"
        case .upstage: return "上舞台"
        case .movers: return "動態"
        case .all: return "全部"
        }
    }

    /// Whether a fixture belongs to this group, by its role / zone / render model. Groups overlap freely
    /// (a moving head upstage is in `upstage`, `movers`, and `all`); the HTP rule in `effectiveMaster`
    /// resolves multi-membership.
    func contains(_ fixture: FixtureGroup) -> Bool {
        switch self {
        case .front:
            return fixture.role == .frontLight || fixture.zone == .stageFront
        case .backgroundWash:
            return fixture.role == .backgroundWash
        case .upstage:
            return fixture.zone == .stageBack
        case .movers:
            switch fixture.renderModel {
            case .movingHeadBeam, .laser, .ledStrobeBar: return true
            default: return false
            }
        case .all:
            return true
        }
    }
}

extension LightOverride {
    /// Final (color, intensity) for a light, folding the **group submaster** into the cue → override
    /// resolution (SPEC 08 load invariant):
    ///
    ///     final = isOff ? 0 : (intensity ?? (cueIntensity × groupMaster))
    ///
    /// - An explicit per-light intensity override **wins over** the group master (channel beats
    ///   submaster — real console behaviour).
    /// - The group master only scales lights with no explicit intensity override.
    /// - A colour override applies regardless and is **not** affected by the master.
    /// - `isOff` forces 0 regardless of the master.
    ///
    /// This is a distinct 3-argument signature (no default) so the existing 2-argument
    /// `resolved(cueColor:cueIntensity:)` keeps resolving group-master-free call sites unambiguously.
    func resolved(cueColor: String, cueIntensity: Double, groupMaster: Double) -> (color: String, intensity: Double) {
        let color = colorHex ?? cueColor
        if isOff { return (color, 0) }
        if let intensity { return (color, intensity) }
        return (color, cueIntensity * groupMaster)
    }
}
