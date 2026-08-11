import AppKit
import Foundation

/// A film recipe: the per-shot prompts and narration a film was built from.
///
/// Same document the web editor reads and writes, so a film can move between the two and
/// between people. Field names mirror the gateway's storyboard so importing needs no mapping —
/// every mapping layer is somewhere the two formats can drift apart.
struct MetagRecipe: Codable, Sendable {
    struct Shot: Codable, Sendable {
        var prompt: String
        var narration: String
        var engine: String?
        var seconds: Double?
    }

    var metag_recipe: Int = 1
    var title: String?
    var lang: String?
    var shots: [Shot]
}

@MainActor
enum MetagRecipeIO {

    /// Build a recipe from what is on the timeline.
    ///
    /// Only shots we generated are included. Imported footage has no prompt, so writing it
    /// out would hand someone a recipe that silently rebuilds an incomplete film.
    static func build(from editor: EditorViewModel) -> MetagRecipe {
        let fps = Double(max(editor.timeline.fps, 1))
        let clips = editor.timeline.tracks
            .filter { $0.type == .video }
            .flatMap(\.clips)
            .sorted { $0.startFrame < $1.startFrame }
        var shots: [MetagRecipe.Shot] = []
        for clip in clips {
            guard let asset = editor.generatedAsset(clipId: clip.id),
                  let input = asset.generationInput,
                  input.backendJobId?.isEmpty == false
            else { continue }
            shots.append(
                MetagRecipe.Shot(
                    prompt: input.prompt,
                    narration: "",
                    engine: input.model,
                    seconds: (Double(clip.durationFrames) / fps * 100).rounded() / 100
                )
            )
        }
        return MetagRecipe(title: nil, lang: nil, shots: shots)
    }

    nonisolated static func decode(_ data: Data) throws -> MetagRecipe {
        let recipe = try JSONDecoder().decode(MetagRecipe.self, from: data)
        guard recipe.metag_recipe == 1, !recipe.shots.isEmpty, recipe.shots.count <= 8 else {
            throw Failure.unrecognised
        }
        guard recipe.shots.allSatisfy({ !$0.prompt.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw Failure.unrecognised
        }
        return recipe
    }

    /// Rebuild a film from a recipe.
    ///
    /// Always on our own engine regardless of what the recipe declares — a recipe from someone
    /// else should not be able to spend your credits at flagship rates without you choosing to.
    static func submit(_ recipe: MetagRecipe) async throws -> String {
        try await MetagGateway.submitStoryboard(
            title: recipe.title ?? recipe.shots[0].prompt,
            prompts: recipe.shots.map(\.prompt),
            narrations: recipe.shots.map(\.narration)
        )
    }

    enum Failure: LocalizedError {
        case unrecognised
        case nothingToExport

        var errorDescription: String? {
            switch self {
            case .unrecognised: return L10n.key("That file is not a METAG recipe.")
            case .nothingToExport: return L10n.key("This timeline has no generated shots to export.")
            }
        }
    }
}

@MainActor
extension EditorWindowController {

    @objc func exportRecipe(_ sender: Any?) {
        let recipe = MetagRecipeIO.build(from: editorViewModel)
        guard !recipe.shots.isEmpty else {
            editorViewModel.mediaPanelToast = MediaPanelToast(
                message: MetagRecipeIO.Failure.nothingToExport.localizedDescription
            )
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "film.recipe.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(recipe)) ?? Data()
        let editor = editorViewModel
        Task.detached {
            do {
                try data.write(to: url, options: .atomic)
                await MainActor.run {
                    editor.mediaPanelToast = MediaPanelToast(
                        message: L10n.key("Recipe saved."), kind: .success
                    )
                }
            } catch {
                await MainActor.run {
                    editor.mediaPanelToast = MediaPanelToast(message: error.localizedDescription)
                }
            }
        }
    }

    @objc func importRecipe(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let editor = editorViewModel
        Task {
            do {
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                let recipe = try MetagRecipeIO.decode(data)
                let jobId = try await MetagRecipeIO.submit(recipe)
                editor.mediaPanelToast = MediaPanelToast(
                    message: L10n.string("Rebuilding \(recipe.shots.count.formatted()) shots from the recipe."),
                    kind: .progress
                )
                Log.generation.notice("recipe import started job \(jobId)")
            } catch {
                editor.mediaPanelToast = MediaPanelToast(message: error.localizedDescription)
            }
        }
    }
}
