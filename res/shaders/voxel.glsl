//fragment
#version 450 core

in vec3 v_Near;
in vec3 v_Dir;
in vec3 v_CameraPos;

out vec4 f_Color;

uniform sampler2D u_TextureUnit;
uniform sampler3D u_ChunkTexUnit;
uniform samplerCube u_SkyboxUnit;

uniform float u_MaxRayLength = 100;
uniform int u_Size;
uniform int u_AtlasSize;
uniform int u_AtlasTextureSize;
uniform vec3 u_SunDir;

const int c_Materials = 4;

struct Ray
{
  vec3 pos;
  vec3 dir;
  float rayLength;
  float energy;
  float voxel;
  int reflectionDepth;
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

//#define _COLOR_ONLY
#ifndef _COLOR_ONLY
struct Material
{
  float reflectivity;
  float refractivity;
  bool transparent;
  bool reflective;
  float diffuseFactor;
  float specularityFactor;
  float specularityExponent;
  int texX;
  int texY;
};

Material materials[c_Materials] = {
  Material(0,1,true,false,0,0,0,0,0), // Air
  Material(0,1,false,false,0.4,0.2,10,0,0), // Stone
  Material(0.6,1.5,true,true,1,1,1,0,1), // Glass
  Material(0,1,false,false,0.4,0.1,1,1,1), // Grass
};
#else

struct Material
{
  float reflectivity;
  float refractivity;
  bool transparent;
  bool reflective;
  float diffuseFactor;
  float specularityFactor;
  float specularityExponent;
  vec4 color;
};

Material materials[c_Materials] = {
  Material(0,1,true,false,0,0,0,vec4(0)), // Air
  Material(0,1,false,false,0.4,0.2,10,vec4(0.5,0.5,0.5,1.0)), // Stone
  Material(0.6,1.5,true,true,1,1,1,vec4(0)), // Glass
  Material(0,1,false,false,0.4,0.2,10,vec4(0.05,0.5,0.1,1)), // Grass
};

#endif

float ambient = 0.4;

int intersectionAxis[3][3] = {{0,2,1}, {1,0,2}, {2,0,1}};

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

float Fresnel(Ray ray, RayIntersection intersection)
{
  vec3 normal = vec3(0,0,0);
  normal[intersection.collisionDir] = sign(ray.dir[intersection.collisionDir]);
  return 1.0 - dot(normal, ray.dir);
}

Ray GetShadowRay(Ray ray, RayIntersection intersection)
{
  Ray shadowRay;
  vec3 normal = vec3(0,0,0);
  normal[intersection.collisionDir] = sign(ray.dir[intersection.collisionDir]);
  float sig = sign(normal[intersection.collisionDir]) * sign(u_SunDir[intersection.collisionDir]);
  shadowRay.voxel = intersection.voxel;
  shadowRay.pos = intersection.collisionPoint - u_SunDir * 0.0001 * sig;
  shadowRay.dir = normalize(u_SunDir);
  shadowRay.rayLength = intersection.rayLength;
  shadowRay.energy = ray.energy;
  shadowRay.reflectionDepth = 0; 
  return shadowRay;
}

Ray GetReflectionRay(Ray ray, RayIntersection intersection)
{
  Material material = GetMaterial(intersection.voxel);
  Ray reflectionRay;
  reflectionRay.voxel = 0;
  reflectionRay.pos = intersection.collisionPoint;
  reflectionRay.dir = ray.dir;
  reflectionRay.dir[intersection.collisionDir] = -ray.dir[intersection.collisionDir];
  reflectionRay.rayLength = intersection.rayLength;
  reflectionRay.energy = ray.energy * Fresnel(ray, intersection);
  reflectionRay.reflectionDepth = ray.reflectionDepth+1; 
  return reflectionRay;
}

Ray GetRefractionRay(Ray ray, RayIntersection intersection)
{
  vec3 normal = vec3(0,0,0);
  normal[intersection.collisionDir] = -sign(ray.dir[intersection.collisionDir]);

  float outRefractivity = GetMaterial(GetVoxel(intersection.collisionPoint + normal * 0.5)).refractivity;
  float inRefractivity= GetMaterial(GetVoxel(intersection.collisionPoint - normal * 0.5)).refractivity;

  Material material = GetMaterial(intersection.voxel);
  Ray refractionRay;
  refractionRay.voxel = intersection.voxel;
  refractionRay.pos = intersection.collisionPoint;
  refractionRay.dir = refract(normalize(ray.dir), normal,  outRefractivity / inRefractivity);

  // Total Internal Reflection
  if(refractionRay.dir == vec3(0))
  {
    refractionRay = GetReflectionRay(ray, intersection);
    refractionRay.voxel = ray.voxel;
  }
  refractionRay.rayLength = intersection.rayLength;
  refractionRay.energy = ray.energy;
  refractionRay.reflectionDepth = ray.reflectionDepth; 
  return refractionRay;
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

vec4 GetColor(RayIntersection intersection)
{
  Material mat = GetMaterial(intersection.voxel);
#ifndef _COLOR_ONLY
  vec2 texCoord = GetTextureCoordinate(
      vec2(
        intersection.collisionPoint[intersection.texAxis1],
        intersection.collisionPoint[intersection.texAxis2]),
      mat.texX,mat.texY);
  return texture(u_TextureUnit, texCoord);
#else
  return mat.color;
#endif
}

vec3 RayColor(Ray ray, RayIntersection intersection, vec3 color, float brightness)
{
  vec4 rayColor = GetColor(intersection);
  return color * (1.0 - ray.energy) + rayColor.rgb * ray.energy * rayColor.a * brightness;
}

RayIntersection RayMarchShadow(inout Ray ray)
{
  float rayLength = ray.rayLength;
  vec3 currentPos = ray.pos;
  vec3 nextPlane = vec3(
      ray.dir.x < 0 ? ceil(currentPos.x-1) : floor(currentPos.x+1),
      ray.dir.y < 0 ? ceil(currentPos.y-1) : floor(currentPos.y+1),
      ray.dir.z < 0 ? ceil(currentPos.z-1) : floor(currentPos.z+1));

  vec3 stepDir = sign(ray.dir);
  float rayVoxel = ray.voxel;

  vec3 t = (nextPlane - ray.pos) / ray.dir;

  while(rayLength < u_MaxRayLength)
  {
    if(!TestCube(currentPos, ray.dir, vec3(u_Size*0.5), vec3(u_Size)))
    {
      return RayIntersection(0, vec3(0,0,0), 0, 0, 1, 2, false);
    }
    float tMin = min(t.x, min(t.y, t.z));
    t -= tMin;
    rayLength += tMin;
    currentPos = ray.pos + (rayLength - ray.rayLength) * ray.dir;
    vec3 eq = vec3(equal(t, vec3(0,0,0)));
    vec3 indices = eq * vec3(0,1,2);
    float voxel = GetVoxel(currentPos + 0.5 * eq * stepDir);
    int index = int(floor(indices.x + indices.y + indices.z));

    if(HasVoxel(voxel))
    {
      RayIntersection intersection =
        RayIntersection(
            voxel,
            currentPos,
            rayLength,
            intersectionAxis[index][0],
            intersectionAxis[index][1],
            intersectionAxis[index][2], true);

      Material mat = GetMaterial(voxel);
      if(!mat.transparent && GetColor(intersection).a == 1)
      {
        return intersection;
      }
    }
    t[intersectionAxis[index][0]] = ((currentPos + stepDir - ray.pos) / ray.dir - (rayLength - ray.rayLength))[intersectionAxis[index][0]];

  }
  return RayIntersection(0, vec3(0,0,0), 0, 0, 1, 2, false);
}

RayIntersection RayMarch(inout Ray ray)
{
  float rayLength = ray.rayLength;
  vec3 currentPos = ray.pos;
  vec3 nextPlane = vec3(
      ray.dir.x < 0 ? ceil(currentPos.x-1) : floor(currentPos.x+1),
      ray.dir.y < 0 ? ceil(currentPos.y-1) : floor(currentPos.y+1),
      ray.dir.z < 0 ? ceil(currentPos.z-1) : floor(currentPos.z+1));

  vec3 stepDir = sign(ray.dir);
  float rayVoxel = ray.voxel;

  vec3 t = (nextPlane - ray.pos) / ray.dir;
  int internalReflection = 0;

  while(rayLength < u_MaxRayLength)
  {
    if(!TestCube(currentPos, ray.dir, vec3(u_Size*0.5), vec3(u_Size)))
    {
      return RayIntersection(0, vec3(0,0,0), 0, 0, 1, 2, false);
    }
    float tMin = min(t.x, min(t.y, t.z));
    t -= tMin;
    rayLength += tMin;
    vec3 oldPos = currentPos;
    currentPos = ray.pos + (rayLength - ray.rayLength) * ray.dir;
    vec3 eq = vec3(equal(t, vec3(0,0,0)));
    vec3 indices = eq * vec3(0,1,2);
    float voxel = GetVoxel(currentPos + 0.5 * eq * stepDir);
    int index = int(floor(indices.x + indices.y + indices.z));
    RayIntersection intersection =
      RayIntersection(
          voxel,
          currentPos,
          rayLength,
          intersectionAxis[index][0],
          intersectionAxis[index][1],
          intersectionAxis[index][2], true);

    if(HasVoxel(voxel) && voxel != rayVoxel)
    {
      return intersection;
    }
    else if(rayVoxel != 0 && voxel == 0)
    {
      // Inside transparent voxel
      vec3 oldDir = ray.dir;
      ray = GetRefractionRay(ray, intersection);
      if(ray.voxel == rayVoxel)
      {
        internalReflection++;
        if(internalReflection > 10)
        {
          ray.dir = oldDir;
          ray.voxel = 0;
        }
      }
      rayVoxel = ray.voxel;

      vec3 nextPlane = vec3(
          ray.dir.x < 0 ? ceil(currentPos.x-1) : floor(currentPos.x+1),
          ray.dir.y < 0 ? ceil(currentPos.y-1) : floor(currentPos.y+1),
          ray.dir.z < 0 ? ceil(currentPos.z-1) : floor(currentPos.z+1));
      t = (nextPlane - ray.pos) / ray.dir;
      stepDir = sign(ray.dir);
    }
    t[intersectionAxis[index][0]] = ((currentPos + stepDir - ray.pos) / ray.dir - (rayLength - ray.rayLength))[intersectionAxis[index][0]];
  }
  return RayIntersection(0, vec3(0,0,0), 0, 0, 1, 2, false);
}

vec3 GetSkyboxColor(Ray ray, vec3 color)
{
  vec3 unitDir = normalize(ray.dir);
  float sun = 10 * pow(dot(normalize(u_SunDir), unitDir), 400.0);
  float grad = (unitDir.y + 1.0) * 0.5;
  vec3 skyboxColor = max(vec3(0,grad*0.75,grad), vec3(sun, sun, 0));
  return mix(skyboxColor, color, 1.0 - ray.energy);
}

RayIntersection TraceWithShadow(Ray ray, inout vec3 color)
{
  RayIntersection intersection = RayMarch(ray);
  if(intersection.found)
  {
    // Shadow ray
    Ray shadowRay = GetShadowRay(ray, intersection);
    RayIntersection shadowIntersection = RayMarchShadow(shadowRay);
      vec3 normal = vec3(0,0,0);
      normal[intersection.collisionDir] = -sign(ray.dir[intersection.collisionDir]);
    float brightness = 0.0f;
    if(shadowIntersection.found)
    {
      // Full shadow
      brightness = ambient;
    }
    else
    {
      Material material = GetMaterial(intersection.voxel);
      float diffuse = material.diffuseFactor * max(dot(normal, shadowRay.dir), 0.0);
      float specular = material.specularityFactor * pow(max(dot(reflect(shadowRay.dir, normal), ray.dir), 0.0f), material.specularityExponent);
      brightness  = ambient + diffuse + specular;
    }
    color = RayColor(ray, intersection, color, brightness);
  }
  else
  {
    color = mix(GetSkyboxColor(ray, color), color, 1 - ray.energy);
  }
  return intersection;
}

#define MAX_REFLECTIONS 1
#define MAX_TRANSPARENCIES 2

void main()
{
  Ray ray = Ray(v_Near + vec3(u_Size*0.5), normalize(v_Dir), 0, 1, 0.0, 0);
  vec3 color = vec3(0,0,0);

  // max reflections + max transparencies
  Ray[MAX_REFLECTIONS + MAX_TRANSPARENCIES + 1] stack;
  stack[0] = ray;
  int stackSize = 1;

  int transparencies = 0;

  while(stackSize > 0)
  {
    Ray ray = stack[--stackSize];
    RayIntersection intersection = TraceWithShadow(ray, color);
    if(intersection.found)
    {
      Material material = GetMaterial(intersection.voxel);
      if(material.reflective && ray.reflectionDepth < MAX_REFLECTIONS)
      {
        stack[stackSize++] = GetReflectionRay(ray, intersection);
      }
      if(material.transparent && transparencies < MAX_TRANSPARENCIES && GetColor(intersection).a != 1)
      {
        stack[stackSize++] = GetRefractionRay(ray, intersection);
        transparencies++;
      }
      if(HasVoxel(ray.voxel))
        transparencies--;
    }
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
