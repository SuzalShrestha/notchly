import AppKit
import SwiftUI

/// Notchly Pro. Polar.sh (https://polar.sh) is the merchant of record: checkout, tax, receipts, subscriptions,
/// refunds and the dashboard for sales, MRR, churn and license activations. A purchase grants a License Keys
/// benefit; the app activates the key once per Mac and revalidates it. Setup steps: PRO.md.
///
/// The app calls only Polar's public customer-portal endpoints, which need no secret, so nothing to leak here.
/// ponytail: the gate runs in an open-source client; anyone can build it with the check removed. It keeps
/// honest users honest. Move premium logic to a server if that ever costs real money.
enum Pro {
    // Fill these from the Polar dashboard before a release. Empty → keys cannot be activated (fail closed).
    /// Settings › General › Organization ID.
    static let organizationID = ""
    /// Products › Benefits › the "License Keys" benefit attached to every Pro product.
    static let benefitID = ""
    /// Products › Checkout Links (one link can offer monthly, yearly and lifetime products).
    static let checkoutLink = ""
    /// Customer portal, where buyers manage their subscription: https://polar.sh/<org-slug>/portal
    static let portalLink = ""
    /// Sandbox for testing: https://sandbox-api.polar.sh/v1/customer-portal/license-keys/
    static let api = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/")!

    static var isConfigured: Bool { !organizationID.isEmpty && !benefitID.isEmpty }
    static var checkout: URL { URL(string: checkoutLink) ?? AppInfo.website }
    static var portal: URL? { URL(string: portalLink) }

    /// What Pro unlocks. Everything else stays free.
    static let modes: Set<NotchMode> = [.agents, .prompter]
    static let widgets: Set<NookWidget> = [.aiUsage, .pulse]

    /// Pro keeps working this long without reaching Polar (travel, outages).
    static let offlineGrace: TimeInterval = 14 * 86400
    static let revalidateEvery: TimeInterval = 12 * 3600
}

struct LicenseState: Codable, Equatable {
    var key = ""
    var activationID = ""
    var displayKey = ""
    var email: String?
    var expiresAt: Date?
    var validatedAt: Date?

    func isPro(now: Date) -> Bool {
        guard !activationID.isEmpty, let v = validatedAt else { return false }
        if let e = expiresAt, e <= now { return false }
        // A validation time in the future means the clock was set back to stretch the grace period.
        return v <= now.addingTimeInterval(300) && now.timeIntervalSince(v) < Pro.offlineGrace
    }
}

@MainActor @Observable
final class License {
    static let shared = License()
    private static let file = "license.json"

    private(set) var state = DataFile.load(License.file, as: LicenseState.self) ?? LicenseState()
    private(set) var busy = false
    var message: String?
    /// `--snapshot` renders Pro views unlocked.
    var unlockedForSnapshots = false
    @ObservationIgnored private var timer: Timer?

    var isPro: Bool { unlockedForSnapshots || state.isPro(now: Date()) }

    func start() {
        Task { await validate() }
        timer = Timer.scheduledTimer(withTimeInterval: Pro.revalidateEvery, repeats: true) { _ in
            Task { @MainActor in await License.shared.validate() }
        }
    }

    func activate(_ raw: String) async {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !busy else { return }
        guard Pro.isConfigured else { message = "Notchly Pro is not on sale in this build yet."; return }
        busy = true
        defer { busy = false }
        do {
            let (data, code) = try await post("activate", ["key": key, "organization_id": Pro.organizationID, "label": Self.deviceLabel])
            guard code == 200, let a = try? Self.decoder.decode(Activation.self, from: data) else {
                message = Self.failure(data, code); return
            }
            // A key for another product of the same Polar organization: give the activation slot back.
            guard a.licenseKey.benefitId == Pro.benefitID else {
                _ = try? await post("deactivate", ["key": key, "organization_id": Pro.organizationID, "activation_id": a.id])
                message = "This key is not for Notchly Pro."; return
            }
            save(LicenseState(key: key, activationID: a.id, displayKey: a.licenseKey.displayKey ?? "",
                              email: a.licenseKey.customer?.email, expiresAt: Self.date(a.licenseKey.expiresAt), validatedAt: Date()))
            message = "Notchly Pro is active. Thank you!"
        } catch {
            message = "Could not reach Polar. Check your connection and try again."
        }
    }

    /// Confirms the key is still granted. A refund, cancelled subscription or revoked key returns 404 and ends Pro;
    /// network errors and server errors keep the last good state until the offline grace runs out.
    func validate() async {
        let s = state
        guard Pro.isConfigured, !s.activationID.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        guard let (data, code) = try? await post("validate", ["key": s.key, "organization_id": Pro.organizationID,
                                                                "activation_id": s.activationID, "benefit_id": Pro.benefitID]),
              state.activationID == s.activationID else { return }
        if code == 200, let k = try? Self.decoder.decode(Key.self, from: data) {
            state.expiresAt = Self.date(k.expiresAt)
            state.email = k.customer?.email ?? state.email
            state.validatedAt = Date()
            save(state)
        } else if code == 404 {
            save(LicenseState())
            message = "Your Pro license is no longer active: it was refunded, cancelled, expired or removed from this Mac."
        }
    }

    /// Frees this Mac's activation slot so the key can be used on another Mac.
    func deactivate() async {
        let s = state
        guard !s.activationID.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        let result = try? await post("deactivate", ["key": s.key, "organization_id": Pro.organizationID, "activation_id": s.activationID])
        guard let code = result?.1, code == 204 || code == 404 else {
            message = "Could not reach Polar, so the key is still active on this Mac. Try again later."; return
        }
        save(LicenseState())
        message = "Removed from this Mac. Enter the key on your other Mac to use Pro there."
    }

    private func save(_ s: LicenseState) {
        state = s
        // Excluded from backup: an activation belongs to this Mac, not to a restore on a new one.
        // ponytail: plain 0600 file like the rest of the data folder; move the key to the Keychain once builds
        // are Developer ID signed (ad-hoc builds change identity on each update, so the Keychain would prompt).
        DataFile.save(s, to: Self.file, excludeFromBackup: true)
    }

    // MARK: Polar API

    private struct Key: Decodable {
        struct Customer: Decodable { let email: String? }
        let benefitId: String
        let displayKey: String?
        let expiresAt: String?
        let customer: Customer?
    }

    private struct Activation: Decodable {
        let id: String
        let licenseKey: Key
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Ephemeral: no cache or cookies on disk for requests that carry the license key.
    private static let session = URLSession(configuration: .ephemeral)

    private func post(_ path: String, _ body: [String: String]) async throws -> (Data, Int) {
        var req = URLRequest(url: Pro.api.appendingPathComponent(path), timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await Self.session.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func failure(_ data: Data, _ code: Int) -> String {
        let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["detail"] as? String
        switch code {
        case 404: return "That license key was not found. Check it and try again."
        case 403: return detail.map { String($0.prefix(200)) } ?? "This key cannot be activated: it is revoked, expired or on too many Macs."
        case 422: return "That does not look like a Notchly license key."
        default: return "Polar returned an error (\(code)). Try again later."
        }
    }

    /// Polar sends ISO 8601 with up to microseconds; the fraction is dropped (second precision is enough).
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
    }

    /// Shown to the buyer in Polar's portal next to each activation, e.g. "Notchly on Mac15,3". No user or host name.
    static var deviceLabel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let model = String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
        return "Notchly on \(model.isEmpty ? "Mac" : model)"
    }

    static func selfTest() {
        let now = Date()
        var s = LicenseState(key: "K", activationID: "A", validatedAt: now.addingTimeInterval(-3600))
        precondition(s.isPro(now: now))
        precondition(!LicenseState().isPro(now: now))
        s.validatedAt = now.addingTimeInterval(-Pro.offlineGrace - 1); precondition(!s.isPro(now: now))
        s.validatedAt = now.addingTimeInterval(86400); precondition(!s.isPro(now: now))
        s.validatedAt = now; s.expiresAt = now.addingTimeInterval(-1); precondition(!s.isPro(now: now))
        s.expiresAt = now.addingTimeInterval(60); precondition(s.isPro(now: now))
        s.activationID = ""; precondition(!s.isPro(now: now))

        precondition(date("2026-01-15T10:20:30.123456Z") == date("2026-01-15T10:20:30Z"))
        precondition(date("2026-01-15T10:20:30+00:00") == date("2026-01-15T10:20:30Z") && date("2026-01-15T10:20:30Z") != nil)
        precondition(date(nil) == nil && date("soon") == nil)

        let json = #"{"id":"act_1","license_key":{"benefit_id":"b1","display_key":"****-AB12","expires_at":null,"status":"granted","customer":{"email":"a@b.c"}}}"#
        let a = try! decoder.decode(Activation.self, from: Data(json.utf8))
        precondition(a.id == "act_1" && a.licenseKey.benefitId == "b1" && a.licenseKey.expiresAt == nil && a.licenseKey.customer?.email == "a@b.c")
        precondition(failure(Data(#"{"detail":"License key activation limit reached"}"#.utf8), 403) == "License key activation limit reached")
        precondition(failure(Data(#"{"detail":[{"msg":"x"}]}"#.utf8), 422).contains("does not look"))
        precondition(deviceLabel.hasPrefix("Notchly on "))
    }
}

// MARK: - Locked views and the Pro settings pane

/// Shown in place of a Pro tab or widget.
struct ProLockedView: View {
    let title: String
    var compact = false
    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            Image(systemName: "lock.fill").font(.system(size: compact ? 14 : 20, weight: .semibold)).foregroundStyle(Theme.claudeLight)
            Text(compact ? title : "\(title) is part of Notchly Pro").font(Theme.title(compact ? 12 : 14)).multilineTextAlignment(.center)
            if !compact {
                Text("Pro unlocks the Agents tab with its mascots, the Prompter, and the AI Usage and Pulse widgets.")
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            }
            HStack(spacing: 6) {
                Button("Upgrade") { NSWorkspace.shared.open(Pro.checkout) }.buttonStyle(FilledButtonStyle(tint: Theme.claude, foreground: .white, compact: true))
                if !compact { Button("Enter Key") { AppDelegate.shared?.openSettings(.pro) }.buttonStyle(GhostButtonStyle(compact: true)) }
            }
        }
        .padding(compact ? 8 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

struct ProPane: View {
    @State private var key = ""

    var body: some View {
        let license = License.shared
        let s = license.state
        SettingsPane(title: "Notchly Pro") {
            if license.isPro {
                SettingsCard(title: "Your license") {
                    SettingsRow(title: "Pro is active", subtitle: s.email) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title2)
                    }
                    Divider()
                    SettingsRow(title: "Key") { Text(s.displayKey.isEmpty ? "••••" : s.displayKey).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                    if let e = s.expiresAt {
                        Divider()
                        SettingsRow(title: "Valid until") { Text(e.formatted(date: .long, time: .omitted)) }
                    }
                    if let v = s.validatedAt {
                        Divider()
                        SettingsRow(title: "Last checked", subtitle: "Pro keeps working offline for 14 days after a check.") {
                            Text(v.formatted(.relative(presentation: .named)))
                        }
                    }
                    Divider()
                    SettingsRow(title: "Billing", subtitle: "Change plan, update your card, get invoices or cancel.") {
                        if let portal = Pro.portal { Link("Manage Subscription", destination: portal) }
                    }
                    Divider()
                    SettingsRow(title: "Move to another Mac", subtitle: "Frees this Mac's activation.") {
                        Button("Deactivate") { Task { await license.deactivate() } }.disabled(license.busy)
                    }
                }
            } else {
                SettingsCard(title: "Unlock everything") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(["Agents tab: live coding agent sessions, plans and alerts", "Roaming agent mascots and agent live activities",
                                 "Prompter: a teleprompter under your camera", "AI Usage and Pulse widgets", "Supports an independent developer"], id: \.self) {
                            Label($0, systemImage: "checkmark.circle.fill").symbolRenderingMode(.multicolor)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                    SettingsRow(title: "Buy Notchly Pro", subtitle: "Secure checkout by Polar. Monthly, yearly or lifetime.") {
                        Button("Upgrade…") { NSWorkspace.shared.open(Pro.checkout) }.buttonStyle(.borderedProminent)
                    }
                }
                SettingsCard(title: "Already bought it?") {
                    SettingsRow(title: "License key", subtitle: "It is in your receipt email and in the Polar customer portal.") {
                        HStack {
                            TextField("NOTCHLY-…", text: $key).textFieldStyle(.roundedBorder).frame(width: 260)
                                .onSubmit { Task { await license.activate(key) } }
                            Button("Activate") { Task { await license.activate(key) } }
                                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || license.busy)
                        }
                    }
                }
            }
            if license.busy { ProgressView().controlSize(.small) }
            if let m = license.message { Text(m).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .onAppear { license.message = nil }
    }
}
