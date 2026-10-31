import Darwin
import SwiftUI

/// CPU, memory, network and disk samples every 2 s while a Pulse widget is visible.
@MainActor @Observable
final class PulseSampler {
    static let shared = PulseSampler()
    private(set) var cpu = 0.0
    private(set) var memory = 0.0
    private(set) var netIn = 0.0
    private(set) var netOut = 0.0
    private(set) var diskFree: Int64 = 0
    private(set) var diskUsed = 0.0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var lastTicks: (busy: UInt64, total: UInt64)?
    @ObservationIgnored private var lastNet: (rx: UInt32, tx: UInt32, at: Date)?

    func attach() {
        users += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { PulseSampler.shared.sample() } }
    }

    func detach() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        timer?.invalidate(); timer = nil; lastTicks = nil; lastNet = nil
    }

    private func sample() {
        if let t = Self.cpuTicks() {
            if let p = lastTicks { cpu = Self.usage(prev: p, cur: t) }
            lastTicks = t
        }
        memory = Self.memoryUsed()
        if let n = Self.netBytes() {
            let now = Date()
            if let p = lastNet {
                let dt = max(now.timeIntervalSince(p.at), 0.1)
                netIn = Double(n.rx &- p.rx) / dt
                netOut = Double(n.tx &- p.tx) / dt
            }
            lastNet = (n.rx, n.tx, now)
        }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity, total > 0 {
            diskFree = free
            diskUsed = 1 - Double(free) / Double(total)
        }
    }

    nonisolated static func usage(prev: (busy: UInt64, total: UInt64), cur: (busy: UInt64, total: UInt64)) -> Double {
        let dt = cur.total &- prev.total
        return dt == 0 ? 0 : min(Double(cur.busy &- prev.busy) / Double(dt), 1)
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var cpus: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpus, &info, &count) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(cpus) {
            let b = i * Int(CPU_STATE_MAX)
            func tick(_ s: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[b + Int(s)])) }
            let used = tick(CPU_STATE_USER) + tick(CPU_STATE_SYSTEM) + tick(CPU_STATE_NICE)
            busy += used
            total += used + tick(CPU_STATE_IDLE)
        }
        return (busy, total)
    }

    /// Activity Monitor's "Memory Used": app (internal − purgeable) + wired + compressed.
    private static func memoryUsed() -> Double {
        var s = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let pages = max(Int64(s.internal_page_count) - Int64(s.purgeable_count), 0) + Int64(s.wire_count) + Int64(s.compressor_page_count)
        return min(Double(pages) * Double(vm_kernel_page_size) / Double(ProcessInfo.processInfo.physicalMemory), 1)
    }

    /// Sum of if_data byte counters on non-loopback links. UInt32 wrapping keeps deltas right across counter wrap.
    private static func netBytes() -> (rx: UInt32, tx: UInt32)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var rx: UInt32 = 0, tx: UInt32 = 0
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let d = ifa.ifa_data,
                  !String(cString: ifa.ifa_name).hasPrefix("lo") else { continue }
            let data = d.assumingMemoryBound(to: if_data.self).pointee
            rx &+= data.ifi_ibytes
            tx &+= data.ifi_obytes
        }
        return (rx, tx)
    }

    nonisolated static func selfTest() {
        assert(usage(prev: (100, 1000), cur: (150, 1100)) == 0.5)
        assert(usage(prev: (5, 10), cur: (5, 10)) == 0)
        assert(UInt32(5) &- UInt32.max == 6)   // wrapped counter still gives the right delta
    }
}

struct PulseWidget: View {
    var body: some View {
        let s = PulseSampler.shared
        let b = PowerMonitor.shared
        WidgetCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(Theme.secondaryText)
                    Text("Pulse").font(Theme.title(13))
                }
                HStack(spacing: 0) {
                    PulseRing(label: "CPU", value: s.cpu, tint: Theme.blue)
                    Spacer(minLength: 2)
                    PulseRing(label: "RAM", value: s.memory, tint: Theme.accent)
                    Spacer(minLength: 2)
                    if b.hasBattery {
                        PulseRing(label: "BAT", value: Double(b.percent) / 100, tint: Theme.green)
                    } else {
                        PulseRing(label: "DISK", value: s.diskUsed, tint: Theme.green)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("↓ \(Self.rate(s.netIn))  ↑ \(Self.rate(s.netOut))")
                    Text("\(Self.bytes(Double(s.diskFree))) free")
                }
                .font(Theme.caption).monospacedDigit().foregroundStyle(Theme.secondaryText).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .onAppear { s.attach() }
        .onDisappear { s.detach() }
    }

    static func rate(_ bytesPerSecond: Double) -> String { bytes(bytesPerSecond) + "/s" }

    static func bytes(_ n: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(n))
    }
}

private struct PulseRing: View {
    let label: String
    let value: Double
    let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Theme.chip, lineWidth: 4)
                Circle().trim(from: 0, to: value).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int((value * 100).rounded()))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 30, height: 30)
            .animation(.easeInOut(duration: 0.6), value: value)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
        }
    }
}
