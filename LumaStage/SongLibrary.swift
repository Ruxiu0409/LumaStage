import Foundation

// MARK: - 音樂資料庫選曲來源（SPEC 12 WI-2，Foundation-only、納入 smoke 集）
//
// 這是「從裝置音樂資料庫挑一首歌」這條*來源*的注入接縫（seam），與分析/播放/生成管線解耦。
// 平台無關：本檔只描述 *能挑到什麼*（`SongLibraryItem`）與 *怎麼挑*（`SongLibraryBrowsing`），
// 完全不 import MusicKit / MediaPlayer / UIKit。真正的框架實作只活在 `MusicKitSongLibrary.swift`
// （`#if canImport(MusicKit)…`），就像 `SongAnalyzing` 的平台實作只活在 `MusicUnderstandingService`、
// 而 `LumaSyncTransport` 的真正傳輸只活在 `MultipeerSyncTransport`。
//
// 核心限制（不是 bug，是平台事實）：分析與播放都需要一個*可讀取取樣的真實檔案 URL*。資料庫中唯一
// 能交出這種 URL 的是非保護、已下載到本機的項目；受 DRM 保護的 Apple Music 串流曲目交不出可解碼的
// 檔案 URL，因此在挑選前就標 `isProtected = true`，挑到也以 `.protected` 優雅拒絕。
//
// 因為本檔 Foundation-only（無框架 import），它留在可測試核心裡，smoke 測試能在沒有模擬器的環境下
// 對著協定驗證 loopback 行為。

/// 資料庫中一首可挑選的歌曲，平台無關的值型別。
///
/// `id` 取自平台的穩定識別（MusicKit/MediaPlayer 的 persistentID 字串），`duration` 以秒計、未知為 0；
/// `isProtected` 為 true 代表無法取得可讀 `assetURL`（DRM 或尚未下載到本機），不可分析。
struct SongLibraryItem: Identifiable, Equatable {
    let id: String          // 穩定識別（MusicKit/MediaPlayer 的 persistentID 字串）
    let title: String
    let artist: String
    let duration: Double    // 秒；未知為 0
    let isProtected: Bool   // true = 無 assetURL（DRM／未下載），不可分析
}

/// 選曲來源可能回報的錯誤；平台實作須把框架型別映射成這些，不洩漏框架型別到上層。
enum SongSourceError: Error, Equatable {
    case unauthorized               // 使用者未授權存取音樂資料庫
    case protected                  // 受保護／未下載，無可讀檔案 URL
    case unsupported                // 此平台無音樂資料庫框架可用
    case resolveFailed(String)      // 其他解析失敗（附繁中／除錯說明）
}

/// 注入接縫，平台無關（同 `LightingLookGenerating` / `SongAnalyzing` / `LumaSyncTransport` 的形狀）。
/// 平台實作（`MusicKitSongLibrary`）是唯一觸碰真實框架之處；測試／預覽用 `LoopbackSongLibrary`。
protocol SongLibraryBrowsing {
    /// 請求存取音樂資料庫的授權；回傳是否取得授權。
    func authorize() async -> Bool
    /// 最近的歌曲，最多 `limit` 首。
    func recentSongs(limit: Int) async -> [SongLibraryItem]
    /// 以查詢字串（比對 title／artist）搜尋歌曲。
    func search(_ query: String) async -> [SongLibraryItem]
    /// 解析出可讀取取樣的真實檔案 URL，餵給既有的分析＋播放管線。
    /// 受保護／未下載項目（無可讀 `assetURL`）→ `throw SongSourceError.protected`。
    func resolvePlayableURL(for item: SongLibraryItem) async throws -> URL
}

/// 測試／預覽用的 in-process 實作：吃一組固定的 `[SongLibraryItem]` 與一個固定的已解析 file URL，
/// 不碰任何平台框架。讓整條選曲流程（瀏覽／搜尋／解析、含 `.protected` 拒絕）能在 headless smoke
/// 測試裡跑完，毋須真機或真實音樂資料庫——與 `LoopbackSyncTransport` 對 `LumaSyncTransport` 的角色相同。
struct LoopbackSongLibrary: SongLibraryBrowsing {
    /// 注入的曲目清單（`recentSongs`／`search` 都從這裡取）。
    let items: [SongLibraryItem]
    /// 注入的「已解析」可播檔案 URL（非保護項目一律回這個）。
    let resolvedURL: URL
    /// 注入的授權結果（預設已授權）。
    let isAuthorized: Bool

    init(items: [SongLibraryItem], resolvedURL: URL, isAuthorized: Bool = true) {
        self.items = items
        self.resolvedURL = resolvedURL
        self.isAuthorized = isAuthorized
    }

    func authorize() async -> Bool {
        isAuthorized
    }

    func recentSongs(limit: Int) async -> [SongLibraryItem] {
        Array(items.prefix(max(0, limit)))
    }

    func search(_ query: String) async -> [SongLibraryItem] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(needle) || $0.artist.lowercased().contains(needle)
        }
    }

    func resolvePlayableURL(for item: SongLibraryItem) async throws -> URL {
        if item.isProtected {
            throw SongSourceError.protected
        }
        return resolvedURL
    }
}
