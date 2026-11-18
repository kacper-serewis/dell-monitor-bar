import Foundation
import DDCBridge
import MonitorCore

struct MonitorState: Identifiable {
    let id: String
    let name: String
    var capabilities: Capabilities?
    var brightness: VCPValue?
    var contrast: VCPValue?
    var input: UInt8?
    var error: String?
}

private final class NativeTransport: DDCTransport {
    let display: DMBDisplay
    init(_ display: DMBDisplay) { self.display = display }
    func exchange(_ frame: [UInt8], replyLength: Int) throws -> [UInt8] {
        let data = try display.exchange(Data(frame), replyLength: UInt(replyLength))
        return Array(data)
    }
}

/// All I/O is serialized off the main actor, including discovery and hotplug.
actor MonitorBackend {
    private var sessions: [String: DDCSession] = [:]
    private var capabilities: [String: Capabilities] = [:]

    func scan(forceCapabilities: Bool = false) -> [MonitorState] {
        let displays = DMBDiscoverDisplays()
        let connected = Set(displays.map(\.identifier))
        sessions = sessions.filter { connected.contains($0.key) }
        capabilities = capabilities.filter { connected.contains($0.key) }
        return displays.map { display in
            let session = DDCSession(transport: NativeTransport(display))
            sessions[display.identifier] = session
            var state = MonitorState(id: display.identifier, name: display.name)
            do {
                if forceCapabilities || capabilities[display.identifier] == nil {
                    // Never keep stale permissions after a failed capability refresh.
                    capabilities[display.identifier] = nil
                    capabilities[display.identifier] = try session.capabilities()
                }
                guard let caps = capabilities[display.identifier] else { throw DDCError.notReady }
                state.capabilities = caps
                var errors: [String] = []
                if caps.supports(0x10) {
                    do { state.brightness = try session.read(0x10) }
                    catch { errors.append("Brightness: \(error.localizedDescription)") }
                }
                if caps.supports(0x12) {
                    do { state.contrast = try session.read(0x12) }
                    catch { errors.append("Contrast: \(error.localizedDescription)") }
                }
                if caps.supports(0x60) {
                    do { state.input = UInt8(try session.read(0x60).current & 0xFF) }
                    catch { errors.append("Input: \(error.localizedDescription)") }
                }
                if !errors.isEmpty { state.error = errors.joined(separator: "\n") }
            } catch { state.error = error.localizedDescription }
            return state
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

    private func connection(_ id: String) throws -> (DDCSession, Capabilities) {
        guard let session = sessions[id], let caps = capabilities[id] else { throw DDCError.notReady }
        return (session, caps)
    }
    func level(_ id: String, code: UInt8, value: UInt16) throws -> VCPValue {
        let (session, caps) = try connection(id)
        return try session.setLevel(code, value: value, capabilities: caps)
    }
    func input(_ id: String, value: UInt8) throws {
        let (session, caps) = try connection(id)
        try session.setInput(UInt16(value), capabilities: caps)
    }
    func switchUSB(_ id: String) throws {
        let (session, caps) = try connection(id)
        try session.switchUSB(capabilities: caps)
    }
}
