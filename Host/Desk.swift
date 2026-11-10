// Feeds the Weather (San Diego, Open-Meteo, no key needed) and Batteries widgets.
import Foundation
import IOKit.ps
import WidgetKit

enum WeatherFetcher {
    static let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=32.7157&longitude=-117.1611"
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m"
        + "&hourly=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset"
        + "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America%2FLos_Angeles&forecast_days=2")!

    struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double, apparent_temperature: Double, relative_humidity_2m: Double
            let weather_code: Int, is_day: Int, wind_speed_10m: Double
        }
        struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int]; let is_day: [Int] }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double]; let sunrise: [String]; let sunset: [String] }
        let current: Current, hourly: Hourly, daily: Daily
    }

    static func fetch() async {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Response.self, from: data) else { NSLog("NowPlaying: weather fetch failed"); return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        var w = Weather()
        w.temp = r.current.temperature_2m
        w.feelsLike = r.current.apparent_temperature
        w.humidity = r.current.relative_humidity_2m
        w.code = r.current.weather_code
        w.isDay = r.current.is_day == 1
        w.wind = r.current.wind_speed_10m
        w.high = r.daily.temperature_2m_max.first ?? 0
        w.low = r.daily.temperature_2m_min.first ?? 0
        w.sunrise = r.daily.sunrise.first.flatMap(f.date)
        w.sunset = r.daily.sunset.first.flatMap(f.date)
        let now = Date()
        w.hours = r.hourly.time.indices.compactMap { i in
            guard let t = f.date(from: r.hourly.time[i]), t > now.addingTimeInterval(-3600) else { return nil }
            return Weather.Hour(time: t, temp: r.hourly.temperature_2m[i], code: r.hourly.weather_code[i], isDay: r.hourly.is_day[i] == 1)
        }.prefix(12).map { $0 }
        w.updatedAt = now
        do { try w.save() } catch { NSLog("NowPlaying: \(error)") }
        WidgetCenter.shared.reloadTimelines(ofKind: "Weather")
    }
}

enum BatteryCollector {
    static func run(_ path: String, _ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return Data() }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return d
    }

    static func percent(_ any: Any?) -> Int? {
        guard let s = any as? String else { return nil }
        return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    static func collect() -> Batteries {
        var items: [Battery] = []

        // this Mac
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                items.append(Battery(name: "MacBook", kind: .mac, percent: cur * 100 / max,
                                     charging: (d[kIOPSIsChargingKey] as? Bool ?? false) || onAC))
            }
        }

        // AirPods: each earbud is its own power source (Part Identifier Left / Right / Case).
        // A bud that's charging is sitting in the case, so only the ones in use are shown.
        let pods = airPods()
        items += pods

        // Bluetooth names / types / AirPods levels
        var names: [String: (String, String)] = [:]   // address → (name, minor type)
        let sp = run("/usr/sbin/system_profiler", ["-json", "SPBluetoothDataType"])
        if let root = try? JSONSerialization.jsonObject(with: sp) as? [String: Any],
           let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first {
            for (key, value) in bt where key.hasSuffix("connected") {
                let connected = key == "device_connected"
                for entry in value as? [[String: Any]] ?? [] {
                    for (name, raw) in entry {
                        guard let dev = raw as? [String: Any] else { continue }
                        let type = dev["device_minorType"] as? String ?? ""
                        if let addr = dev["device_address"] as? String { names[addr.uppercased()] = (name, type) }
                        guard connected else { continue }
                        let short = name.replacingOccurrences(of: #"^.*['’]s "#, with: "", options: .regularExpression)
                        let l = percent(dev["device_batteryLevelLeft"]), r = percent(dev["device_batteryLevelRight"])
                        if l != nil || r != nil {
                            if !pods.isEmpty { continue }   // already listed per earbud
                            items.append(Battery(name: short, kind: .airpods, percent: [l, r].compactMap { $0 }.min()!))
                            if let c = percent(dev["device_batteryLevelCase"]) {
                                items.append(Battery(name: "Case", kind: .airpodsCase, percent: c))
                            }
                        } else if let m = percent(dev["device_batteryLevelMain"]) {
                            items.append(Battery(name: short, kind: kind(type), percent: m))
                        }
                    }
                }
            }
        }

        // Magic Trackpad / Mouse / Keyboard report through IOKit
        let io = run("/usr/sbin/ioreg", ["-r", "-a", "-l", "-k", "BatteryPercent"])
        if let list = try? PropertyListSerialization.propertyList(from: io, format: nil) as? [[String: Any]] {
            for d in list {
                guard let pct = d["BatteryPercent"] as? Int else { continue }
                let addr = (d["DeviceAddress"] as? String ?? "").replacingOccurrences(of: "-", with: ":").uppercased()
                let (fullName, type) = names[addr] ?? ((d["Product"] as? String) ?? "Accessory", "")
                let short = fullName.replacingOccurrences(of: #"^.*['’]s "#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #" #\d+$"#, with: "", options: .regularExpression)
                let flags = d["BatteryStatusFlags"] as? Int ?? 0
                if items.contains(where: { $0.name == short }) { continue }
                items.append(Battery(name: short, kind: kind(type.isEmpty ? short : type), percent: pct, charging: flags & 0x2 != 0))
            }
        }
        return Batteries(items: items, updatedAt: Date())
    }

    /// IOPSCopyPowerSourcesByType(kIOPSSourceAll) also lists Bluetooth accessories (not exported in the SDK headers).
    static func airPods() -> [Battery] {
        typealias ByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let sym = dlsym(h, "IOPSCopyPowerSourcesByType"),
              let info = unsafeBitCast(sym, to: ByType.self)(0)?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        var buds: [Battery] = [], cases: [Battery] = []
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d["Type"] as? String == "Accessory Source",
                  let part = d["Part Identifier"] as? String,
                  let pct = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            switch part {
            case "Left": buds.append(Battery(name: "Left", kind: .airpodLeft, percent: pct, charging: charging))
            case "Right": buds.append(Battery(name: "Right", kind: .airpodRight, percent: pct, charging: charging))
            case "Case": cases.append(Battery(name: "Case", kind: .airpodsCase, percent: pct, charging: charging))
            default: continue
            }
        }
        let inUse = buds.filter { !$0.charging }
        return (inUse.isEmpty ? buds : inUse).sorted { $0.name < $1.name } + cases
    }

    static func kind(_ type: String) -> Battery.Kind {
        let t = type.lowercased()
        if t.contains("trackpad") { return .trackpad }
        if t.contains("mouse") { return .mouse }
        if t.contains("keyboard") { return .keyboard }
        if t.contains("head") { return .headphones }
        return .other
    }

    static func update() {
        DispatchQueue.global(qos: .utility).async {
            let b = collect()
            // levels change slowly; skip the save + widget reload when nothing moved
            if Batteries.load()?.items == b.items { return }
            do { try b.save() } catch { NSLog("NowPlaying: \(error)") }
            WidgetCenter.shared.reloadTimelines(ofKind: "Batteries")
        }
    }
}
