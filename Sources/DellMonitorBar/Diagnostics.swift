import AppKit
import SwiftUI

enum Diagnostics {
    /// Explicit opt-in hardware test. It changes brightness by one raw unit,
    /// verifies it, and restores the original even if the first verification fails.
    static func verifyBrightness() async {
        let backend = MonitorBackend()
        let monitors = await backend.scan(forceCapabilities: true)
        guard !monitors.isEmpty else { print("No monitors found"); exit(1) }
        var failed = false
        for monitor in monitors {
            guard let before = monitor.brightness, before.maximum > 0, before.current <= before.maximum else {
                print("\(monitor.name): cannot read original brightness; skipped")
                failed = true
                continue
            }
            let target = before.current > 0 ? before.current - 1 : 1
            do {
                let changed = try await backend.level(monitor.id, code: 0x10, value: target)
                print("\(monitor.name): \(before.current) → \(changed.current)")
            } catch {
                print("\(monitor.name): test failed: \(error.localizedDescription)")
                failed = true
            }
            do {
                let restored = try await backend.level(monitor.id, code: 0x10, value: before.current)
                print("\(monitor.name): restored \(restored.current)")
            } catch {
                print("\(monitor.name): RESTORE FAILED: \(error.localizedDescription)")
                failed = true
            }
        }
        if failed { exit(1) }
    }

    /// Render only this app's own view offscreen, without capturing the desktop.
    @MainActor static func renderPreview(to path: String) async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = AppModel(automaticallyRefresh: false)
        model.monitors = await model.backend.scan(forceCapabilities: true)
        let view = NSHostingView(rootView: PanelView(model: model, refreshOnAppear: false)
            .environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        try? await Task.sleep(nanoseconds: 200_000_000)
        let size = view.fittingSize
        view.setFrameSize(size)
        window.setContentSize(size)
        view.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Rendered \(Int(size.width))×\(Int(size.height)) panel to \(path)")
        } catch { print(error.localizedDescription); exit(1) }
    }
}
