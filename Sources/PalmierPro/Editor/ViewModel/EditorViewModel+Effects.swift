import Foundation

/// One owner for writing effect params, so the inspector sliders and the canvas overlays
/// share the same insert order, prune-when-neutral rule, and undo grouping.
extension EditorViewModel {
    static let regionRemoveEffectId = "stylize.regionRemove"

    func toggleRegionRemovalEditing(clipId: String) {
        if regionRemovalClipId == clipId {
            regionRemovalClipId = nil
            return
        }
        guard activePreviewTab == .timeline, clipFor(id: clipId)?.mediaType.isVisual == true else { return }
        cancelChromaKeySampling()
        pause()
        regionRemovalClipId = clipId
    }

    /// Live edit during a drag — no undo entry.
    func applyEffectParams(clipIds: [String], effectId: String, values: [String: Double]) {
        applyClipProperties(clipIds: clipIds) { clip in
            Self.writeEffectParams(into: &clip, effectId: effectId, values: values)
        }
    }

    /// One undoable entry across every target clip.
    func commitEffectParams(clipIds: [String], effectId: String, values: [String: Double], actionName: String) {
        commitClipProperties(clipIds: clipIds, actionName: actionName) { clip in
            Self.writeEffectParams(into: &clip, effectId: effectId, values: values)
        }
    }

    func effectParam(_ clip: Clip, effectId: String, key: String) -> Double? {
        guard let spec = EffectRegistry.descriptor(id: effectId)?.params.first(where: { $0.key == key }) else { return nil }
        return (clip.effects ?? []).first { $0.type == effectId }?
            .params[key]?.resolved(at: 0, default: spec.defaultValue) ?? spec.defaultValue
    }

    private static func writeEffectParams(into clip: inout Clip, effectId: String, values: [String: Double]) {
        var effects = clip.effects ?? []
        upsertEffectParams(&effects, effectId: effectId, values: values)
        clip.effects = effects.isEmpty ? nil : effects
    }

    /// Upserts params into the singleton effect of its type, inserting in canonical order when
    /// first touched and pruning it once every param is back to default, so a neutral
    /// adjustment leaves no effect and no render pass behind.
    nonisolated static func upsertEffectParams(_ effects: inout [Effect], effectId: String, values: [String: Double]) {
        guard let descriptor = EffectRegistry.descriptor(id: effectId) else { return }
        if let i = effects.firstIndex(where: { $0.type == effectId }) {
            for (key, value) in values {
                effects[i].params[key] = EffectParam(value: value)
            }
            let allDefault = descriptor.params.allSatisfy { spec in
                (effects[i].params[spec.key]?.value ?? spec.defaultValue) == spec.defaultValue
            }
            if allDefault { effects.remove(at: i) }
        } else {
            let changesSomething = values.contains { key, value in
                descriptor.params.first { $0.key == key }?.defaultValue != value
            }
            guard changesSomething else { return }
            var effect = descriptor.makeEffect()
            for (key, value) in values {
                effect.params[key] = EffectParam(value: value)
            }
            effects.insert(effect, at: EffectRegistry.insertIndex(effects, for: effectId))
        }
    }
}
