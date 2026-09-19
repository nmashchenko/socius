import SwiftUI
import Darwin

struct DeveloperRuntimeView: View {
    @Bindable var presence: EdgeDockController
    @State private var memoryMB: Double?
    @State private var peakMB: Double = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            timing("Idle seconds", value: $presence.idleSeconds)
            timing("Peek seconds", value: $presence.peekSeconds)
            HStack {
                Button("Demo 5s") { presence.idleSeconds = 5; presence.peekSeconds = 5 }
                Button("Production") { presence.idleSeconds = 30; presence.peekSeconds = 300 }
            }.font(.system(size: 11))
            Divider()
            if let memoryMB {
                Text(String(format: "Memory  %.1f MB", memoryMB)).monospacedDigit()
                Text(String(format: "Peak while open  %.1f MB", peakMB)).monospacedDigit().foregroundStyle(Palette.muted)
            } else { Text("Memory unavailable") }
            Text("Socius process · updates every second").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.font(.system(size: 11))
        .task {
            while !Task.isCancelled {
                memoryMB = Self.memoryFootprint()
                peakMB = max(peakMB, memoryMB ?? 0)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    private func timing(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number.precision(.fractionLength(0)))
                .labelsHidden().frame(width: 55).textFieldStyle(.roundedBorder)
            Stepper(label, value: value, in: 1...3600, step: 1).labelsHidden()
        }
    }
    static func memoryFootprint() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : nil
    }
}
