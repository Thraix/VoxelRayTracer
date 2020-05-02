#pragma once

#include <common/Types.h>
#include <common/Memory.h>
#include <graphics/textures/Texture2D.h>
#include <math/Vec2.h>

class FrameBuffer
{
  Greet::Ref<Greet::Texture2D> texture;
  uint fbo;
  uint renderBuffer;
  uint width;
  uint height;

  private:
    FrameBuffer(uint width, uint height);

  public:
    virtual ~FrameBuffer();
    void Resize(uint width, uint height);

    const Greet::Ref<Greet::Texture2D>& GetTexture() const;

    const Greet::Vec2 GetSize() const { return Greet::Vec2{(float)width, (float)height}; }
    uint GetWidth() const { return width; }
    uint GetHeight() const { return height; }
    void Enable();
    void Clear();
    static void Disable();

    static Greet::Ref<FrameBuffer> Create(uint width, uint height);
};

