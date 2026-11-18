import AppKit
import Combine
import MonitorCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var monitors: [MonitorState] = []
    @Published var isBusy = false
    @Published var message: String?
    @Published var messageIsError = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var levelAdjustments = LevelAdjustments()
    let backend: any MonitorServing
    private var subscriptions = Set<AnyCancellable>()
    private var pendingRefresh = false
    private var pendingCapabilities = false

    init(automaticallyRefresh: Bool = true, backend: any MonitorServing = MonitorBackend()) {
        self.backend = backend
        guard automaticallyRefresh else { return }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(forceCapabilities: true) }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(forceCapabilities: true) }
            .store(in: &subscriptions)
        refresh()
    }

    private func finished() {
        isBusy = false
        if startNextLevelWrite() { return }
        if pendingRefresh {
            let force = pendingCapabilities
            pendingRefresh = false
            pendingCapabilities = false
            refresh(forceCapabilities: force)
        }
    }

    func refresh(forceCapabilities: Bool = false) {
        guard !isBusy else {
            pendingRefresh = true
            pendingCapabilities = pendingCapabilities || forceCapabilities
            return
        }
        isBusy = true
        Task {
            monitors = await backend.scan(forceCapabilities: forceCapabilities)
            levelAdjustments.retainMonitors(Set(monitors.map(\.id)))
            finished()
        }
    }

    func displayedLevel(_ monitor: MonitorState, code: UInt8, reading: VCPValue) -> Double {
        levelAdjustments.value(for: LevelControlID(monitorID: monitor.id, code: code), confirmed: reading.current)
    }

    func updateLevel(_ monitor: MonitorState, code: UInt8, value: Double, maximum: UInt16) {
        levelAdjustments.update(LevelControlID(monitorID: monitor.id, code: code), value: value, maximum: maximum)
    }

    func editLevel(_ monitor: MonitorState, code: UInt8, editing: Bool) {
        levelAdjustments.setEditing(LevelControlID(monitorID: monitor.id, code: code), editing)
        if !editing { startNextLevelWrite() }
    }

    @discardableResult private func startNextLevelWrite() -> Bool {
        guard !isBusy, let write = levelAdjustments.next() else { return false }
        isBusy = true
        message = nil
        Task {
            do {
                let reading = try await backend.level(write.control.monitorID, code: write.control.code, value: write.value)
                if let index = monitors.firstIndex(where: { $0.id == write.control.monitorID }) {
                    if write.control.code == 0x10 { monitors[index].brightness = reading }
                    else { monitors[index].contrast = reading }
                }
            } catch {
                showError(error)
                // Restore the displayed value from the device after a rejected write.
                monitors = await backend.scan(forceCapabilities: false)
            }
            // Publish confirmed readback first, then clear only this request's
            // draft. A newer drag remains visible even if this write failed.
            levelAdjustments.complete(write)
            finished()
        }
        return true
    }

    func setInput(_ monitor: MonitorState, input: UInt8) {
        guard !isBusy, monitor.input != input else { return }
        isBusy = true
        message = nil
        Task {
            do {
                try await backend.input(monitor.id, value: input)
                message = "\(monitor.name): input switch sent."
                messageIsError = false
                if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
                    // The screen may leave this Mac. Don't present the request as readback.
                    monitors[index].input = nil
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                pendingRefresh = true
            } catch {
                message = "Input switch outcome unknown: \(error.localizedDescription) The screen may already have changed inputs."
                messageIsError = true
                pendingRefresh = true
            }
            finished()
        }
    }

    func switchUSB(_ monitor: MonitorState) {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        Task {
            do {
                try await backend.switchUSB(monitor.id)
                message = "USB switch sent to \(monitor.name). The active USB host cannot be read back."
                messageIsError = false
            } catch {
                message = "USB switch outcome unknown: \(error.localizedDescription) Check where USB went before trying again."
                messageIsError = true
            }
            // Debounce accidental double clicks; never repeat the command automatically.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            finished()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && SMAppService.mainApp.status == .requiresApproval {
                message = "Allow Dell Monitor Bar in System Settings → General → Login Items."
                messageIsError = false
            }
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        message = error.localizedDescription
        messageIsError = true
    }
}
