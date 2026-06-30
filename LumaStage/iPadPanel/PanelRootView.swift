#if os(iOS)
import SwiftUI

/// The control desk's two-tab shell: **Lighting** (the editable control panel, shown first) and
/// **Chat** (live conversation mirror). The live-link state shows as a pill in each tab's navigation
/// bar (`PanelConnectionToolbar`).
struct PanelRootView: View {
    /// The control desk opens on **Lighting** — operators reach for the cue/intensity controls first;
    /// the Chat mirror is secondary.
    private enum PanelTab {
        case chat, lighting
    }

    // TEMP — runs on baked-in sample data so the iPad UI works without a live Apple Vision Pro link.
    // Swap `.mockPreview()` back to `LumaPanelModel()` to reconnect over Multipeer.
    @State private var model = LumaPanelModel.mockPreview()
    @State private var selectedTab: PanelTab = .lighting

    var body: some View {
        TabView(selection: $selectedTab) {
            PanelChatView(model: model)
                .tabItem { Label("對話", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(PanelTab.chat)

            PanelLightingView(model: model)
                .tabItem { Label("燈光", systemImage: "lightbulb.fill") }
                .tag(PanelTab.lighting)
        }
        .task { model.start() }
    }
}

/// Compact live-link indicator placed in each tab's **navigation bar**: a status dot + text leading,
/// and the current look name trailing when connected. It lives in the nav bar rather than a
/// full-width top bar because on iPadOS the `TabView` tab bar is itself top-anchored — a top
/// `safeAreaInset` sat on top of it and covered the tabs. Shared by both tabs so the connection
/// state is always visible regardless of which tab is showing.
struct PanelConnectionToolbar: ToolbarContent {
    let model: LumaPanelModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(model.connectionStatusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            // The state is conveyed visually by a green/orange dot, so fold the whole pill
            // into one VoiceOver element whose value is the status text — the state then
            // never depends on colour alone.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("連線狀態")
            .accessibilityValue(model.connectionStatusText)
        }
        if let name = model.lighting?.lookName, model.isConnected {
            ToolbarItem(placement: .topBarTrailing) {
                Text(name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityLabel("目前燈光效果")
                    .accessibilityValue(name)
            }
        }
    }
}

#Preview {
    PanelRootView()
}
#endif
