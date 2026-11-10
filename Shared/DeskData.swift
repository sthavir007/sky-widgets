// Data for the Weather and Batteries widgets, written by the host next to state.json.
import Foundation

private func loadJSON<T: Decodable>(_ name: String) -> T? {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    guard let d = try? Data(contentsOf: PlayerState.folder.appendingPathComponent(name)) else { return nil }
    return try? dec.decode(T.self, from: d)
}

private func saveJSON<T: Encodable>(_ value: T, _ name: String) throws {
    try FileManager.default.createDirectory(at: PlayerState.folder, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    try enc.encode(value).write(to: PlayerState.folder.appendingPathComponent(name), options: .atomic)
}

struct Weather: Codable {
    struct Hour: Codable { var time: Date; var temp: Double; var code: Int; var isDay: Bool }
    var city = "San Diego"
    var temp: Double = 0
    var feelsLike: Double = 0
    var code = 0              // WMO weather code
    var isDay = true
    var high: Double = 0
    var low: Double = 0
    var humidity: Double = 0
    var wind: Double = 0      // mph
    var sunrise: Date?
    var sunset: Date?
    var hours: [Hour] = []
    var updatedAt = Date()

    static func load() -> Weather? { loadJSON("weather.json") }
    func save() throws { try saveJSON(self, "weather.json") }
}

struct Battery: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case mac, trackpad, mouse, keyboard, airpods, airpodLeft, airpodRight, airpodsCase, headphones, other }
    var id: String { name + kind.rawValue }
    var name: String
    var kind: Kind
    var percent: Int
    var charging = false
}

struct Batteries: Codable {
    var items: [Battery] = []
    var updatedAt = Date()

    static func load() -> Batteries? { loadJSON("batteries.json") }
    func save() throws { try saveJSON(self, "batteries.json") }
}

/// WMO weather code → SF Symbol + words.
enum Sky {
    static func symbol(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    static func words(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 80...82: return "Showers"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorms"
        default: return "Cloudy"
        }
    }
}
