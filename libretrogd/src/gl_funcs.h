#ifndef LIBRETROGD_GL_FUNCS_H
#define LIBRETROGD_GL_FUNCS_H

// Ponte mínima para o OpenGL do processo.
//
// Não incluímos header de GL nenhum de propósito: no desktop seria <GL/gl.h> +
// glext, no Android <GLES3/gl3.h>, e as duas árvores brigam por tipos e por
// ligação. Como o Godot já abriu a biblioteca de GL antes de nós — é ele quem
// tem o contexto —, basta pedir os ponteiros por dlsym e declarar aqui os
// poucos tipos e constantes que usamos. Assim o CMake não muda e o mesmo
// código serve para as duas plataformas.
//
// Só vale chamar isto da thread que tem o contexto corrente, que no renderer
// gl_compatibility é a principal — a mesma de onde sai run_frame().

#include <cstddef>
#include <cstdint>

namespace libretrogd {

typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLboolean;
typedef void GLvoid;

// Constantes usadas (valores fixos pela especificação, iguais em GL e GLES).
enum : GLenum {
	GL_NO_ERROR = 0,
	GL_UNSIGNED_BYTE = 0x1401,
	GL_TEXTURE_2D = 0x0DE1,
	GL_VIEWPORT = 0x0BA2,
	GL_RGBA = 0x1908,
	GL_RGBA8 = 0x8058,
	GL_NEAREST = 0x2600,
	GL_LINEAR = 0x2601,
	GL_TEXTURE_MAG_FILTER = 0x2800,
	GL_TEXTURE_MIN_FILTER = 0x2801,
	GL_TEXTURE_WRAP_S = 0x2802,
	GL_TEXTURE_WRAP_T = 0x2803,
	GL_CLAMP_TO_EDGE = 0x812F,
	GL_PACK_ALIGNMENT = 0x0D05,
	GL_FRAMEBUFFER = 0x8D40,
	GL_RENDERBUFFER = 0x8D41,
	GL_COLOR_ATTACHMENT0 = 0x8CE0,
	GL_DEPTH_ATTACHMENT = 0x8D00,
	GL_STENCIL_ATTACHMENT = 0x8D20,
	GL_DEPTH_STENCIL_ATTACHMENT = 0x821A,
	GL_DEPTH_COMPONENT24 = 0x81A6,
	GL_DEPTH24_STENCIL8 = 0x88F0,
	GL_FRAMEBUFFER_COMPLETE = 0x8CD5,
	GL_FRAMEBUFFER_BINDING = 0x8CA6,
};

// Ponteiros resolvidos por gl_load(). Nomes iguais aos da API, sem o prefixo,
// para o código de chamada ficar legível.
struct GLFuncs {
	void (*GenFramebuffers)(GLsizei, GLuint *) = nullptr;
	void (*BindFramebuffer)(GLenum, GLuint) = nullptr;
	void (*DeleteFramebuffers)(GLsizei, const GLuint *) = nullptr;
	void (*FramebufferTexture2D)(GLenum, GLenum, GLenum, GLuint, GLint) = nullptr;
	void (*FramebufferRenderbuffer)(GLenum, GLenum, GLenum, GLuint) = nullptr;
	GLenum (*CheckFramebufferStatus)(GLenum) = nullptr;
	void (*GenRenderbuffers)(GLsizei, GLuint *) = nullptr;
	void (*BindRenderbuffer)(GLenum, GLuint) = nullptr;
	void (*DeleteRenderbuffers)(GLsizei, const GLuint *) = nullptr;
	void (*RenderbufferStorage)(GLenum, GLenum, GLsizei, GLsizei) = nullptr;
	void (*GenTextures)(GLsizei, GLuint *) = nullptr;
	void (*BindTexture)(GLenum, GLuint) = nullptr;
	void (*DeleteTextures)(GLsizei, const GLuint *) = nullptr;
	void (*TexImage2D)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const GLvoid *) = nullptr;
	void (*TexParameteri)(GLenum, GLenum, GLint) = nullptr;
	void (*GetIntegerv)(GLenum, GLint *) = nullptr;
	void (*ReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, GLvoid *) = nullptr;
	void (*PixelStorei)(GLenum, GLint) = nullptr;
	void (*Viewport)(GLint, GLint, GLsizei, GLsizei) = nullptr;
	GLenum (*GetError)() = nullptr;
};

// Resolve os ponteiros uma vez. Devolve nullptr se a biblioteca de GL não
// abriu ou se faltou algum símbolo — nesse caso não há como fazer hw render e
// quem chama precisa recusar SET_HW_RENDER em vez de crashar adiante.
const GLFuncs *gl_load();

// O que entregamos ao core como `get_proc_address`: ele pede pelo nome as
// funções de GL que for usar. Passa por eglGetProcAddress/glXGetProcAddress
// quando existe, porque extensões só aparecem por lá.
void *gl_proc_address(const char *p_name);

} // namespace libretrogd

#endif // LIBRETROGD_GL_FUNCS_H
