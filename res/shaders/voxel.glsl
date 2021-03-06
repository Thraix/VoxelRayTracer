//fragment
#version 450 core

#define MAX_REFLECTIONS 1
#define MAX_TRANSPARENCIES 2
/* #define _COLOR_ONLY */

in vec3 v_Near;
in vec3 v_Dir;
in vec3 v_CameraPos;

out vec4 f_Color;

uniform sampler2D u_TextureUnit;
uniform sampler3D u_ChunkTexUnit;

uniform float u_MaxRayLength = 100;
uniform int u_Size;
uniform int u_AtlasSize;
uniform int u_AtlasTextureSize;
uniform vec3 u_SunDir;
uniform float u_Time;
uniform float u_RayNoise;
uniform float u_ReflectionNoise;
uniform float u_RefractionNoise;

const int c_Materials = 4;

struct Ray
{
  vec3 pos;
  vec3 dir;
  float rayLength;
  float energy;
  float voxel;
  int reflectionDepth;
  int transparencyDepth;
};

struct RayIntersection
{
  float voxel;
  vec3 collisionPoint;
  float rayLength;
  vec3 normal;
  vec2 texCoord;
  bool found;
};

#ifndef _COLOR_ONLY
struct Material
{
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
  Material(1,true,false,0,0,0,0,0), // Air
  Material(1,false,false,0.4,0.6,60,0,0), // Stone
  Material(1.5,true,true,1,1,0.3,0,1), // Glass
  Material(1,false,false,0.4,0.4,20,1,1), // Grass
};
#else

struct Material
{
  float refractivity;
  bool transparent;
  bool reflective;
  float diffuseFactor;
  float specularityFactor;
  float specularityExponent;
  vec4 color;
};

Material materials[c_Materials] = {
  Material(1,true,false,0,0,0,vec4(0)), // Air
  Material(1,false,false,0.4,0.2,10,vec4(0.5,0.5,0.5,1.0)), // Stone
  Material(1.5,true,true,1,1,1,vec4(0)), // Glass
  Material(1,false,false,0.4,0.2,10,vec4(0.05,0.5,0.1,1)), // Grass
};

#endif

float ambient = 0.3;

int intersectionAxis[3][3] = {{0,2,1}, {1,0,2}, {2,0,1}};

// ------------------ RANDOMIZATION CODE BEGIN ------------------------------

// A single iteration of Bob Jenkins' One-At-A-Time hashing algorithm.
uint Hash(uint x) 
{
  x += ( x << 10u );
  x ^= ( x >>  6u );
  x += ( x <<  3u );
  x ^= ( x >> 11u );
  x += ( x << 15u );
  return x;
}

uint Hash(uvec4 v) 
{ 
  return Hash(v.x ^ Hash(v.y) ^ Hash(v.z) ^ Hash(v.w));
}

// Construct a float with half-open range [0:1] using low 23 bits.
// All zeroes yields 0.0, all ones yields the next smallest representable value below 1.0.
float FloatConstruct( uint m ) 
{
  const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
  const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

  m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
  m |= ieeeOne;                          // Add fractional part to 1.0

  float  f = uintBitsToFloat( m );       // Range [1:2]
  return f - 1.0;                        // Range [0:1]
}

float Random( vec4  v ) 
{ 
  return FloatConstruct(Hash(floatBitsToUint(v))); 
}

vec3 RandomizeDirection(vec3 dir, vec3 pos, float randomness, float seed)
{
  // Bad solution
  float dx = Random(vec4(pos + dir + seed, 0 + seed));
  float dy = Random(vec4(pos + dir + seed, 0.5 + seed));
  float dz = Random(vec4(pos + dir + seed, 1.0 + seed));

  return normalize(dir + (vec3(dx, dy, dz) - 0.5) * randomness);
}

// ------------------ RANDOMIZATION CODE END ------------------------------

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
  return 1.0 - dot(-intersection.normal, ray.dir);
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
  return texture(u_TextureUnit, intersection.texCoord);
#else
  return mat.color;
#endif
}

vec3 RayColor(Ray ray, RayIntersection intersection, vec3 color, float brightness)
{
  vec4 rayColor = GetColor(intersection);
  return mix(color, rayColor.rgb * rayColor.a * brightness, ray.energy);
}


Ray GetShadowRay(Ray ray, RayIntersection intersection)
{
  Ray shadowRay;
  shadowRay.voxel = intersection.voxel;
  shadowRay.pos = intersection.collisionPoint;
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
  reflectionRay.dir = RandomizeDirection(reflect(ray.dir, intersection.normal), intersection.collisionPoint, u_ReflectionNoise, u_Time);
  reflectionRay.rayLength = intersection.rayLength;
  reflectionRay.energy = ray.energy * Fresnel(ray, intersection);
  reflectionRay.reflectionDepth = ray.reflectionDepth+1; 
  reflectionRay.transparencyDepth = ray.transparencyDepth; 
  return reflectionRay;
}

Ray GetRefractionRay(Ray ray, RayIntersection intersection)
{
  float outRefractivity = GetMaterial(GetVoxel(intersection.collisionPoint + intersection.normal * 0.5)).refractivity;
  float inRefractivity= GetMaterial(GetVoxel(intersection.collisionPoint - intersection.normal * 0.5)).refractivity;

  Material material = GetMaterial(intersection.voxel);
  Ray refractionRay;
  refractionRay.voxel = intersection.voxel;
  refractionRay.pos = intersection.collisionPoint;
  refractionRay.dir = refract(normalize(ray.dir), intersection.normal,  outRefractivity / inRefractivity);

  // Total Internal Reflection
  if(refractionRay.dir == vec3(0))
  {
    refractionRay = GetReflectionRay(ray, intersection);
    refractionRay.voxel = ray.voxel;
    refractionRay.energy = ray.energy;
  }
  else
  {
    refractionRay.dir = RandomizeDirection(refractionRay.dir, refractionRay.pos, u_RefractionNoise, u_Time);
    refractionRay.energy = ray.energy;
    if(!HasVoxel(ray.voxel))
      refractionRay.energy *= 1-GetColor(intersection).a;
  }
  refractionRay.rayLength = intersection.rayLength;
  refractionRay.reflectionDepth = ray.reflectionDepth; 
  refractionRay.transparencyDepth = ray.transparencyDepth+1; 
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

bool RayMarchShadow(inout Ray ray)
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
      return false;
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
      Material mat = GetMaterial(voxel);
      if(!mat.transparent)
      {
        return true;
      }
    }
    t[intersectionAxis[index][0]] = ((currentPos + stepDir - ray.pos) / ray.dir - (rayLength - ray.rayLength))[intersectionAxis[index][0]];

  }
  return false;
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
      return RayIntersection(0, vec3(0,0,0), 0, vec3(0), vec2(0), false);
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

    vec3 normal = vec3(0);
    Material mat = GetMaterial(voxel);
    normal[intersectionAxis[index][0]] = -sign(ray.dir[intersectionAxis[index][0]]);
#ifndef _COLOR_ONLY
    vec2 texCoord = 
      GetTextureCoordinate(
          vec2(
            currentPos[intersectionAxis[index][1]],
            currentPos[intersectionAxis[index][2]]),
          mat.texX, mat.texY);
#else 
    vec2 texCoord = vec2(0,0);
#endif
    RayIntersection intersection = RayIntersection(
        voxel,
        currentPos,
        rayLength,
        normal,
        texCoord, true);

    if(HasVoxel(voxel) && voxel != rayVoxel)
    {
      return intersection;
    }
    else if(rayVoxel != 0 && voxel == 0)
    {
      // Inside transparent voxel
      vec3 oldDir = ray.dir;
      ray = GetRefractionRay(ray, intersection);
      ray.transparencyDepth--;
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
  return RayIntersection(0, vec3(0,0,0), 0, vec3(0), vec2(0), false);
}

vec3 GetSkyboxColor(Ray ray, vec3 color)
{
  vec3 unitDir = normalize(ray.dir);
  float sun = 10 * pow(dot(normalize(u_SunDir), unitDir), 400.0);
  float grad = (unitDir.y + 1.0) * 0.5;
  vec3 skyboxColor = max(vec3(0,grad*0.75,grad), vec3(sun, sun, 0)) * max(u_SunDir.y, 0.0);
  return mix(skyboxColor, color, 1.0 - ray.energy);
}

RayIntersection TraceWithShadow(inout Ray ray, inout vec3 color)
{
  RayIntersection intersection = RayMarch(ray);
  if(intersection.found)
  {
    // Shadow ray
    Ray shadowRay = GetShadowRay(ray, intersection);
    bool inShadow = RayMarchShadow(shadowRay);
    float brightness = 0.0f;
    if(inShadow)
    {
      // Full shadow
      brightness = ambient;
    }
    else
    {
      Material material = GetMaterial(intersection.voxel);
      float diffuse = material.diffuseFactor * max(dot(intersection.normal, shadowRay.dir), 0.0);
      float specular = material.specularityFactor * pow(max(dot(reflect(shadowRay.dir, intersection.normal), ray.dir), 0.0f), material.specularityExponent);
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

void main()
{
  vec3 color = vec3(0,0,0);

  Ray[MAX_REFLECTIONS + MAX_TRANSPARENCIES + 1] stack;
  stack[0] = Ray(v_Near + vec3(u_Size*0.5), RandomizeDirection(normalize(v_Dir), v_Near, u_RayNoise, u_Time), 0, 1.0, 0.0, 0, 0);

  int stackSize = 1;

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
      if(material.transparent && ray.transparencyDepth < MAX_TRANSPARENCIES && GetColor(intersection).a != 1)
      {
        stack[stackSize++] = GetRefractionRay(ray, intersection);
      }
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
