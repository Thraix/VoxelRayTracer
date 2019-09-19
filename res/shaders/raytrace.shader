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

const vec3 sphere[] = vec3[](vec3(0,-3,0),vec3(-3,0,0),vec3(3,0,0),vec3(0,3,0));
const vec3 sphereColor[] = vec3[](vec3(1,1,1),vec3(1,0.75,1),vec3(0.75,1,1),vec3(1,1,1));

const vec3 cubePos[] = vec3[](vec3(0,1,6),vec3(1,0,6),vec3(0,0,6),vec3(0,-1,6));

const float sphereRad = 2.0f;
uniform sampler2D u_TextureUnit;

const float c_Pi = 3.141592653;

void main()
{
  vec3 unitDir = normalize(v_Dir);
  float depth = 0;
  bool hasSet = false;
  for(int i = 0;i<sphere.length(); i++)
  {
    float t = dot(sphere[i] - v_CameraPos, unitDir);

    vec3 p = v_Near + unitDir * t;
    float len = length(sphere[i] - p);
    if(len < sphereRad && t > 0)
    {
      // near + dir * t = 0
      // Where on the sphere it collided

      // sphereRad * sphereRad = t3 * t3 + len(sphere[i] - p)^2
      float t1 = t - sqrt(pow(sphereRad,2) - pow(length(sphere[i] - p),2));
      if(t1 < depth || !hasSet)
      {
        vec3 intersect = v_Near + unitDir * t1;
        vec3 spherePos = intersect - sphere[i];
        vec2 texCoord = vec2((atan(spherePos.x, spherePos.z) + c_Pi * 0.5) / c_Pi, (spherePos.y / sphereRad + 1) / 2 );

        vec3 shade = vec3(texture(u_TextureUnit, texCoord)) * sphereColor[i] * pow(sphereRad - len,0.3);
        f_Color = vec4(shade,1);
        depth = t1;
        hasSet = true;
      }
    }
  }
  for(int i = 0;i<cubePos.length();i++)
  {
    float tX1  = (cubePos[i].x - v_Near.x) / unitDir.x;
    float tX2  = (cubePos[i].x + 1 - v_Near.x) / unitDir.x;

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
        if(pX.y < cubePos[i].y+1 && pX.y > cubePos[i].y && pX.z < cubePos[i].z+1 && pX.z > cubePos[i].z)
        {
          float shade = 1 - length(pX.yz - cubePos[i].yz - 0.5);
          f_Color = vec4(shade,shade,shade,1);
          depth = tX;
          hasSet = true;
        }
      }
    }

    float tY1  = (cubePos[i].y - v_Near.y) / unitDir.y;
    float tY2  = (cubePos[i].y + 1 - v_Near.y) / unitDir.y;

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
        if(pY.x < cubePos[i].x+1 && pY.x > cubePos[i].x && pY.z < cubePos[i].z+1 && pY.z > cubePos[i].z)
        {
          float shade = 1 - length(pY.xz - cubePos[i].xz - 0.5);
          f_Color = vec4(shade,shade,shade,1);
          depth = tY;
        }
      }
    }

    float tZ1  = (cubePos[i].z - v_Near.z) / unitDir.z;
    float tZ2  = (cubePos[i].z + 1 - v_Near.z) / unitDir.z;

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
        if(pZ.x < cubePos[i].x+1 && pZ.x > cubePos[i].x && pZ.y < cubePos[i].y+1 && pZ.y > cubePos[i].y)
        {
          float shade = 1 - length(pZ.xy - cubePos[i].xy - 0.5);
          f_Color = vec4(shade,shade,shade,1);
          depth = tZ;
          hasSet = true;
        }
      }
    }
  } 
}
