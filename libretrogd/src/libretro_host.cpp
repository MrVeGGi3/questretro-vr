#include "libretro_host.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
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
	ClassDB::bind_method(D_METHOD("get_fps"), &LibretroHost::get_fps);
	ClassDB::bind_method(D_METHOD("get_sample_rate"), &LibretroHost::get_sample_rate);
	ClassDB::bind_method(D_METHOD("get_audio"), &LibretroHost::get_audio);
	ClassDB::bind_method(D_METHOD("set_button", "port", "id", "pressed"), &LibretroHost::set_button);
	ClassDB::bind_method(D_METHOD("clear_input"), &LibretroHost::clear_input);
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
	if (!field) { UtilityFunctions::push_error(String("libretrogd: símbolo ausente: ") + name); }

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
		UtilityFunctions::push_warning("libretrogd: memória " + itos(p_id) +
				" tem tamanho mas não tem ponteiro");
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
		UtilityFunctions::push_warning(String("libretrogd: memória ") + itos(p_id) +
				" tem " + itos(tam) + " bytes, mas os dados têm " + itos(p_data.size()) +
				" — ignorando");
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
		UtilityFunctions::push_error("libretrogd: core não expõe a API libretro esperada");
		unload();
		return false;
	}

	g_active_host = this;

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
			UtilityFunctions::push_error(String("libretrogd: não abriu a ROM: ") + p_path);
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

	game_loaded = true;
	UtilityFunctions::print(String("libretrogd: ROM carregada — ") +
			String::num_int64((int64_t)av.geometry.base_width) + "x" +
			String::num_int64((int64_t)av.geometry.base_height) + " @ " +
			String::num(av_fps, 2) + "fps");
	return true;
}

void LibretroHost::run_frame() {
	if (game_loaded && p_retro_run) {
		p_retro_run();
	}
}

void LibretroHost::unload_rom() {
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
	if (game_loaded && p_retro_unload_game) {
		p_retro_unload_game();
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
	input_state[0] = input_state[1] = 0;
	game_data.clear();
}

// ---------------------------------------------------------------------------
// Vídeo
// ---------------------------------------------------------------------------
void LibretroHost::_on_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
	// data == NULL sinaliza frame duplicado; mantém o buffer anterior.
	if (data == nullptr || width == 0 || height == 0) {
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
	(void)index;
	if (device != RETRO_DEVICE_JOYPAD || port >= 2 || id > 15) {
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

void LibretroHost::clear_input() {
	input_state[0] = input_state[1] = 0;
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
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
			static CharString sd = globalize(system_dir).utf8();
			*reinterpret_cast<const char **>(data) = sd.get_data();
			return true;
		}
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
			static CharString sv = globalize(save_dir).utf8();
			*reinterpret_cast<const char **>(data) = sv.get_data();
			return true;
		}
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
			auto *cb = reinterpret_cast<retro_log_callback *>(data);
			cb->log = cb_log;
			return true;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE: {
			// Sem opções customizadas no MVP: o core usa os defaults.
			auto *var = reinterpret_cast<retro_variable *>(data);
			var->value = nullptr;
			return false;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
			*reinterpret_cast<bool *>(data) = false;
			return true;
		}
		default:
			return false;
	}
}
