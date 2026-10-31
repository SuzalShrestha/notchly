import AppKit

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

    static func selfTest() {
        precondition(isNewer("v1.1.0", than: "1.0.0") && isNewer("1.10.0", than: "1.9.3") && isNewer("v2", than: "1.99.99"))
        precondition(!isNewer("v1.0.0", than: "1.0.0") && !isNewer("1.0", than: "1.0.0") && !isNewer("v0.9.9", than: "1.0.0"))
        precondition(!isNewer("v1.0.0-beta", than: "1.0.0") && isNewer("v1.0.1-rc1", than: "1.0.0"))
    }
}

private struct LatestRelease: Decodable {
    let tagName: String
    let htmlURL: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url" }
}

/// Manual update check (status menu › Check for Updates…). Never runs on its own.
@MainActor
enum Updates {
    private static var checking = false

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
        if let release, AppInfo.isNewer(release.tagName, than: AppInfo.version) {
            alert.messageText = "Notchly \(release.tagName.drop { $0 == "v" }) is available"
            alert.informativeText = "You have version \(AppInfo.version). Download the new version, quit Notchly, and replace the app in Applications. Your settings and data are kept."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            download = URL(string: release.htmlURL) ?? AppInfo.releases
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
        if alert.runModal() == .alertFirstButtonReturn, let download { NSWorkspace.shared.open(download) }
    }
}
