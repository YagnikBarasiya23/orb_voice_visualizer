#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;

// A ray-marched sphere displaced by 3D value noise, lit with a diffuse term,
// a fresnel rim and a specular highlight, with a halo outside. The silhouette
// is anti-aliased from the ray's closest approach, so the edge stays crisp.
uniform vec2 uSize;
uniform float uPhase;
uniform float uAmp;
uniform float uDisp;
uniform float uGlow;
uniform vec3 uC1;
uniform vec3 uC2;

out vec4 fragColor;

float hash(vec3 p) { p = fract(p * .3183 + .1); p *= 17.; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }

// Quintic fade hides the lattice that a cubic fade leaves in the shading.
float noise(vec3 x) {
  vec3 i = floor(x), f = fract(x);
  f = f * f * f * (f * (f * 6. - 15.) + 10.);
  return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Rotating between octaves hides the axis-aligned blocks that value noise has.
const mat3 rot = mat3(0., .8, .6, -.8, .36, -.48, -.6, -.48, .64);

// Three octaves keep the surface smooth; the colour reads its own, rotated field.
float shape(vec3 p) { float v = 0., a = .5; for (int i = 0; i < 3; i++) { v += a * noise(p); p = rot * p * 2.03; a *= .5; } return v / .875; }

float map(vec3 p) {
  float r = 1. + uAmp * .12;
  return length(p) - r - (uDisp + uAmp * .2) * (shape(p * 1.5 + vec3(0., 0., uPhase)) - .5) * 2.;
}

vec3 shade(vec3 p, vec3 rd) {
  vec2 e = vec2(.0015, 0.);
  vec3 n = normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx)));
  vec3 l = normalize(vec3(.5, .8, .6));
  // Half-Lambert wraps the light round the lumps, so they read as gloss, not grime.
  float diff = pow(dot(n, l) * .5 + .5, 1.6);
  vec3 q = rot * p * 1.3 + vec3(uPhase * .35, 0., uPhase * .2);
  float band = smoothstep(.15, .85, shape(q + .6 * vec3(shape(q + 3.1), shape(q - 1.7), 0.)));
  vec3 base = mix(uC1, uC2, band);
  float rim = pow(1. - max(dot(n, -rd), 0.), 3.);
  float spec = pow(max(dot(reflect(rd, n), l), 0.), 48.);
  vec3 col = base * (.38 + .7 * diff);
  col += rim * mix(uC2, vec3(1.), .45) * 1.15;
  col += spec * .6;
  return clamp(col, 0., 1.);
}

void main() {
  float unit = min(uSize.x, uSize.y);
  vec2 uv = (FlutterFragCoord().xy - .5 * uSize) / unit;
  uv.y = -uv.y; // Flutter's y runs down; the light comes from above.
  vec3 ro = vec3(0., 0., 4.4), rd = normalize(vec3(uv * 1.15, -1.5));

  float t = 0., closest = 1e9, tClosest = 0.;
  bool hit = false;
  for (int i = 0; i < 96; i++) {
    float d = map(ro + rd * t);
    if (d < closest) { closest = d; tClosest = t; }
    if (d < .0008) { hit = true; break; }
    t += d * .75;
    if (t > 7.) break;
  }

  float l = length(uv);
  float g = exp(-7. * max(l - .36, 0.)) * (uGlow * .6 + uAmp * .5) * (1. - smoothstep(.4, .5, l));
  g = clamp(g, 0., 1.);
  vec4 halo = vec4(uC1 * g, g);

  if (hit) {
    fragColor = vec4(shade(ro + rd * t, rd), 1.);
    return;
  }
  // About one logical pixel of the sphere's surface, in world units.
  float edge = 2.6 / unit;
  float cover = 1. - smoothstep(0., edge, closest);
  if (cover <= 0.) {
    fragColor = halo;
    return;
  }
  fragColor = mix(halo, vec4(shade(ro + rd * tClosest, rd), 1.), cover);
}
