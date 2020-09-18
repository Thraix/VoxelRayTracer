#include <Greet.h>

#include "FrameBuffer.h"

#include <thread>

/* #define _GLASS_CUBE */
#define _TERRAIN
/* #define _REFRACTION */
/* #define _HIGH_PERFORMANCE */

using namespace Greet;

class Cam
{
  private:
    Vec3<float> position;
    Vec3<float> rotation;
    Mat4 viewMatrix;
    Mat4 projectionMatrix;
    Mat4 invPVMatrix;

  public:
    Cam(const Mat4& projectionMatrix)
      : position{0}, rotation{0}, viewMatrix{Mat4::Identity()}, projectionMatrix{projectionMatrix}, invPVMatrix{Mat4::Identity()}
    {
      RecalcViewMatrix();
    }

    void SetProjectionMatrix(const Mat4& _projectionMatrix)
    {
      projectionMatrix = _projectionMatrix;
      RecalcViewMatrix();
    }

    const Mat4& GetInvPVMatrix() const
    {
      return invPVMatrix;
    }
    const Mat4& GetViewMatrix() const
    {
      return viewMatrix;
    }

    void SetPosition(const Vec3<float>& _position)
    {
      position = _position;
      RecalcViewMatrix();
    }

    const Vec3<float>& GetPosition() const
    {
      return position;
    }

    void SetRotation(const Vec3<float>& _rotation)
    {
      rotation = _rotation;
      RecalcViewMatrix();
    }

    const Vec3<float>& GetRotation() const
    {
      return rotation;
    }

    inline void RecalcViewMatrix()
    {
      viewMatrix = Mat4::RotateX(-rotation.x) * Mat4::RotateY(-rotation.y) * Mat4::Translate(-position);
      RecalcInvPVMatrix();
    }

    inline void RecalcInvPVMatrix()
    {
      invPVMatrix = ~(projectionMatrix * viewMatrix);
    }
};

class CamController
{
  private:
    Cam& cam;

  public:
    CamController(Cam& cam)
      : cam{cam} {}

    void Update(float timeElapsed)
    {
      Vec3<float> rot = cam.GetRotation();
      Vec3<float> lastRot = rot;
      float rotationSpeed = 3 * timeElapsed;
      if (Input::IsKeyDown(GREET_KEY_UP))
        rot.x += rotationSpeed;
      if (Input::IsKeyDown(GREET_KEY_DOWN))
        rot.x -= rotationSpeed;
      if (Input::IsKeyDown(GREET_KEY_LEFT))
        rot.y += rotationSpeed;
      if (Input::IsKeyDown(GREET_KEY_RIGHT))
        rot.y -= rotationSpeed;

      Vec2f posDelta{0};
      float zDelta = 0;
      float moveSpeed = 5 * timeElapsed;
      if (Input::IsKeyDown(GREET_KEY_W))
        posDelta.y -= moveSpeed;
      if (Input::IsKeyDown(GREET_KEY_S))
        posDelta.y += moveSpeed;
      if (Input::IsKeyDown(GREET_KEY_A))
        posDelta.x -= moveSpeed;
      if (Input::IsKeyDown(GREET_KEY_D))
        posDelta.x += moveSpeed;
      if (Input::IsKeyDown(GREET_KEY_LEFT_SHIFT))
        zDelta -= moveSpeed;
      if (Input::IsKeyDown(GREET_KEY_SPACE))
        zDelta += moveSpeed;

      posDelta.Rotate(-rot.y);

      if(posDelta != Vec2f{0} || zDelta != 0)
        cam.SetPosition(cam.GetPosition() + Vec3<float>{posDelta.x, zDelta, posDelta.y});
      if(rot != lastRot)
        cam.SetRotation(rot);
    }
};

class AppScene : public Scene
{
  public:
    Ref<Shader> rayTracingShader;
    Ref<Shader> filterShader;
    Ref<Shader> passthroughShader;
    Ref<VertexArray> vao;
    Ref<VertexBuffer> vbo;
    Ref<Buffer> ibo;
    Ref<FrameBuffer> fbo1;
    Ref<FrameBuffer> fbo2;
    Ref<FrameBuffer> fbo3;

    FrameBuffer* lastFrameBuffer = nullptr;
    FrameBuffer* currentFrameBuffer = nullptr;
    FrameBuffer* rayTraceFrameBuffer = nullptr;

    Ref<uint> texture3D;
    Cam cam;
    CamController camController;
    Ref<Atlas> atlas;
    uint size;
    uint temporalSamples = 1;

    bool dayNightCycle = true;
    float timeOfDay = 0.0;
    float dayTime = 50.0;

    float temporalAlpha = 1.0;
    float rayNoise = 0.0;
    float reflectionNoise = 0.0;
    float refractionNoise = 0.0;

    AppScene()
      : cam{Mat4::Perspective(RenderCommand::GetViewportAspect(), 90, 0.01,100.0f)}, camController{cam}
    {
      fbo1 = FrameBuffer::Create(1440, 810);
      fbo2 = FrameBuffer::Create(1440, 810);
      fbo3 = FrameBuffer::Create(1440, 810);

      currentFrameBuffer = fbo1.get();
      lastFrameBuffer = fbo2.get();
      rayTraceFrameBuffer = fbo3.get();

      cam.SetPosition({-3.45, 2.17, 3.53});
      cam.SetRotation({-33.00, -48.00, 0.00});
      Vec2f screen[4] = {
        {-1.0f, 1.0f}, {1.0f, 1.0f}, {1.0f, -1.0f}, {-1.0f, -1.0f}};
      uint indices[6] = {0, 2, 1, 0, 3, 2};
#ifdef _HIGH_PERFORMANCE
      atlas.reset(new Atlas(32,16));
      atlas->Enable(0);
      atlas->AddTexture("stone", "res/textures/stone.png");
      atlas->AddTexture("dirt", "res/textures/dirt.png");
      atlas->AddTexture("glass", "res/textures/glass.png");
      atlas->AddTexture("grass", "res/textures/grass.png");
      atlas->Disable();
      size = 32;
      std::vector<float> noise = Greet::Noise::GenNoise(size, size, 5, 10, 10, 0.5, 0, 0);
#else
      atlas.reset(new Atlas(256,128));
      atlas->Enable(0);
      atlas->AddTexture("stone", "res/textures/stone128.png");
      atlas->AddTexture("dirt", "res/textures/dirt128.png");
      atlas->AddTexture("glass", "res/textures/glass128.png");
      atlas->AddTexture("grass", "res/textures/grass128.png");
      atlas->Disable();
      size = 128;
      std::vector<float> noise = Greet::Noise::GenNoise(size, size, 5, 10, 10, 0.125, 0, 0);
#endif

      vao = VertexArray::Create();
      vbo = VertexBuffer::CreateStatic(screen, sizeof(screen));
      vbo->SetStructure({{0, BufferAttributeType::VEC2}});
      vao->AddVertexBuffer(vbo);
      vbo->Disable();

      ibo = Buffer::Create(sizeof(indices), BufferType::INDEX, BufferDrawType::STATIC);
      ibo->UpdateData(indices);
      vao->SetIndexBuffer(ibo);
      ibo->Disable();
      vao->Disable();
      //std::vector<float> data = Greet::Noise::GenNoise(size, size, size, 3, 4, 4, 4, 2, 0, 0, 0);
      /* static std::vector<float> GenNoise(uint width, uint height, uint length,
       * uint octave, uint stepX, uint stepY, uint stepZ, float persistance, int
       * offsetX, int offsetY, int offsetZ); */
      rayTracingShader = Shader::FromFile("res/shaders/voxel.glsl");
      filterShader = Shader::FromFile("res/shaders/temporal.glsl");
      passthroughShader  = Shader::FromFile("res/shaders/passthrough.glsl");
      uint tex;
      GLCall(glGenTextures(1, &tex));
      std::vector<byte> data(size * size * size);
#ifdef _TERRAIN
      int i = 0;
      for(int z = 0; z < size; z++)
      {
        for(int x = 0; x < size; x++)
        {
          for(int y = 0; y < noise[x + z * size] * size; y++)
          {
            data[x + y * size + z * size * size] = 1;
          }
          int grassLevel = noise[x + z * size] * size;
          data[x + grassLevel * size + z * size * size] = 3;
        }
      }
      if(size <= 64)
      {
        for(int z = 2; z < size-2; z++)
        {
          for(int y = noise[z * size] * size+1; y < size; y++)
          {
            data[y * size + z * size * size] = 2;
          }
        }
        for(int x = 2; x < size-1; x++)
        {
          for(int y = noise[x * size + size - 4] * size+1; y < size-4; y++)
          {
            data[x + y * size + (size-4) * size * size] = 2;
          }
        }
      }

      for(int z = 2; z < size-2; z++)
      {
        for(int y = noise[size -1 +  z * size] * size+1; y < size-4; y++)
        {
          data[size-1 + y * size + z * size * size] = 3;
        }
      }
#elif defined(_GLASS_CUBE)
      for(int i = 0; i < size; i++)
      {
        for(int j = 0; j < size; j++)
        {
          data[size-1 + i * size + j * size * size] = 2;
          data[i * size + j * size * size] = 2;
          data[i + j * size + (size-1) * size * size] = 2;
          data[i + j * size] = 2;
          data[i + (size-1) * size + j * size * size] = 2;
          data[i + j * size * size] = 2;
        }
      }
      data[size/2 + size/2 * size + size/2 * size * size] = 3;
#elif defined(_REFRACTION)

      data[size/2 + size/2 * size + size / 2 * size * size] = 2;

      for(int i = size/4; i < 3 * size / 4; i++)
      {
        for(int j =size/4;  j < 3 * size / 4; j++)
        {
          data[size-1 + i * size + j * size * size] = 3;
          data[i * size + j * size * size] = 3;
          data[i + j * size + (size-1) * size * size] = 3;
          data[i + j * size] = 3;
          data[i + (size-1) * size + j * size * size] = 3;
          data[i + j * size * size] = 3;
        }
      }
#endif
      /* std::vector<byte> data(size * size * size); */
      /* for(int z = 0;z<size;z++) */
      /* { */
      /*   for(int y = 0;y<size;y++) */
      /*   { */
      /*     for(int x = 0;x<size;x++) */
      /*     { */
      /*       if(y < size-2 || (y == size-1 && x == 0 && z == 0) || (y == size-2 && x == 1 && z == 1)) */
      /*       { */
      /*         if(y < size-2) */
      /*           data[x + y * size + z * size * size] = 1; */
      /*         else */
      /*           data[x + y * size + z * size * size] = 2; */
      /*       } */
      /*       else */
      /*         data[x + y * size + z * size * size] = 0; */
      /*     } */
      /*   } */
      /* } */
      /* for(int z = 0;z<size;z++) */
      /* { */
      /*   for(int y = size-2;y<size;y++) */
      /*   { */
      /*     data[size-1 + y * size + z * size * size] = 2; */
      /*   } */
      /* } */
      glBindTexture(GL_TEXTURE_3D, tex);
      GLCall(glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST));
      GLCall(glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST));
      GLCall(glTexImage3D(GL_TEXTURE_3D, 0, GL_RED, size, size, size, 0, GL_RED, GL_UNSIGNED_BYTE, data.data()));
      texture3D.reset(new uint{tex});
    }
    inline static int fps = 0;

    virtual void Render() const override
    {
      RenderCommand::PushViewportStack({0,0}, rayTraceFrameBuffer->GetSize(), true);
      rayTraceFrameBuffer->Enable();
      rayTraceFrameBuffer->Clear();
      TextureManager::LoadTexture2D("res/textures/stone.meta")->Enable(0);
      atlas->Enable(0);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_3D, *texture3D);
      rayTracingShader->Enable();
      rayTracingShader->SetUniformMat4("u_PVInvMatrix", cam.GetInvPVMatrix());
      rayTracingShader->SetUniformMat4("u_ViewMatrix", cam.GetViewMatrix());
      rayTracingShader->SetUniform1i("u_Size", size);
      rayTracingShader->SetUniform1i("u_AtlasSize", atlas->GetAtlasSize());
      rayTracingShader->SetUniform1i("u_AtlasTextureSize", atlas->GetTextureSize());
      rayTracingShader->SetUniform1i("u_TextureUnit", 0);
      rayTracingShader->SetUniform1i("u_ChunkTexUnit", 1);
      rayTracingShader->SetUniform1f("u_RayNoise", rayNoise);
      rayTracingShader->SetUniform1f("u_ReflectionNoise", reflectionNoise);
      rayTracingShader->SetUniform1f("u_RefractionNoise", refractionNoise);
      static float i = 0;
      i++;
      rayTracingShader->SetUniform1f("u_Time", i);
      Vec2f dir = Vec2f{1.0f,0.0f};
      dir.Rotate(timeOfDay * M_PI * 2 / dayTime);
      rayTracingShader->SetUniform3f("u_SunDir", Vec3<float>{dir.y, dir.x, 0.2}.Normalize());
      vao->Enable();
      glBeginQuery(GL_TIME_ELAPSED, 1);
      vao->Render(DrawType::TRIANGLES, 6);
      glEndQuery(GL_TIME_ELAPSED);
      vao->Disable();
      rayTracingShader->Disable();
      GLuint64 result;
      glGetQueryObjectui64v(1, GL_QUERY_RESULT, &result);
      float ms = result * 1e-6;
      if(ms > 1000)
        abort();
      fps = 1000 / ms;
      rayTraceFrameBuffer->Disable();

      // Filter
      currentFrameBuffer->Enable();
      currentFrameBuffer->Clear();
      filterShader->Enable();
      filterShader->SetUniform1i("u_TextureUnitNew", 0);
      filterShader->SetUniform1i("u_TextureUnitOld", 1);
      filterShader->SetUniform1f("u_Alpha", temporalAlpha);
      filterShader->SetUniform1i("u_Samples", temporalSamples);
      rayTraceFrameBuffer->GetTexture()->Enable(0);
      lastFrameBuffer->GetTexture()->Enable(1);
      vao->Enable();
      vao->Render(DrawType::TRIANGLES, 6);
      vao->Disable();
      currentFrameBuffer->Disable();
      RenderCommand::PopViewportStack();

      // Passthrough
      passthroughShader->Enable();
      passthroughShader->SetUniform1i("u_TextureUnit", 0);
      currentFrameBuffer->GetTexture()->Enable(0);
      vao->Enable();
      vao->Render(DrawType::TRIANGLES, 6);
      vao->Disable();
    }

    virtual void PostRender() override
    {
      // Swap buffers
      std::swap(lastFrameBuffer, currentFrameBuffer);
      temporalSamples++;
    }

    virtual void Update(float timeElapsed) override
    {
      if(dayNightCycle)
      {
        timeOfDay += timeElapsed;
        while(timeOfDay > dayTime)
          timeOfDay -= dayTime;
      }
      camController.Update(timeElapsed);
    }

    void OnEvent(Event& event) override
    {
      Scene::OnEvent(event);
      if(EVENT_IS_TYPE(event, EventType::KEY_PRESS))
      {
        KeyPressEvent& e = static_cast<KeyPressEvent&>(event);
        if(e.GetButton() == GREET_KEY_C)
        {
          cam.SetPosition({-3.45, 2.17, 3.53});
          cam.SetRotation({-33.00, -48.00, 0.00});
        }
        else if(e.GetButton() == GREET_KEY_F)
        {
          Log::Info("Clear Framebuffer");
          std::swap(lastFrameBuffer, rayTraceFrameBuffer);
          temporalSamples = 1;
        }
        else if(e.GetButton() == GREET_KEY_F1)
        {

          lastFrameBuffer->Enable();
          Utils::Screenshot(lastFrameBuffer->GetWidth(), lastFrameBuffer->GetHeight());
          lastFrameBuffer->Disable();
        }
      }

    }

    void ViewportResize(ViewportResizeEvent& event) override
    {
      cam.SetProjectionMatrix(Mat4::Perspective(event.GetWidth() / event.GetHeight(), 90, 0.01f, 100.0f));
#ifdef _HIGH_PERFORMANCE
      int width = 400;
      int height = 400;
#else
      int width = event.GetWidth();
      int height = event.GetHeight();
#endif
      fbo1->Enable();
      fbo1->Resize(width, height);
      fbo2->Enable();
      fbo2->Resize(width, height);
      fbo3->Enable();
      fbo3->Resize(width, height);
      FrameBuffer::Disable();
    }
};

class Application : public App
{
  public:
    Label* fpsLabel = nullptr;
    Slider* daySlider = nullptr;
    SceneView* sceneView = nullptr;
    AppScene* appScene;

    Application() : App{"RayTracer", 1440, 810}
    {
      SetFrameCap(60);
    }

    void Init() override
    {
      FontManager::Add("noto", FontContainer("res/fonts/NotoSansUI-Regular.ttf"));
      InitScene();
      InitGUI();
    }

    void InitGUI()
    {
      GUIScene* scene = new GUIScene(new GUIRenderer());
      Frame* frame = FrameFactory::GetFrame("res/guis/header.xml");
      scene->AddFrameQueued(frame);

      if (frame)
      {
        fpsLabel = frame->GetComponentByName<Label>("fpsCounter");
        if (!fpsLabel)
          Log::Error("Couldn't find Label");
        sceneView = frame->GetComponentByName<SceneView>("scene");
        if (!sceneView)
          Log::Error("Couldn't find SceneView");
        else
          sceneView->GetSceneManager().Add3DScene(appScene, "appScene");
        using namespace std::placeholders;
        Button* button = frame->GetComponentByName<Button>("ToggleDayNight");
        if (!button)
          Log::Error("Couldn't find ToggleDayNight button");
        else
          button->SetOnClickCallback(std::bind(&Application::OnDayNightCyclePress, std::ref(*this), _1));
        button = frame->GetComponentByName<Button>("MakeDay");
        if (!button)
          Log::Error("Couldn't find MakeDay button");
        else
          button->SetOnClickCallback(std::bind(&Application::OnMakeDayPress, std::ref(*this), _1));
        daySlider = frame->GetComponentByName<Slider>("TimeSlider");
        if (!daySlider)
          Log::Error("Couldn't find TimeSlider");
        else
          daySlider->SetOnValueChangeCallback(std::bind(&Application::ChangeTimeOfDay, std::ref(*this), _1, _2, _3));
        Slider* slider = frame->GetComponentByName<Slider>("TemporalSlider");
        if (!slider )
          Log::Error("Couldn't find TemporalSlider");
        else
          slider ->SetOnValueChangeCallback(std::bind(&Application::ChangeTemporalAlpha, std::ref(*this), _1, _2, _3));
        slider = frame->GetComponentByName<Slider>("RayNoiseSlider");
        if (!slider )
          Log::Error("Couldn't find RayNoiseSlider");
        else
          slider ->SetOnValueChangeCallback(std::bind(&Application::ChangeRayNoise, std::ref(*this), _1, _2, _3));
        slider = frame->GetComponentByName<Slider>("ReflectionNoiseSlider");
        if (!slider )
          Log::Error("Couldn't find ReflectionNoiseSlider");
        else
          slider ->SetOnValueChangeCallback(std::bind(&Application::ChangeReflectionNoise, std::ref(*this), _1, _2, _3));
        slider = frame->GetComponentByName<Slider>("RefractionNoiseSlider");
        if (!slider )
          Log::Error("Couldn't find RefractionNoiseSlider");
        else
          slider ->SetOnValueChangeCallback(std::bind(&Application::ChangeRefractionNoise, std::ref(*this), _1, _2, _3));
      }
      else
      {
        Log::Error("Couldn't find Frame");
      }

      GlobalSceneManager::GetSceneManager().Add2DScene(scene, "GUI");
    }

    void InitScene()
    {
      appScene = new AppScene();
    }

    void Tick() override
    {
      if (fpsLabel)
        fpsLabel->SetText(std::to_string(AppScene::fps));
    }

    void Render() override
    {}
    /*
    void RenderGUI()
    {
    GUI::BeginFrame("Frame");
      GUI::BeginContainer();
        GUI::Button();
        EndContainer();
        GUI::EndFrame();
    }


     */

    void Update(float timeElapsed) override
    {
      if(daySlider)
        daySlider->SetValue(appScene->timeOfDay / appScene->dayTime);
    }

    void OnEvent(Event& e) override
    {}

    void OnDayNightCyclePress(Component* button)
    {
      appScene->dayNightCycle = !appScene->dayNightCycle;
    }

    void OnMakeDayPress(Component* button)
    {
      appScene->timeOfDay = 0.9 * appScene->dayTime;
    }

    void ChangeTimeOfDay(Component* slider, float oldValue, float newValue)
    {
      appScene->timeOfDay = newValue * appScene->dayTime;
    }

    void ChangeTemporalAlpha(Component* slider, float oldValue, float newValue)
    {
      appScene->temporalAlpha = newValue;
    }

    void ChangeRayNoise(Component* slider, float oldValue, float newValue)
    {
      appScene->rayNoise = newValue;
      Log::Info("Ray: ", newValue);
    }

    void ChangeReflectionNoise(Component* slider, float oldValue, float newValue)
    {
      appScene->reflectionNoise = newValue;
      Log::Info("Reflection: ", newValue);
    }

    void ChangeRefractionNoise(Component* slider, float oldValue, float newValue)
    {
      appScene->refractionNoise = newValue;
      Log::Info("Refraction: ", newValue);
    }
};

int main()
{
  Application app;
  app.Start();
  return 0;
}
