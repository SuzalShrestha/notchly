import SwiftUI

/// `Notchly --snapshot <dir>`: renders notch states to PNGs for visual checks without screen capture.
@MainActor
enum Snapshot {
    static func run(to dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let notch = CGSize(width: 185, height: 32)   // 14" MacBook Pro camera housing

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
        render("open-agents-grid", grid)
        AgentsFeature.settings.value.layout = layout

        let moods: [(String, PetMood)] = [("sleeping", .sleeping), ("idle", .idle), ("thinking", .thinking), ("working-edit", .working(.edit)),
                                          ("working-command", .working(.command)), ("alert", .alert), ("celebrating", .celebrating), ("oops", .oops)]
        save("pet-moods", HStack(spacing: 8) {
            ForEach(moods.indices, id: \.self) { i in
                VStack(spacing: 4) {
                    PetView(mood: moods[i].1, size: 120, animated: false)
                    Text(moods[i].0).font(Theme.caption).foregroundStyle(.white)
                }
            }
        }.padding(16).background(.black))

        for page in OnboardingPage.allCases {
            save("onboarding-\(page.rawValue + 1)", OnboardingView(page: page) { _ in })
        }
        print("snapshot: done")
    }
}
