import CoreImage
import Foundation

/// Rectangular element removal (watermark, bug, old logo) via a Metal kernel.
/// Kernel: `Metal/RegionRemove.metal`.
enum RegionRemoveKernel {
    private static let kernel = CIKernelLoader.kernel("RegionRemove", "regionRemove")

    /// Rect is normalized to the source extent with `y` measured from the top, matching `Crop`.
    static func apply(_ image: CIImage, extent: CGRect, x: Double, y: Double, width: Double, height: Double) -> CIImage {
        guard let kernel, extent.width > 0, extent.height > 0 else { return image }
        let originX = min(max(x, 0), 1)
        let originY = min(max(y, 0), 1)
        let w = min(max(width, 0), 1 - originX)
        let h = min(max(height, 0), 1 - originY)
        guard w > 0, h > 0 else { return image }

        let minX = extent.origin.x + originX * extent.width
        // Core Image is bottom-left origin; the rect is authored top-left.
        let minY = extent.origin.y + (1 - originY - h) * extent.height
        let box = CGRect(x: minX, y: minY, width: w * extent.width, height: h * extent.height)
        let region = CIVector(x: box.minX, y: box.minY, z: box.maxX, w: box.maxY)
        let sampled = box.insetBy(dx: -1, dy: -1)
        return kernel.apply(
            extent: extent,
            roiCallback: { _, r in r.union(sampled) },
            arguments: [image, region]
        ) ?? image
    }
}
