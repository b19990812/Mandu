#include "CurlGeometry.h"
// Deliberately independent of EGL/NAPI: the same functions run in the native
// renderer and in the bounded host geometry replay.
extern "C" double sin(double);
extern "C" double cos(double);
extern "C" double sqrt(double);
static float Bound(float x, float low, float high) { return x < low ? low : x > high ? high : x; }
CurlFold CurlMakeFold(float width, float height, float progress, float cornerY, float fingerY, float velocity)
{
    constexpr float pi = 3.14159265358979323846f;
    const float p = Bound(progress, 0, 1);
    const float cy = Bound(cornerY, 0, 1) * height;
    const float dx = 2 * width * p;
    const float reach = static_cast<float>(sqrt(Bound(4 * p * (1-p),0,1))) * width;
    const float lead = 1.7f * width * (p < 0.5f ? p : 1-p);
    const float limit = reach < lead ? reach : lead;
    const float dy = Bound(cy - Bound(fingerY,0,1) * height,-limit,limit);
    const float distance = static_cast<float>(sqrt(dx * dx + dy * dy));
    if (p < 0.00001f || distance < 0.00001f) { return {1, 0, width + 1, cy, 0}; }
    const float nx = dx / distance;
    const float ny = dy / distance;
    const float speed = Bound(velocity < 0 ? -velocity : velocity, 0, 4);
    const float desired = width * (0.105f + 0.012f * speed) * static_cast<float>(sin(pi * p));
    const float spineLimit = Bound((2 * nx * width - distance)/pi,0,width);
    const float radius = Bound(desired,0,spineLimit < distance*0.24f ? spineLimit : distance*0.24f);
    const float bend = (distance + pi * radius) * 0.5f;
    return {nx, ny, width - nx * bend, cy - ny * bend, radius};
}
CurlPoint CurlProject(float x, float y, CurlFold f)
{
    constexpr float pi = 3.14159265358979323846f;
    const float q = (x - f.axisX) * f.nx + (y - f.axisY) * f.ny;
    if (q <= 0) { return {x, y, 0, 0, 0, 1}; }
    const float r = f.radius > 0.000001f ? f.radius : 0.000001f;
    const float angle = Bound(q / r, 0, pi);
    const float curved = q < pi * r ? r * static_cast<float>(sin(angle)) : -(q - pi * r);
    return {x + (curved - q) * f.nx, y + (curved - q) * f.ny,
        r * (1 - static_cast<float>(cos(angle))), -static_cast<float>(sin(angle)) * f.nx,
        -static_cast<float>(sin(angle)) * f.ny, static_cast<float>(cos(angle))};
}
