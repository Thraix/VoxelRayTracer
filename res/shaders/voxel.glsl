//vertex
#version 330 core

layout(location = 0) in vec2 a_Position;

out vec3 v_Near;
out vec3 v_Dir;
out vec3 v_CameraPos;

uniform mat4 u_ViewMatrix;
uniform mat4 u_PVInvMatrix;
uniform vec3 cameraPos;


void main()
{
  vec4 near4 = u_PVInvMatrix * vec4(a_Position, -1.0f, 1.0);
  vec4 far4 = u_PVInvMatrix * vec4(a_Position, 1.0f, 1.0);
  v_Near = vec3(near4) / near4.w;
  v_Dir = vec3(far4) / far4.w - v_Near;
  gl_Position = vec4(a_Position, 0.0f, 1.0f);
  v_CameraPos = vec3(inverse(u_ViewMatrix) * vec4(0,0,0,1));
}

//fragment
#version 330 core

in vec3 v_Near;
in vec3 v_Dir;
in vec3 v_CameraPos;

out vec4 f_Color;

const float sphereRad = 2.0f;
uniform sampler2D u_TextureUnit;
uniform sampler3D u_ChunkTexUnit;

void main()
{
  vec3 unitDir = normalize(v_Dir);
  float depth = 0;
  bool hasSet = false;
  for(int j = 0;j<16;j++)
  {
    for(int i = 0;i<16;i++)
    {
      if(texture(u_ChunkTexUnit, vec3((i + 0.5)/16,(j + 0.5)/16,0.5/16)).r < 0.5)
        continue;
      vec3 pos = vec3(i,j,0);

      float tX1  = (pos.x - v_Near.x) / unitDir.x;
      float tX2  = (pos.x + 1.0f - v_Near.x) / unitDir.x;

      float tX = 0;
      if(tX1 > 0 || tX2 > 0)
      {
        if(tX1 > 0 && tX2 > 0)
        {
          if(tX1 < tX2)
            tX = tX1;
          else 
            tX = tX2;
        }
        else if(tX1 > 0)
          tX = tX1;
        else
          tX = tX2;
        if(tX < depth || !hasSet)
        {
          vec3 pX = v_Near + unitDir * tX;
          if(pX.y < pos.y+1 && pX.y > pos.y && pX.z < pos.z+1 && pX.z > pos.z)
          {
            float shade = 1 - length(pX.yz - pos.yz - 0.5);
            f_Color = vec4(shade,shade,shade,1);
            depth = tX;
            hasSet = true;
          }
        }
      }

      float tY1  = (pos.y - v_Near.y) / unitDir.y;
      float tY2  = (pos.y + 1 - v_Near.y) / unitDir.y;

      float tY = 0;
      if(tY1 > 0 || tY2 > 0)
      {
        if(tY1 > 0 && tY2 > 0)
        {
          if(tY1 < tY2)
            tY = tY1;
          else
            tY = tY2;
        }
        else if(tY1 > 0)
          tY = tY1;
        else
          tY = tY2;
        if(tY < depth || !hasSet)
        {
          vec3 pY = v_Near + unitDir * tY;
          if(pY.x < pos.x+1 && pY.x > pos.x && pY.z < pos.z+1 && pY.z > pos.z)
          {
            float shade = 1 - length(pY.xz - pos.xz - 0.5);
            f_Color = vec4(shade,shade,shade,1);
            depth = tY;
            hasSet = true;
          }
        }
      }

      float tZ1  = (pos.z - v_Near.z) / unitDir.z;
      float tZ2  = (pos.z + 1 - v_Near.z) / unitDir.z;

      float tZ = 0;
      if(tZ1 > 0 || tZ2 > 0)
      {
        if(tZ1 > 0 && tZ2 > 0)
        {
          if(tZ1 < tZ2)
            tZ = tZ1;
          else 
            tZ = tZ2;
        }
        else if(tZ1 > 0)
          tZ = tZ1;
        else
          tZ = tZ2;
        if(tZ < depth || !hasSet)
        {
          vec3 pZ = v_Near + unitDir * tZ;
          if(pZ.x < pos.x+1 && pZ.x > pos.x && pZ.y < pos.y+1 && pZ.y > pos.y)
          {
            float shade = 1 - length(pZ.xy - pos.xy - 0.5);
            f_Color = vec4(shade,shade,shade,1);
            depth = tZ;
            hasSet = true;
          }
        }
      }
    }
  }
}
