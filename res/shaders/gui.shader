//vertex
#version 330 core

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 texCoord;
layout(location = 2) in float texID;
layout(location = 3) in vec4 color;
layout(location = 4) in vec4 viewport;
layout(location = 5) in float isHsv;

uniform mat3 pr_matrix = mat3(1.0);
uniform mat3 ml_matrix = mat3(1.0);

out DATA
{
	vec2 pos;
	float texID;
	vec2 texCoord;
	vec4 color;
	vec4 viewport;
	float isHsv;
} vs_out;

void main()
{
	gl_Position = vec4(pr_matrix * vec3(position, 1.0), 1.0);
	vs_out.pos = position;
	vs_out.texCoord = vec2(texCoord.x, 1 - texCoord.y);
	vs_out.texID = texID;
	vs_out.color = color;
	vs_out.viewport = viewport;
	vs_out.isHsv = isHsv;
}

//fragment
#version 330 core

layout(location = 0) out vec4 color;

in DATA
{
	vec2 pos;
	float texID;
	vec2 texCoord;
	vec4 color;
	vec4 viewport;
	float isHsv;
} fs_in;

uniform sampler2D textures[32];

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main()
{
	if (fs_in.pos.x < fs_in.viewport.x || fs_in.pos.y < fs_in.viewport.y || fs_in.pos.x > fs_in.viewport.z || fs_in.pos.y > fs_in.viewport.w)
		discard;
	if (fs_in.isHsv > 0.5f)
		color = vec4(hsv2rgb(fs_in.color.xyz),fs_in.color.a);
	else
		color = fs_in.color;
	if (fs_in.texID>0.0)
	{
		int tid = int(fs_in.texID - 0.5);
		color *= texture(textures[tid], fs_in.texCoord);
	}
}
