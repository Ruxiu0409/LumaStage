import Foundation

/// Identifies a concrete fixture model in the Fixture Guide — and the procedural 3D geometry the
/// SceneKit thumbnail (`LightingFixtureSceneFactory`) and RealityKit observatory
/// (`FixtureRealityModel`) build for it. This is the catalog's primary key (each guide entry has a
/// unique model), decoupled from `FixtureRole` so a role can be served by several products. Every
/// model is a real-world product fixture — the earlier abstract role-teaching models (washBar /
/// spotBarrel / frontFresnel / backgroundBatten) were removed.
enum LightingFixtureVisualModel: String, CaseIterable, Hashable {
    // Real-world product fixtures.
    case ledStrobeBar
    case movingHeadBeam
    case ledPar
    case audienceBlinder
    case ledFresnel
    case laser
}

enum LightingFixturePreviewTechnology: String, Equatable {
    case sceneKit3D
}

struct LightingFixtureCatalogItem: Identifiable, Equatable {
    /// The catalog is keyed on the visual model (unique per entry), not the role — several product
    /// fixtures can share a typical role (e.g. a PAR and a strobe bar both wash).
    var id: LightingFixtureVisualModel { visualModel }
    var visualModel: LightingFixtureVisualModel
    /// The cue role this fixture typically serves — a teaching annotation linking the product back to
    /// the AI vocabulary. Not a unique key.
    var role: FixtureRole
    var displayName: String
    var englishName: String
    var shortDescription: String
    var beginnerPromptHint: String
    var useCase: String
    var previewTechnology: LightingFixturePreviewTechnology = .sceneKit3D
}

enum LightingFixtureCatalog {
    /// Catalog item for a given visual model, if present.
    static func item(for model: LightingFixtureVisualModel) -> LightingFixtureCatalogItem? {
        allFixtures.first(where: { $0.visualModel == model })
    }

    /// The fixture models in catalog order — the observatory carousel's page order.
    static var carouselModels: [LightingFixtureVisualModel] {
        allFixtures.map(\.visualModel)
    }

    static let allFixtures: [LightingFixtureCatalogItem] = [
        // MARK: - Real-world product fixtures
        LightingFixtureCatalogItem(
            visualModel: .ledStrobeBar,
            role: .wash,
            displayName: "LED 頻閃燈條",
            englishName: "LED Strobe Bar",
            shortDescription: "一排明亮的 LED 燈珠，能快速連續閃爍，並沿著燈條跑出顏色追逐效果。",
            beginnerPromptHint: "在 drop 段落加入快速的白色頻閃。",
            useCase: "適合 drop、節拍重擊，以及需要俐落有力閃光的高能量時刻。"
        ),
        LightingFixtureCatalogItem(
            visualModel: .movingHeadBeam,
            role: .spot,
            displayName: "搖頭光束燈",
            englishName: "Moving Head Beam Light",
            shortDescription: "可電動水平與垂直轉動的燈頭，能將緊束、銳利的光束投射到舞台任何位置。",
            beginnerPromptHint: "在副歌時讓光束在舞台上來回掃動。",
            useCase: "適合動態效果、空中光束，以及在演出中追蹤表演者或改變焦點。"
        ),
        LightingFixtureCatalogItem(
            visualModel: .ledPar,
            role: .wash,
            displayName: "LED PAR 燈",
            englishName: "LED PAR Light",
            shortDescription: "一個小巧的燈體，內含可混色的 LED 燈珠，能以均勻飽和的光淹沒整個區域。",
            beginnerPromptHint: "用 PAR 燈把舞台打成深藍色。",
            useCase: "適合基礎色彩、均勻的舞台覆蓋，以及場景之間快速換色。"
        ),
        LightingFixtureCatalogItem(
            visualModel: .audienceBlinder,
            role: .frontLight,
            displayName: "觀眾爆閃燈",
            englishName: "Audience Blinder",
            shortDescription: "一塊由大型暖白 COB 燈珠組成的面板，朝向觀眾打出一整片刺眼的強光。",
            beginnerPromptHint: "在最後一個節拍用暖色爆閃打向觀眾。",
            useCase: "適合炒熱觀眾、安可，以及把光線朝觀眾打出的盛大揭幕時刻。"
        ),
        LightingFixtureCatalogItem(
            visualModel: .ledFresnel,
            role: .frontLight,
            displayName: "LED 聚光柔光燈",
            englishName: "LED Fresnel",
            shortDescription: "一款邊緣柔和的 LED 燈具，搭配菲涅耳透鏡，散發平順均勻、邊緣漸層柔和的光。",
            beginnerPromptHint: "給表演者一道柔和的暖色前光。",
            useCase: "適合柔和的主光、溫和的前方覆蓋，以及讓臉部自然、沒有硬邊的呈現。"
        ),
        LightingFixtureCatalogItem(
            visualModel: .laser,
            role: .spot,
            displayName: "雷射燈",
            englishName: "Laser",
            shortDescription: "射出又細又銳利的彩色光束，在空中劃出俐落的線條與扇形，是高能量段落最吸睛的特效。",
            beginnerPromptHint: "在副歌時加入一組綠色雷射光束掃過舞台上空。",
            useCase: "適合 drop、副歌與高潮段落；在煙霧中劃出鮮明的空中光束，瞬間點燃全場氣氛。"
        )
    ]
}

/// Pure paging state for the fixture observatory carousel: a fixed ordered list of fixture
/// models plus the currently shown index. Paging left/right wraps around both ends. Kept
/// Foundation-only so the smoke tests can pin the wrap/select behavior without a view; the
/// spatial `FixtureObservatoryView` is the only consumer.
struct FixtureCarousel: Equatable {
    let models: [LightingFixtureVisualModel]
    private(set) var index: Int

    /// Builds a carousel over `models`, starting at `startModel` (falls back to the first model when
    /// the start is absent or not in the list). An empty `models` list is replaced by the full
    /// catalog order so `current` is always valid.
    init(models: [LightingFixtureVisualModel] = LightingFixtureCatalog.carouselModels, startAt startModel: LightingFixtureVisualModel? = nil) {
        let safeModels = models.isEmpty ? LightingFixtureCatalog.carouselModels : models
        self.models = safeModels
        if let startModel, let start = safeModels.firstIndex(of: startModel) {
            index = start
        } else {
            index = 0
        }
    }

    var current: LightingFixtureVisualModel {
        models[index]
    }

    var currentItem: LightingFixtureCatalogItem? {
        LightingFixtureCatalog.item(for: current)
    }

    var hasMultiple: Bool {
        models.count > 1
    }

    /// Pages by `steps` (negative = left), wrapping around both ends.
    mutating func advance(by steps: Int) {
        guard !models.isEmpty else { return }
        let count = models.count
        index = ((index + steps) % count + count) % count
    }

    /// Jumps to `model` if it is in the list; otherwise leaves the index unchanged.
    mutating func select(model: LightingFixtureVisualModel) {
        guard let target = models.firstIndex(of: model) else { return }
        index = target
    }
}
