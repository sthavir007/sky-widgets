// Renders every widget (normal + dimmed "vibrant" look) to PNGs for checking the design:
// swiftc -D PREVIEW -parse-as-library Preview/main.swift Widget/*.swift Shared/*.swift -o .build/preview && .build/preview <dir>
import SwiftUI
import WidgetKit

@MainActor func render() {
    let s = PlayerState.load()
    let np = Entry(date: Date(), state: s, art: s.artURL.flatMap { NSImage(contentsOf: $0) })
    let weather = WeatherEntry(date: Date(), weather: Weather.load())
    let batt = BatteryEntry(date: Date(), batteries: Batteries.load() ?? Batteries())
    let demoBatt = BatteryEntry(date: Date(), batteries: Batteries(items: [
        Battery(name: "MacBook", kind: .mac, percent: 100, charging: true),
        Battery(name: "AirPods Pro", kind: .airpods, percent: 64),
        Battery(name: "Case", kind: .airpodsCase, percent: 15),
        Battery(name: "Magic Trackpad", kind: .trackpad, percent: 96)]))

    let small = CGSize(width: 170, height: 170), medium = CGSize(width: 364, height: 170)
    let jobs: [(String, CGSize, NSImage?, AnyView)] = [
        ("np-small", small, np.art, AnyView(NowPlayingView(entry: np, forced: .systemSmall))),
        ("np-medium", medium, np.art, AnyView(NowPlayingView(entry: np, forced: .systemMedium))),
        ("clock", small, nil, AnyView(ClockView(entry: ClockEntry(date: Date())))),
        ("calendar", small, nil, AnyView(MonthView(entry: CalendarEntry(date: Date())))),
        ("weather-small", small, nil, AnyView(WeatherView(entry: weather, forced: .systemSmall))),
        ("weather-medium", medium, nil, AnyView(WeatherView(entry: weather, forced: .systemMedium))),
        ("batt-small", small, nil, AnyView(BatteriesView(entry: batt, forced: .systemSmall))),
        ("batt-small4", small, nil, AnyView(BatteriesView(entry: demoBatt, forced: .systemSmall))),
        ("batt-medium", medium, nil, AnyView(BatteriesView(entry: demoBatt, forced: .systemMedium))),
    ]
    for vibrant in [false, true] {
        for (name, size, art, view) in jobs {
            let v = view
                .frame(width: size.width, height: size.height)
                .background(GlowBackground(art: art))
                .background(vibrant ? Color(white: 0.32) : .clear)   // stand-in for the system's dimmed material
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .environment(\.vibrant, vibrant)
                .padding(20).background(Color(white: 0.55))
            let r = ImageRenderer(content: v); r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                let out = CommandLine.arguments[1] + "/\(name)\(vibrant ? "-dim" : "").png"
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            }
        }
    }
}
@main struct PreviewMain { static func main() { MainActor.assumeIsolated { render() } } }
