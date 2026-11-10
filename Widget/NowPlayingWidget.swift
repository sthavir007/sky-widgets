// Now Playing desktop widget: Spotify's current track with a light-blue glow, live progress, and
// previous / play-pause / next buttons (AppIntents → Darwin notification → host → AppleScript).
// Clicking anywhere else opens Spotify (nowplaying://open, handled by the host).
import AppIntents
import ImageIO
import SwiftUI
import WidgetKit

// MARK: intents

func send(_ c: Command) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFNotificationName(c.notification as CFString), nil, nil, true)
}

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play / Pause"
    func perform() async throws -> some IntentResult {
        send(.playpause)
        try? await Task.sleep(for: .milliseconds(300))   // let the host write the new state first
        return .result()
    }
}

struct NextIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    func perform() async throws -> some IntentResult {
        send(.next)
        try? await Task.sleep(for: .milliseconds(700))
        return .result()
    }
}

struct PreviousIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    func perform() async throws -> some IntentResult {
        send(.previous)
        try? await Task.sleep(for: .milliseconds(700))
        return .result()
    }
}

// MARK: timeline

struct Entry: TimelineEntry {
    let date: Date
    let state: PlayerState
    let art: NSImage?
    var backdrop: NSImage? = nil   // tiny copy of the art for the blurred background
}

/// Album art decoded once per track and shrunk to what the widget draws. WidgetKit re-encodes every
/// image in an entry as PNG, so the full 640px JPEG made each reload far more expensive than needed.
enum ArtCache {
    private static let lock = NSLock()
    private static var file: String?
    private static var images: (art: NSImage?, backdrop: NSImage?) = (nil, nil)

    static func images(for s: PlayerState) -> (art: NSImage?, backdrop: NSImage?) {
        lock.lock(); defer { lock.unlock() }
        if s.artFile == file { return images }
        file = s.artFile
        images = (s.artURL.flatMap { thumbnail($0, 300) }, s.artURL.flatMap { thumbnail($0, 64) })
        return images
    }

    private static func thumbnail(_ url: URL, _ px: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: px] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct Provider: TimelineProvider {
    func entry() -> Entry {
        let s = PlayerState.load()
        let art = ArtCache.images(for: s)
        return Entry(date: Date(), state: s, art: art.art, backdrop: art.backdrop)
    }
    func placeholder(in context: Context) -> Entry {
        var s = PlayerState()
        s.running = true; s.title = "Song Title"; s.artist = "Artist"; s.duration = 200; s.position = 60
        return Entry(date: Date(), state: s, art: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview && !PlayerState.load().running ? placeholder(in: context) : entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let e = entry()
        let s = e.state
        // the host reloads us on every change; this is only a fallback
        let next = s.playing ? Date().addingTimeInterval(max(5, s.duration - s.position(at: Date())) + 1)
                             : Date().addingTimeInterval(1800)
        completion(Timeline(entries: [e], policy: .after(next)))
    }
}

// MARK: pieces

struct ArtView: View {
    let art: NSImage?
    let corner: CGFloat
    @Environment(\.vibrant) private var vibrant

    var body: some View {
        ZStack {
            if let art {
                Image(nsImage: art).resizable().keepColors().aspectRatio(contentMode: .fill)
            } else {
                if !vibrant {
                    LinearGradient(colors: [Palette.glowDeep.opacity(0.55), Palette.night2], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Accent())
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(.white.opacity(vibrant ? 0.5 : 0.14), lineWidth: vibrant ? 1 : 0.5))
        .glow(Palette.glow.opacity(0.45), radius: 10)
    }
}

struct PlayButton: View {
    let playing: Bool
    let size: CGFloat
    @Environment(\.vibrant) private var vibrant

    var body: some View {
        Button(intent: PlayPauseIntent()) {
            ZStack {
                if vibrant {
                    Circle().strokeBorder(.white, lineWidth: 1.5)
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [.white, Palette.glow], startPoint: .top, endPoint: .bottom))
                        .glow(Palette.glow.opacity(0.9), radius: size * 0.28)
                }
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.40, weight: .bold))
                    .foregroundStyle(vibrant ? .white : Palette.ink)
                    .offset(x: playing ? 0 : size * 0.04)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

struct SkipButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let size: CGFloat

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: size * 1.9, height: size * 1.9)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A thin glowing bar; ticks along on its own while playing (no reloads needed).
struct Progress: View {
    let state: PlayerState
    let date: Date
    @Environment(\.vibrant) private var vibrant

    var body: some View {
        Group {
            if let r = range, state.playing {
                ProgressView(timerInterval: r, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.linear)
                    .tint(vibrant ? .white : Palette.glow)
            } else {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(vibrant ? 0.3 : 0.16))
                        Capsule()
                            .fill(vibrant ? AnyShapeStyle(.white)
                                          : AnyShapeStyle(LinearGradient(colors: [Palette.glowDeep, Palette.glow], startPoint: .leading, endPoint: .trailing)))
                            .frame(width: max(4, g.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
        }
        .glow(Palette.glow.opacity(0.8))
    }

    var fraction: CGFloat { state.duration > 0 ? CGFloat(min(1, state.position / state.duration)) : 0 }

    var range: ClosedRange<Date>? {
        guard state.duration > 0 else { return nil }
        let start = date.addingTimeInterval(-state.position(at: date))
        return start...start.addingTimeInterval(state.duration)
    }
}

struct TimeLabels: View {
    let state: PlayerState
    let date: Date

    var body: some View {
        HStack(spacing: 0) {
            if let r = Progress(state: state, date: date).range, state.playing {
                // timer text fills its frame, so alignment has to come from multilineTextAlignment
                Text(timerInterval: r, countsDown: false)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Text(timerInterval: r, countsDown: true)
                    .multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(clock(state.position))
                Spacer()
                Text(clock(state.duration))
            }
        }
        .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
    }

    func clock(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

// MARK: layouts

struct NowPlayingView: View {
    let entry: Entry
    var forced: WidgetFamily?
    @Environment(\.widgetFamily) private var envFamily
    var family: WidgetFamily { forced ?? envFamily }
    var s: PlayerState { entry.state }

    var title: String { s.running && !s.title.isEmpty ? s.title : "Nothing playing" }
    var subtitle: String { s.running && !s.artist.isEmpty ? s.artist : "Click to open Spotify" }

    var body: some View {
        Group {
            if family == .systemSmall { small } else { medium }
        }
        .widgetURL(URL(string: "nowplaying://open"))
    }

    var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: family == .systemSmall ? 11 : 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .lineLimit(1)
    }

    var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ArtView(art: entry.art, corner: 12).frame(width: 72, height: 72)
                Spacer(minLength: 6)
                VStack(spacing: 6) {
                    PlayButton(playing: s.playing, size: 36)
                    SkipButton(intent: NextIntent(), symbol: "forward.fill", size: 12)
                }
            }
            Spacer(minLength: 6)
            titles
            Spacer(minLength: 7)
            Progress(state: s, date: entry.date)
        }
        .padding(14)
    }

    var medium: some View {
        HStack(spacing: 14) {
            ArtView(art: entry.art, corner: 16)
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(symbol: s.playing ? "waveform" : "pause.circle",
                        text: !s.running ? "SPOTIFY" : s.playing ? "NOW PLAYING" : "PAUSED")
                Spacer(minLength: 4)
                titles
                Spacer(minLength: 6)
                Progress(state: s, date: entry.date)
                TimeLabels(state: s, date: entry.date).padding(.top, 3)
                Spacer(minLength: 2)
                HStack(spacing: 14) {
                    Spacer(minLength: 0)
                    SkipButton(intent: PreviousIntent(), symbol: "backward.fill", size: 14)
                    PlayButton(playing: s.playing, size: 36)
                    SkipButton(intent: NextIntent(), symbol: "forward.fill", size: 14)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
    }
}

#if !PREVIEW
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowPlaying", provider: Provider()) { entry in
            Themed {
                NowPlayingView(entry: entry)
                    .skyBackdrop()
                    .containerBackground(for: .widget) { Themed { GlowBackground(art: entry.backdrop ?? entry.art) } }
            }
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing on Spotify, with play, pause and skip.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
#endif
