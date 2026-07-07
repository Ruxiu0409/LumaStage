import Foundation

// MARK: - Music library source (SPEC 12 WI-3 — platform layer, NOT in the smoke set)
//
// The platform implementation of the Foundation-only `SongLibraryBrowsing` boundary (defined in
// `SongLibrary.swift`). This is the ONLY file that touches a device music-library framework: per the WI-1
// capability spike, the chosen path is **MediaPlayer**, because `MPMediaItem.assetURL` is the only API that
// hands back a readable, decodable on-device file URL — the kind both song analysis
// (`MusicUnderstandingSession` / `AVURLAsset`) and playback (`MusicSyncEngine` → `AVAudioPlayer`) require.
// MusicKit can browse/play the Apple Music catalog but never surfaces a decodable local file URL for DRM
// content, so it is unsuitable as an analysis source and is intentionally not used here.
//
// `assetURL` is non-nil ONLY for non-protected, locally-downloaded items. Protected / streaming / not-yet-
// downloaded items report `assetURL == nil` at runtime — that's a platform/DRM limitation, not a bug — so we
// mark them `isProtected = true` up front (so the UI can disable them) and `throw .protected` if one is
// resolved anyway.
//
// The type is named `MusicKitSongLibrary` because SPEC 12 pins this name (WI-4 defaults to
// `MusicKitSongLibrary()`); the underlying framework is MediaPlayer per the WI-1 conclusion.
//
// This file imports MediaPlayer, so it is platform-only and is deliberately kept OUT of the headless
// smoke-test compile set. No MediaPlayer type ever leaks across the `SongLibraryBrowsing` API surface.

#if canImport(MediaPlayer) && (os(visionOS) || os(iOS))

import MediaPlayer

/// Device music-library browser backed by Apple's `MediaPlayer` framework. Lists/searches the user's local
/// songs and resolves a readable file `URL` (`MPMediaItem.assetURL`) for non-protected, downloaded items so
/// the existing analysis + playback pipeline can consume it. DRM/streaming/undownloaded items are surfaced as
/// `isProtected` and rejected with `SongSourceError.protected`.
struct MusicKitSongLibrary: SongLibraryBrowsing {

    // MARK: Authorization

    /// Bridge `MPMediaLibrary.requestAuthorization` (completion-based) to async; `.authorized` → true.
    func authorize() async -> Bool {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }

    // MARK: Browse / search

    /// Most-recent local songs, newest first. Sorts by `MPMediaItemPropertyDateAdded` (recency), then maps the
    /// first `limit` items into the platform-agnostic `SongLibraryItem`.
    func recentSongs(limit: Int) async -> [SongLibraryItem] {
        guard limit > 0 else { return [] }
        let query = MPMediaQuery.songs()
        let items = query.items ?? []
        // Newest first by date added; items without a date sort to the end.
        let sorted = items.sorted { lhs, rhs in
            lhs.dateAdded > rhs.dateAdded
        }
        return sorted.prefix(limit).map(Self.makeItem(from:))
    }

    /// Title-substring search over the local song library. Maps every match into `SongLibraryItem`.
    func search(_ query: String) async -> [SongLibraryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let mediaQuery = MPMediaQuery.songs()
        let predicate = MPMediaPropertyPredicate(
            value: trimmed,
            forProperty: MPMediaItemPropertyTitle,
            comparisonType: .contains
        )
        mediaQuery.addFilterPredicate(predicate)
        let items = mediaQuery.items ?? []
        return items.map(Self.makeItem(from:))
    }

    // MARK: Resolve playable URL

    /// Re-query the item by its persistentID and return its `assetURL`. Protected/undownloaded (nil URL) →
    /// `throw .protected`; not found in the library → `throw .resolveFailed(...)`. Never leaks a MediaPlayer type.
    func resolvePlayableURL(for item: SongLibraryItem) async throws -> URL {
        guard let mediaItem = Self.lookUp(persistentIDString: item.id) else {
            throw SongSourceError.resolveFailed("找不到此曲目：\(item.title)")
        }
        guard let url = mediaItem.assetURL else {
            // assetURL == nil → DRM-protected, streaming, or not downloaded locally → unreadable samples.
            throw SongSourceError.protected
        }
        return url
    }

    // MARK: Mapping (MPMediaItem → SongLibraryItem; MediaPlayer types stay inside this file)

    /// Map a single `MPMediaItem` into the platform-agnostic `SongLibraryItem`. `isProtected` is keyed on the
    /// presence of `assetURL`: a nil URL means the samples can't be read (DRM/undownloaded), so the item can't
    /// be analyzed.
    private static func makeItem(from item: MPMediaItem) -> SongLibraryItem {
        SongLibraryItem(
            id: String(describing: item.persistentID),
            title: item.title ?? "未命名",
            artist: item.artist ?? "",
            duration: item.playbackDuration,
            isProtected: item.assetURL == nil
        )
    }

    /// Re-query the library for the `MPMediaItem` whose `persistentID` string matches `id`. Returns nil if no
    /// such item exists (e.g. it was removed since browsing).
    private static func lookUp(persistentIDString id: String) -> MPMediaItem? {
        guard let persistentID = MPMediaEntityPersistentID(id) else { return nil }
        let query = MPMediaQuery.songs()
        let predicate = MPMediaPropertyPredicate(
            value: NSNumber(value: persistentID),
            forProperty: MPMediaItemPropertyPersistentID,
            comparisonType: .equalTo
        )
        query.addFilterPredicate(predicate)
        return query.items?.first
    }
}

#else

// MARK: - Framework absent

/// When MediaPlayer isn't available on the platform (e.g. macOS / headless tooling), browsing a device music
/// library is unsupported. Mirrors `MusicUnderstandingService`'s framework-absent branch: authorization fails,
/// browse/search return empty, and resolving throws `.unsupported`. The built-in demo song and file-import
/// sources are unaffected — they never touch this seam.
struct MusicKitSongLibrary: SongLibraryBrowsing {
    func authorize() async -> Bool { false }

    func recentSongs(limit: Int) async -> [SongLibraryItem] { [] }

    func search(_ query: String) async -> [SongLibraryItem] { [] }

    func resolvePlayableURL(for item: SongLibraryItem) async throws -> URL {
        throw SongSourceError.unsupported
    }
}

#endif  // canImport(MediaPlayer) && (os(visionOS) || os(iOS))
