//fragment
#version 450 core

in vec3 v_Near;
in vec3 v_Dir;
in vec3 v_CameraPos;

out vec4 f_Color;

uniform sampler2D u_TextureUnit;
uniform sampler3D u_ChunkTexUnit;
uniform samplerCube u_SkyboxUnit;

uniform float u_MaxRayLength = 200;
uniform int u_Size;
uniform int u_AtlasSize;
uniform int u_AtlasTextureSize;
uniform vec3 u_SunDir;

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
  float voxel;
  vec3 collisionPoint;
  float rayLength;
  int collisionDir;
  int texAxis1;
  int texAxis2;
  bool found;
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
uniform Material materials[c_Materials] = {
  Material(0,1,0,0), // Air
  Material(0,1,0,0), // Stone
  Material(0.6,1.5,0,1) // Glass
};

const int intersectionAxis[3][3] = {{0,2,1}, {1,0,2}, {2,0,1}};

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

vec2 GetTextureCoordinate(vec2 voxelPlane, int x, int y)
{
  vec2 texCoord = voxelPlane - floor(voxelPlane);
  texCoord = vec2(texCoord.x + x, 1 - texCoord.y + y) * u_AtlasTextureSize / u_AtlasSize;
  return vec2(texCoord.x, 1.0f - texCoord.y);
}

vec3 RayColor(Ray ray, RayIntersection intersection, vec3 color)
{
  Material material = GetMaterial(intersection.voxel);
  vec2 texCoord = GetTextureCoordinate(
      vec2(
        intersection.collisionPoint[intersection.texAxis1],
        intersection.collisionPoint[intersection.texAxis2]),
      material.texX,material.texY);
  return mix(texture(u_TextureUnit, texCoord).xyz, color, 1.0 - ray.energy);
}

RayIntersection RayMarch(Ray ray)
{
  float iterations = 0;
  float rayLength = 0;
  vec3 currentPos = ray.pos;
  vec3 nextPlane = vec3(
      ray.dir.x < 0 ? ceil(currentPos.x-1) : floor(currentPos.x+1),
      ray.dir.y < 0 ? ceil(currentPos.y-1) : floor(currentPos.y+1),
      ray.dir.z < 0 ? ceil(currentPos.z-1) : floor(currentPos.z+1));

  vec3 stepDir = sign(ray.dir);

  vec3 t = (nextPlane - ray.pos) / ray.dir;

  while(rayLength < u_MaxRayLength)
  {
    iterations++;
    if(!TestCube(currentPos, ray.dir, vec3(u_Size*0.5), vec3(u_Size)))
    {
      return RayIntersection(0, vec3(0,0,0), 0, 0, 1, 2, false);
    }
    float tMin = min(t.x, min(t.y, t.z));
    t -= tMin;
    rayLength += tMin;
    currentPos = ray.pos + rayLength * ray.dir;
    vec3 eq = vec3(equal(t, vec3(0,0,0)));
    vec3 indices = eq * vec3(0,1,2);
    float voxel = GetVoxel(currentPos + 0.5 * eq * stepDir);
    int index = int(floor(indices.x + indices.y + indices.z));

    if(HasVoxel(voxel))
    {
      return RayIntersection(
          voxel,
          currentPos,
          ray.rayLength + rayLength,
          intersectionAxis[index][0],
          intersectionAxis[index][1],
          intersectionAxis[index][2], true);
    }

    t[intersectionAxis[index][0]] = ((currentPos + stepDir - ray.pos) / ray.dir - rayLength)[intersectionAxis[index][0]];
  }
  return RayIntersection(0, vec3(0,0,0), 0, 0, 1, 2, false);
}

Ray GetShadowRay(Ray ray, RayIntersection intersection)
{
  Ray shadowRay;
  vec3 normal = vec3(0,0,0);
  normal[intersection.collisionDir] = sign(ray.dir[intersection.collisionDir]);
  float sig = sign(normal[intersection.collisionDir]) * sign(u_SunDir[intersection.collisionDir]);
  shadowRay.pos = intersection.collisionPoint - u_SunDir * 0.0001 * sig;
  shadowRay.dir = u_SunDir;
  shadowRay.rayLength = intersection.rayLength;
  shadowRay.recursiveDepth = ray.recursiveDepth + 1;
  shadowRay.energy = (1.0 - pow(clamp(dot(sig*normal, u_SunDir), 0.0, 1.0),0.4)) / 2 + 0.5;
  shadowRay.shadowRay = true;
  return shadowRay;
}

Ray GetReflectionRay(Ray ray, RayIntersection intersection)
{
  Material material = GetMaterial(intersection.voxel);
  Ray reflectionRay;
  reflectionRay.pos = intersection.collisionPoint;
  reflectionRay.dir = ray.dir;
  reflectionRay.dir[intersection.collisionDir] = -ray.dir[intersection.collisionDir];
  reflectionRay.rayLength = intersection.rayLength;
  reflectionRay.energy = material.reflectivity * ray.energy;
  reflectionRay.shadowRay = false;
  return reflectionRay;
}

vec3 GetSkyboxColor(Ray ray, vec3 color)
{
  vec3 unitDir = normalize(ray.dir);
  float sun = 10 * pow(dot(normalize(u_SunDir), unitDir), 400.0);
  float grad = (unitDir.y + 1.0) * 0.5;
  vec3 skyboxColor = max(vec3(0,grad*0.75,grad), vec3(sun, sun, 0));
  return mix(skyboxColor, color, 1.0 - ray.energy);
}

void main()
{
  vec3 color = vec3(0,0,0);
  Ray ray = Ray(v_Near + vec3(u_Size*0.5), v_Dir, 0, 1, 1, false);
  RayIntersection intersection = RayMarch(ray);
  if(intersection.found)
  {
    color = RayColor(ray, intersection, color);
    // Shadow ray
    Ray shadowRay = GetShadowRay(ray, intersection);
    RayIntersection shadowIntersection = RayMarch(shadowRay);
    if(shadowIntersection.found)
      color *= shadowRay.energy; // Energy for shadows is how much it shouldn't shade
    Ray reflectionRay = GetReflectionRay(ray, intersection);
    if(reflectionRay.energy > 0.1)
    {
      RayIntersection reflectionIntersection = RayMarch(reflectionRay);
      if(reflectionIntersection.found)
      {
        color = RayColor(reflectionRay, reflectionIntersection, color);
        // Shadow ray
        shadowRay = GetShadowRay(reflectionRay, reflectionIntersection);
        shadowIntersection = RayMarch(shadowRay);
        if(shadowIntersection.found)
          color *= shadowRay.energy; // Energy for shadows is how much it shouldn't shade
      }
      else
      {
        color = GetSkyboxColor(reflectionRay, color);
      }
    }
  }
  else
  {
    color = GetSkyboxColor(ray, color);
  }

  f_Color = vec4(color, 1.0);
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
