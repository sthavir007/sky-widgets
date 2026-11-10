// What the widget shows: written by the host to ~/Library/Application Support/NowPlaying/state.json,
// with the album art next to it as art-<id>.jpg.
import Foundation

struct PlayerState: Codable, Equatable {
    var running = false
    var playing = false
    var title = ""
    var artist = ""
    var album = ""
    var trackID = ""
    var duration: Double = 0      // seconds
    var position: Double = 0      // seconds, at `updatedAt`
    var updatedAt = Date()
    var artFile: String?          // file name inside the folder

    static var folder: URL {
        // the widget is sandboxed, so FileManager's home points into its container; use the real one
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/NowPlaying")
    }
    static var file: URL { folder.appendingPathComponent("state.json") }
    var artURL: URL? { artFile.map { Self.folder.appendingPathComponent($0) } }

    static func load() -> PlayerState {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let d = try? Data(contentsOf: file), let s = try? dec.decode(PlayerState.self, from: d) else { return PlayerState() }
        return s
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: Self.file, options: .atomic)
    }

    /// Where the track would be at `date` if it kept playing.
    func position(at date: Date) -> Double {
        guard playing else { return position }
        return min(duration, position + date.timeIntervalSince(updatedAt))
    }
}

/// Widget buttons → host: Darwin notifications (allowed from the widget's sandbox).
enum Command: String, CaseIterable {
    case playpause, next, previous
    var notification: String { "com.sthavir.nowplaying.\(rawValue)" }
}
