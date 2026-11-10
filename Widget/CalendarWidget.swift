// Month calendar in the glow theme. Clicking it opens Apple Calendar (nowplaying://calendar, handled by the host).
import SwiftUI
import WidgetKit

struct CalendarEntry: TimelineEntry { let date: Date }

struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry { CalendarEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) { completion(CalendarEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        // one entry per day, at midnight, so "today" moves on its own
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let entries = (0..<7).map { CalendarEntry(date: cal.date(byAdding: .day, value: $0, to: today)!) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct MonthView: View {
    let entry: CalendarEntry
    @Environment(\.vibrant) private var vibrant

    /// The month's days laid out in weeks; nil = blank cell before the 1st / after the last day.
    var weeks: [[Int?]] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: entry.date)!.start
        let days = cal.range(of: .day, in: .month, for: entry.date)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { $0 }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.component(.day, from: entry.date)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 }
        let rows = weeks
        let rowHeight: CGFloat = rows.count > 5 ? 17 : 20

        VStack(alignment: .leading, spacing: 0) {
            Text(entry.date.formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Accent())
                .glow(Palette.glow.opacity(0.7))
                .padding(.leading, 3)
                .padding(.bottom, 5)
            HStack(spacing: 0) {
                ForEach(order, id: \.self) { i in
                    Text(symbols[i])
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 3)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let weekend = order[c] == 0 || order[c] == 6
                        if let d = rows[r][c] {
                            let isToday = d == today
                            if isToday && vibrant {
                                // dimmed desktop mode paints everything white, so a dark number on the white
                                // circle vanished; punch the number out of the circle instead
                                ZStack {
                                    Circle().fill(.white)
                                    Text("\(d)")
                                        .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                                .frame(width: 19, height: 19)
                                .frame(maxWidth: .infinity)
                            } else {
                            Text("\(d)")
                                .font(.system(size: 11, weight: isToday ? .heavy : .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(isToday ? AnyShapeStyle(vibrant ? Color.black : Palette.ink)
                                                 : AnyShapeStyle(.white.opacity(d < today ? 0.4 : weekend ? 0.55 : 0.9)))
                                .frame(width: 19, height: 19)
                                .background {
                                    if isToday {
                                        Circle().fill(Accent()).glow(Palette.glow, radius: 6)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .widgetURL(URL(string: "nowplaying://calendar"))
    }
}

#if !PREVIEW
struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Calendar", provider: CalendarProvider()) { entry in
            Themed { MonthView(entry: entry).skyBackdrop().containerBackground(for: .widget) { Themed { GlowBackground() } } }
        }
        .configurationDisplayName("Calendar")
        .description("This month, with today lit up. Click to open Calendar.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
#endif
