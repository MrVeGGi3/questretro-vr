#include "libretro_host.h"

#include "gl_funcs.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>

using namespace godot;

// Um core ativo por vez: os callbacks C do libretro não carregam user-data,
// então roteamos todos para a instância viva através deste ponteiro.
static LibretroHost *g_active_host = nullptr;

// ---------------------------------------------------------------------------
// Callbacks C estáticos exigidos pela API libretro
// ---------------------------------------------------------------------------
static void cb_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
	if (g_active_host) {
		g_active_host->_on_video_refresh(data, width, height, pitch);
	}
}

static void cb_audio_sample(int16_t left, int16_t right) {
	if (g_active_host) {
		int16_t buf[2] = { left, right };
		g_active_host->_on_audio_batch(buf, 1);
	}
}

static size_t cb_audio_sample_batch(const int16_t *data, size_t frames) {
	if (g_active_host) {
		g_active_host->_on_audio_batch(data, frames);
	}
	return frames;
}

static void cb_input_poll() {
	// Estado é empurrado do GDScript via set_button(); nada a fazer aqui.
}

static int16_t cb_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
	if (g_active_host) {
		return g_active_host->_on_input_state(port, device, index, id);
	}
	return 0;
}

static uintptr_t cb_get_current_framebuffer() {
	return g_active_host ? g_active_host->_on_get_current_framebuffer() : 0;
}

static retro_proc_address_t cb_get_proc_address(const char *sym) {
	return reinterpret_cast<retro_proc_address_t>(libretrogd::gl_proc_address(sym));
}

static bool cb_environment(unsigned cmd, void *data) {
	if (g_active_host) {
		return g_active_host->_on_environment(cmd, data);
	}
	return false;
}

static void cb_log(enum retro_log_level level, const char *fmt, ...) {
	char line[1024];
	va_list args;
	va_start(args, fmt);
	vsnprintf(line, sizeof(line), fmt, args);
	va_end(args);
	// remove newline final para não duplicar no console do Godot
	size_t n = strlen(line);
	while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) {
		line[--n] = '\0';
	}
	UtilityFunctions::print(String("[core:") + itos(level) + "] " + String(line));
}

// ---------------------------------------------------------------------------
// LibretroHost
// ---------------------------------------------------------------------------
void LibretroHost::_bind_methods() {
	// Antes de load_core na lista porque é antes dele no uso: o core pergunta os
	// diretórios durante o próprio retro_set_environment.
	ClassDB::bind_method(D_METHOD("set_system_dir", "path"), &LibretroHost::set_system_dir);
	ClassDB::bind_method(D_METHOD("get_system_dir"), &LibretroHost::get_system_dir);
	ClassDB::bind_method(D_METHOD("set_save_dir", "path"), &LibretroHost::set_save_dir);
	ClassDB::bind_method(D_METHOD("get_save_dir"), &LibretroHost::get_save_dir);

	ClassDB::bind_method(D_METHOD("load_core", "path"), &LibretroHost::load_core);
	ClassDB::bind_method(D_METHOD("load_rom", "path"), &LibretroHost::load_rom);
	ClassDB::bind_method(D_METHOD("unload_rom"), &LibretroHost::unload_rom);
	ClassDB::bind_method(D_METHOD("unload"), &LibretroHost::unload);
	ClassDB::bind_method(D_METHOD("supports_state"), &LibretroHost::supports_state);
	ClassDB::bind_method(D_METHOD("save_state"), &LibretroHost::save_state);
	ClassDB::bind_method(D_METHOD("load_state", "data"), &LibretroHost::load_state);
	ClassDB::bind_method(D_METHOD("get_memory_size", "id"), &LibretroHost::get_memory_size);
	ClassDB::bind_method(D_METHOD("get_memory", "id"), &LibretroHost::get_memory);
	ClassDB::bind_method(D_METHOD("set_memory", "id", "data"), &LibretroHost::set_memory);
	ClassDB::bind_method(D_METHOD("run_frame"), &LibretroHost::run_frame);
	ClassDB::bind_method(D_METHOD("get_frame"), &LibretroHost::get_frame);
	ClassDB::bind_method(D_METHOD("get_frame_width"), &LibretroHost::get_frame_width);
	ClassDB::bind_method(D_METHOD("get_frame_height"), &LibretroHost::get_frame_height);
	ClassDB::bind_method(D_METHOD("get_pixel_format"), &LibretroHost::get_pixel_format);
	ClassDB::bind_method(D_METHOD("get_fps"), &LibretroHost::get_fps);
	ClassDB::bind_method(D_METHOD("get_sample_rate"), &LibretroHost::get_sample_rate);
	ClassDB::bind_method(D_METHOD("get_audio"), &LibretroHost::get_audio);
	ClassDB::bind_method(D_METHOD("set_button", "port", "id", "pressed"), &LibretroHost::set_button);
	ClassDB::bind_method(D_METHOD("set_analog", "port", "index", "axis", "value"), &LibretroHost::set_analog);
	ClassDB::bind_method(D_METHOD("set_pointer", "port", "x", "y", "pressed"), &LibretroHost::set_pointer);
	ClassDB::bind_method(D_METHOD("set_controller_device", "port", "device"), &LibretroHost::set_controller_device);
	ClassDB::bind_method(D_METHOD("clear_input"), &LibretroHost::clear_input);
	ClassDB::bind_method(D_METHOD("get_options"), &LibretroHost::get_options);
	ClassDB::bind_method(D_METHOD("get_option", "key"), &LibretroHost::get_option);
	ClassDB::bind_method(D_METHOD("set_option", "key", "value"), &LibretroHost::set_option);
	ClassDB::bind_method(D_METHOD("get_input_descriptors"), &LibretroHost::get_input_descriptors);
	ClassDB::bind_method(D_METHOD("is_hw_render"), &LibretroHost::is_hw_render);
	ClassDB::bind_method(D_METHOD("is_core_loaded"), &LibretroHost::is_core_loaded);
	ClassDB::bind_method(D_METHOD("is_game_loaded"), &LibretroHost::is_game_loaded);

	BIND_ENUM_CONSTANT(JOYPAD_B);
	BIND_ENUM_CONSTANT(JOYPAD_Y);
	BIND_ENUM_CONSTANT(JOYPAD_SELECT);
	BIND_ENUM_CONSTANT(JOYPAD_START);
	BIND_ENUM_CONSTANT(JOYPAD_UP);
	BIND_ENUM_CONSTANT(JOYPAD_DOWN);
	BIND_ENUM_CONSTANT(JOYPAD_LEFT);
	BIND_ENUM_CONSTANT(JOYPAD_RIGHT);
	BIND_ENUM_CONSTANT(JOYPAD_A);
	BIND_ENUM_CONSTANT(JOYPAD_X);
	BIND_ENUM_CONSTANT(JOYPAD_L);
	BIND_ENUM_CONSTANT(JOYPAD_R);
	BIND_ENUM_CONSTANT(JOYPAD_L2);
	BIND_ENUM_CONSTANT(JOYPAD_R2);
	BIND_ENUM_CONSTANT(JOYPAD_L3);
	BIND_ENUM_CONSTANT(JOYPAD_R3);

	BIND_ENUM_CONSTANT(MEMORY_SAVE_RAM);
	BIND_ENUM_CONSTANT(MEMORY_RTC);

	BIND_ENUM_CONSTANT(DEVICE_JOYPAD);
	BIND_ENUM_CONSTANT(DEVICE_ANALOG);
	BIND_ENUM_CONSTANT(ANALOG_LEFT);
	BIND_ENUM_CONSTANT(ANALOG_RIGHT);
	BIND_ENUM_CONSTANT(ANALOG_X);
	BIND_ENUM_CONSTANT(ANALOG_Y);
}

LibretroHost::LibretroHost() {
	// diretórios padrão graváveis para saves/BIOS dos cores
	system_dir = "user://system";
	save_dir = "user://saves";
}

LibretroHost::~LibretroHost() {
	unload();
}

// Converte um caminho res:// ou user:// do Godot para caminho absoluto do SO.
static String globalize(const String &p_path) {
	return ProjectSettings::get_singleton()->globalize_path(p_path);
}

void LibretroHost::resolve_symbols() {
#define SYM(field, name) \
	field = reinterpret_cast<decltype(field)>(dlsym(lib_handle, name)); \
	if (!field) { UtilityFunctions::push_error(String::utf8("libretrogd: símbolo ausente: ") + name); }

	SYM(p_retro_init, "retro_init");
	SYM(p_retro_deinit, "retro_deinit");
	SYM(p_retro_run, "retro_run");
	SYM(p_retro_load_game, "retro_load_game");
	SYM(p_retro_unload_game, "retro_unload_game");
	SYM(p_retro_get_system_info, "retro_get_system_info");
	SYM(p_retro_get_system_av_info, "retro_get_system_av_info");
	SYM(p_retro_set_environment, "retro_set_environment");
	SYM(p_retro_set_video_refresh, "retro_set_video_refresh");
	SYM(p_retro_set_audio_sample, "retro_set_audio_sample");
	SYM(p_retro_set_audio_sample_batch, "retro_set_audio_sample_batch");
	SYM(p_retro_set_input_poll, "retro_set_input_poll");
	SYM(p_retro_set_input_state, "retro_set_input_state");
	SYM(p_retro_set_controller_port_device, "retro_set_controller_port_device");
#undef SYM

// Os de save state são opcionais na API libretro: ausência não é erro, só
// significa que a página de Saves fica indisponível para este core.
#define SYM_OPT(field, name) \
	field = reinterpret_cast<decltype(field)>(dlsym(lib_handle, name));

	SYM_OPT(p_retro_serialize_size, "retro_serialize_size");
	SYM_OPT(p_retro_serialize, "retro_serialize");
	SYM_OPT(p_retro_unserialize, "retro_unserialize");
	SYM_OPT(p_retro_get_memory_data, "retro_get_memory_data");
	SYM_OPT(p_retro_get_memory_size, "retro_get_memory_size");
#undef SYM_OPT
}

bool LibretroHost::supports_state() const {
	return p_retro_serialize_size && p_retro_serialize && p_retro_unserialize;
}

PackedByteArray LibretroHost::save_state() {
	PackedByteArray out;
	if (!game_loaded || !supports_state()) {
		UtilityFunctions::push_error("libretrogd: save_state sem jogo ou sem suporte do core");
		return out;
	}
	// O tamanho pode variar entre frames; consultar sempre antes de gravar.
	size_t tam = p_retro_serialize_size();
	if (tam == 0) {
		UtilityFunctions::push_error("libretrogd: retro_serialize_size retornou 0");
		return out;
	}
	out.resize((int64_t)tam);
	if (!p_retro_serialize(out.ptrw(), tam)) {
		UtilityFunctions::push_error("libretrogd: retro_serialize falhou");
		out.clear();
	}
	return out;
}

bool LibretroHost::load_state(const PackedByteArray &p_data) {
	if (!game_loaded || !supports_state()) {
		UtilityFunctions::push_error("libretrogd: load_state sem jogo ou sem suporte do core");
		return false;
	}
	if (p_data.is_empty()) {
		UtilityFunctions::push_error("libretrogd: load_state com estado vazio");
		return false;
	}
	if (!p_retro_unserialize(p_data.ptr(), (size_t)p_data.size())) {
		UtilityFunctions::push_error("libretrogd: retro_unserialize falhou (estado de outro core/ROM?)");
		return false;
	}
	return true;
}

// ---------------------------------------------------------------------------
// Memória do core (SRAM de bateria, RTC)
// ---------------------------------------------------------------------------
// O ponteiro de retro_get_memory_data só vale depois de retro_load_game e pode
// mudar de endereço a cada carga, então é reconsultado a cada chamada — nunca
// guardado num campo.
int LibretroHost::get_memory_size(int p_id) const {
	if (!game_loaded || !p_retro_get_memory_size || p_id < 0) {
		return 0;
	}
	return (int)p_retro_get_memory_size((unsigned)p_id);
}

PackedByteArray LibretroHost::get_memory(int p_id) const {
	PackedByteArray out;
	int tam = get_memory_size(p_id);
	if (tam <= 0 || !p_retro_get_memory_data) {
		return out;
	}
	const void *src = p_retro_get_memory_data((unsigned)p_id);
	if (!src) {
		// Tamanho > 0 sem ponteiro é bug do core; melhor devolver vazio do que
		// gravar lixo por cima de um save bom.
		UtilityFunctions::push_warning(String::utf8("libretrogd: memória ") + itos(p_id) +
				String::utf8(" tem tamanho mas não tem ponteiro"));
		return out;
	}
	out.resize((int64_t)tam);
	memcpy(out.ptrw(), src, (size_t)tam);
	return out;
}

bool LibretroHost::set_memory(int p_id, const PackedByteArray &p_data) {
	int tam = get_memory_size(p_id);
	if (tam <= 0 || !p_retro_get_memory_data) {
		return false;
	}
	// Tamanho diferente é .srm de outra ROM ou de outro core: escrever assim
	// corrompe o save do jogo em silêncio, então recusa.
	if (p_data.size() != tam) {
		UtilityFunctions::push_warning(String::utf8("libretrogd: memória ") + itos(p_id) +
				" tem " + itos(tam) + String::utf8(" bytes, mas os dados têm ") + itos(p_data.size()) +
				String::utf8(" — ignorando"));
		return false;
	}
	void *dst = p_retro_get_memory_data((unsigned)p_id);
	if (!dst) {
		return false;
	}
	memcpy(dst, p_data.ptr(), (size_t)tam);
	return true;
}

bool LibretroHost::load_core(const String &p_path) {
	unload();

	String abs = globalize(p_path);
	lib_handle = dlopen(abs.utf8().get_data(), RTLD_LAZY | RTLD_LOCAL);
	if (!lib_handle) {
		UtilityFunctions::push_error(String("libretrogd: dlopen falhou: ") + String(dlerror()));
		return false;
	}

	resolve_symbols();
	if (!p_retro_init || !p_retro_run || !p_retro_load_game || !p_retro_set_environment) {
		UtilityFunctions::push_error(String::utf8("libretrogd: core não expõe a API libretro esperada"));
		unload();
		return false;
	}

	g_active_host = this;

	// GET_SYSTEM_DIRECTORY e GET_SAVE_DIRECTORY prometem caminhos ao core, e
	// ele os usa sem conferir se existem: o GLideN64 guarda o cache de shaders
	// compilados no de sistema, e o mupen escreve .srm/.eep no de save. Criar
	// aqui, antes do retro_init, é o que torna a promessa verdadeira.
	DirAccess::make_dir_recursive_absolute(system_dir);
	DirAccess::make_dir_recursive_absolute(save_dir);

	// A ordem importa: environment antes de init para o core ler pixel format etc.
	p_retro_set_environment(cb_environment);
	p_retro_set_video_refresh(cb_video_refresh);
	if (p_retro_set_audio_sample) p_retro_set_audio_sample(cb_audio_sample);
	if (p_retro_set_audio_sample_batch) p_retro_set_audio_sample_batch(cb_audio_sample_batch);
	p_retro_set_input_poll(cb_input_poll);
	p_retro_set_input_state(cb_input_state);

	// descobre se o core exige caminho completo (need_fullpath)
	retro_system_info sysinfo;
	memset(&sysinfo, 0, sizeof(sysinfo));
	if (p_retro_get_system_info) {
		p_retro_get_system_info(&sysinfo);
		need_fullpath = sysinfo.need_fullpath;
	}

	p_retro_init();
	core_loaded = true;
	UtilityFunctions::print(String("libretrogd: core carregado (") +
			(sysinfo.library_name ? String(sysinfo.library_name) : String("?")) + ")");
	return true;
}

bool LibretroHost::load_rom(const String &p_path) {
	if (!core_loaded) {
		UtilityFunctions::push_error("libretrogd: load_rom sem core carregado");
		return false;
	}
	// Trocar de jogo sem descarregar o anterior deixa o core em estado
	// inconsistente (e vaza o que ele alocou no load anterior).
	unload_rom();

	String abs = globalize(p_path);

	retro_game_info info;
	memset(&info, 0, sizeof(info));
	CharString abs_utf8 = abs.utf8();
	info.path = abs_utf8.get_data();

	if (need_fullpath) {
		info.data = nullptr;
		info.size = 0;
	} else {
		Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::READ);
		if (f.is_null()) {
			UtilityFunctions::push_error(String::utf8("libretrogd: não abriu a ROM: ") + p_path);
			return false;
		}
		PackedByteArray bytes = f->get_buffer(f->get_length());
		f->close();
		game_data.assign(bytes.ptr(), bytes.ptr() + bytes.size());
		info.data = game_data.data();
		info.size = game_data.size();
	}

	if (!p_retro_load_game(&info)) {
		UtilityFunctions::push_error("libretrogd: retro_load_game falhou");
		return false;
	}

	// lê a/v info (resolução base, fps, sample rate)
	retro_system_av_info av;
	memset(&av, 0, sizeof(av));
	if (p_retro_get_system_av_info) {
		p_retro_get_system_av_info(&av);
		av_fps = av.timing.fps > 0 ? av.timing.fps : 60.0;
		av_sample_rate = av.timing.sample_rate > 0 ? av.timing.sample_rate : 32040.0;
	}

	// Com hw render, o core ainda não desenhou nada: falta o FBO e o aviso de
	// que o contexto está pronto. A ordem é essa — context_reset é onde o core
	// compila shaders e cria texturas, e ele já pode pedir o framebuffer.
	if (hw_enabled) {
		int alvo_w = (int)av.geometry.max_width;
		int alvo_h = (int)av.geometry.max_height;
		if (alvo_w <= 0 || alvo_h <= 0) {
			alvo_w = (int)av.geometry.base_width;
			alvo_h = (int)av.geometry.base_height;
		}
		if (hw_criar_alvo(alvo_w, alvo_h)) {
			hw_pronto = true;
			if (hw_cb.context_reset) {
				hw_cb.context_reset();
			}
		} else {
			// Sem FBO o core desenharia no alvo do Godot. Melhor sair sem
			// imagem do que corromper o que a cena está desenhando.
			UtilityFunctions::push_error(
					"libretrogd: hw render pedido mas o FBO não subiu — sem vídeo");
			hw_enabled = false;
		}
	}

	game_loaded = true;
	UtilityFunctions::print(String::utf8("libretrogd: ROM carregada — ") +
			String::num_int64((int64_t)av.geometry.base_width) + "x" +
			String::num_int64((int64_t)av.geometry.base_height) + " @ " +
			String::num(av_fps, 2) + "fps");
	return true;
}

void LibretroHost::run_frame() {
	if (!game_loaded || !p_retro_run) {
		return;
	}
	if (!hw_pronto) {
		p_retro_run();
		return;
	}

	// Emprestamos o contexto do Godot ao core, então devolvemos o alvo de
	// render exatamente como estava. Sem isto o Godot desenha o próximo frame
	// dentro do FBO do emulador.
	const libretrogd::GLFuncs *gl = libretrogd::gl_load();
	using namespace libretrogd;
	GLint fbo_antes = 0;
	GLint viewport_antes[4] = { 0, 0, 0, 0 };
	if (gl) {
		gl->GetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo_antes);
		gl->GetIntegerv(GL_VIEWPORT, viewport_antes);
		gl->BindFramebuffer(GL_FRAMEBUFFER, hw_fbo);
		gl->Viewport(0, 0, hw_alvo_w, hw_alvo_h);
	}

	p_retro_run();

	if (gl) {
		gl->BindFramebuffer(GL_FRAMEBUFFER, (GLuint)fbo_antes);
		gl->Viewport(viewport_antes[0], viewport_antes[1],
				viewport_antes[2], viewport_antes[3]);
	}
}

void LibretroHost::unload_rom() {
	// Antes do unload_game: o core solta aqui as texturas e shaders que criou,
	// e depois de descarregado ele não tem mais como fazê-lo.
	if (hw_pronto && hw_cb.context_destroy) {
		hw_cb.context_destroy();
	}
	hw_pronto = false;
	hw_destruir_alvo();

	if (game_loaded && p_retro_unload_game) {
		p_retro_unload_game();
	}
	game_loaded = false;
	game_data.clear();
	frame_rgba.clear();
	frame_width = 0;
	frame_height = 0;
	audio_accum.clear();
	clear_input();
}

void LibretroHost::unload() {
	// Passa por unload_rom() em vez de chamar retro_unload_game direto: é ele
	// que avisa o core para soltar os recursos de GPU antes de tudo sumir.
	if (game_loaded) {
		unload_rom();
	}
	if (core_loaded && p_retro_deinit) {
		p_retro_deinit();
	}
	if (lib_handle) {
		dlclose(lib_handle);
		lib_handle = nullptr;
	}
	if (g_active_host == this) {
		g_active_host = nullptr;
	}
	core_loaded = false;
	game_loaded = false;
	reset_state();
}

void LibretroHost::reset_state() {
	frame_rgba.clear();
	frame_width = frame_height = 0;
	audio_accum.clear();
	clear_input();
	game_data.clear();
	// Opções e mapa de controle pertencem ao core, não ao jogo: só somem quando
	// o core sai. Por isso a limpeza mora aqui e não em unload_rom().
	options.clear();
	options_dirty = false;
	input_descriptors.clear();
	// O pedido de hw render também é do core: o próximo pode não querer.
	hw_pronto = false;
	hw_enabled = false;
	hw_cb = {};
	hw_destruir_alvo();
}

// ---------------------------------------------------------------------------
// Renderização por hardware
// ---------------------------------------------------------------------------
// O core não devolve pixels: ele desenha num FBO nosso. O ciclo é
//   run_frame() -> salva o alvo do Godot -> binda o nosso -> retro_run()
//               -> lê o resultado -> devolve o alvo do Godot.
// Devolver é obrigatório: sem isso o core fica com o alvo de render e o Godot
// passa a desenhar dentro do FBO dele.
uintptr_t LibretroHost::_on_get_current_framebuffer() {
	return hw_fbo;
}

bool LibretroHost::hw_criar_alvo(int p_width, int p_height) {
	const libretrogd::GLFuncs *gl = libretrogd::gl_load();
	if (!gl || p_width <= 0 || p_height <= 0) {
		return false;
	}
	if (hw_fbo && hw_alvo_w == p_width && hw_alvo_h == p_height) {
		return true;  // já serve
	}
	hw_destruir_alvo();

	using namespace libretrogd;
	GLint fbo_antes = 0;
	gl->GetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo_antes);

	gl->GenTextures(1, &hw_tex);
	gl->BindTexture(GL_TEXTURE_2D, hw_tex);
	gl->TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, p_width, p_height, 0,
			GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
	gl->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	gl->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	gl->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	gl->TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

	gl->GenFramebuffers(1, &hw_fbo);
	gl->BindFramebuffer(GL_FRAMEBUFFER, hw_fbo);
	gl->FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, hw_tex, 0);

	// Profundidade só se o core pediu. Um core 2D não paga por ela; o N64 sim.
	if (hw_cb.depth) {
		gl->GenRenderbuffers(1, &hw_depth);
		gl->BindRenderbuffer(GL_RENDERBUFFER, hw_depth);
		// Combinado quando também há stencil: um anexo em vez de dois, que é o
		// que o GLES3 aceita sem reclamar de formato.
		if (hw_cb.stencil) {
			gl->RenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, p_width, p_height);
			gl->FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
					GL_RENDERBUFFER, hw_depth);
		} else {
			gl->RenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, p_width, p_height);
			gl->FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
					GL_RENDERBUFFER, hw_depth);
		}
		gl->BindRenderbuffer(GL_RENDERBUFFER, 0);
	}

	GLenum estado = gl->CheckFramebufferStatus(GL_FRAMEBUFFER);
	gl->BindFramebuffer(GL_FRAMEBUFFER, (GLuint)fbo_antes);
	gl->BindTexture(GL_TEXTURE_2D, 0);

	if (estado != GL_FRAMEBUFFER_COMPLETE) {
		UtilityFunctions::push_error(String("libretrogd: FBO incompleto (0x") +
				String::num_int64(estado, 16) + ")");
		hw_destruir_alvo();
		return false;
	}

	hw_alvo_w = p_width;
	hw_alvo_h = p_height;
	frame_rgba.assign((size_t)p_width * (size_t)p_height * 4, 0);
	UtilityFunctions::print(String("libretrogd: hw render em FBO ") +
			itos(p_width) + "x" + itos(p_height) +
			(hw_cb.depth ? " (com profundidade)" : ""));
	return true;
}

void LibretroHost::hw_destruir_alvo() {
	const libretrogd::GLFuncs *gl = libretrogd::gl_load();
	if (gl) {
		using namespace libretrogd;
		if (hw_fbo) gl->DeleteFramebuffers(1, &hw_fbo);
		if (hw_tex) gl->DeleteTextures(1, &hw_tex);
		if (hw_depth) gl->DeleteRenderbuffers(1, &hw_depth);
	}
	hw_fbo = hw_tex = hw_depth = 0;
	hw_alvo_w = hw_alvo_h = 0;
}

void LibretroHost::hw_ler_frame(int p_width, int p_height) {
	const libretrogd::GLFuncs *gl = libretrogd::gl_load();
	if (!gl || !hw_fbo || p_width <= 0 || p_height <= 0) {
		return;
	}
	using namespace libretrogd;
	size_t linha = (size_t)p_width * 4;
	frame_rgba.resize(linha * (size_t)p_height);

	GLint fbo_antes = 0;
	gl->GetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo_antes);
	gl->BindFramebuffer(GL_FRAMEBUFFER, hw_fbo);
	// Sem isto o GL assume alinhamento de 4 por linha; com RGBA já bate, mas
	// deixar explícito evita surpresa se um dia lermos outro formato.
	gl->PixelStorei(GL_PACK_ALIGNMENT, 1);
	gl->ReadPixels(0, 0, p_width, p_height, GL_RGBA, GL_UNSIGNED_BYTE, frame_rgba.data());
	gl->BindFramebuffer(GL_FRAMEBUFFER, (GLuint)fbo_antes);

	// O GL numera as linhas de baixo para cima; a Image do Godot, de cima para
	// baixo. Quando o core desenha na convenção do GL (o normal), desviramos.
	if (hw_cb.bottom_left_origin) {
		hw_linha.resize(linha);
		for (int y = 0; y < p_height / 2; ++y) {
			uint8_t *a = frame_rgba.data() + (size_t)y * linha;
			uint8_t *b = frame_rgba.data() + (size_t)(p_height - 1 - y) * linha;
			memcpy(hw_linha.data(), a, linha);
			memcpy(a, b, linha);
			memcpy(b, hw_linha.data(), linha);
		}
	}

	frame_width = p_width;
	frame_height = p_height;
}

// ---------------------------------------------------------------------------
// Vídeo
// ---------------------------------------------------------------------------
void LibretroHost::_on_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
	// data == NULL sinaliza frame duplicado; mantém o buffer anterior.
	if (data == nullptr || width == 0 || height == 0) {
		return;
	}

	// Com hw render o core não manda pixels: manda este sentinela dizendo "o
	// frame está no FBO que você me deu". A resolução varia de frame a frame
	// (o N64 troca de modo de vídeo), então ela chega por aqui, não do av_info.
	if (data == RETRO_HW_FRAME_BUFFER_VALID) {
		hw_ler_frame((int)width, (int)height);
		return;
	}

	frame_width = (int)width;
	frame_height = (int)height;
	frame_rgba.resize((size_t)width * height * 4);
	uint8_t *dst = frame_rgba.data();
	const uint8_t *src = reinterpret_cast<const uint8_t *>(data);

	switch (pixel_format) {
		case RETRO_PIXEL_FORMAT_XRGB8888: {
			for (unsigned y = 0; y < height; ++y) {
				const uint32_t *row = reinterpret_cast<const uint32_t *>(src + y * pitch);
				for (unsigned x = 0; x < width; ++x) {
					uint32_t p = row[x];
					*dst++ = (p >> 16) & 0xFF; // R
					*dst++ = (p >> 8) & 0xFF;  // G
					*dst++ = p & 0xFF;         // B
					*dst++ = 0xFF;             // A
				}
			}
			break;
		}
		case RETRO_PIXEL_FORMAT_RGB565: {
			for (unsigned y = 0; y < height; ++y) {
				const uint16_t *row = reinterpret_cast<const uint16_t *>(src + y * pitch);
				for (unsigned x = 0; x < width; ++x) {
					uint16_t p = row[x];
					uint8_t r = (p >> 11) & 0x1F;
					uint8_t g = (p >> 5) & 0x3F;
					uint8_t b = p & 0x1F;
					*dst++ = (r << 3) | (r >> 2);
					*dst++ = (g << 2) | (g >> 4);
					*dst++ = (b << 3) | (b >> 2);
					*dst++ = 0xFF;
				}
			}
			break;
		}
		case RETRO_PIXEL_FORMAT_0RGB1555:
		default: {
			for (unsigned y = 0; y < height; ++y) {
				const uint16_t *row = reinterpret_cast<const uint16_t *>(src + y * pitch);
				for (unsigned x = 0; x < width; ++x) {
					uint16_t p = row[x];
					uint8_t r = (p >> 10) & 0x1F;
					uint8_t g = (p >> 5) & 0x1F;
					uint8_t b = p & 0x1F;
					*dst++ = (r << 3) | (r >> 2);
					*dst++ = (g << 3) | (g >> 2);
					*dst++ = (b << 3) | (b >> 2);
					*dst++ = 0xFF;
				}
			}
			break;
		}
	}
}

String LibretroHost::get_pixel_format() const {
	// Com hw render o core desenha no FBO e `pixel_format` fica valendo o que o
	// core declarou sem nunca ser usado — dizer o nome dele aqui apontaria o
	// diagnóstico para um laço que não roda.
	if (hw_pronto) {
		return "hw";
	}
	switch (pixel_format) {
		case RETRO_PIXEL_FORMAT_XRGB8888: return "XRGB8888";
		case RETRO_PIXEL_FORMAT_RGB565: return "RGB565";
		case RETRO_PIXEL_FORMAT_0RGB1555: return "0RGB1555";
		default: return "0RGB1555";  // o mesmo fallback do switch da conversão
	}
}

Ref<Image> LibretroHost::get_frame() const {
	if (frame_width == 0 || frame_height == 0 || frame_rgba.empty()) {
		return Ref<Image>();
	}
	PackedByteArray bytes;
	bytes.resize((int64_t)frame_rgba.size());
	memcpy(bytes.ptrw(), frame_rgba.data(), frame_rgba.size());
	return Image::create_from_data(frame_width, frame_height, false, Image::FORMAT_RGBA8, bytes);
}

// ---------------------------------------------------------------------------
// Áudio
// ---------------------------------------------------------------------------
void LibretroHost::_on_audio_batch(const int16_t *data, size_t frames) {
	const float inv = 1.0f / 32768.0f;
	audio_accum.reserve(audio_accum.size() + frames * 2);
	for (size_t i = 0; i < frames * 2; ++i) {
		audio_accum.push_back((float)data[i] * inv);
	}
}

PackedVector2Array LibretroHost::get_audio() {
	PackedVector2Array out;
	size_t pairs = audio_accum.size() / 2;
	out.resize((int64_t)pairs);
	Vector2 *w = out.ptrw();
	for (size_t i = 0; i < pairs; ++i) {
		w[i] = Vector2(audio_accum[i * 2], audio_accum[i * 2 + 1]);
	}
	audio_accum.clear();
	return out;
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------
int16_t LibretroHost::_on_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
	if (port >= 2) {
		return 0;
	}
	if (device == RETRO_DEVICE_ANALOG) {
		// Índice BUTTON pede a *pressão* de um botão, não um eixo. Só temos
		// digital, então devolvemos o fundo de escala quando está apertado —
		// é o que o RetroArch faz para controle sem gatilho analógico.
		if (index == RETRO_DEVICE_INDEX_ANALOG_BUTTON) {
			return (id <= 15 && (input_state[port] & (1u << id))) ? 0x7fff : 0;
		}
		if (index > RETRO_DEVICE_INDEX_ANALOG_RIGHT || id > RETRO_DEVICE_ID_ANALOG_Y) {
			return 0;
		}
		return analog_state[port][index][id];
	}
	if (device == RETRO_DEVICE_POINTER) {
		// Índice > 0 seria um segundo dedo; a caneta é uma só.
		if (index > 0) {
			return 0;
		}
		switch (id) {
			case RETRO_DEVICE_ID_POINTER_X:
				return pointer_x[port];
			case RETRO_DEVICE_ID_POINTER_Y:
				return pointer_y[port];
			case RETRO_DEVICE_ID_POINTER_PRESSED:
				return pointer_pressed[port] ? 1 : 0;
			// Quantos ponteiros estão encostados agora. Cores consultam isto
			// antes de ler X/Y, e devolver 0 aqui faz o toque ser ignorado
			// mesmo com PRESSED valendo 1.
			case RETRO_DEVICE_ID_POINTER_COUNT:
				return pointer_pressed[port] ? 1 : 0;
			default:
				return 0;
		}
	}
	if (device != RETRO_DEVICE_JOYPAD || id > 15) {
		return 0;
	}
	return (input_state[port] & (1u << id)) ? 1 : 0;
}

void LibretroHost::set_button(int p_port, int p_id, bool p_pressed) {
	if (p_port < 0 || p_port >= 2 || p_id < 0 || p_id > 15) {
		return;
	}
	if (p_pressed) {
		input_state[p_port] |= (1u << p_id);
	} else {
		input_state[p_port] &= ~(1u << p_id);
	}
}

void LibretroHost::set_analog(int p_port, int p_index, int p_axis, double p_value) {
	if (p_port < 0 || p_port >= 2 || p_index < 0 || p_index > 1 || p_axis < 0 || p_axis > 1) {
		return;
	}
	// 0x7fff nos dois sentidos, para o centro cair exatamente em zero — o -32768
	// que caberia no int16 deixaria a esquerda mais forte que a direita.
	double v = p_value < -1.0 ? -1.0 : (p_value > 1.0 ? 1.0 : p_value);
	analog_state[p_port][p_index][p_axis] = (int16_t)(v * 32767.0);
}

void LibretroHost::set_pointer(int p_port, double p_x, double p_y, bool p_pressed) {
	if (p_port < 0 || p_port >= 2) {
		return;
	}
	double x = p_x < -1.0 ? -1.0 : (p_x > 1.0 ? 1.0 : p_x);
	double y = p_y < -1.0 ? -1.0 : (p_y > 1.0 ? 1.0 : p_y);
	// Mesmo 0x7fff dos eixos, e pela mesma razão: com o -32768 que caberia no
	// int16 o lado esquerdo teria um passo a mais que o direito.
	pointer_x[p_port] = (int16_t)(x * 32767.0);
	pointer_y[p_port] = (int16_t)(y * 32767.0);
	pointer_pressed[p_port] = p_pressed;
}

void LibretroHost::set_controller_device(int p_port, int p_device) {
	if (p_port < 0 || p_port >= 2 || !p_retro_set_controller_port_device) {
		return;
	}
	p_retro_set_controller_port_device((unsigned)p_port, (unsigned)p_device);
}

void LibretroHost::clear_input() {
	input_state[0] = input_state[1] = 0;
	memset(analog_state, 0, sizeof(analog_state));
	// A caneta junto: quem chama isto é o menu abrindo, e o menu abre com o
	// gatilho na mão. Sem zerar aqui, a caneta ficaria encostada na tela do jogo
	// durante todo o tempo em que o painel estivesse aberto.
	memset(pointer_x, 0, sizeof(pointer_x));
	memset(pointer_y, 0, sizeof(pointer_y));
	pointer_pressed[0] = pointer_pressed[1] = false;
}

// ---------------------------------------------------------------------------
// Opções do core
// ---------------------------------------------------------------------------
LibretroHost::CoreOption *LibretroHost::find_option(const String &p_key) {
	for (CoreOption &o : options) {
		if (o.key == p_key) {
			return &o;
		}
	}
	return nullptr;
}

const LibretroHost::CoreOption *LibretroHost::find_option(const String &p_key) const {
	return const_cast<LibretroHost *>(this)->find_option(p_key);
}

void LibretroHost::register_option(const String &p_key, const String &p_desc, const String &p_info,
		const PackedStringArray &p_values, const PackedStringArray &p_labels,
		const String &p_default) {
	if (p_key.is_empty()) {
		return;
	}
	CoreOption *existente = find_option(p_key);
	// Um core pode declarar o mesmo conjunto duas vezes (v2 e depois o fallback
	// v1). Redeclarar não pode apagar uma escolha que o GDScript já fez.
	String escolhido = existente ? existente->value : String();

	CoreOption opt;
	opt.key = p_key;
	opt.desc = p_desc;
	opt.info = p_info;
	opt.values = p_values;
	opt.labels = p_labels;
	opt.default_value = p_default.is_empty() && !p_values.is_empty() ? p_values[0] : p_default;
	opt.value = escolhido.is_empty() ? opt.default_value : escolhido;
	opt.value_utf8 = opt.value.utf8();

	if (existente) {
		*existente = opt;
	} else {
		options.push_back(opt);
	}
}

// SET_VARIABLES: cada entrada é "Título; val1|val2|val3", o primeiro é o padrão.
void LibretroHost::parse_variables(const struct retro_variable *p_vars) {
	if (!p_vars) {
		return;
	}
	for (const retro_variable *v = p_vars; v->key && v->value; ++v) {
		String bruto = String::utf8(v->value);
		int corte = bruto.find(";");
		String desc = corte >= 0 ? bruto.substr(0, corte) : bruto;
		String lista = corte >= 0 ? bruto.substr(corte + 1).strip_edges() : String();

		PackedStringArray vals;
		for (const String &item : lista.split("|", false)) {
			String limpo = item.strip_edges();
			if (!limpo.is_empty()) {
				vals.push_back(limpo);
			}
		}
		// Sem rótulos separados neste formato: o id é o que a UI mostra.
		register_option(String::utf8(v->key), desc, String(), vals, vals,
				vals.is_empty() ? String() : vals[0]);
	}
}

void LibretroHost::parse_options_v1(const struct retro_core_option_definition *p_defs) {
	if (!p_defs) {
		return;
	}
	for (const retro_core_option_definition *d = p_defs; d->key; ++d) {
		PackedStringArray vals;
		PackedStringArray labels;
		for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX && d->values[i].value; ++i) {
			vals.push_back(String::utf8(d->values[i].value));
			labels.push_back(d->values[i].label
					? String::utf8(d->values[i].label)
					: String::utf8(d->values[i].value));
		}
		register_option(String::utf8(d->key),
				d->desc ? String::utf8(d->desc) : String(),
				d->info ? String::utf8(d->info) : String(),
				vals, labels,
				d->default_value ? String::utf8(d->default_value) : String());
	}
}

void LibretroHost::parse_options_v2(const struct retro_core_option_v2_definition *p_defs) {
	if (!p_defs) {
		return;
	}
	for (const retro_core_option_v2_definition *d = p_defs; d->key; ++d) {
		PackedStringArray vals;
		PackedStringArray labels;
		for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX && d->values[i].value; ++i) {
			vals.push_back(String::utf8(d->values[i].value));
			labels.push_back(d->values[i].label
					? String::utf8(d->values[i].label)
					: String::utf8(d->values[i].value));
		}
		register_option(String::utf8(d->key),
				d->desc ? String::utf8(d->desc) : String(),
				d->info ? String::utf8(d->info) : String(),
				vals, labels,
				d->default_value ? String::utf8(d->default_value) : String());
	}
}

Array LibretroHost::get_options() const {
	Array out;
	for (const CoreOption &o : options) {
		Dictionary d;
		d["key"] = o.key;
		d["desc"] = o.desc;
		d["info"] = o.info;
		d["values"] = o.values;
		d["labels"] = o.labels;
		d["default"] = o.default_value;
		d["value"] = o.value;
		out.push_back(d);
	}
	return out;
}

Array LibretroHost::get_input_descriptors() const {
	return input_descriptors;
}

String LibretroHost::get_option(const String &p_key) const {
	const CoreOption *o = find_option(p_key);
	return o ? o->value : String();
}

void LibretroHost::set_option(const String &p_key, const String &p_value) {
	CoreOption *o = find_option(p_key);
	if (!o) {
		UtilityFunctions::push_warning(String::utf8("libretrogd: opção desconhecida: ") + p_key);
		return;
	}
	// Valor fora da lista faz o core cair no default dele sem avisar; barrar
	// aqui transforma um erro de digitação num aviso legível.
	if (!o->values.is_empty() && o->values.find(p_value) < 0) {
		UtilityFunctions::push_warning(String::utf8("libretrogd: valor inválido para ") + p_key +
				": " + p_value + String::utf8(" (aceitos: ") + String(", ").join(o->values) + ")");
		return;
	}
	if (o->value == p_value) {
		return;
	}
	o->value = p_value;
	o->value_utf8 = p_value.utf8();
	options_dirty = true;
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------
bool LibretroHost::_on_environment(unsigned cmd, void *data) {
	switch (cmd) {
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
			unsigned fmt = *reinterpret_cast<const unsigned *>(data);
			pixel_format = fmt;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
			*reinterpret_cast<bool *>(data) = true;
			return true;
		}
		// Os buffers são membros (ver o comentário deles no cabeçalho): o ponteiro
		// entregue ao core sobrevive ao retorno desta função, e recalcular a cada
		// chamada é o que faz `set_system_dir` valer.
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
			system_dir_utf8 = globalize(system_dir).utf8();
			*reinterpret_cast<const char **>(data) = system_dir_utf8.get_data();
			// Imprime porque "BIOS não encontrada" é indistinguível de "procurei
			// no lugar errado" sem esta linha — e no headset não há como listar a
			// pasta que o core enxergou. É uma linha por carga de core.
			UtilityFunctions::print(String("libretrogd: BIOS/firmware em ") + String(system_dir_utf8.get_data()));
			return true;
		}
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
			save_dir_utf8 = globalize(save_dir).utf8();
			*reinterpret_cast<const char **>(data) = save_dir_utf8.get_data();
			return true;
		}
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
			auto *cb = reinterpret_cast<retro_log_callback *>(data);
			cb->log = cb_log;
			return true;
		}
		case RETRO_ENVIRONMENT_SET_HW_RENDER: {
			auto *cb = reinterpret_cast<retro_hw_render_callback *>(data);
			if (!cb) {
				return false;
			}
			// Só as variantes de OpenGL. Vulkan exigiria a interface de
			// negociação de dispositivo, e aqui o Godot roda em
			// gl_compatibility — é o contexto dele que emprestamos ao core.
			if (cb->context_type != RETRO_HW_CONTEXT_OPENGL &&
					cb->context_type != RETRO_HW_CONTEXT_OPENGL_CORE &&
					cb->context_type != RETRO_HW_CONTEXT_OPENGLES2 &&
					cb->context_type != RETRO_HW_CONTEXT_OPENGLES3 &&
					cb->context_type != RETRO_HW_CONTEXT_OPENGLES_VERSION) {
				UtilityFunctions::push_warning(
						String("libretrogd: core pediu contexto de vídeo não suportado (tipo ") +
						itos((int)cb->context_type) + ")");
				return false;
			}
			// O contexto que emprestamos é o do Godot, e ele só existe se o
			// Godot estiver rodando em gl_compatibility. Num renderer baseado
			// em RenderingDevice (Vulkan) há libGLESv2 no sistema e os
			// símbolos resolvem — mas não há contexto corrente, e o core
			// desenharia no vazio. Este é o caso do Android, onde
			// `rendering_method.mobile` manda e o padrão é Vulkan.
			RenderingServer *rs = RenderingServer::get_singleton();
			if (rs && rs->get_rendering_device() != nullptr) {
				UtilityFunctions::push_warning(String::utf8(
						"libretrogd: hw render recusado — o Godot não está em "
						"gl_compatibility (renderer baseado em RenderingDevice)"));
				return false;
			}
			// Sem as funções de GL não há FBO para oferecer. Recusar aqui faz o
			// core cair no renderizador de software dele, que é ruim mas roda;
			// aceitar e falhar depois seria tela preta sem explicação.
			if (libretrogd::gl_load() == nullptr) {
				return false;
			}
			hw_cb = *cb;
			cb->get_current_framebuffer = cb_get_current_framebuffer;
			cb->get_proc_address = cb_get_proc_address;
			hw_enabled = true;
			return true;
		}
		case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS: {
			// Chega uma vez por core (às vezes por jogo). É o core dizendo o
			// nome de cada id do joypad libretro no console dele.
			input_descriptors.clear();
			auto *d = reinterpret_cast<const retro_input_descriptor *>(data);
			for (; d && d->description; ++d) {
				Dictionary e;
				e["port"] = (int)d->port;
				e["device"] = (int)d->device;
				e["index"] = (int)d->index;
				e["id"] = (int)d->id;
				e["desc"] = String::utf8(d->description);
				input_descriptors.push_back(e);
			}
			return true;
		}
		case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: {
			// Declarar 2 é o que faz um core moderno mandar SET_CORE_OPTIONS_V2
			// em vez de decair para o formato de 2012.
			*reinterpret_cast<unsigned *>(data) = 2;
			return true;
		}
		case RETRO_ENVIRONMENT_SET_VARIABLES: {
			parse_variables(reinterpret_cast<const retro_variable *>(data));
			return true;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
			parse_options_v1(reinterpret_cast<const retro_core_option_definition *>(data));
			return true;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
			// Só o inglês: `local` seria a tradução, e não traduzimos a UI do core.
			auto *intl = reinterpret_cast<const retro_core_options_intl *>(data);
			parse_options_v1(intl ? intl->us : nullptr);
			return true;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
			auto *v2 = reinterpret_cast<const retro_core_options_v2 *>(data);
			parse_options_v2(v2 ? v2->definitions : nullptr);
			// Devolver true diria "eu mostro categorias"; não mostramos, e o core
			// só usa isso para escolher o rótulo, então false é o honesto.
			return false;
		}
		case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
			auto *intl = reinterpret_cast<const retro_core_options_v2_intl *>(data);
			parse_options_v2(intl && intl->us ? intl->us->definitions : nullptr);
			return false;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE: {
			auto *var = reinterpret_cast<retro_variable *>(data);
			if (!var || !var->key) {
				return false;
			}
			const CoreOption *o = find_option(String::utf8(var->key));
			if (!o) {
				// nullptr é como a API diz "não tenho essa opção"; o core usa o
				// default interno dele.
				var->value = nullptr;
				return false;
			}
			var->value = o->value_utf8.get_data();
			return true;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
			*reinterpret_cast<bool *>(data) = options_dirty;
			// Consultar zera: o core relê tudo agora, e só uma mudança nova
			// justifica pedir que releia de novo.
			options_dirty = false;
			return true;
		}
		default:
			return false;
	}
}
