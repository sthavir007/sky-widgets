// Shared look for all the widgets: dark glass, light-blue glow, SF Pro Rounded.
// When macOS dims desktop widgets (an app is in front / Stage Manager → "vibrant" rendering), colors,
// shadows and blurs turn into grey smudges, so every piece has a crisp monochrome form for that mode.
import SwiftUI
import WidgetKit

enum Palette {
    static let glow = Color(red: 0.72, green: 0.88, blue: 1.00)       // #B8E0FF (paler, readable on the sky-blue glass)
    static let glowDeep = Color(red: 0.35, green: 0.62, blue: 0.98)
    static let ink = Color(red: 0.04, green: 0.08, blue: 0.15)
    // sky-blue glass (was a near-black navy the user couldn't read against)
    static let night1 = Color(red: 0.13, green: 0.30, blue: 0.54)
    static let night2 = Color(red: 0.24, green: 0.47, blue: 0.74)
    static let warn = Color(red: 1.00, green: 0.45, blue: 0.42)
}

private struct VibrantKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// true when the system renders the widget dimmed / monochrome
    var vibrant: Bool {
        get { self[VibrantKey.self] }
        set { self[VibrantKey.self] = newValue }
    }
}

/// Wrap each widget's root in this so the pieces know which mode they're drawn in.
struct Themed<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    var forceVibrant: Bool? = nil
    @ViewBuilder let content: Content
    var body: some View { content.environment(\.vibrant, forceVibrant ?? (mode != .fullColor)) }
}

private struct Glow: ViewModifier {
    @Environment(\.vibrant) private var vibrant
    let color: Color
    let radius: CGFloat
    func body(content: Content) -> some View {
        if vibrant { content } else { content.shadow(color: color, radius: radius) }
    }
}

extension View {
    func glow(_ color: Color = Palette.glow.opacity(0.75), radius: CGFloat = 4) -> some View {
        modifier(Glow(color: color, radius: radius))
    }
}

extension Image {
    /// Photos (album art) keep their real colours when macOS tints/dims widgets; otherwise the
    /// system paints the whole image as one flat block.
    @ViewBuilder func keepColors() -> some View {
        if #available(macOS 15.0, *) { self.widgetAccentedRenderingMode(.fullColor) } else { self }
    }
}

/// The accent: light blue normally, plain white when dimmed.
struct Accent: ShapeStyle {
    func resolve(in env: EnvironmentValues) -> Color { env.vibrant ? .white : Palette.glow }
}

/// The same sky-blue gradient as a bitmap. When macOS dims desktop widgets it throws away colours,
/// but a full-colour image survives, so dimmed widgets stay light blue instead of going black.
enum SkyImage {
    // a smooth gradient, so 200pt stretches without a visible difference; WidgetKit re-encodes it as PNG
    // for every entry of every widget (twice when dimmed), so smaller is much cheaper
    static let image: NSImage = {
        let side: CGFloat = 200
        let size = NSSize(width: side, height: side)
        let img = NSImage(size: size)
        img.lockFocus()
        NSGradient(colors: [NSColor(red: 0.33, green: 0.58, blue: 0.85, alpha: 1), NSColor(red: 0.18, green: 0.39, blue: 0.68, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -45)
        NSGradient(colors: [NSColor(Palette.glow).withAlphaComponent(0.35), .clear])?
            .draw(fromCenter: NSPoint(x: 0, y: side), radius: 0, toCenter: NSPoint(x: 0, y: side), radius: side * 0.95, options: [])
        img.unlockFocus()
        return img
    }()
}

/// When macOS dims desktop widgets it also throws away the containerBackground and shows its own
/// see-through glass (black-ish over a dark wallpaper). So in that mode the sky image is drawn behind
/// the content itself, which the system keeps.
private struct SkyBackdrop: ViewModifier {
    @Environment(\.vibrant) private var vibrant
    func body(content: Content) -> some View {
        if vibrant {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { Image(nsImage: SkyImage.image).resizable().keepColors().clipShape(ContainerRelativeShape()) }
        } else {
            content
        }
    }
}

extension View {
    /// Apply inside `Themed` on each widget's content view.
    func skyBackdrop() -> some View { modifier(SkyBackdrop()) }
}

struct GlowBackground: View {
    var art: NSImage? = nil
    @Environment(\.vibrant) private var vibrant

    var body: some View {
        if vibrant {
            Image(nsImage: SkyImage.image).resizable().keepColors()
        } else {
            ZStack {
                LinearGradient(colors: [Palette.night2, Palette.night1], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let art {
                    Image(nsImage: art).resizable().keepColors().aspectRatio(contentMode: .fill)
                        .blur(radius: 30).saturation(1.3).opacity(0.30)
                }
                RadialGradient(colors: [Palette.glow.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
                RadialGradient(colors: [Palette.glowDeep.opacity(0.22), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 200)
                // the glow around the edge: a soft blurred rim plus a crisp hairline
                ContainerRelativeShape().strokeBorder(Palette.glow, lineWidth: 6).blur(radius: 10)
                ContainerRelativeShape().strokeBorder(Palette.glow.opacity(0.9), lineWidth: 2).blur(radius: 3)
                ContainerRelativeShape().strokeBorder(
                    LinearGradient(colors: [Palette.glow, Palette.glow.opacity(0.25), Palette.glow.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
            }
        }
    }
}

/// Small caps label at the top of a widget, e.g. "NOW PLAYING".
struct Eyebrow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2)
        }
        .foregroundStyle(Accent())
        .glow(Palette.glow.opacity(0.7))
        .lineLimit(1)
    }
}

/// A glowing progress ring (batteries, clock seconds…).
struct GlowRing: View {
    let value: Double
    var lineWidth: CGFloat = 6
    var color: Color = Palette.glow
    @Environment(\.vibrant) private var vibrant

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(vibrant ? 0.25 : 0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(vibrant ? AnyShapeStyle(.white) : AnyShapeStyle(LinearGradient(colors: [Palette.glowDeep, color], startPoint: .bottom, endPoint: .top)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .glow(color.opacity(0.8), radius: 5)
        }
    }
}
