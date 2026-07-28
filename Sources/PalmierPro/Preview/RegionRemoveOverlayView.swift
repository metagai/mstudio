import AppKit
import SwiftUI

/// Draws the Region Removal rectangle straight on the canvas: drag on bare footage to define it,
/// drag inside to move it, drag a corner to resize. Writes the same effect params as the inspector.
struct RegionRemoveOverlayView: View {
    @Environment(EditorViewModel.self) private var editor

    @State private var dragStart: NormalizedRect?
    @State private var drawOrigin: CGPoint?

    private let handleSize = AppTheme.Spacing.smMd
    private let minSize = 0.02

    var body: some View {
        GeometryReader { geo in
            if let clip = targetClip {
                let frame = editor.activeFrame
                let transform = clip.transformAt(frame: frame)
                let sourceRect = sourceRect(clip, frame: frame, viewSize: geo.size)
                let region = currentRect(clip)
                let regionRect = screenRect(region, in: sourceRect)

                ZStack {
                    Canvas { ctx, _ in
                        ctx.stroke(
                            Path(sourceRect),
                            with: .color(AppTheme.Border.subtleColor),
                            style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thin, dash: [4, 4])
                        )
                        guard region.isDrawable else { return }
                        ctx.fill(Path(regionRect), with: .color(AppTheme.Accent.timecodeColor.opacity(AppTheme.Opacity.muted)))
                        ctx.stroke(Path(regionRect), with: .color(AppTheme.Accent.timecodeColor), lineWidth: AppTheme.BorderWidth.medium)
                    }
                    .allowsHitTesting(false)

                    // Bare footage: a drag here defines a new rectangle.
                    Rectangle()
                        .fill(AppTheme.Background.clearColor)
                        .contentShape(Rectangle())
                        .frame(width: sourceRect.width, height: sourceRect.height)
                        .position(x: sourceRect.midX, y: sourceRect.midY)
                        .onHover { (($0 ? NSCursor.crosshair : NSCursor.arrow)).set() }
                        .gesture(drawGesture(clip: clip, sourceRect: sourceRect))

                    if region.isDrawable {
                        Rectangle()
                            .fill(AppTheme.Background.clearColor)
                            .contentShape(Rectangle())
                            .frame(width: regionRect.width, height: regionRect.height)
                            .position(x: regionRect.midX, y: regionRect.midY)
                            .onHover { (($0 ? NSCursor.openHand : NSCursor.arrow)).set() }
                            .gesture(panGesture(clip: clip, sourceRect: sourceRect))

                        ForEach(Corner.allCases, id: \.self) { corner in
                            let pos = position(corner, in: regionRect)
                            Rectangle()
                                .fill(AppTheme.Accent.timecodeColor)
                                .frame(width: handleSize, height: handleSize)
                                .position(x: pos.x, y: pos.y)
                                .gesture(resizeGesture(clip: clip, corner: corner, sourceRect: sourceRect))
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .rotationEffect(
                    .degrees(transform.rotation),
                    anchor: UnitPoint(x: sourceRect.midX / geo.size.width, y: sourceRect.midY / geo.size.height)
                )
            }
        }
        .onDisappear { NSCursor.arrow.set() }
    }

    // MARK: - Gestures

    private func drawGesture(clip: Clip, sourceRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if drawOrigin == nil { drawOrigin = value.startLocation }
                write(drawnRect(from: value, in: sourceRect), clip: clip, commit: false)
            }
            .onEnded { value in
                let rect = drawnRect(from: value, in: sourceRect)
                drawOrigin = nil
                write(rect, clip: clip, commit: true)
            }
    }

    private func drawnRect(from value: DragGesture.Value, in sourceRect: CGRect) -> NormalizedRect {
        let start = drawOrigin ?? value.startLocation
        let rect = CGRect(
            x: min(start.x, value.location.x),
            y: min(start.y, value.location.y),
            width: abs(value.location.x - start.x),
            height: abs(value.location.y - start.y)
        )
        return normalized(rect, in: sourceRect)
    }

    private func panGesture(clip: Clip, sourceRect: CGRect) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = currentRect(clip) }
                write(panned(value.translation, in: sourceRect), clip: clip, commit: false)
            }
            .onEnded { value in
                let rect = panned(value.translation, in: sourceRect)
                dragStart = nil
                write(rect, clip: clip, commit: true)
            }
    }

    private func panned(_ translation: CGSize, in sourceRect: CGRect) -> NormalizedRect {
        guard let start = dragStart, sourceRect.width > 0, sourceRect.height > 0 else { return dragStart ?? .zero }
        let x = min(max(start.x + Double(translation.width / sourceRect.width), 0), 1 - start.width)
        let y = min(max(start.y + Double(translation.height / sourceRect.height), 0), 1 - start.height)
        return NormalizedRect(x: x, y: y, width: start.width, height: start.height)
    }

    private func resizeGesture(clip: Clip, corner: Corner, sourceRect: CGRect) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = currentRect(clip) }
                write(resized(corner, by: value.translation, in: sourceRect), clip: clip, commit: false)
            }
            .onEnded { value in
                let rect = resized(corner, by: value.translation, in: sourceRect)
                dragStart = nil
                write(rect, clip: clip, commit: true)
            }
    }

    private func resized(_ corner: Corner, by translation: CGSize, in sourceRect: CGRect) -> NormalizedRect {
        guard let start = dragStart, sourceRect.width > 0, sourceRect.height > 0 else { return dragStart ?? .zero }
        let dx = Double(translation.width / sourceRect.width)
        let dy = Double(translation.height / sourceRect.height)
        var minX = start.x, minY = start.y
        var maxX = start.x + start.width, maxY = start.y + start.height
        switch corner {
        case .topLeft:     minX += dx; minY += dy
        case .topRight:    maxX += dx; minY += dy
        case .bottomLeft:  minX += dx; maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        }
        minX = min(max(minX, 0), maxX - minSize)
        minY = min(max(minY, 0), maxY - minSize)
        maxX = max(min(maxX, 1), minX + minSize)
        maxY = max(min(maxY, 1), minY + minSize)
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - State

    private func write(_ rect: NormalizedRect, clip: Clip, commit: Bool) {
        let values = ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
        if commit {
            editor.commitEffectParams(
                clipIds: [clip.id], effectId: EditorViewModel.regionRemoveEffectId,
                values: values, actionName: "Change Region Removal"
            )
        } else {
            editor.applyEffectParams(clipIds: [clip.id], effectId: EditorViewModel.regionRemoveEffectId, values: values)
        }
    }

    private func currentRect(_ clip: Clip) -> NormalizedRect {
        func value(_ key: String) -> Double {
            editor.effectParam(clip, effectId: EditorViewModel.regionRemoveEffectId, key: key) ?? 0
        }
        return NormalizedRect(x: value("x"), y: value("y"), width: value("width"), height: value("height"))
    }

    private var targetClip: Clip? {
        guard let id = editor.regionRemovalClipId, editor.activePreviewTab == .timeline else { return nil }
        return editor.clipFor(id: id)
    }

    // MARK: - Layout

    /// Effects run on the cropped source, so the rect is normalized to the visible crop window.
    private func sourceRect(_ clip: Clip, frame: Int, viewSize: CGSize) -> CGRect {
        let videoRect = PreviewHitTester.videoContentRect(in: viewSize, timeline: editor.timeline)
        let t = clip.transformAt(frame: frame)
        let topLeft = t.topLeft
        let clipRect = CGRect(
            x: videoRect.origin.x + topLeft.x * videoRect.width,
            y: videoRect.origin.y + topLeft.y * videoRect.height,
            width: t.width * videoRect.width,
            height: t.height * videoRect.height
        )
        let crop = clip.cropAt(frame: frame)
        return CGRect(
            x: clipRect.minX + crop.left * clipRect.width,
            y: clipRect.minY + crop.top * clipRect.height,
            width: crop.visibleWidthFraction * clipRect.width,
            height: crop.visibleHeightFraction * clipRect.height
        )
    }

    private func screenRect(_ rect: NormalizedRect, in sourceRect: CGRect) -> CGRect {
        CGRect(
            x: sourceRect.minX + rect.x * sourceRect.width,
            y: sourceRect.minY + rect.y * sourceRect.height,
            width: rect.width * sourceRect.width,
            height: rect.height * sourceRect.height
        )
    }

    private func normalized(_ rect: CGRect, in sourceRect: CGRect) -> NormalizedRect {
        guard sourceRect.width > 0, sourceRect.height > 0 else { return .zero }
        let minX = min(max(Double((rect.minX - sourceRect.minX) / sourceRect.width), 0), 1)
        let minY = min(max(Double((rect.minY - sourceRect.minY) / sourceRect.height), 0), 1)
        let maxX = min(max(Double((rect.maxX - sourceRect.minX) / sourceRect.width), 0), 1)
        let maxY = min(max(Double((rect.maxY - sourceRect.minY) / sourceRect.height), 0), 1)
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func position(_ corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    struct NormalizedRect: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        static let zero = NormalizedRect(x: 0, y: 0, width: 0, height: 0)

        var isDrawable: Bool { width > 0 && height > 0 }
    }
}
