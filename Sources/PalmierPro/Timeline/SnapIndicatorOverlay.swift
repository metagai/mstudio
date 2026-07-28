import AppKit

/// Dashed yellow snap-line CAShapeLayer. Two X sources (local drag, external drop) —
@MainActor
final class SnapIndicatorOverlay {
    private let layer = CAShapeLayer()
    private weak var view: TimelineView?

    private var localX: Double?
    private var externalX: Double?

    init(view: TimelineView) {
        self.view = view
        // systemYellow 压在时间轴纸底(#F4F1EA)上只有 1.34:1 —— 1px 虚线等于不存在。
        // 品牌绿 5.20:1，且在深色片段上同样读得出。
        layer.strokeColor = DesignTokens.accent.cgColor
        layer.fillColor = nil
        layer.lineWidth = 1
        layer.lineDashPattern = [4, 4]
        layer.zPosition = 90
        layer.isHidden = true
        view.layer?.addSublayer(layer)
    }

    func setLocalX(_ x: Double?) {
        guard localX != x else { return }
        localX = x
        update()
    }

    func setExternalX(_ x: Double?) {
        guard externalX != x else { return }
        externalX = x
        update()
    }

    private func update() {
        guard let view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let viewport = view.visibleRect
        if let x = localX ?? externalX, !viewport.isEmpty {
            let geo = view.geometry
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - viewport.minX, y: Double(geo.rulerHeight) - viewport.minY))
            path.addLine(to: CGPoint(x: x - viewport.minX, y: Double(view.bounds.height) - viewport.minY))
            layer.path = path
            if layer.frame != viewport {
                layer.frame = viewport
            }
            layer.isHidden = false
        } else {
            layer.isHidden = true
            layer.path = nil
        }
        CATransaction.commit()
    }
}
