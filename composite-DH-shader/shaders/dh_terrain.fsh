#version 330 compatibility

in vec4 blockColor;
in vec2 texcoord;
in vec3 worldLightVectorUniform;

out vec4 fragColor;

uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
uniform sampler2D depthtex0;

uniform float viewWidth;
uniform float viewHeight;
uniform int worldTime;
uniform float sunAngle;

uniform int DEBUG_MODE;

#include "/lib/distort.glsl"

/* Lighting constants */
const vec3 blocklightColor = vec3(0.125, 0.0625, 0.01);
const vec3 skylightColor  = vec3(0.025, 0.075, 0.15);
const vec3 sunlightColor  = vec3(0.4);
const vec3 ambientColor   = vec3(0.15);
const float MIN_AMBIENT   = 0.01;

/* Helper functions */
float luminance(vec3 c){ return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 projectAndDivide(mat4 projectionMatrix, vec3 position){
    vec4 homPos = projectionMatrix * vec4(position, 1.0);
    return homPos.xyz / homPos.w;
}

void main() {
    // 1) Base color from DH
    vec3 baseColor = blockColor.rgb;
    if (DEBUG_MODE == 1) { fragColor = vec4(baseColor, 1.0); return; }

    // 2) Depth discard: only render distant terrain (DH pass)
    vec2 texcoord0 = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float depth = texture(depthtex0, texcoord0).r;
    if (depth != 1.0) discard;
    if (DEBUG_MODE == 2) { fragColor = vec4(vec3(depth), 1.0); return; }

    // 3) Lighting vector (from vertex uniform)
    vec3 worldLightVector = normalize(worldLightVectorUniform);

    // 4) Simple normal
    vec3 normal = vec3(0.0, 1.0, 0.0);
    float NdotL = max(dot(worldLightVector, normal), 0.0);
    if (DEBUG_MODE == 4) { fragColor = vec4(vec3(NdotL), 1.0); return; }

    // 5) Approximate lightmap based on brightness
    float lum = clamp(luminance(baseColor), 0.0, 1.0);
    vec3 blocklight = (0.4 + lum * 0.8) * blocklightColor;
    vec3 skylight  = (0.4 + (1.0 - lum) * 0.6) * skylightColor;
    float horizonLight = 0.25 + 0.75 * NdotL;

    // Optional: faint backscatter to keep distant terrain from going pitch-black
    float backScatter = 0.2 * (1.0 - NdotL);

    // 6) Time-of-day adjustment
    float time_multi;
    if (worldTime <= 1000.0) {
        time_multi = worldTime / 1000.0; // dawn
    } else if (worldTime < 12000.0) {
        time_multi = 1.0; // day
    } else if (worldTime <= 13000.0) {
        time_multi = 1.0 - (worldTime - 12000.0) / 1000.0; // dusk
    } else {
        time_multi = 0.1; // night
    }

    // 7) Simple direct sunlight — no soft shadow sampling
    vec3 sunlight = sunlightColor * (horizonLight + backScatter) * time_multi;

    // 8) Ambient term
    vec3 ambient = ambientColor + vec3(0.12) * (1.0 - NdotL);

    // 9) Combine all light components
    vec3 finalColor = baseColor * (blocklight + skylight + ambient + sunlight);

    fragColor = vec4(finalColor, 1.0);
}
