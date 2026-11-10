// Now Playing host: watches Spotify (its PlaybackStateChanged broadcast + AppleScript for the artwork),
// keeps state.json fresh for the widget, runs the widget's play/pause/skip buttons, and opens
// Spotify when the widget is clicked (nowplaying://open). No window, no Dock icon.
import AppKit
import WidgetKit

let spotifyID = "com.spotify.client"

@MainActor
final class Spotify {
    var state = PlayerState.load()
    var dryRun = false            // --print: don't touch state.json
    private var lastArtID = ""

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyID).isEmpty }

    /// Runs AppleScript against Spotify, but never launches it.
    @discardableResult
    func script(_ body: String) -> NSAppleEventDescriptor? {
        guard isRunning else { return nil }
        var err: NSDictionary?
        let r = NSAppleScript(source: "tell application id \"\(spotifyID)\"\n\(body)\nend tell")?.executeAndReturnError(&err)
        if let err { NSLog("NowPlaying: AppleScript \(err)") }
        return r
    }

    func refresh() {
        var s = PlayerState()
        s.running = isRunning
        if s.running, let r = script("""
            set t to current track
            return {player state as string, name of t, artist of t, album of t, id of t, duration of t, player position, artwork url of t}
            """), r.numberOfItems >= 8 {
            func str(_ i: Int) -> String { r.atIndex(i)?.stringValue ?? "" }
            s.playing = str(1) == "playing"
            s.title = str(2); s.artist = str(3); s.album = str(4); s.trackID = str(5)
            s.duration = Double(r.atIndex(6)?.int32Value ?? 0) / 1000
            s.position = r.atIndex(7)?.doubleValue ?? 0
            s.updatedAt = Date()
            s.artFile = state.artFile
            fetchArt(str(8), id: s.trackID)
        }
        // the 30s safety net and Spotify's repeated broadcasts mostly report what we already show;
        // reloading the widget for those cost ~2s of CPU each time
        if s.sameAs(state) { return }
        publish(s)
    }

    func publish(_ s: PlayerState) {
        state = s
        if dryRun { return }
        do { try s.save() } catch { NSLog("NowPlaying: \(error)") }
        // only the Now Playing widget reads state.json; Clock / Calendar / Weather / Batteries have their own timelines
        WidgetCenter.shared.reloadTimelines(ofKind: "NowPlaying")
    }

    private func fetchArt(_ urlString: String, id: String) {
        guard id != lastArtID, let url = URL(string: urlString) else { return }
        lastArtID = id
        let name = "art-" + id.replacingOccurrences(of: ":", with: "_") + ".jpg"
        let dest = PlayerState.folder.appendingPathComponent(name)
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            try? FileManager.default.createDirectory(at: PlayerState.folder, withIntermediateDirectories: true)
            // keep only the current picture
            for f in (try? FileManager.default.contentsOfDirectory(atPath: PlayerState.folder.path)) ?? [] where f.hasPrefix("art-") {
                try? FileManager.default.removeItem(at: PlayerState.folder.appendingPathComponent(f))
            }
            try? data.write(to: dest, options: .atomic)
            if state.trackID == id {
                var s = state; s.artFile = name
                publish(s)
            }
        }
    }

    func run(_ c: Command) {
        switch c {
        case .playpause:
            if !isRunning { openSpotify(); return }
            script("playpause")
            // show the new state right away; Spotify's broadcast confirms it a moment later
            var s = state
            s.position = s.position(at: Date()); s.updatedAt = Date(); s.playing.toggle()
            publish(s)
        case .next: script("next track")
        case .previous: script("previous track")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

extension PlayerState {
    /// Same track, same play state, and the position is where the widget's live progress bar already has it.
    func sameAs(_ o: PlayerState) -> Bool {
        running == o.running && playing == o.playing && title == o.title && artist == o.artist && album == o.album
            && trackID == o.trackID && duration == o.duration && artFile == o.artFile
            && abs(position - o.position(at: updatedAt)) < 2
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let spotify = Spotify()

    func applicationWillFinishLaunching(_ n: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        spotify.refresh()
        // once per launch (login / reinstall), so every widget picks up the installed build and fresh data
        WidgetCenter.shared.reloadAllTimelines()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spotify.refresh() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == spotifyID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.spotify.refresh() }
            }
        }
        // widget buttons
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for c in Command.allCases {
            CFNotificationCenterAddObserver(center, Unmanaged.passUnretained(self).toOpaque(), { _, observer, name, _, _ in
                guard let observer, let raw = name?.rawValue as String?,
                      let cmd = Command.allCases.first(where: { $0.notification == raw }) else { return }
                let d = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { d.spotify.run(cmd) } }
            }, c.notification as CFString, nil, .deliverImmediately)
        }
        // safety net in case a broadcast is missed (e.g. seeking)
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.spotify.refresh() }
        }
        // weather + batteries widgets
        Task { await WeatherFetcher.fetch() }
        BatteryCollector.update()
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in Task { await WeatherFetcher.fetch() } }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in BatteryCollector.update() }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { await WeatherFetcher.fetch() }
            BatteryCollector.update()
        }
        // opened by hand → just bring up Spotify
        if !CommandLine.arguments.contains("--background") { spotify.openSpotify() }
    }

    @objc func openURL(_ e: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        // nowplaying://calendar → Apple Calendar; anything else (nowplaying://open) → Spotify
        let url = e.paramDescriptor(forKeyword: keyDirectObject)?.stringValue.flatMap(URL.init(string:))
        if url?.host == "calendar", let cal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: cal, configuration: NSWorkspace.OpenConfiguration())
        } else {
            spotify.openSpotify()
        }
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        spotify.openSpotify(); return false
    }
}

// `Now Playing --print` prints what the widget would show
if CommandLine.arguments.contains("--print") {
    MainActor.assumeIsolated {
        let s = Spotify(); s.dryRun = true; s.refresh()
        print(String(data: try! JSONEncoder().encode(s.state), encoding: .utf8)!)
    }
    exit(0)
}

// `Now Playing --desk` prints what the weather + batteries widgets would show
if CommandLine.arguments.contains("--desk") {
    let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
    print(String(data: try! enc.encode(BatteryCollector.collect()), encoding: .utf8)!)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
