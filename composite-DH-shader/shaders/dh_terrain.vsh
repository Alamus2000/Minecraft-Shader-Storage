#version 330 compatibility

uniform vec3 worldLightVector;

out vec4 blockColor;
out vec2 texcoord;
out float vertexDepth;
out vec3 worldLightVectorUniform;


void main() {
    blockColor = gl_Color;
    texcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vec4 clipPos = ftransform();
    vertexDepth = clipPos.z / clipPos.w; // normalized device coordinate depth
    gl_Position = clipPos;
    worldLightVectorUniform = worldLightVector;
}