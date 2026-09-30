#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;

// Same maths as the web Orb: a ray-marched sphere displaced by 3D value noise,
// lit with a rim term and a two-colour band, with a halo outside.
uniform vec2 uSize;
uniform float uPhase;
uniform float uAmp;
uniform float uDisp;
uniform float uGlow;
uniform vec3 uC1;
uniform vec3 uC2;

out vec4 fragColor;

float hash(vec3 p) { p = fract(p * .3183 + .1); p *= 17.; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }

float noise(vec3 x) {
  vec3 i = floor(x), f = fract(x);
  f = f * f * (3. - 2. * f);
  return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) { float v = 0., a = .5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.; a *= .5; } return v; }

float map(vec3 p) {
  float r = 1. + uAmp * .12;
  return length(p) - r - (uDisp + uAmp * .2) * (fbm(p * 1.8 + vec3(0., 0., uPhase)) - .5) * 2.;
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - .5 * uSize) / min(uSize.x, uSize.y);
  uv.y = -uv.y; // Flutter's y runs down; the light comes from above.
  vec3 ro = vec3(0., 0., 4.4), rd = normalize(vec3(uv * 1.15, -1.5));
  float t = 0.;
  bool hit = false;
  for (int i = 0; i < 64; i++) {
    float d = map(ro + rd * t);
    if (d < .002) { hit = true; break; }
    t += d * .7;
    if (t > 7.) break;
  }
  if (hit) {
    vec3 p = ro + rd * t;
    vec2 e = vec2(.002, 0.);
    vec3 n = normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx)));
    float rim = pow(1. - max(dot(n, -rd), 0.), 2.5);
    float band = fbm(p * 2.5 + uPhase * .4);
    vec3 col = mix(uC1, uC2, band) * (.35 + .65 * max(dot(n, normalize(vec3(.5, .8, .6))), 0.)) + rim * mix(uC2, vec3(1.), .4) * 1.3;
    fragColor = vec4(col, 1.);
  } else {
    float l = length(uv);
    float g = exp(-7. * max(l - .36, 0.)) * (uGlow * .6 + uAmp * .5) * (1. - smoothstep(.4, .5, l));
    g = clamp(g, 0., 1.);
    fragColor = vec4(uC1 * g, g);
  }
}
