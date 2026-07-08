import Foundation

/// Persists the user's project list to on-device storage so projects created (or edited) in the app survive
/// an app relaunch — reopening LumaStage shows the projects the user built before, instead of always
/// reseeding only the built-in showcase.
///
/// Deliberately **Foundation-only** (JSON + `FileManager`) so it stays in the headless smoke compile set
/// alongside the other core models. `LumaStageProject` (and its whole graph — `StageLayout` / `LightingLook`
/// / `RigConstraint`) is already `Codable`, so this is a thin encode/decode-to-disk wrapper. The store
/// `directory` is injectable so the smoke tests round-trip through a temp folder instead of the real
/// Application Support container.
///
/// Both operations are best-effort and never throw: a missing or corrupt file simply means "no saved
/// projects" (the caller falls back to `LumaStageProject.defaultProjects()`), and a failed write returns
/// `false` rather than crashing the UI action that triggered the save.
struct ProjectStore {
    let directory: URL
    let fileName: String

    init(directory: URL? = nil, fileName: String = "projects.json") {
        self.directory = directory ?? Self.defaultDirectory
        self.fileName = fileName
    }

    /// The app's on-device store: `<Application Support>/LumaStage`. Falls back to the temp directory only if
    /// Application Support can't be resolved (it always can on visionOS), so persistence still functions.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LumaStage", isDirectory: true)
    }

    private var fileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    /// Loads the persisted projects, or `nil` when nothing is saved yet or the file can't be read/decoded.
    func load() -> [LumaStageProject]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([LumaStageProject].self, from: data)
    }

    /// Writes the projects to disk atomically, creating the store directory if needed. Best-effort — returns
    /// `false` (never throws) if the write fails, so a persistence hiccup can't crash a save-triggering action.
    @discardableResult
    func save(_ projects: [LumaStageProject]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(projects)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
