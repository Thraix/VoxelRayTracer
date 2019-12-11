#include <Greet.h>

#include "FrameBuffer.h"

#include <thread>

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
      float rotationSpeed = 180 * timeElapsed;
      if (Input::IsKeyDown(GREET_KEY_UP))
        rot.x += rotationSpeed;
      if (Input::IsKeyDown(GREET_KEY_DOWN))
        rot.x -= rotationSpeed;
      if (Input::IsKeyDown(GREET_KEY_LEFT))
        rot.y += rotationSpeed;
      if (Input::IsKeyDown(GREET_KEY_RIGHT))
        rot.y -= rotationSpeed;

      Vec2 posDelta{0};
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

      if(posDelta != Vec2{0} || zDelta != 0)
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

    float timer = 0;
    Ref<uint> texture3D;
    Cam cam;
    CamController camController;
    Ref<Atlas> atlas;
    uint size;
    uint temporalSamples = 1;

    AppScene()
      : cam{Mat4::ProjectionMatrix(RenderCommand::GetViewportAspect(), 90, 0.01,100.0f)}, camController{cam}
    {
      fbo1 = FrameBuffer::Create(1440, 810);
      fbo2 = FrameBuffer::Create(1440, 810);
      fbo3 = FrameBuffer::Create(1440, 810);

      currentFrameBuffer = fbo1.get();
      lastFrameBuffer = fbo2.get();
      rayTraceFrameBuffer = fbo3.get();

      cam.SetPosition({-3.45, 2.17, 3.53});
      cam.SetRotation({-33.00, -48.00, 0.00});
      Vec2 screen[4] = {
        {-1.0f, 1.0f}, {1.0f, 1.0f}, {1.0f, -1.0f}, {-1.0f, -1.0f}};
      uint indices[6] = {0, 2, 1, 0, 3, 2};
      atlas.reset(new Atlas(256,128));
      atlas->Enable(0);
      atlas->AddTexture("stone", "res/textures/stone128.png");
      atlas->AddTexture("dirt", "res/textures/dirt128.png");
      atlas->AddTexture("glass", "res/textures/glass128.png");
      atlas->AddTexture("grass", "res/textures/grass128.png");
      atlas->Disable();

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
      size = 32;
      //std::vector<float> data = Greet::Noise::GenNoise(size, size, size, 3, 4, 4, 4, 2, 0, 0, 0);
      /* static std::vector<float> GenNoise(uint width, uint height, uint length,
       * uint octave, uint stepX, uint stepY, uint stepZ, float persistance, int
       * offsetX, int offsetY, int offsetZ); */
      std::vector<float> noise = Greet::Noise::GenNoise(size, size, 5, 10, 10, 0.5, 0, 0);
      rayTracingShader = Shader::FromFile("res/shaders/voxel.glsl");
      filterShader = Shader::FromFile("res/shaders/temporal.glsl");
      passthroughShader  = Shader::FromFile("res/shaders/passthrough.glsl");
      uint tex;
      GLCall(glGenTextures(1, &tex));
      std::vector<byte> data(size * size * size);
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
      for(int z = 2; z < size-2; z++)
      {
          for(int y = noise[z * size] * size+1; y < size; y++)
          {
          data[y * size + z * size * size] = 2;
          }
      }
      for(int z = 2; z < size-2; z++)
      {
          for(int y = noise[size - 4 + z * size] * size+1; y < size-4; y++)
          {
            data[size - 4 + y * size + z * size * size] = 2;
          }
      }

      for(int z = 2; z < size-2; z++)
      {
          for(int y = noise[size -1 +  z * size] * size+1; y < size-4; y++)
          {
            data[size-1 + y * size + z * size * size] = 3;
          }
      }
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
      rayTraceFrameBuffer->Enable();
      rayTraceFrameBuffer->Clear();
      TextureManager::Get2D("stone").Enable(0);
      atlas->Enable(0);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_3D, *texture3D);
      TextureManager::Get3D("skybox").Enable(2);
      rayTracingShader->Enable();
      rayTracingShader->SetUniformMat4("u_PVInvMatrix", cam.GetInvPVMatrix());
      rayTracingShader->SetUniformMat4("u_ViewMatrix", cam.GetViewMatrix());
      rayTracingShader->SetUniform1i("u_Size", size);
      rayTracingShader->SetUniform1i("u_AtlasSize", atlas->GetAtlasSize());
      rayTracingShader->SetUniform1i("u_AtlasTextureSize", atlas->GetTextureSize());
      rayTracingShader->SetUniform1i("u_TextureUnit", 0);
      rayTracingShader->SetUniform1i("u_ChunkTexUnit", 1);
      rayTracingShader->SetUniform1i("u_SkyboxUnit", 2);
      static float i = 0;
      i++;
      rayTracingShader->SetUniform1f("u_Time", i);
      Vec2 dir = Vec2{1,0};
      dir.RotateR(timer * 0.125);
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
      filterShader->SetUniform1i("u_Samples", temporalSamples);
      rayTraceFrameBuffer->GetTexture().Enable(0);
      lastFrameBuffer->GetTexture().Enable(1);
      vao->Enable();
      vao->Render(DrawType::TRIANGLES, 6);
      vao->Disable();
      currentFrameBuffer->Disable();

      // Passthrough
      passthroughShader->Enable();
      passthroughShader->SetUniform1i("u_TextureUnit", 0);
      currentFrameBuffer->GetTexture().Enable(0);
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
      timer += timeElapsed;
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
      }

    }

    void ViewportResize(ViewportResizeEvent& event) override
    {
      cam.SetProjectionMatrix(Mat4::ProjectionMatrix(event.GetWidth() / event.GetHeight(), 90, 0.01f, 100.0f));
      fbo1->Enable();
      fbo1->Resize(event.GetWidth(), event.GetHeight());
      fbo2->Enable();
      fbo2->Resize(event.GetWidth(), event.GetHeight());
      fbo3->Enable();
      fbo3->Resize(event.GetWidth(), event.GetHeight());
      FrameBuffer::Disable();
    }
};

class Application : public App
{
  public:
    Label* fpsLabel = nullptr;
    SceneView* sceneView = nullptr;
    AppScene* appScene;

    Application() : App{"RayTracer", 1440, 810}
    {
      SetFrameCap(60);
    }

    void Init() override
    {
      Loaders::LoadTextures("res/loaders/textures.json");
      FontManager::Add(new FontContainer("res/fonts/NotoSansUI-Regular.ttf", "noto"));
      InitGUI();
      InitScene();
    }

    void InitGUI()
    {
      GUIScene* scene = new GUIScene(new GUIRenderer());
      scene->AddFrame(FrameFactory::GetFrame("res/guis/header.xml"));

      if (auto frame = scene->GetFrame("FrameHeader"))
      {
        fpsLabel = frame->GetComponentByName<Label>("fpsCounter");
        if (!fpsLabel)
          Log::Error("Couldn't find Label");
        sceneView = frame->GetComponentByName<SceneView>("scene");
        if (!sceneView)
          Log::Error("Couldn't find SceneView");
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
      sceneView->GetSceneManager().Add3DScene(appScene, "appScene");
    }

    void Tick() override
    {
      if (fpsLabel)
        fpsLabel->SetText(std::to_string(AppScene::fps));
    }

    void Render() override
    {}

    void Update(float timeElapsed) override
    {}

    void OnEvent(Event& e) override
    {}
};

int main()
{
  Application app;
  app.Start();
  return 0;
}
