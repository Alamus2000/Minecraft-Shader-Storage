#version 330 compatibility

attribute vec4 mc_Entity;

uniform mat4 gbufferModelViewInverse;
uniform int worldTime;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 normal;

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

	normal = gl_NormalMatrix * gl_Normal; // this gives us the normal in view space
	normal = mat3(gbufferModelViewInverse) * normal; // this converts the normal to world/player space
	if (mc_Entity.x == 0.0 || mc_Entity.x == 1.0 || mc_Entity.x == 2.0 || mc_Entity.x == 3.0 || mc_Entity.x == 4.0 || mc_Entity.x == 5.0|| mc_Entity.x == 6.0 || mc_Entity.x == 7.0 || mc_Entity.x == 8.0 || mc_Entity.x == 9.0 || mc_Entity.x == 10.0)
	{
		gl_Position.x = gl_Position.x + cos(worldTime *.05) * .025;
		gl_Position.y = gl_Position.y + sin(worldTime *.05) * .025;
	}
}
