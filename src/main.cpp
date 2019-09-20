#include <Greet.h>

using namespace Greet;
class AppScene : public Scene
{
  public:
    Ref<Shader> shader;
    Ref<VertexArray> vao;
    Ref<VertexBuffer> vbo;
    Ref<Buffer> ibo;
    Mat4 projectionMatrix;
    Mat4 viewMatrix;
    Mat4 pvInvMatrix;
    float timer = 0;
    Ref<uint> texture3D;

    AppScene()
    {
      Vec2 screen[4] = {
        {-1.0f, 1.0f}, {1.0f, 1.0f}, {1.0f, -1.0f}, {-1.0f, -1.0f}};
      uint indices[6] = {0, 2, 1, 0, 3, 2};

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
      int size = 16;
      std::vector<float> data = Greet::Noise::GenNoise(size,size,size,3,4,4,4,2,0,0,0);
      /* static std::vector<float> GenNoise(uint width, uint height, uint length, uint octave, uint stepX, uint stepY, uint stepZ, float persistance, int offsetX, int offsetY, int offsetZ); */
      shader = Shader::FromFile("res/shaders/voxel.glsl");
      shader->Enable();
      shader->SetUniform1i("u_Size", size);
      shader->Disable();
      uint tex;
      GLCall(glGenTextures(1, &tex));
      byte bytes[size * size * size];
      int i = 0;
      for(float d : data)
      {
        bytes[i] = d * 255;
        i++;
      }
      glBindTexture(GL_TEXTURE_3D, tex);
      GLCall(glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER,  GL_NEAREST));
      GLCall(glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_NEAREST));
      GLCall(glTexImage3D(GL_TEXTURE_3D, 0, GL_RED, size, size, size, 0, GL_RED, GL_UNSIGNED_BYTE, bytes));
      texture3D.reset(new uint{tex});
    }
    inline static int fps = 0;

    virtual void Render() const override
    {
      static int index = 0;
      shader->Enable();
      TextureManager::Get2D("concrete").Enable(0);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_3D, *texture3D);
      TextureManager::Get3D("skybox").Enable(2);
      TextureManager::Get2D("stone").Enable(3);
      shader->SetUniform1i("u_TextureUnit", 0);
      shader->SetUniform1i("u_ChunkTexUnit", 1);
      shader->SetUniform1i("u_SkyboxUnit", 2);
      shader->SetUniform1i("u_TextureUnit2", 3);
      shader->SetUniformMat4("u_PVInvMatrix", pvInvMatrix);
      shader->SetUniformMat4("u_ViewMatrix", viewMatrix);
      vao->Enable();
      glBeginQuery(GL_TIME_ELAPSED, index);
      vao->Render(DrawType::TRIANGLES, 6);
      glEndQuery(GL_TIME_ELAPSED);
      vao->Disable();
      shader->Disable();
      GLuint64 result;
      glGetQueryObjectui64v(index, GL_QUERY_RESULT, &result);
      index++;
      float ms = result * 1e-6;
      fps = 1000 / ms;
    }

    virtual void Update(float timeElapsed) override
    {
      timer += timeElapsed;
      viewMatrix = Mat4::Translate(0, 0, -15) * Mat4::RotateRY(-timer/5);
      projectionMatrix = Mat4::ProjectionMatrix(
          RenderCommand::GetViewportAspect(), 90, 0.01, 100.0f);
      pvInvMatrix = Mat4::Inverse(projectionMatrix * viewMatrix);
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
      FontManager::Add(
          new FontContainer("res/fonts/NotoSansUI-Regular.ttf", "noto"));
      InitGUI();
      InitScene();
    }

    void InitGUI()
    {
      GUIScene* scene = new GUIScene(new GUIRenderer(),
          Shader::FromFile("res/shaders/gui.shader"));
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
