import Foundation

enum LightingFixtureVisualModel: String, CaseIterable, Hashable {
    case washBar
    case spotBarrel
    case frontFresnel
    case backgroundBatten
}

enum LightingFixturePreviewTechnology: String, Equatable {
    case sceneKit3D
}

struct LightingFixtureCatalogItem: Identifiable, Equatable {
    var id: FixtureRole { role }
    var role: FixtureRole
    var displayName: String
    var englishName: String
    var shortDescription: String
    var beginnerPromptHint: String
    var useCase: String
    var visualModel: LightingFixtureVisualModel
    var previewTechnology: LightingFixturePreviewTechnology = .sceneKit3D
}

enum LightingFixtureCatalog {
    static let allFixtures: [LightingFixtureCatalogItem] = [
        LightingFixtureCatalogItem(
            role: .wash,
            displayName: "Wash Light",
            englishName: "Wash Light",
            shortDescription: "Covers the stage or performance area with broad light so the overall color and atmosphere are established first.",
            beginnerPromptHint: "Wash the whole stage in a cool or warm color.",
            useCase: "Useful for base color, mood building, and making the entire area feel visually unified.",
            visualModel: .washBar
        ),
        LightingFixtureCatalogItem(
            role: .spot,
            displayName: "Spot Light",
            englishName: "Spot Light",
            shortDescription: "Uses a focused beam to point at a performer or specific position, guiding the audience’s attention.",
            beginnerPromptHint: "Put a spot light on the singer or host.",
            useCase: "Useful for solos, hosting, awards, or any section that needs a clear focal point.",
            visualModel: .spotBarrel
        ),
        LightingFixtureCatalogItem(
            role: .frontLight,
            displayName: "Front Light",
            englishName: "Front Light",
            shortDescription: "Lights the performer’s face and body from the audience direction, making people clearly visible.",
            beginnerPromptHint: "Make the front light brighter so the performers are clearer.",
            useCase: "Useful for openings, speeches, choir sections, or any moment where facial expression needs to read.",
            visualModel: .frontFresnel
        ),
        LightingFixtureCatalogItem(
            role: .backgroundWash,
            displayName: "Background Wash",
            englishName: "Background Wash",
            shortDescription: "Lights the back of the stage or backdrop, adding color depth behind the performers.",
            beginnerPromptHint: "Change the background wash to deep blue while keeping the foreground warm.",
            useCase: "Useful for night mood, highlights, warm-cool contrast, and separating performers from the background.",
            visualModel: .backgroundBatten
        )
    ]
}
