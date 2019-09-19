//fragment
#version 450 core

in vec3 v_Near;
in vec3 v_Dir;
in vec3 v_CameraPos;

out vec4 f_Color;

uniform sampler2D u_TextureUnit;
uniform sampler3D u_ChunkTexUnit;
uniform samplerCube u_SkyboxUnit;

bool HasVoxel(vec3 coord)
{
  if(coord.x < 0 || coord.y < 0 || coord.z < 0 || coord.x > 15 || coord.y > 15 || coord.z > 15)
    return false;
  return texture(u_ChunkTexUnit, coord/16).r > 0.65;
}

struct Ray
{
  vec3 pos;
  vec3 dir;
  float rayLength;
  int recursiveDepth;
};



vec4 RayCast(vec3 pos, vec3 dir)
{
  vec3 unitDir = normalize(dir);

  Ray ray;
  ray.pos = pos;
  ray.dir = unitDir;
  ray.rayLength  = 0;
  ray.recursiveDepth = 1;

  Ray rays[10];
  int rayCount = 1;
  rays[0] = ray;
  rays[1].recursiveDepth = 3;

  vec4 color = vec4(0,0,0,0);

  for(int i = 0;i<rays.length;i++)
  {
    if(rays[i].recursiveDepth >= 3)
      break;
    float rayLengthTotal = rays[i].rayLength;
    float rayLength = 0;
    vec3 currentPos = rays[i].pos;
    vec3 nextPlane = vec3(
        rays[i].dir.x < 0 ? ceil(currentPos.x-1) : floor(currentPos.x+1),
        rays[i].dir.y < 0 ? ceil(currentPos.y-1) : floor(currentPos.y+1),
        rays[i].dir.z < 0 ? ceil(currentPos.z-1) : floor(currentPos.z+1));

    vec3 stepDir = rays[i].dir / abs(rays[i].dir);

    vec3 t = (nextPlane - rays[i].pos) / rays[i].dir;

    while(rayLengthTotal < 50)
    {
      float tMin = min(t.x, min(t.y, t.z));
      if(tMin < 0)
      {
        return color * vec4(1,0,1,1);
      }
      t -= tMin;
      rayLengthTotal += tMin;
      rayLength += tMin;
      currentPos = rays[i].pos + rayLength * rays[i].dir;

      if(t.x == 0)
      {
        if(HasVoxel(currentPos + vec3(stepDir.x * 0.5,0,0)))
        {
          rays[rayCount].pos = currentPos;
          rays[rayCount].dir = vec3(-unitDir.x, unitDir.y, unitDir.z);
          rays[rayCount].rayLength = rayLengthTotal;
          rays[rayCount].recursiveDepth = rays[i].recursiveDepth + 1;
          rays[rayCount+1].recursiveDepth = 3;
          rayCount++;
          color += vec4(texture(u_TextureUnit, currentPos.zy - floor(currentPos.zy)).xyz /(rays[i].recursiveDepth+1), 1.0);
          break;
        }
        t.x = (currentPos.x + stepDir.x - rays[i].pos.x) / rays[i].dir.x - rayLength;
      }
      else if(t.y == 0)
      {
        if(HasVoxel(currentPos + vec3(0, stepDir.y * 0.5,0)))
        {
          rays[rayCount].pos = currentPos;
          rays[rayCount].dir = vec3(unitDir.x, -unitDir.y, unitDir.z);
          rays[rayCount].rayLength = rayLengthTotal;
          rays[rayCount].recursiveDepth = rays[i].recursiveDepth + 1;
          rays[rayCount+1].recursiveDepth = 3;
          rayCount++;
          color += vec4(texture(u_TextureUnit, currentPos.xz - floor(currentPos.xz)).xyz /(rays[i].recursiveDepth+1), 1.0);
          break;
        }
        t.y = (currentPos.y + stepDir.y - rays[i].pos.y) / rays[i].dir.y - rayLength;
      }
      else if(t.z == 0)
      {
        if(HasVoxel(currentPos + vec3(0, 0, stepDir.z * 0.5)))
        {
          rays[rayCount].pos = currentPos;
          rays[rayCount].dir = vec3(unitDir.x, unitDir.y, -unitDir.z);
          rays[rayCount].rayLength = rayLengthTotal;
          rays[rayCount].recursiveDepth = rays[i].recursiveDepth + 1;
          rays[rayCount+1].recursiveDepth = 3;
          rayCount++;
          color += vec4(texture(u_TextureUnit, currentPos.xy - floor(currentPos.xy)).xyz / (rays[i].recursiveDepth+1), 1.0);
          break;
        }
        t.z = (currentPos.z + stepDir.z - rays[i].pos.z) / rays[i].dir.z - rayLength;
      }
    }
    if(rayLengthTotal > 50)
      color += vec4(texture(u_SkyboxUnit, rays[i].dir).xyz/rays[i].recursiveDepth,1.0);
  }
  return color;
}

void main()
{
  f_Color = RayCast(v_Near + vec3(8,8,8), v_Dir);
  if(f_Color == vec4(0,0,0,0))
  {
    f_Color = texture(u_SkyboxUnit, normalize(v_Dir));
  }
}

//vertex
#version 450 core

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
