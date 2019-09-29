//fragment
#version 450 core

in vec3 v_Near;
in vec3 v_Dir;
in vec3 v_CameraPos;

out vec4 f_Color;

uniform sampler2D u_TextureUnit;
uniform sampler3D u_ChunkTexUnit;
uniform samplerCube u_SkyboxUnit;

uniform float u_MaxRecursionDepth = 4;
uniform float u_MaxRayLength = 200;
uniform int u_Size;
uniform int u_AtlasSize;
uniform int u_AtlasTextureSize;
uniform vec3 u_SunDir;

const int MAX_RAYS = 4;
const int c_Materials = 3;

struct Ray
{
  vec3 pos;
  vec3 dir;
  float rayLength;
  float energy;
  float recursiveDepth;
  bool shadowRay;
};

struct RayIntersection
{
  bool found;
  float voxel;
  int collisionDir;
  int texAxis1;
  int texAxis2;
};

struct Material
{
  float reflectivity;
  float refractivity;
  int texX;
  int texY;
};

// I really want this to be const instead of uniform, 
// but for some reason this causes huge performance decreases.
// I'm talking up to 10 seconds per frame. For unknown reasons.
uniform Material materials[c_Materials] = Material[c_Materials](
  Material(0,1,0,0), // Air
  Material(0,1,0,0), // Stone
  Material(0.6,1.5,0,1) // Glass 
);

bool HasVoxel(float value)
{
  return int(value * 256) > 0;
}

float GetVoxel(vec3 coord)
{
  if(coord.x < 0 || coord.y < 0 || coord.z < 0 || coord.x > u_Size|| coord.y > u_Size || coord.z > u_Size)
    return 0;
  return texture(u_ChunkTexUnit, coord / u_Size).r;
}

Material GetMaterial(float voxel)
{
  int i = clamp(int(voxel * 256), 0, c_Materials-1);
  return materials[i];
}

bool TestCube(vec3 currentPos, vec3 dir, vec3 centerPos, vec3 size)
{
  return ! 
    ((currentPos.x > centerPos.x + size.x / 2 && dir.x > 0) || 
     (currentPos.x < centerPos.x - size.x / 2 && dir.x < 0) ||
     (currentPos.y > centerPos.y + size.y / 2 && dir.y > 0) ||
     (currentPos.y < centerPos.y - size.y / 2 && dir.y < 0) ||
     (currentPos.z > centerPos.z + size.z / 2 && dir.z > 0) ||
     (currentPos.z < centerPos.z - size.z / 2 && dir.z < 0));
}

float CalcEnergy(Ray ray, float block)
{
  if(block < 0.65)
    return pow(ray.energy * 0.8, 2);//pow((ray.energy * 2/4),2);
  else
    return 0;//pow((ray.energy * 2/4),2);
}

vec2 GetTextureCoordinate(vec2 voxelPlane, int x, int y)
{
  vec2 texCoord = voxelPlane - floor(voxelPlane);
  texCoord = vec2(texCoord.x + x, 1 - texCoord.y + y) * u_AtlasTextureSize / u_AtlasSize;
  return vec2(texCoord.x, 1.0f - texCoord.y);
}

void RayCollision(Ray ray, float voxel, vec3 currentPos, float rayLengthTotal, int collisionDir, int axis1, int axis2, inout Ray rays[MAX_RAYS], inout int rayCount, inout vec4 color)
{
  Material material = GetMaterial(voxel);

  // Shadow rays 
  if(ray.recursiveDepth < u_MaxRecursionDepth && rayCount < MAX_RAYS && !ray.shadowRay)
  {
    vec3 normal = vec3(0,0,0);
    normal[collisionDir] = sign(ray.dir[collisionDir]);
    float sig = sign(normal[collisionDir]) * sign(u_SunDir[collisionDir]);
    rays[rayCount].pos = currentPos - u_SunDir * 0.0001 * sig;
    rays[rayCount].dir = u_SunDir;
    rays[rayCount].rayLength = rayLengthTotal;
    rays[rayCount].recursiveDepth = ray.recursiveDepth + 1;
    rays[rayCount].energy = (1.0 - pow(clamp(dot(sig*normal, u_SunDir), 0.0, 1.0),0.4)) / 2 + 0.5;
    rays[rayCount].shadowRay = true;
    rayCount++;
  }

  // Reflection
  if(ray.recursiveDepth < u_MaxRecursionDepth && rayCount < MAX_RAYS && !ray.shadowRay)
  {
    rays[rayCount].pos = currentPos;
    rays[rayCount].dir = ray.dir;
    rays[rayCount].dir[collisionDir] = -ray.dir[collisionDir];
    rays[rayCount].rayLength = rayLengthTotal;
    rays[rayCount].recursiveDepth = ray.recursiveDepth + 1;
    rays[rayCount].energy = material.reflectivity * ray.energy;
    rays[rayCount].shadowRay = false;
    if(rays[rayCount].energy > 0.1)
      rayCount++;
  }
  if(ray.shadowRay)
  {
    color.xyz *= ray.energy;
  }
  else
  {
    vec2 texCoord = GetTextureCoordinate(vec2(currentPos[axis1], currentPos[axis2]),material.texX,material.texY);
    color = mix(vec4(texture(u_TextureUnit, texCoord).xyz, 1.0), color, 1.0 - ray.energy);
  }
}

const int value[3][3] = {{0,2,1}, {1,0,2}, {2,0,1}};

vec4 RayCast(vec3 pos, vec3 dir)
{
  Ray rays[MAX_RAYS];
  int rayCount = 1;
  rays[0].pos = pos;
  rays[0].dir = normalize(dir);
  rays[0].rayLength = 0;
  rays[0].energy = 1;
  rays[0].recursiveDepth = 1;
  rays[0].shadowRay = false;

  vec4 color = vec4(0,0,0,1);

  float iterations = 0;
  for(int i = 0;i<rayCount;i++)
  {
    float rayLengthTotal = rays[i].rayLength;
    float rayLength = 0;
    vec3 currentPos = rays[i].pos;
    vec3 nextPlane = vec3(
        rays[i].dir.x < 0 ? ceil(currentPos.x-1) : floor(currentPos.x+1),
        rays[i].dir.y < 0 ? ceil(currentPos.y-1) : floor(currentPos.y+1),
        rays[i].dir.z < 0 ? ceil(currentPos.z-1) : floor(currentPos.z+1));

    vec3 stepDir = sign(rays[i].dir);

    vec3 t = (nextPlane - rays[i].pos) / rays[i].dir;

    RayIntersection intersection;
    intersection.found = false;
    while(rayLengthTotal < u_MaxRayLength)
    {
      iterations++;
      if(!TestCube(currentPos, rays[i].dir, vec3(u_Size*0.5), vec3(u_Size)))
      {
        rayLengthTotal = u_MaxRayLength;
        break;
      }
      float tMin = min(t.x, min(t.y, t.z));
      /* if(tMin < 0) */
      /* { */
      /*   return color * vec4(1,0,1,1); */
      /* } */
      t -= tMin;
      rayLengthTotal += tMin;
      rayLength += tMin;
      currentPos = rays[i].pos + rayLength * rays[i].dir;
      vec3 eq = vec3(equal(t, vec3(0,0,0)));
      vec3 indices = eq * vec3(0,1,2);
      float voxel = GetVoxel(currentPos + 0.5 * eq * stepDir);
      int index = int(floor(indices.x + indices.y + indices.z));

      if(eq.x + eq.y + eq.z != 0 && HasVoxel(voxel))
      {
        intersection.voxel = voxel;
        intersection.collisionDir = value[index][0];
        intersection.texAxis1 = value[index][1];
        intersection.texAxis2 = value[index][2];
        intersection.found = true;
        break;
      }
      t[value[index][0]] = ((currentPos + stepDir - rays[i].pos) / rays[i].dir - rayLength)[value[index][0]];
    }
    if(intersection.found)
      RayCollision(rays[i], intersection.voxel, currentPos, rayLengthTotal, intersection.collisionDir, intersection.texAxis1, intersection.texAxis2 , rays, rayCount, color);
    else if(!rays[i].shadowRay)
      color = mix(vec4(texture(u_SkyboxUnit, rays[i].dir).xyz, 1.0), color, 1.0 - rays[i].energy);
  }
  /* if(iterations == 1) */
  /*   return vec4(1,0,0,1); */
  /* if(iterations == 2) */
  /*   return vec4(1,1,0,1); */
  /* if(iterations == 3) */
  /*   return vec4(1,0,1,1); */
  /* return vec4(vec3(iterations / 0.0f),1); */
  return color;
}

void main()
{
  f_Color = RayCast(v_Near + vec3(u_Size*0.5), v_Dir);
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
