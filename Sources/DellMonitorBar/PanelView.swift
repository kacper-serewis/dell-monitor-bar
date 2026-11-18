import SwiftUI
import MonitorCore

struct PanelView: View {
    @ObservedObject var model: AppModel
    var refreshOnAppear = true
    @State private var contentHeight: CGFloat = 470

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "display.2").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dell Monitor Bar").font(.headline)
                    Text(model.monitors.isEmpty ? "Your displays, within reach" : "\(model.monitors.count) connected \(model.monitors.count == 1 ? "display" : "displays")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Communicating with monitors") }
            }

            if model.monitors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isBusy ? "Looking for Dell monitors…" : "No Dell monitors found")
                        .font(.subheadline.weight(.medium))
                    Text("Connect a display directly over USB-C, DisplayPort or a supported HDMI connection. Enable DDC/CI in the monitor’s menu.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.monitors) { monitor in
                            MonitorCard(monitor: monitor, model: model)
                        }
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                    })
                }.frame(height: min(560, contentHeight))
                    .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
            }

            if let message = model.message {
                Label(message, systemImage: model.messageIsError ? "exclamationmark.triangle" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(model.messageIsError ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("operation-status")
            }

            Divider()
            HStack {
                Button { model.refresh(forceCapabilities: true) } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.disabled(model.isBusy).help("Read monitor capabilities and current settings again")
                Spacer()
                Menu {
                    Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    Button("About Dell Monitor Bar") {
                        NSApp.orderFrontStandardAboutPanel(options: [
                            .applicationName: "Dell Monitor Bar",
                            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
                            .credits: NSAttributedString(string: "Open-source monitor controls for Apple Silicon.\nKVM support is experimental.\nNot affiliated with Dell.")
                        ])
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    Divider()
                    Button("Quit Dell Monitor Bar") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: { Image(systemName: "gearshape") }
                    .menuStyle(.borderlessButton).frame(width: 26)
                    .accessibilityLabel("Settings")
            }.controlSize(.small)
        }
        .padding(18)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if refreshOnAppear && !model.isBusy { model.refresh() } }
    }
}

private struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 470
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct MonitorCard: View {
    let monitor: MonitorState
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(monitor.name.replacingOccurrences(of: "DELL ", with: ""))
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if let input = monitor.input {
                    Text(Capabilities.inputName(input)).font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.tint.opacity(0.1), in: Capsule())
                }
            }
            if let brightness = monitor.brightness, brightness.maximum > 0, brightness.current <= brightness.maximum {
                LevelSlider(title: "Brightness", symbol: "sun.max", reading: brightness,
                            monitorName: monitor.name, value: levelBinding(code: 0x10, reading: brightness),
                            editingChanged: { model.editLevel(monitor, code: 0x10, editing: $0) })
            }
            if let contrast = monitor.contrast, contrast.maximum > 0, contrast.current <= contrast.maximum {
                LevelSlider(title: "Contrast", symbol: "circle.lefthalf.filled", reading: contrast,
                            monitorName: monitor.name, value: levelBinding(code: 0x12, reading: contrast),
                            editingChanged: { model.editLevel(monitor, code: 0x12, editing: $0) })
            }
            if let caps = monitor.capabilities, !caps.inputs.isEmpty {
                HStack {
                    Label("Input", systemImage: "cable.connector").font(.subheadline)
                    Spacer()
                    Menu {
                        ForEach(caps.inputs, id: \.self) { input in
                            Button {
                                model.setInput(monitor, input: input)
                            } label: {
                                if input == monitor.input {
                                    Label(Capabilities.inputName(input), systemImage: "checkmark")
                                } else { Text(Capabilities.inputName(input)) }
                            }
                        }
                    } label: {
                        Text(monitor.input.map(Capabilities.inputName) ?? "Select input")
                    }.fixedSize().disabled(model.isBusy)
                        .accessibilityLabel("\(monitor.name) input")
                }
            }
            if monitor.capabilities?.supports(0xE7) == true {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Button { model.switchUSB(monitor) } label: {
                        Label("Switch USB host", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }.disabled(model.isBusy)
                        .accessibilityLabel("\(monitor.name) switch USB host")
                    Text("Moves the monitor’s USB devices to the other computer. Experimental; some monitors require PiP/PBP.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let error = monitor.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07), lineWidth: 1))
    }

    private func levelBinding(code: UInt8, reading: VCPValue) -> Binding<Double> {
        Binding(
            get: { model.displayedLevel(monitor, code: code, reading: reading) },
            set: { model.updateLevel(monitor, code: code, value: $0, maximum: reading.maximum) }
        )
    }
}

private struct LevelSlider: View {
    let title: String
    let symbol: String
    let reading: VCPValue
    let monitorName: String
    @Binding var value: Double
    let editingChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label(title, systemImage: symbol).font(.subheadline)
                Spacer()
                Text("\(Int((value / Double(reading.maximum) * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...Double(reading.maximum), onEditingChanged: editingChanged)
                .accessibilityLabel("\(monitorName) \(title.lowercased())")
        }
    }
}
