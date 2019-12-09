#include "FrameBuffer.h"

#include <internal/GreetGL.h>

FrameBuffer::FrameBuffer(uint width, uint height)
  : width{width}, height{height}
{
  texture = Greet::Texture2D(width, height, Greet::TextureParams(Greet::TextureFilter::NEAREST, Greet::TextureWrap::NONE, Greet::TextureInternalFormat::RGB));
  GLCall(glGenFramebuffers(1, &fbo));
  GLCall(glGenRenderbuffers(1, &renderBuffer));
  GLCall(glBindFramebuffer(GL_FRAMEBUFFER, fbo));
  GLCall(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture.GetTexId(), 0));

  GLCall(glBindRenderbuffer(GL_RENDERBUFFER, renderBuffer));
  GLCall(glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height));
  GLCall(glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, renderBuffer));

  GLCall(glBindFramebuffer(GL_FRAMEBUFFER, 0));
}

FrameBuffer::~FrameBuffer()
{
  GLCall(glDeleteFramebuffers(1, &fbo));
  GLCall(glDeleteRenderbuffers(1, &renderBuffer));
}

const Greet::Texture2D& FrameBuffer::GetTexture() const
{
  return texture;
}

void FrameBuffer::Enable()
{
  GLCall(glBindFramebuffer(GL_FRAMEBUFFER, fbo));
  GLCall(glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT));
}

void FrameBuffer::Disable()
{
  GLCall(glBindFramebuffer(GL_FRAMEBUFFER, 0));
}

void FrameBuffer::Resize(uint width, uint height)
{
  texture = Greet::Texture2D(width, height, Greet::TextureParams(Greet::TextureFilter::NEAREST, Greet::TextureWrap::NONE, Greet::TextureInternalFormat::RGB));
  GLCall(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture.GetTexId(), 0));

  GLCall(glBindRenderbuffer(GL_RENDERBUFFER, renderBuffer));
  GLCall(glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height));
  GLCall(glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, renderBuffer));
}

Greet::Ref<FrameBuffer> FrameBuffer::Create(uint width, uint height)
{
  return std::shared_ptr<FrameBuffer>(new FrameBuffer(width, height));
}
