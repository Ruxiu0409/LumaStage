#if os(iOS)
import SwiftUI

/// **Chat tab** — a live mirror of the operator's conversation with the on-device Foundation Models
/// running on the Apple Vision Pro. Messages stream in as the host generates; the in-progress
/// transcript shows as a live bubble. The input bar lets the iPad also kick off a generation
/// (`.generate`), which the AVP runs and streams back.
struct PanelChatView: View {
    let model: LumaPanelModel
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                if phaseText != nil { phaseRow }
                inputBar
            }
            .navigationTitle("對話")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { PanelConnectionToolbar(model: model) }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.conversation.messages) { message in
                    ChatBubble(message: message)
                        .id(message.id)
                        .listRowSeparator(.hidden)
                }
                if !model.conversation.liveTranscript.isEmpty {
                    ChatBubble(
                        message: LumaChatMessage(id: "live", sender: .user, text: model.conversation.liveTranscript, timestamp: 0),
                        isLive: true
                    )
                    .id("live")
                    .listRowSeparator(.hidden)
                }
                if let error = model.conversation.lastError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .id("error")
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .overlay { if isEmpty { emptyState } }
            .onChange(of: model.conversation.messages.count) { scrollToBottom(proxy) }
            .onChange(of: model.conversation.liveTranscript) { scrollToBottom(proxy) }
        }
    }

    private var isEmpty: Bool {
        model.conversation.messages.isEmpty && model.conversation.liveTranscript.isEmpty
    }

    private var emptyState: some View {
        ContentUnavailableView(
            model.isConnected ? "尚無對話" : "未連線",
            systemImage: model.isConnected ? "bubble.left.and.bubble.right" : "wifi.slash",
            description: Text(model.isConnected
                ? "對 Vision Pro 說話，或在下方輸入提示來設計燈光效果。"
                : "在同一個 Wi-Fi 下的 Apple Vision Pro 上開啟 LumaStage 以建立連線。")
        )
    }

    /// A friendly status line while the host is mid-generation (anything but idle).
    private var phaseText: String? {
        switch model.conversation.phase {
        case "listening": return "聆聽中…"
        case "transcribing": return "轉錄中…"
        case "interpreting": return "解讀中…"
        case "applying": return "套用中…"
        case "explaining": return "說明中…"
        case "error": return nil
        default: return nil
        }
    }

    private var phaseRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(phaseText ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("請 AI 設計一個燈光效果…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(!canSend)
        }
        .padding(12)
        .background(.bar)
    }

    private var canSend: Bool {
        model.isConnected && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, model.isConnected else { return }
        model.send(.generate(prompt: prompt))
        draft = ""
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if !model.conversation.liveTranscript.isEmpty {
                proxy.scrollTo("live", anchor: .bottom)
            } else if let last = model.conversation.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct ChatBubble: View {
    let message: LumaChatMessage
    var isLive: Bool = false

    var body: some View {
        HStack {
            if message.sender == .user { Spacer(minLength: 48) }
            bubble
            if message.sender != .user { Spacer(minLength: 48) }
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
    }

    private var bubble: some View {
        Text(message.text)
            .font(.callout)
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isLive ? 0.7 : 1)
            .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
    }

    private var background: Color {
        switch message.sender {
        case .user: return .accentColor
        case .model: return Color(.secondarySystemBackground)
        case .system: return Color(.tertiarySystemBackground)
        }
    }

    private var foreground: Color {
        message.sender == .user ? .white : .primary
    }
}
#endif
