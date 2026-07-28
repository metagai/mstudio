#include <CoreImage/CoreImage.h>
using namespace metal;

// ffmpeg `delogo` in Core Image: replace the box interior by inverse-distance interpolation
// from the four border pixels just outside it. No model, no re-encode, hue-preserving.
// `region` is (minX, minY, maxX, maxY) in source pixels, Core Image bottom-left origin.
extern "C" float4 regionRemove(coreimage::sampler img, float4 region, coreimage::destination dest) {
    float2 p = dest.coord();
    if (p.x < region.x || p.x > region.z || p.y < region.y || p.y > region.w) {
        return img.sample(img.coord());
    }
    float xl = region.x - 1.0;
    float xr = region.z + 1.0;
    float yb = region.y - 1.0;
    float yt = region.w + 1.0;
    float wl = 1.0 / max(p.x - xl, 1.0);
    float wr = 1.0 / max(xr - p.x, 1.0);
    float wb = 1.0 / max(p.y - yb, 1.0);
    float wt = 1.0 / max(yt - p.y, 1.0);
    float4 acc = img.sample(img.transform(float2(xl, p.y))) * wl
               + img.sample(img.transform(float2(xr, p.y))) * wr
               + img.sample(img.transform(float2(p.x, yb))) * wb
               + img.sample(img.transform(float2(p.x, yt))) * wt;
    return acc / (wl + wr + wb + wt);
}
