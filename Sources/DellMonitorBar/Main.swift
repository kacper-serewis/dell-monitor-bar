import AppKit
import SwiftUI

@main
@MainActor
enum Main {
    static func main() async {
        if CommandLine.arguments.contains("--verify-brightness") {
            await Diagnostics.verifyBrightness()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.indices.contains(index + 1) {
            await Diagnostics.renderPreview(to: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let monitors = await MonitorBackend().scan(forceCapabilities: true)
            let rows: [[String: Any]] = monitors.map { monitor in
                ["name": monitor.name,
                 "brightness": monitor.brightness.map { Int($0.current) } as Any? ?? NSNull(),
                 "contrast": monitor.contrast.map { Int($0.current) } as Any? ?? NSNull(),
                 "input": monitor.input.map { Int($0) } as Any? ?? NSNull(),
                 "inputs": monitor.capabilities?.inputs.map { Int($0) } ?? [],
                 "kvmAdvertised": monitor.capabilities?.supports(0xE7) ?? false,
                 "error": monitor.error as Any? ?? NSNull()]
            }
            if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            if monitors.isEmpty || monitors.contains(where: { $0.error != nil }) { exit(1) }
            return
        }
        MonitorBarApp.main()
    }
}

@MainActor
struct MonitorBarApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra("Dell Monitor Bar", systemImage: "display.2") {
            PanelView(model: model)
        }.menuBarExtraStyle(.window)
    }
}
