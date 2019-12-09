#pragma once

#include <common/Types.h>
#include <common/Memory.h>
#include <graphics/textures/Texture2D.h>

class FrameBuffer
{
  Greet::Texture2D texture;
  uint fbo;
  uint renderBuffer;
  uint width;
  uint height;

  private:
    FrameBuffer(uint width, uint height);

  public:
    virtual ~FrameBuffer();
    void Resize(uint width, uint height);

    const Greet::Texture2D& GetTexture() const;
    void Enable();
    static void Disable();

    static Greet::Ref<FrameBuffer> Create(uint width, uint height);
};

