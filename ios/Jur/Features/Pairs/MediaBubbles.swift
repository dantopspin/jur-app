// Photo and voice messages in a chat.
import SwiftUI

/// A chat photo: loads through a signed URL; blurred until tapped (if the setting is on),
/// and always blurred first when the iPhone flags it as nudity.
struct PhotoBubble: View {
    let message: Message
    let mine: Bool
    @AppStorage(ChatMedia.blurKey) private var blurPhotos = true
    @State private var image: UIImage?
    @State private var sensitive = false
    @State private var revealed = false
    @State private var failed = false
    @State private var fullScreen = false
    @Namespace private var zoom

    private var blurred: Bool { !mine && !revealed && (blurPhotos || sensitive) }

    var body: some View {
        ZStack {
            Color.q.line
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .blur(radius: blurred ? 30 : 0)
                    .clipped()
                if blurred {
                    Label(t(sensitive ? "safety.mayContainNudity" : "safety.tapToView"), systemImage: "eye.slash")
                        .qText(.footnote).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Sp.md).padding(.vertical, Sp.sm)
                        .background(.ultraThinMaterial, in: Capsule())
                        .multilineTextAlignment(.center)
                        .padding(Sp.md)
                }
            } else if failed {
                Image(systemName: "photo").font(.q(.title2)).foregroundStyle(Color.q.hint)
            } else {
                ProgressView()
            }
        }
        .frame(width: 220, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .qZoomSource(id: message.id, in: zoom)
        .contentShape(Rectangle())
        .onTapGesture {
            guard image != nil else { return }
            if blurred { withAnimation(Motion.fade) { revealed = true } } else { fullScreen = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("chat2.photo") + (blurred ? ", " + t(sensitive ? "safety.mayContainNudity" : "safety.tapToView") : ""))
        .accessibilityAddTraits(.isButton)
        .task(id: message.id) { await load() }
        .fullScreenCover(isPresented: $fullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let image { ZoomablePhoto(image: image).ignoresSafeArea() }
                CloseButton(action: { fullScreen = false }, onBlue: true).padding(Layout.margin)
            }
            .qZoomDestination(id: message.id, in: zoom)
        }
    }

    private func load() async {
        guard image == nil, let path = message.mediaPath else { return }
        do {
            let data = try await ChatMedia.data(path)
            guard let img = UIImage(data: data) else { failed = true; return }
            if !mine { sensitive = await ChatMedia.isSensitive(img) }
            image = img
        } catch { failed = true }
    }
}

/// A voice note: play / pause, a progress bar, and the length.
struct VoiceBubble: View {
    let message: Message
    let mine: Bool
    @State private var player = VoicePlayer.shared
    /// 0…1 across the bar; animated linearly over the note's length while it plays.
    @State private var fill: CGFloat = 0

    private var playing: Bool { player.playingPath == message.mediaPath && message.mediaPath != nil }
    private var length: String {
        let s = (message.mediaMs ?? 0) / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        Button {
            guard let p = message.mediaPath else { return }
            Task { await player.toggle(p) }
        } label: {
            HStack(spacing: Sp.md) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.q(.headline))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
                    .background((mine ? Color.white : Color.q.blue).opacity(mine ? 0.2 : 1), in: Circle())
                    .foregroundStyle(.white)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill((mine ? Color.white : Color.q.blueText).opacity(0.3))
                        Capsule().fill(mine ? Color.white : Color.q.blueText)
                            .frame(width: g.size.width * fill)
                    }
                }
                .frame(width: 110, height: 4)
                Text(length).font(.q(.footnote)).fontWeight(.bold).monospacedDigit().fixedSize()
            }
            .foregroundStyle(mine ? .white : Color.q.ink)
            .padding(.horizontal, Sp.md)
            .padding(.vertical, Sp.sm)
            .background(mine ? Color.q.blue : Color.q.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.qPressCard)
        .onChange(of: playing) { _, now in
            if now {
                fill = 0
                withAnimation(.linear(duration: max(player.duration, 0.1))) { fill = 1 }
            } else {
                withAnimation(Motion.fade) { fill = 0 }
            }
        }
        .animation(Motion.snappy, value: playing)
        .accessibilityLabel(t("chat2.voice") + ", " + length)
        .accessibilityValue(playing ? t("chat2.playing") : "")
    }
}

/// While recording: elapsed time, cancel, send.
struct RecordingBar: View {
    let started: Date
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: Sp.md) {
            Button(t("chat2.cancel"), action: onCancel)
                .font(.q(.callout)).foregroundStyle(Color.q.danger)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 44)
            Spacer()
            // The one loop allowed here: it means "recording".
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.q.danger)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: started, by: 1)) { ctx in
                let s = Int(ctx.date.timeIntervalSince(started))
                Text(String(format: "%d:%02d", s / 60, s % 60)).qText(.number)
            }
            Spacer()
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.q(.headline)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.q.blue, in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(t("chat.send"))
        }
        .padding(.horizontal, Sp.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("chat2.hold"))
    }
}
