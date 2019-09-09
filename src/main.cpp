#include <Greet.h>

using namespace Greet;
class AppScene : public Scene
{
  public:
    std::shared_ptr<Shader> shader;
    std::shared_ptr<VertexArray> vao;
    std::shared_ptr<Buffer> vbo;
    std::shared_ptr<Buffer> ibo;
    Mat4 projectionMatrix;
    Mat4 viewMatrix;
    Mat4 pvInvMatrix;
    std::shared_ptr<Skybox> skybox;
    float timer = 0;

    AppScene()
    {
      Vec2 screen[4] = 
      {
        {-1.0f,  1.0f},
        { 1.0f,  1.0f},
        { 1.0f, -1.0f},
        {-1.0f, -1.0f}
      };
      uint indices[6] = 
      {
        0, 2, 1,
        0, 3, 2
      };

      vao.reset(new VertexArray{});
      vao->Enable();
      vbo.reset(new Buffer{sizeof(screen), BufferType::ARRAY, BufferDrawType::STATIC});

      uint positionLocation = 0;//glGetAttribLocation(shader.GetProgram(), "a_Position");

      vbo->Enable();
      vbo->UpdateData(screen);
      GLCall(glVertexAttribPointer(positionLocation, 2, GL_FLOAT, GL_FALSE, 0, 0));
      GLCall(glEnableVertexAttribArray(positionLocation));
      vbo->Disable();

      ibo.reset(new Buffer{sizeof(indices), BufferType::INDEX, BufferDrawType::STATIC});
      ibo->Enable();
      ibo->UpdateData(indices);
      ibo->Disable();

      vao->Disable();
      shader.reset(new Shader{Shader::FromFile("res/shaders/raytrace.shader")});
      skybox.reset(new Skybox(TextureManager::Get3D("skybox")));

    }

    virtual void Render() const override
    {
      skybox->Render(projectionMatrix, viewMatrix);

      shader->Enable();
      TextureManager::Get2D("earth").Enable();
      shader->SetUniform1i("u_TextureUnit", 0);
      shader->SetUniformMat4("u_PVInvMatrix", pvInvMatrix);
      shader->SetUniformMat4("u_ViewMatrix", viewMatrix);
      vao->Enable();
      ibo->Enable();
      GLCall(glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0));
      ibo->Disable();
      vao->Disable();
      shader->Disable();

    }

    virtual void Update(float timeElapsed) override
    {
      timer += timeElapsed;
      viewMatrix = Mat4::Translate(0,0,-10) * Mat4::RotateRY(-timer);
      projectionMatrix = Mat4::ProjectionMatrix(RenderCommand::GetViewportAspect(), 90, 0.01, 100.0f);
      pvInvMatrix = Mat4::Inverse(projectionMatrix * viewMatrix);
    }
};

class Application : public App
{
  public:

    Label* fpsLabel = nullptr;
    SceneView* sceneView = nullptr;
    AppScene* appScene;

    Application()
      : App{"RayTracer", 1440, 810}
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

      if(auto frame = scene->GetFrame("FrameHeader"))
      {
        fpsLabel = frame->GetComponentByName<Label>("fpsCounter");
        if(!fpsLabel)
          Log::Error("Couldn't find Label");
        sceneView = frame->GetComponentByName<SceneView>("scene");
        if(!sceneView)
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
      if(fpsLabel)
        fpsLabel->SetText(std::to_string(GetFPS()));
    }

    void Render() override
    {
    }

    void Update(float timeElapsed) override
    {
    }

    void OnEvent(Event& e) override
    {}
};

int main()
{
  Application app;
  app.Start();
  return 0;
}
