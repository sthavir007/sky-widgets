// Clock, Weather (San Diego) and Batteries widgets in the same glow theme as Now Playing.
import SwiftUI
import WidgetKit

// MARK: - Clock

struct ClockEntry: TimelineEntry { let date: Date }

struct ClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockEntry { ClockEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (ClockEntry) -> Void) { completion(ClockEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockEntry>) -> Void) {
        // one entry per minute for an hour
        let start = Calendar.current.dateInterval(of: .minute, for: Date())!.start
        let entries = (0..<60).map { ClockEntry(date: start.addingTimeInterval(Double($0) * 60)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// "12:56:01". The hour is static (one timeline entry per minute); "56:01" is a live timer
/// counting up from the top of the hour, which the system ticks every second by itself
/// (Text(.currentDate) with seconds showed no seconds on the desktop).
struct ClockTime: View {
    let date: Date

    var body: some View {
        let hourStart = Calendar.current.dateInterval(of: .hour, for: date)!.start
        let early = Calendar.current.component(.minute, from: date) < 10
        let hour = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)))
        HStack(spacing: 0) {
            // the timer shows "5:01" below ten minutes, so the leading zero is static
            Text(hour + ":" + (early ? "0" : ""))
            // a timer fills whatever frame it gets, so a hidden sample sets the slot to its exact width
            Text(early ? "0:00" : "00:00").hidden().overlay(alignment: .leading) {
                Text(timerInterval: hourStart...hourStart.addingTimeInterval(3600), countsDown: false)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

struct ClockView: View {
    let entry: ClockEntry

    var body: some View {
        ZStack {
            VStack(spacing: 3) {
                ClockTime(date: entry.date)
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .glow(Palette.glow.opacity(0.5), radius: 8)
                    .lineLimit(1)
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Weather

struct WeatherEntry: TimelineEntry { let date: Date; let weather: Weather? }

struct WeatherProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        var w = Weather(); w.temp = 72; w.high = 75; w.low = 63; w.code = 2
        return WeatherEntry(date: Date(), weather: w)
    }
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        completion(Weather.load().map { WeatherEntry(date: Date(), weather: $0) } ?? placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        // the host refreshes every 15 minutes and reloads us
        let w = Weather.load()
        let now = Date()
        let entries = (0..<4).map { WeatherEntry(date: now.addingTimeInterval(Double($0) * 900), weather: w) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

func deg(_ t: Double) -> String { "\(Int(t.rounded()))°" }

struct WeatherView: View {
    let entry: WeatherEntry
    var forced: WidgetFamily?
    @Environment(\.widgetFamily) private var envFamily
    var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        if let w = entry.weather {
            if family == .systemSmall { now(w).padding(14) } else {
                HStack(spacing: 14) {
                    now(w)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 6)
                    hourly(w)
                }
                .padding(14)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "cloud.sun").font(.system(size: 28)).foregroundStyle(Accent())
                Text("Loading weather…").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    func now(_ w: Weather) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Eyebrow(symbol: "location.fill", text: w.city.uppercased())
                Spacer(minLength: 4)
            }
            HStack(alignment: .center, spacing: 6) {
                Text(deg(w.temp))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .glow(Palette.glow.opacity(0.5), radius: 10)
                Spacer(minLength: 0)
                Image(systemName: Sky.symbol(w.code, day: w.isDay))
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Accent())
                    .glow(Palette.glow.opacity(0.8), radius: 8)
            }
            .padding(.top, 2)
            Spacer(minLength: 2)
            Text(Sky.words(w.code))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("H:\(deg(w.high))  L:\(deg(w.low))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        .frame(maxWidth: family == .systemSmall ? .infinity : 128, alignment: .leading)
    }

    func hourly(_ w: Weather) -> some View {
        let hours = w.hours.filter { $0.time > entry.date.addingTimeInterval(-3600) }.prefix(5)
        return HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { i, h in
                VStack(spacing: 8) {
                    Text(i == 0 ? "Now" : h.time.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: Sky.symbol(h.code, day: h.isDay))
                        .font(.system(size: 17))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Accent())
                        .glow(Palette.glow.opacity(0.7), radius: 5)
                        .frame(height: 22)
                    Text(deg(h.temp))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Batteries

struct BatteryEntry: TimelineEntry { let date: Date; let batteries: Batteries }

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), batteries: Batteries(items: [
            Battery(name: "MacBook", kind: .mac, percent: 80, charging: true),
            Battery(name: "AirPods Pro", kind: .airpods, percent: 64),
            Battery(name: "Case", kind: .airpodsCase, percent: 90),
            Battery(name: "Magic Trackpad", kind: .trackpad, percent: 45)]))
    }
    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        let b = Batteries.load()
        completion(b.map { BatteryEntry(date: Date(), batteries: $0) } ?? placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let e = BatteryEntry(date: Date(), batteries: Batteries.load() ?? Batteries())
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(600))))
    }
}

extension Battery.Kind {
    var symbol: String {
        switch self {
        case .mac: return "laptopcomputer"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .mouse: return "magicmouse.fill"
        case .keyboard: return "keyboard.fill"
        case .airpods: return "airpodspro"
        case .airpodLeft: return "airpodpro.left"
        case .airpodRight: return "airpodpro.right"
        case .airpodsCase: return "airpodspro.chargingcase.wireless.fill"
        case .headphones: return "headphones"
        case .other: return "battery.75percent"
        }
    }
}

struct BatteryRing: View {
    let battery: Battery
    let size: CGFloat
    var showName = false
    @Environment(\.vibrant) private var vibrant

    var body: some View {
        let low = battery.percent <= 20 && !battery.charging
        VStack(spacing: 5) {
            ZStack {
                GlowRing(value: Double(battery.percent) / 100, lineWidth: size * 0.09, color: low ? Palette.warn : Palette.glow)
                Image(systemName: battery.kind.symbol)
                    .font(.system(size: size * 0.34, weight: .medium))
                    .foregroundStyle(.white)
                if battery.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(Accent())
                        .glow(Palette.glow, radius: 4)
                        .padding(3)
                        .background(Circle().fill(vibrant ? Color.clear : Palette.night1))
                        .offset(y: -size / 2)
                }
            }
            .frame(width: size, height: size)
            Text("\(battery.percent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(low && !vibrant ? Palette.warn : .white.opacity(0.85))
            if showName {
                Text(battery.name)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }
}

struct BatteriesView: View {
    let entry: BatteryEntry
    var forced: WidgetFamily?
    @Environment(\.widgetFamily) private var envFamily
    var family: WidgetFamily { forced ?? envFamily }

    var body: some View {
        let items = Array(entry.batteries.items.prefix(4))
        Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "battery.100.bolt").font(.system(size: 26)).foregroundStyle(Accent())
                    Text("No batteries found").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
            } else if family == .systemSmall {
                if items.count <= 2 {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(symbol: "bolt.fill", text: "BATTERIES")
                        Spacer(minLength: 0)
                        HStack(spacing: 12) {
                            ForEach(items) { BatteryRing(battery: $0, size: 56) }
                        }
                        .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                } else {
                    let rows = [Array(items.prefix(2)), Array(items.dropFirst(2))]
                    VStack(spacing: 6) {
                        ForEach(rows.indices, id: \.self) { r in
                            HStack(spacing: 14) { ForEach(rows[r]) { BatteryRing(battery: $0, size: 46) } }
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(symbol: "bolt.fill", text: "BATTERIES")
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        ForEach(items) { BatteryRing(battery: $0, size: 58, showName: true).frame(maxWidth: .infinity) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
        }
    }
}

#if !PREVIEW
struct ClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Clock", provider: ClockProvider()) { entry in
            Themed { ClockView(entry: entry).skyBackdrop().containerBackground(for: .widget) { Themed { GlowBackground() } } }
        }
        .configurationDisplayName("Clock")
        .description("The time and date.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Weather", provider: WeatherProvider()) { entry in
            Themed { WeatherView(entry: entry).skyBackdrop().containerBackground(for: .widget) { Themed { GlowBackground() } } }
        }
        .configurationDisplayName("San Diego Weather")
        .description("Current conditions and the next few hours in San Diego.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct BatteriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Batteries", provider: BatteryProvider()) { entry in
            Themed { BatteriesView(entry: entry).skyBackdrop().containerBackground(for: .widget) { Themed { GlowBackground() } } }
        }
        .configurationDisplayName("Batteries")
        .description("Your Mac, AirPods and trackpad charge.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct DeskBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        ClockWidget()
        CalendarWidget()
        WeatherWidget()
        BatteriesWidget()
    }
}
#endif
