#version 330 compatibility

in vec4 blockColor;
in vec2 texcoord;
in float vertexDepth;


out vec4 colorOut;

/* --- DH & composite-like uniforms --- */
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;

uniform sampler2D shadowtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowcolor0;

uniform sampler2D depthtex0;


uniform sampler2D noisetex;

uniform vec3 shadowLightPosition;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform mat4 gbufferModelViewInverse;
uniform float viewWidth;
uniform float viewHeight;

uniform int worldTime;
uniform float sunAngle;

// Debug / tuning uniforms you can tweak in-game (if supported)
uniform int DEBUG_MODE = 0; // 0 = normal, 1 = show baseColor, 2 = show depth, 3 = show shadow, 4 = show NdotL

#include "/lib/distort.glsl"

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

const vec3 blocklightColor = vec3(0.0625, 0.03125, 0.005);
const vec3 skylightColor = vec3(0.025, 0.075, 0.15);
const vec3 sunlightColor = vec3(0.75);
const vec3 ambientColor = vec3(0.25);

vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
    vec4 homPos = projectionMatrix * vec4(position, 1.0);
    return homPos.xyz / homPos.w;
}

/* Basic non-random sample kernel (deterministic) - Poisson-like 9-sample offsets */
const int K_SAMPLES = 9;
vec2 kernel[K_SAMPLES] = vec2[](
    vec2( 0.0,  0.0),
    vec2( 1.0,  0.0),
    vec2(-1.0,  0.0),
    vec2( 0.0,  1.0),
    vec2( 0.0, -1.0),
    vec2( 0.7,  0.7),
    vec2(-0.7,  0.7),
    vec2( 0.7, -0.7),
    vec2(-0.7, -0.7)
);

/* Shadow sampling helpers (safe/clamped) */
vec3 getShadowSampleClamped(vec2 uv) {
    // clamp UVs to avoid sampling outside shadow map (will reduce artifacts)
    vec2 cuv = clamp(uv, vec2(0.001), vec2(0.999));
    // sample the full shadow map (contains translucent & opaque)
    float t = texture(shadowtex0, cuv).r;
    return vec3(t); // used by getShadow logic below
}

vec3 getShadow(vec3 shadowScreenPos){
  // If the shadow map isn't valid at all, default to full light
  if (any(lessThan(shadowScreenPos.xy, vec2(0.0))) || any(greaterThan(shadowScreenPos.xy, vec2(1.0)))) {
    // outside shadow atlas => consider fully lit
    return vec3(1.0);
  }

  float transparentShadow = step(shadowScreenPos.z, texture(shadowtex0, shadowScreenPos.xy).r);
  if(transparentShadow == 1.0){
    return vec3(1.0);
  }

  float opaqueShadow = step(shadowScreenPos.z, texture(shadowtex1, shadowScreenPos.xy).r);
  if(opaqueShadow == 0.0){
    return vec3(0.0);
  }

  vec4 shadowColor = texture(shadowcolor0, shadowScreenPos.xy);
  return shadowColor.rgb * (1.0 - shadowColor.a);
}

/* Deterministic soft shadow: average fixed kernel around the center sample */
vec3 getSoftShadowStable(vec4 shadowClipPos){
  // convert to NDC and screen
  if (shadowClipPos.w <= 0.0) {
    // behind the light or invalid; treat as lit
    return vec3(1.0);
  }
  vec3 shadowNDCPos = shadowClipPos.xyz / shadowClipPos.w;
  vec2 center = shadowNDCPos.xy * 0.5 + 0.5;

  // choose radius in pixels -> convert to uv offset by shadowMapResolution
  float radius = SHADOW_RADIUS;             // keep same tunable radius
  float res = shadowMapResolution;          // defined in your includes
  vec3 accum = vec3(0.0);
  for (int i = 0; i < K_SAMPLES; ++i) {
    vec2 offsetUV = center + (kernel[i] * radius) / res;
    // clamp so we never sample outside
    offsetUV = clamp(offsetUV, vec2(0.001), vec2(0.999));
    // sample shadow using safe method (getShadow expects screenPos with z, but we approximate z with center.z)
    vec3 sample = getShadow(vec3(offsetUV, shadowNDCPos.z));
    accum += sample;
  }
  return accum / float(K_SAMPLES);
}

/* luminance helper */
float luminance(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

void main() {
  // 1) base color
  vec3 baseColor = blockColor.rgb;

  // debug mode: show baseColor
  if (DEBUG_MODE == 1) { fragColor = vec4(baseColor, 1.0); return; }

  // 2) depth & early-out
  vec2 texcoord0 = gl_FragCoord.xy / vec2(viewWidth,viewHeight);
  float depth = texture(depthtex0,texcoord0).r;
  if (depth != 1.0) discard;

  if (DEBUG_MODE == 2) {
    // show depth as grayscale
    fragColor = vec4(vec3(depth), 1.0); return;
  }

  // 3) reconstruct position (view) and world feet pos for shadows
  vec3 NDCPos = vec3(texcoord.xy, depth) * 2.0 - 1.0;
  vec3 viewPos = projectAndDivide(dhProjectionInverse, NDCPos);
  vec3 feetPlayerPos = (gl_ModelViewMatrixInverse * vec4(viewPos, 1.0)).xyz;

  // 4) compute shadow (stable kernel)
  vec3 shadowViewPos = (shadowModelView * vec4(feetPlayerPos, 1.0)).xyz;
  vec4 shadowClipPos = shadowProjection * vec4(shadowViewPos, 1.0);
  vec3 shadow = getSoftShadowStable(shadowClipPos);

  if (DEBUG_MODE == 3) {
    fragColor = vec4(shadow, 1.0); return;
  }

  // 5) world light vector
  vec3 lightVector = normalize(shadowLightPosition);
  mat3 mvInv3 = mat3(gbufferModelViewInverse);
  vec3 worldLightVector = normalize(mvInv3 * lightVector);

  // 6) normal approx & NdotL
  vec3 normal = vec3(0.0, 1.0, 0.0);
  float NdotL = clamp(dot(worldLightVector, normal), 0.0, 1.0);

  if (DEBUG_MODE == 4) {
    fragColor = vec4(vec3(NdotL), 1.0); return;
  }

  // 7) light approximations (from composite)
  float lum = clamp(luminance(baseColor), 0.0, 1.0);
  vec3 blocklight = (0.4 + lum * 0.8) * blocklightColor;
  vec3 skylight  = (0.4 + (1.0 - lum) * 0.6) * skylightColor;

  float time_multi;
  if (worldTime > 0 && worldTime < 6000) {
    time_multi = clamp((worldTime / 2000.0), 0.1, 2.5);
  } else if (worldTime >= 6000 && worldTime < 12000) {
    time_multi = clamp((-worldTime / 2000.0), 0.1, 2.5);
  } else {
    time_multi = 0.1;
  }

  vec3 sunlight = sunlightColor * NdotL * shadow * time_multi;
  vec3 ambient  = ambientColor;

  vec3 finalColor = baseColor * (blocklight + skylight + ambient + sunlight);
  finalColor = finalColor * 0.95 + baseColor * 0.05;

  fragColor = vec4(finalColor, 1.0);
}
