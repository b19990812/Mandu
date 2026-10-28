#pragma once
namespace CurlShaders {
constexpr const char* Vertex = R"glsl(#version 300 es
precision highp float;
layout(location=0) in vec2 aUv;
uniform vec2 uScreen;
uniform vec2 uLeaf; // origin x, width; both normalized by physical screen width
uniform float uReverse;
uniform float uSheet;
uniform vec4 uFold; // normal.xy, axis.xy in leaf-width units
uniform float uRadius;
out vec2 vUv;
out vec2 vWorld;
out vec3 vNormal;
out float vHeight;
void main() {
    vUv = aUv;
    vec2 local = vec2(aUv.x, aUv.y * uScreen.y / uLeaf.y);
    vec2 projected = local;
    float height = 0.0;
    vNormal = vec3(0.0,0.0,1.0);
    if (uSheet > 0.5) {
        float q = dot(local - uFold.zw,uFold.xy);
        if (q > 0.0) {
            float r = max(0.000001,uRadius);
            float theta = clamp(q/r,0.0,3.14159265359);
            float mapped = q < 3.14159265359*r ? r*sin(theta) : -(q-3.14159265359*r);
            projected += (mapped-q)*uFold.xy;
            height = r*(1.0-cos(theta))*uLeaf.y;
            vNormal = vec3(-sin(theta)*uFold.xy,cos(theta));
        }
    }
    float side = uReverse > 0.5 ? -1.0 : 1.0;
    vNormal.x *= side;
    float x = uSheet > 0.5 ? uLeaf.x + side*projected.x*uLeaf.y : aUv.x;
    float y = uSheet > 0.5 ? projected.y*uLeaf.y : aUv.y*uScreen.y;
    vWorld = vec2(x,y);
    vHeight = height;
    // Orthographic projection keeps the grabbed corner at the actual finger,
    // without perspective drift or a global scale/rotation of the image.
    gl_Position = vec4(x*2.0-1.0,1.0-y/uScreen.y*2.0,uSheet > 0.5 ? 0.2-height : 0.65,1.0);
}
)glsl";
constexpr const char* Fragment = R"glsl(#version 300 es
precision highp float;
uniform sampler2D uFront;
uniform sampler2D uBehind;
uniform vec2 uScreen;
uniform vec2 uLeaf;
uniform vec4 uFold;
uniform float uRadius;
uniform float uReverse;
uniform float uSheet;
uniform float uBook;
uniform float uBase; // 0 full target, 1 current, 2 target outgoing half
uniform float uProgress;
in vec2 vUv;
in vec2 vWorld;
in vec3 vNormal;
in float vHeight;
out vec4 color;
void main() {
    bool reverse = uReverse > 0.5;
    if (uSheet < 0.5) {
        bool current = uBase > 0.5 && uBase < 1.5;
        if (uBase > 2.5) { current = reverse ? vUv.x >= 0.5 : vUv.x <= 0.5; }
        color = current ? texture(uFront,vUv) : texture(uBehind,vUv);
        if (uProgress > 0.00001 && uProgress < 0.99999) {
            vec2 local = vec2((vWorld.x-uLeaf.x)*(reverse ? -1.0 : 1.0)/uLeaf.y,vWorld.y/uLeaf.y);
            float distance = dot(local-uFold.zw,uFold.xy);
            float softness = max(0.016,uRadius*1.4);
            float strength = sin(uProgress*3.14159265359);
            float shade = exp(-abs(distance)/softness)*0.23*strength;
            color.rgb *= 1.0-shade;
        }
        return;
    }
    vec2 frontUv = vec2(uLeaf.x+(reverse ? -1.0 : 1.0)*vUv.x*uLeaf.y,vUv.y);
    vec3 normal = normalize(vNormal);
    bool back = normal.z < 0.0;
    if (!back) {
        color = texture(uFront,frontUv);
    } else if (uBook > 0.5) {
        // The reverse of a leaf is the receiving half of the NEW spread.
        // UV decreases with material x so final text is upright, never mirrored.
        vec2 backUv = vec2(0.5+(reverse ? 1.0 : -1.0)*vUv.x*uLeaf.y,vUv.y);
        color = texture(uBehind,backUv);
    } else {
        // A single-page image does not contain its physical reverse side.
        // Render opaque paper; never reuse a mirrored comic as its backside.
        float fibre = sin(vUv.x*1900.0+vUv.y*310.0)*0.002;
        color = vec4(vec3(0.963,0.955,0.927)+fibre,1.0);
    }
    vec3 litNormal = back ? -normal : normal;
    vec3 light = normalize(vec3(-0.3,-0.4,1.4));
    float diffuse = max(0.0,dot(litNormal,light));
    float bend = 1.0-abs(normal.z);
    float illumination = clamp(0.77+0.23*diffuse-0.11*bend,0.66,1.0);
    float shine = pow(max(0.0,dot(litNormal,normalize(vec3(-0.15,-0.2,1.0)))),25.0)*bend*0.055;
    color.rgb = clamp(color.rgb*illumination+shine,0.0,1.0);
    color.a = 1.0;
}
)glsl";
}
