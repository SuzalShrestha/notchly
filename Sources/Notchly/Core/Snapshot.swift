import SwiftUI

/// `Notchly --snapshot <dir>`: renders notch states to PNGs for visual checks without screen capture.
@MainActor
enum Snapshot {
    static func run(to dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let notch = CGSize(width: 185, height: 32)   // 14" MacBook Pro camera housing

        /// AppKit render: unlike ImageRenderer it draws ScrollView content (the agents checklist and grid).
        func renderHosted(_ name: String, _ model: NotchModel) {
            let size = CGSize(width: 900, height: model.shapeSize.height + 30)
            let host = NSHostingView(rootView: ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x3B1278), Color(hex: 0x12061F)], startPoint: .top, endPoint: .bottom)
                NotchRootView(model: model)
            }.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("fail", name); return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name).png"))
            print("wrote", name)
        }

        func render(_ name: String, _ model: NotchModel, wallpaper: Bool = true) {
            let size = CGSize(width: 900, height: model.isOpen ? model.shapeSize.height + 30 : 70)
            let view = ZStack(alignment: .top) {
                if wallpaper {
                    LinearGradient(colors: [Color(hex: 0x3B1278), Color(hex: 0x12061F)], startPoint: .top, endPoint: .bottom)
                }
                NotchRootView(model: model)
            }
            .frame(width: size.width, height: size.height)
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { print("fail", name); return }
            try? png.write(to: out.appendingPathComponent("\(name).png"))
            print("wrote", name)
        }

        let closed = NotchModel(screenID: 0, notchSize: notch, hasPhysicalNotch: true)
        render("closed", closed)
        let pill = NotchModel(screenID: 0, notchSize: CGSize(width: 184, height: 24), hasPhysicalNotch: false)
        render("closed-notchless", pill)

        LiveActivityCenter.shared.show(LiveActivity(
            kind: .batteryVisualizer, priority: 50, leadingWidth: 64, trailingWidth: 44,
            leading: AnyView(Text("Charging").font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.green)),
            trailing: AnyView(Text("82%").font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.green))))
        render("closed-activity", closed)
        LiveActivityCenter.shared.remove(.batteryVisualizer)

        for mode in NotchMode.allCases {
            let m = NotchModel(screenID: 0, notchSize: notch, hasPhysicalNotch: true)
            m.mode = mode
            m.isOpen = true
            render("open-\(mode.rawValue)", m)
        }
        for w in NookWidget.allCases {
            let r = ImageRenderer(content: NookWidgetView(widget: w)
                .frame(width: w.units * 40, height: 156).padding(10).background(.black)
                .environment(NotchModel(screenID: 0, notchSize: notch, hasPhysicalNotch: true))
                .preferredColorScheme(.dark))
            r.scale = 2
            if let tiff = r.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: out.appendingPathComponent("widget-\(w.rawValue).png"))
            }
        }
        func save<V: View>(_ name: String, _ view: V) {
            let r = ImageRenderer(content: view.preferredColorScheme(.dark))
            r.scale = 2
            if let tiff = r.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: out.appendingPathComponent("\(name).png"))
                print("wrote", name)
            } else { print("fail", name) }
        }

        // Closed notch while an agent needs you (pet wing).
        AgentStore.shared.refreshActivities()
        render("closed-agent-alert", NotchModel(screenID: 0, notchSize: notch, hasPhysicalNotch: true))

        // Agents tab in the Grid layout (restored afterwards so a local run keeps the user's choice).
        let layout = AgentsFeature.settings.value.layout
        AgentsFeature.settings.value.layout = .grid
        let grid = NotchModel(screenID: 0, notchSize: notch, hasPhysicalNotch: true)
        grid.mode = .agents
        grid.isOpen = true
        renderHosted("open-agents-grid", grid)
        AgentsFeature.settings.value.layout = .focus
        renderHosted("open-agents-focus", grid)
        AgentsFeature.settings.value.layout = layout

        // Contact sheets: every mood for every mascot, and every act for Claude (posed mid-motion, not animated).
        func tile(_ h: Harness, _ mood: PetMood, _ label: String, t: Double = 0.6, age: Double = 99) -> some View {
            VStack(spacing: 4) {
                Canvas { g, sz in PetPainter(mood: mood, sprite: .of(h), t: t, age: age).draw(&g, sz) }.frame(width: 110, height: 110)
                Text(label).font(Theme.caption).foregroundStyle(.white).lineLimit(1)
            }
            .frame(width: 118)
        }
        let moods: [(String, PetMood)] = [("sleeping", .sleeping), ("idle", .idle), ("thinking", .thinking), ("reading", .working(.read)),
                                          ("building", .working(.build)), ("alert", .alert), ("celebrating", .celebrating),
                                          ("oops", .oops), ("stopped", .stopped)]
        save("pet-moods", VStack(alignment: .leading, spacing: 8) {
            ForEach(Harness.allCases, id: \.self) { h in
                HStack(spacing: 4) { ForEach(moods.indices, id: \.self) { i in tile(h, moods[i].1, "\(h.short) \(moods[i].0)") } }
            }
        }.padding(16).background(.black))
        save("pet-acts", VStack(alignment: .leading, spacing: 8) {
            ForEach([Array(PetAct.allCases.prefix(9)), Array(PetAct.allCases.dropFirst(9))], id: \.self) { row in
                HStack(spacing: 4) { ForEach(row, id: \.self) { a in tile(.claude, .working(a), a.rawValue, t: 1.15) } }
            }
        }.padding(16).background(.black))

        for page in OnboardingPage.allCases {
            save("onboarding-\(page.rawValue + 1)", OnboardingView(page: page) { _ in })
        }
        print("snapshot: done")
    }

    /// `Notchly --pet-reel <dir>`: a storyboard of every mascot through each mood and act, one PNG per
    /// frame at 30 fps, for an animator's frame-by-frame review (verify.sh encodes it with ffmpeg).
    static func reel(to dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let story: [(String, PetMood, Double)] = [
            ("sleeping", .sleeping, 1.6), ("wakes up, thinking", .thinking, 1.8), ("reading", .working(.read), 1.6),
            ("editing", .working(.edit), 1.3), ("running a command", .working(.terminal), 1.3), ("building", .working(.build), 1.4),
            ("running tests", .working(.test), 1.4), ("a step failed", .oops, 1.6), ("searching", .working(.search), 1.4),
            ("researching", .working(.web), 1.4), ("asking a helper", .working(.helper), 1.4), ("installing", .working(.install), 1.4),
            ("shipping", .working(.ship), 1.6), ("needs you", .alert, 2.0), ("you stopped it", .stopped, 2.0),
            ("thinking again", .thinking, 1.0), ("done!", .celebrating, 2.4), ("idle", .idle, 3.0),
        ]
        let fps = 30.0
        var frame = 0, start = 0.0
        var previous: PetMood?
        for (label, mood, length) in story {
            for i in 0..<Int(length * fps) {
                let age = Double(i) / fps, t = 1000 + start + age
                let view = VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        ForEach(Harness.allCases, id: \.self) { h in
                            Canvas { g, sz in PetPainter(mood: mood, sprite: .of(h), t: t, from: previous, age: age).draw(&g, sz) }
                                .frame(width: 150, height: 150)
                        }
                    }
                    Text("\(label)  ·  \(String(format: "%.2f", start + age)) s").font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(width: 900, height: 200).background(Color(hex: 0x0B0B0D))
                let r = ImageRenderer(content: view.preferredColorScheme(.dark))
                r.scale = 1
                if let tiff = r.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: out.appendingPathComponent(String(format: "f%04d.png", frame)))
                }
                frame += 1
            }
            start += length
            previous = mood
        }
        print("reel: \(frame) frames")
    }
}
