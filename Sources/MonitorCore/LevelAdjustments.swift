import Foundation

public struct LevelControlID: Hashable {
    public let monitorID: String
    public let code: UInt8
    public init(monitorID: String, code: UInt8) {
        self.monitorID = monitorID
        self.code = code
    }
}

public struct LevelWrite: Equatable {
    public let control: LevelControlID
    public let value: UInt16
    fileprivate let revision: UInt64
}

/// UI drafts stay visible until their own write settles. A late reply for an
/// older adjustment must never replace a newer drag or a queued target.
public struct LevelAdjustments {
    private struct Draft {
        let value: Double
        let revision: UInt64
    }
    private var drafts: [LevelControlID: Draft] = [:]
    private var editing: Set<LevelControlID> = []
    private var queue: [LevelControlID] = []
    private var revision: UInt64 = 0

    public init() {}

    public func value(for control: LevelControlID, confirmed: UInt16) -> Double {
        drafts[control]?.value ?? Double(confirmed)
    }

    public mutating func update(_ control: LevelControlID, value: Double, maximum: UInt16) {
        guard value.isFinite else { return }
        revision &+= 1
        drafts[control] = Draft(value: min(Double(maximum), max(0, value)), revision: revision)
    }

    public mutating func setEditing(_ control: LevelControlID, _ isEditing: Bool) {
        if isEditing {
            editing.insert(control)
        } else {
            editing.remove(control)
            if drafts[control] != nil && !queue.contains(control) { queue.append(control) }
        }
    }

    public mutating func next() -> LevelWrite? {
        // Skip sliders being dragged without blocking other monitors' controls.
        guard let index = queue.firstIndex(where: { !editing.contains($0) }) else { return nil }
        let control = queue.remove(at: index)
        guard let draft = drafts[control] else { return next() }
        return LevelWrite(control: control, value: UInt16(draft.value.rounded()), revision: draft.revision)
    }

    public mutating func complete(_ write: LevelWrite) {
        guard drafts[write.control]?.revision == write.revision,
              !editing.contains(write.control) else { return }
        drafts[write.control] = nil
    }

    public mutating func retainMonitors(_ ids: Set<String>) {
        drafts = drafts.filter { ids.contains($0.key.monitorID) }
        editing = editing.filter { ids.contains($0.monitorID) }
        queue.removeAll { !ids.contains($0.monitorID) }
    }
}
