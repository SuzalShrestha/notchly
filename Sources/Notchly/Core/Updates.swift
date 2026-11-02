import AppKit
import CryptoKit

/// App identity and project links, shared by the menu, About pane and network clients.
enum AppInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let repository = "SuzalShrestha/notchly"
    static let website = URL(string: "https://suzalshrestha.github.io/notchly/")!
    static let sourceCode = URL(string: "https://github.com/\(repository)")!
    static let releases = URL(string: "https://github.com/\(repository)/releases/latest")!
    static let newIssue = URL(string: "https://github.com/\(repository)/issues/new/choose")!
    /// Sent to LRCLIB and GitHub, which ask clients to name themselves.
    static let userAgent = "Notchly/\(version) (https://github.com/\(repository))"

    /// Component-wise numeric compare: "v1.10.0" is newer than "1.9.3"; missing components count as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.drop { $0 == "v" || $0 == "V" }.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Only a page of this repository on github.com is opened from an update check, whatever the API returns.
    static func isReleasePage(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host?.lowercased() == "github.com", url.user == nil, url.port == nil else { return false }
        return url.path.lowercased().hasPrefix("/\(repository.lowercased())/")
    }

    static func selfTest() {
        precondition(isReleasePage(URL(string: "https://github.com/SuzalShrestha/notchly/releases/tag/v1.2.0")))
        precondition(!isReleasePage(URL(string: "https://github.com.evil.io/SuzalShrestha/notchly/")) && !isReleasePage(URL(string: "http://github.com/SuzalShrestha/notchly/x")))
        precondition(!isReleasePage(URL(string: "https://github.com/SuzalShrestha/notchly-fake/x")) && !isReleasePage(URL(string: "file:///tmp/x")) && !isReleasePage(nil))
        precondition(isNewer("v1.1.0", than: "1.0.0") && isNewer("1.10.0", than: "1.9.3") && isNewer("v2", than: "1.99.99"))
        precondition(!isNewer("v1.0.0", than: "1.0.0") && !isNewer("1.0", than: "1.0.0") && !isNewer("v0.9.9", than: "1.0.0"))
        precondition(!isNewer("v1.0.0-beta", than: "1.0.0") && isNewer("v1.0.1-rc1", than: "1.0.0"))
        precondition(isReleasePage(URL(string: "https://github.com/SuzalShrestha/notchly/releases/download/v1.2.0/Notchly.zip")))
        let sum = String(repeating: "ab", count: 32)
        precondition(Updates.digest(in: "\(sum)  Notchly.zip\n") == sum && Updates.digest(in: "nope") == nil && Updates.digest(in: "") == nil)
    }
}

private struct LatestRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let url: String
        enum CodingKeys: String, CodingKey { case name, url = "browser_download_url" }
    }
    let tagName: String
    let htmlURL: String
    let assets: [Asset]?
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url", assets }

    var version: String { String(tagName.drop { $0 == "v" || $0 == "V" }) }
    /// Download link of an asset, only from this repository's release pages on github.com.
    func asset(_ name: String) -> URL? {
        (assets ?? []).first { $0.name == name }.flatMap { URL(string: $0.url) }.flatMap { AppInfo.isReleasePage($0) ? $0 : nil }
    }
}

/// Update check and self-install. With automatic updates on (default), it checks GitHub 20 s after launch and every
/// 6 hours, downloads a newer release, verifies it, and asks to restart; "Later" installs it when Notchly quits.
/// The menu's Check for Updates… does the same on demand.
///
/// ponytail: trust is HTTPS to this repository's GitHub release plus the published SHA-256, the same trust as a
/// manual download. Anyone who can publish a release here can ship code; add an EdDSA signature over the zip, with
/// the private key kept off GitHub, if that matters.
@MainActor
enum Updates {
    /// Own key: GeneralSettings has no tolerant decoder, so a new field there would reset older installs' settings.
    static let automatic = Setting("autoUpdate", default: true)
    private static var checking = false
    private static var timer: Timer?
    /// A verified newer app in Caches, waiting for a restart or quit.
    private static var staged: URL?

    /// A real .app bundle in a folder we can write (not App Translocation, not a read-only volume).
    static var canInstall: Bool {
        let app = Bundle.main.bundleURL, fm = FileManager.default
        return app.pathExtension == "app" && fm.isWritableFile(atPath: app.path)
            && fm.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    static func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { background() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in MainActor.assumeIsolated { background() } }
    }

    private static func background() {
        guard automatic.value, canInstall, !checking, staged == nil else { return }
        checking = true
        Task {
            defer { checking = false }
            guard let r = await latest(), AppInfo.isNewer(r.tagName, than: AppInfo.version), let app = await stage(r) else { return }
            staged = app
            let alert = NSAlert()
            alert.messageText = "Notchly \(r.version) is ready"
            alert.informativeText = "Restart Notchly to start using it, or it installs the next time Notchly quits. Your settings and data are kept."
            // "Later" is the default: this alert takes focus unasked, so a stray Return must not restart the app.
            alert.addButton(withTitle: "Later")
            alert.addButton(withTitle: "Restart Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn { install(relaunch: true) }
        }
    }

    /// `--install-update`: installs the latest release without asking and restarts (used to test updates end to end).
    static func installLatestNow() {
        Task {
            guard let r = await latest(), AppInfo.isNewer(r.tagName, than: AppInfo.version), canInstall,
                  let app = await stage(r) else { print("update: nothing installed"); return }
            staged = app
            print("update: installing", r.version)
            install(relaunch: true)
        }
    }

    /// Called from applicationWillTerminate: a staged update replaces the app once this process has exited.
    static func installOnQuit() { install(relaunch: false) }

    private static func install(relaunch: Bool) {
        guard let app = staged else { return }
        staged = nil
        // Waits for this process to exit, swaps the bundles (rolling back if the move fails), then reopens.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        old="$3.old.$$"
        if mv "$3" "$old"; then
          if mv "$2" "$3"; then rm -rf "$old"; else mv "$old" "$3"; fi
        fi
        [ "$4" = 1 ] && /usr/bin/open "$3"
        exit 0
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "notchly-update", "\(getpid())", app.path, Bundle.main.bundleURL.path, relaunch ? "1" : "0"]
        guard (try? p.run()) != nil else { return }
        if relaunch { NSApp.terminate(nil) }
    }

    /// Downloads the release zip, checks it against the published SHA-256, unpacks it, and accepts the app only if it
    /// has our bundle ID, the release's version, and a valid signature. nil on any failure.
    private static func stage(_ r: LatestRelease) async -> URL? {
        guard let zipURL = r.asset("Notchly.zip"), let sumURL = r.asset("Notchly.zip.sha256"),
              let (sumData, sumResp) = try? await URLSession.shared.data(for: request(sumURL)), ok(sumResp),
              let want = digest(in: String(decoding: sumData, as: UTF8.self)),
              let (zip, zipResp) = try? await URLSession.shared.download(for: request(zipURL)), ok(zipResp),
              let data = try? Data(contentsOf: zip),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == want else { return nil }
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Notchly-Update", isDirectory: true)
        try? fm.removeItem(at: dir)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }
        let app = dir.appendingPathComponent("Notchly.app")
        let unpacked = await Task.detached { run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) }.value
        guard unpacked, let b = Bundle(url: app), b.bundleIdentifier == Bundle.main.bundleIdentifier,
              (b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == r.version else { return nil }
        let signed = await Task.detached { run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) }.value
        return signed ? app : nil
    }

    /// The hex digest at the start of a `shasum -a 256` line.
    nonisolated static func digest(in text: String) -> String? {
        let d = text.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        return d.count == 64 && d.allSatisfy(\.isHexDigit) ? d : nil
    }

    private nonisolated static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 120
        return req
    }

    private static func ok(_ r: URLResponse) -> Bool { (r as? HTTPURLResponse)?.statusCode == 200 }

    static func check() {
        guard !checking else { return }
        checking = true
        Task {
            let release = await latest()
            checking = false
            present(release)
        }
    }

    private static func latest() async -> LatestRelease? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppInfo.repository)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(LatestRelease.self, from: data)
    }

    private static func present(_ release: LatestRelease?) {
        let alert = NSAlert()
        var download: URL?
        var installable: LatestRelease?
        if let release, AppInfo.isNewer(release.tagName, than: AppInfo.version) {
            alert.messageText = "Notchly \(release.version) is available"
            if canInstall {
                alert.informativeText = "You have version \(AppInfo.version). Notchly downloads the update, checks it, and restarts. Your settings and data are kept."
                alert.addButton(withTitle: "Install and Restart")
                installable = release
            } else {
                alert.informativeText = "You have version \(AppInfo.version). Download the new version, quit Notchly, and replace the app in Applications. Your settings and data are kept."
                alert.addButton(withTitle: "Download")
            }
            alert.addButton(withTitle: "Later")
            download = URL(string: release.htmlURL).flatMap { AppInfo.isReleasePage($0) ? $0 : nil } ?? AppInfo.releases
        } else if release != nil {
            alert.messageText = "Notchly is up to date"
            alert.informativeText = "Version \(AppInfo.version) is the latest release."
        } else {
            alert.messageText = "Could not check for updates"
            alert.informativeText = "GitHub did not answer. Check your connection, or open the releases page."
            alert.addButton(withTitle: "Open Releases")
            alert.addButton(withTitle: "OK")
            download = AppInfo.releases
        }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let installable {
            Task {
                if let app = await stage(installable) { staged = app; install(relaunch: true); return }
                // Verification or download failed: fall back to the release page.
                let fail = NSAlert()
                fail.messageText = "The update could not be installed"
                fail.informativeText = "Download it from the release page and replace the app in Applications."
                fail.addButton(withTitle: "Open Release Page")
                fail.addButton(withTitle: "Cancel")
                if fail.runModal() == .alertFirstButtonReturn, let download { NSWorkspace.shared.open(download) }
            }
        } else if let download {
            NSWorkspace.shared.open(download)
        }
    }
}
