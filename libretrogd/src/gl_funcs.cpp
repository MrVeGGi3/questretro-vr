#include "gl_funcs.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/string.hpp>

#include <dlfcn.h>

using namespace godot;

namespace libretrogd {

// Handles das bibliotecas de GL/EGL do processo. Abertas com RTLD_NOLOAD
// primeiro: se o Godot já as carregou — e carregou, é ele quem tem o contexto —
// pegamos o mesmo objeto em vez de uma segunda cópia.
static void *g_gl_lib = nullptr;
static void *g_egl_lib = nullptr;
static void *(*g_egl_get_proc)(const char *) = nullptr;
static void *(*g_glx_get_proc)(const char *) = nullptr;

static void *abrir(const char *p_nome) {
	void *h = dlopen(p_nome, RTLD_LAZY | RTLD_NOLOAD);
	return h ? h : dlopen(p_nome, RTLD_LAZY);
}

static void abrir_bibliotecas() {
	if (g_gl_lib) {
		return;
	}
#if defined(__ANDROID__)
	g_gl_lib = abrir("libGLESv2.so");
	g_egl_lib = abrir("libEGL.so");
#else
	// libGL cobre desktop GL e, via libglvnd, também GLES.
	g_gl_lib = abrir("libGL.so.1");
	if (!g_gl_lib) {
		g_gl_lib = abrir("libGL.so");
	}
	g_egl_lib = abrir("libEGL.so.1");
	if (!g_egl_lib) {
		g_egl_lib = abrir("libEGL.so");
	}
#endif
	if (g_egl_lib) {
		g_egl_get_proc = reinterpret_cast<void *(*)(const char *)>(
				dlsym(g_egl_lib, "eglGetProcAddress"));
	}
	if (g_gl_lib) {
		g_glx_get_proc = reinterpret_cast<void *(*)(const char *)>(
				dlsym(g_gl_lib, "glXGetProcAddressARB"));
		if (!g_glx_get_proc) {
			g_glx_get_proc = reinterpret_cast<void *(*)(const char *)>(
					dlsym(g_gl_lib, "glXGetProcAddress"));
		}
	}
}

void *gl_proc_address(const char *p_name) {
	abrir_bibliotecas();
	// dlsym primeiro: é o que resolve as funções do núcleo da API. Os
	// *GetProcAddress entram depois porque são eles que enxergam extensão.
	if (g_gl_lib) {
		if (void *p = dlsym(g_gl_lib, p_name)) {
			return p;
		}
	}
	if (g_egl_get_proc) {
		if (void *p = g_egl_get_proc(p_name)) {
			return p;
		}
	}
	if (g_glx_get_proc) {
		if (void *p = g_glx_get_proc(p_name)) {
			return p;
		}
	}
	// Última tentativa: o símbolo pode estar no executável ou numa lib já
	// carregada globalmente.
	return dlsym(RTLD_DEFAULT, p_name);
}

const GLFuncs *gl_load() {
	static GLFuncs funcs;
	static bool tentou = false;
	static bool ok = false;
	if (tentou) {
		return ok ? &funcs : nullptr;
	}
	tentou = true;

	abrir_bibliotecas();
	if (!g_gl_lib) {
		UtilityFunctions::push_warning(
				"libretrogd: não abri a biblioteca de OpenGL — sem hw render");
		return nullptr;
	}

	// Um símbolo faltando invalida tudo: melhor recusar o hw render inteiro do
	// que descobrir o buraco no meio de um retro_run.
	bool faltou = false;
	auto pegar = [&](const char *nome) -> void * {
		void *p = gl_proc_address(nome);
		if (!p) {
			UtilityFunctions::push_warning(
					String("libretrogd: símbolo de GL ausente: ") + nome);
			faltou = true;
		}
		return p;
	};

#define PEGAR(campo, nome) \
	funcs.campo = reinterpret_cast<decltype(funcs.campo)>(pegar(nome));

	PEGAR(GenFramebuffers, "glGenFramebuffers")
	PEGAR(BindFramebuffer, "glBindFramebuffer")
	PEGAR(DeleteFramebuffers, "glDeleteFramebuffers")
	PEGAR(FramebufferTexture2D, "glFramebufferTexture2D")
	PEGAR(FramebufferRenderbuffer, "glFramebufferRenderbuffer")
	PEGAR(CheckFramebufferStatus, "glCheckFramebufferStatus")
	PEGAR(GenRenderbuffers, "glGenRenderbuffers")
	PEGAR(BindRenderbuffer, "glBindRenderbuffer")
	PEGAR(DeleteRenderbuffers, "glDeleteRenderbuffers")
	PEGAR(RenderbufferStorage, "glRenderbufferStorage")
	PEGAR(GenTextures, "glGenTextures")
	PEGAR(BindTexture, "glBindTexture")
	PEGAR(DeleteTextures, "glDeleteTextures")
	PEGAR(TexImage2D, "glTexImage2D")
	PEGAR(TexParameteri, "glTexParameteri")
	PEGAR(GetIntegerv, "glGetIntegerv")
	PEGAR(ReadPixels, "glReadPixels")
	PEGAR(PixelStorei, "glPixelStorei")
	PEGAR(Viewport, "glViewport")
	PEGAR(GetError, "glGetError")
#undef PEGAR

	ok = !faltou;
	return ok ? &funcs : nullptr;
}

} // namespace libretrogd
