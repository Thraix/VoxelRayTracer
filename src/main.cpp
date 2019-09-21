#include <Greet.h>

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
    Ref<Shader> shader;
    Ref<VertexArray> vao;
    Ref<VertexBuffer> vbo;
    Ref<Buffer> ibo;
    float timer = 0;
    Ref<uint> texture3D;
    Cam cam;
    CamController camController;
    Ref<Atlas> atlas;

    AppScene()
      : cam{Mat4::ProjectionMatrix(RenderCommand::GetViewportAspect(), 90, 0.01,100.0f)}, camController{cam}
    {
      Vec2 screen[4] = {
        {-1.0f, 1.0f}, {1.0f, 1.0f}, {1.0f, -1.0f}, {-1.0f, -1.0f}};
      uint indices[6] = {0, 2, 1, 0, 3, 2};
      atlas.reset(new Atlas(32,16));
      atlas->Enable(0);
      atlas->AddTexture("stone", "res/textures/stone.png");
      atlas->AddTexture("dirt", "res/textures/dirt.png");
      atlas->AddTexture("glass", "res/textures/glass.png");
      atlas->Disable();

      vao = VertexArray::Create();
      vao->Enable();
      vbo = VertexBuffer::CreateDynamic(screen, sizeof(screen));
      vbo->SetStructure({{0, BufferAttributeType::VEC2}});
      vao->AddVertexBuffer(vbo);
      vbo->Disable();

      ibo = Buffer::Create(sizeof(indices), BufferType::INDEX, BufferDrawType::STATIC);
      ibo->UpdateData(indices);
      ibo->Disable();

      vao->SetIndexBuffer(ibo);
      vao->Disable();
      int size = 4;
      std::vector<float> data = Greet::Noise::GenNoise(size, size, size, 3, 4, 4, 4, 2, 0, 0, 0);
      /* static std::vector<float> GenNoise(uint width, uint height, uint length,
       * uint octave, uint stepX, uint stepY, uint stepZ, float persistance, int
       * offsetX, int offsetY, int offsetZ); */
      shader = Shader::FromFile("res/shaders/voxel.glsl");
      shader->Enable();
      shader->SetUniform1i("u_Size", size);
      shader->SetUniform1i("u_AtlasSize", atlas->GetAtlasSize());
      shader->SetUniform1i("u_AtlasTextureSize", atlas->GetTextureSize());
      shader->SetUniform1i("u_TextureUnit", 0);
      shader->SetUniform1i("u_ChunkTexUnit", 1);
      shader->SetUniform1i("u_SkyboxUnit", 2);
      shader->Disable();
      uint tex;
      GLCall(glGenTextures(1, &tex));
      byte bytes[size * size * size];
      int i = 0;
      for(int z = 0;z<size;z++)
      {
        for(int y = 0;y<size;y++)
        {
          for(int x = 0;x<size;x++)
          {
            if(y < size-2 || (y == size-1 && x == 1 && z == 1) || (y == size-2 && x == 2 && z == 2))
              data[x + y * size + z * size * size] = 0.7;
            else
              data[x + y * size + z * size * size] = 0.4;
          }
        }
      }
      glBindTexture(GL_TEXTURE_3D, tex);
      GLCall(glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_NEAREST));
      GLCall(glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST));
      GLCall(glTexImage3D(GL_TEXTURE_3D, 0, GL_RED, size, size, size, 0, GL_RED, GL_FLOAT, data.data()));
      texture3D.reset(new uint{tex});
    }
    inline static int fps = 0;

    virtual void Render() const override
    {
      TextureManager::Get2D("stone").Enable(0);
      atlas->Enable(0);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_3D, *texture3D);
      TextureManager::Get3D("skybox").Enable(2);
      shader->Enable();
      shader->SetUniformMat4("u_PVInvMatrix", cam.GetInvPVMatrix());
      shader->SetUniformMat4("u_ViewMatrix", cam.GetViewMatrix());
      Vec2 dir = Vec2{1,0};
      dir.RotateR(timer);
      shader->SetUniform3f("u_SunDir", Vec3<float>{dir.x, 1, dir.y}.Normalize());
      vao->Enable();
      glBeginQuery(GL_TIME_ELAPSED, 1);
      vao->Render(DrawType::TRIANGLES, 6);
      glEndQuery(GL_TIME_ELAPSED);
      vao->Disable();
      shader->Disable();
      GLuint64 result;
      glGetQueryObjectui64v(1, GL_QUERY_RESULT, &result);
      float ms = result * 1e-6;
      fps = 1000 / ms;
    }

    virtual void Update(float timeElapsed) override
    {
      timer += timeElapsed; 
      camController.Update(timeElapsed);
    }

    void ViewportResize(ViewportResizeEvent& event) override
    {
      cam.SetProjectionMatrix(Mat4::ProjectionMatrix(event.GetWidth() / event.GetHeight(), 90, 0.01f, 100.0f));
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
      GUIScene* scene = new GUIScene(new GUIRenderer(), Shader::FromFile("res/shaders/gui.shader"));
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
