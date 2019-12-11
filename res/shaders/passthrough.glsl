//fragment
#version 450 core

uniform sampler2D u_TextureUnit;

in vec2 texCoord;

out vec4 color;

void main()
{
  color = texture(u_TextureUnit, texCoord);
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
