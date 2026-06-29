import Foundation

// MARK: - DMX patch planning + paperwork (the load-in "Patch Sheet" / "Magic Sheet")
//
// This is the bridge from the virtual rig to the real world: it turns the look's dynamic fixtures into
// concrete DMX addresses and a printable summary a lighting technician can patch on a real console
// (grandMA2 et al.). It makes the previously dead `DMXPatch` field live — the immersive twin renderer
// ignores `dmx`, so before this nothing ever assigned or exported it outside `showcaseDemo()`.
//
// Kept Foundation-only so the smoke tests pin the allocation + summary without a simulator; the
// SwiftUI export view (`PatchSheetExportView`) is the only platform-specific consumer.

/// Allocates real DMX universes/addresses to a look's rig and writes them onto the fixtures.
enum DMXPatchPlanner {
    /// Each fixture occupies four DMX channels — Dimmer, Red, Green, Blue — matching `DMXPatch.ChannelMap`.
    static let channelsPerFixture = 4
    /// A DMX universe is 512 channels.
    static let universeSize = 512

    /// How many whole fixtures fit in one universe (512 / 4 = 128).
    static var fixturesPerUniverse: Int { universeSize / channelsPerFixture }

    /// Assigns sequential universe/address to every fixture (by rig identity) and returns a copy of the
    /// look with the same `DMXPatch` written onto that fixture in EVERY cue — so the exported sheet and
    /// the persisted/synced look agree. Fixtures are packed from universe 1, address 1; when a fixture's
    /// four-channel footprint would cross 512 it rolls to address 1 of the next universe (no fixture is
    /// split across universes, matching how real consoles patch).
    static func patched(_ look: LightingLook) -> LightingLook {
        guard let rig = look.cues.first?.fixtureGroups, !rig.isEmpty else {
            return look
        }

        var patches: [String: DMXPatch] = [:]
        var universe = 1
        var address = 1
        for fixture in rig {
            if address + channelsPerFixture - 1 > universeSize {
                universe += 1
                address = 1
            }
            patches[fixture.id] = DMXPatch(
                universe: universe,
                address: address,
                channels: .init(
                    dimmer: address,
                    red: address + 1,
                    green: address + 2,
                    blue: address + 3
                )
            )
            address += channelsPerFixture
        }

        var patched = look
        for cueIndex in patched.cues.indices {
            for fixtureIndex in patched.cues[cueIndex].fixtureGroups.indices {
                let id = patched.cues[cueIndex].fixtureGroups[fixtureIndex].id
                if let patch = patches[id] {
                    patched.cues[cueIndex].fixtureGroups[fixtureIndex].dmx = patch
                }
            }
        }
        return patched
    }
}

/// A printable patch sheet derived from a look's rig: one row per fixture (its on-stage number, type,
/// zone, DMX address, and color), plus a summary footer (fixtures / universes / channels). This is the
/// deliverable a designer hands a technician — "design in the headset, export a sheet, patch it for real".
struct LightingPatchSheet: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String { fixtureId }
        /// 1-based, matching the on-stage "Light N" numbering (cue order).
        var number: Int
        var fixtureId: String
        var name: String
        /// The fixture type's display name (from the catalog), e.g. "搖頭光束燈".
        var fixtureType: String
        /// The mount zone (raw value), e.g. "stageBack".
        var zone: String
        var universe: Int
        var address: Int
        /// The channel span this fixture occupies, e.g. "1–4".
        var channelSpan: String
        var colorHex: String
    }

    var lookName: String
    var rows: [Row]

    /// Distinct universes the rig spans.
    var universeCount: Int { Set(rows.map(\.universe)).count }
    /// Total DMX channels consumed.
    var channelCount: Int { rows.count * DMXPatchPlanner.channelsPerFixture }
    /// Fixture count.
    var fixtureCount: Int { rows.count }

    /// Builds the sheet from a look — patching it first so every row has a real address even if the
    /// look's fixtures never carried one. Uses the first cue's fixtures as the rig identity (all cues
    /// share the same fixtures by id and order).
    static func make(from look: LightingLook) -> LightingPatchSheet {
        let patched = DMXPatchPlanner.patched(look)
        let rig = patched.cues.first?.fixtureGroups ?? []
        let span = DMXPatchPlanner.channelsPerFixture
        let rows = rig.enumerated().map { index, fixture -> Row in
            let start = fixture.dmx?.address ?? 0
            return Row(
                number: index + 1,
                fixtureId: fixture.id,
                name: fixture.name,
                fixtureType: LightingFixtureCatalog.item(for: fixture.renderModel)?.displayName
                    ?? fixture.renderModel.rawValue,
                zone: fixture.zone.rawValue,
                universe: fixture.dmx?.universe ?? 1,
                address: start,
                channelSpan: "\(start)–\(start + span - 1)",
                colorHex: fixture.color.value
            )
        }
        return LightingPatchSheet(lookName: patched.lookName, rows: rows)
    }

    /// A plain-text rendering (tab-separated) for sharing/copying when a PDF isn't wanted. Foundation-only.
    var plainText: String {
        var lines = ["LumaStage 燈光配接表 — \(lookName)",
                     "燈號\t名稱\t類型\t區位\tUniverse\t位址\t通道\t顏色"]
        for row in rows {
            lines.append("\(row.number)\t\(row.name)\t\(row.fixtureType)\t\(row.zone)\tU\(row.universe)\t\(row.address)\t\(row.channelSpan)\t\(row.colorHex)")
        }
        lines.append("合計：\(fixtureCount) 盞燈具 · \(universeCount) 個 Universe · \(channelCount) 個 DMX 通道")
        return lines.joined(separator: "\n")
    }
}
