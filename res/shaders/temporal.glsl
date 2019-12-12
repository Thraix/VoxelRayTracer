//fragment
#version 450 core

uniform sampler2D u_TextureUnitNew;
uniform sampler2D u_TextureUnitOld;

in vec2 texCoord;

out vec4 color;
uniform int u_Samples = 1;
uniform float u_Alpha = 1.0;

void main()
{
  vec4 averageColor = texture(u_TextureUnitOld, texCoord);
  vec4 newColor = texture(u_TextureUnitNew, texCoord);
  /* color = averageColor + (newColor - averageColor) / u_Samples; */
  color = u_Alpha * newColor + (1 - u_Alpha) * averageColor;
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
