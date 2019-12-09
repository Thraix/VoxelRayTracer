//fragment
#version 450 core

uniform sampler2D u_TextureUnitNew;
uniform sampler2D u_TextureUnitOld;

in vec2 texCoord;

out vec4 color;

uniform float alpha = 0.9;

void main()
{
  color = texture(u_TextureUnitNew, texCoord) * alpha + texture(u_TextureUnitOld, texCoord) * (1 - alpha);
}

//vertex
#version 450 core

layout(location = 0) in vec2 a_Position;

out vec2 texCoord;

void main()
{
  gl_Position = vec4(a_Position, 0.0, 1.0);
  texCoord = (a_Position + 1.0) * 0.5;
}
