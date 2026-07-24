#ifndef LIBRETROGD_HOST_H
#define LIBRETROGD_HOST_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <vector>

#include "libretro.h"

namespace godot {

// LibretroHost carrega um core libretro (.so/.dll) via dlopen e roda a
// emulação frame a frame. Um core ativo por vez: os callbacks C do libretro
// não têm user-data, então usamos um ponteiro estático para a instância viva.
//
// Uso a partir do GDScript:
//   host.load_core("res://cores/snes9x_libretro.so")
//   host.load_rom("/caminho/jogo.sfc")
//   # a cada frame:
//   host.set_button(0, LibretroHost.JOYPAD_A, true)
//   host.run_frame()
//   texture.update(host.get_frame())      # Ref<Image> RGBA8
//   # áudio: puxar host.get_audio() para um AudioStreamGenerator
class LibretroHost : public RefCounted {
	GDCLASS(LibretroHost, RefCounted)

public:
	// IDs de botão RETRO_DEVICE_ID_JOYPAD_* reexpostos como constantes do Godot.
	enum Joypad {
		JOYPAD_B = 0, JOYPAD_Y = 1, JOYPAD_SELECT = 2, JOYPAD_START = 3,
		JOYPAD_UP = 4, JOYPAD_DOWN = 5, JOYPAD_LEFT = 6, JOYPAD_RIGHT = 7,
		JOYPAD_A = 8, JOYPAD_X = 9, JOYPAD_L = 10, JOYPAD_R = 11,
		JOYPAD_L2 = 12, JOYPAD_R2 = 13, JOYPAD_L3 = 14, JOYPAD_R3 = 15,
	};

	// Regiões de memória RETRO_MEMORY_* reexpostas como constantes do Godot.
	// SAVE_RAM é a bateria do cartucho; RTC é o relógio de jogos que têm um.
	enum Memory {
		MEMORY_SAVE_RAM = 0,
		MEMORY_RTC = 1,
	};

protected:
	static void _bind_methods();

public:
	LibretroHost();
	~LibretroHost();

	bool load_core(const String &p_path);
	bool load_rom(const String &p_path);
	// Descarrega só o jogo, mantendo o core vivo — é o que troca de ROM sem
	// pagar o dlopen de novo.
	void unload_rom();
	void unload();

	// Save states. O core pode não implementar (retro_serialize* são opcionais
	// na API libretro), daí supports_state() antes de oferecer os slots na UI.
	bool supports_state() const;
	PackedByteArray save_state();
	bool load_state(const PackedByteArray &p_data);

	// Memória do core (SRAM de bateria, RTC). Diferente do save state: é o que o
	// jogo grava sozinho quando você salva *dentro* dele, e o frontend é quem
	// persiste em disco — o core nunca escreve o .srm por conta própria.
	// Tamanho 0 significa "este jogo não usa esta região".
	int get_memory_size(int p_id) const;
	PackedByteArray get_memory(int p_id) const;
	bool set_memory(int p_id, const PackedByteArray &p_data);

	void run_frame();

	// Vídeo: última imagem emulada convertida para RGBA8.
	Ref<Image> get_frame() const;
	int get_frame_width() const { return frame_width; }
	int get_frame_height() const { return frame_height; }
	double get_fps() const { return av_fps; }
	double get_sample_rate() const { return av_sample_rate; }

	// Áudio: consome e zera o buffer acumulado desde a última chamada.
	// Retorna pares (L,R) em [-1,1] como PackedVector2Array.
	PackedVector2Array get_audio();

	// Input: estado por porta/botão (RETRO_DEVICE_JOYPAD).
	void set_button(int p_port, int p_id, bool p_pressed);
	void clear_input();

	bool is_core_loaded() const { return core_loaded; }
	bool is_game_loaded() const { return game_loaded; }

	// --- chamados pelos callbacks C estáticos do libretro ---
	void _on_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch);
	void _on_audio_batch(const int16_t *data, size_t frames);
	int16_t _on_input_state(unsigned port, unsigned device, unsigned index, unsigned id);
	bool _on_environment(unsigned cmd, void *data);

private:
	void resolve_symbols();
	void reset_state();

	// handle do dlopen
	void *lib_handle = nullptr;
	bool core_loaded = false;
	bool game_loaded = false;

	// ponteiros para a API retro_* do core
	void (*p_retro_init)() = nullptr;
	void (*p_retro_deinit)() = nullptr;
	void (*p_retro_run)() = nullptr;
	bool (*p_retro_load_game)(const struct retro_game_info *) = nullptr;
	void (*p_retro_unload_game)() = nullptr;
	void (*p_retro_get_system_info)(struct retro_system_info *) = nullptr;
	void (*p_retro_get_system_av_info)(struct retro_system_av_info *) = nullptr;
	void (*p_retro_set_environment)(retro_environment_t) = nullptr;
	void (*p_retro_set_video_refresh)(retro_video_refresh_t) = nullptr;
	void (*p_retro_set_audio_sample)(retro_audio_sample_t) = nullptr;
	void (*p_retro_set_audio_sample_batch)(retro_audio_sample_batch_t) = nullptr;
	void (*p_retro_set_input_poll)(retro_input_poll_t) = nullptr;
	void (*p_retro_set_input_state)(retro_input_state_t) = nullptr;
	// opcionais: nem todo core serializa estado
	size_t (*p_retro_serialize_size)() = nullptr;
	bool (*p_retro_serialize)(void *, size_t) = nullptr;
	bool (*p_retro_unserialize)(const void *, size_t) = nullptr;
	// opcionais: nem todo core expõe memória (e nem todo jogo tem bateria)
	void *(*p_retro_get_memory_data)(unsigned) = nullptr;
	size_t (*p_retro_get_memory_size)(unsigned) = nullptr;

	// info do core
	bool need_fullpath = false;
	unsigned pixel_format = RETRO_PIXEL_FORMAT_0RGB1555; // default do libretro

	// buffers de vídeo (RGBA8) e áudio
	std::vector<uint8_t> frame_rgba;
	int frame_width = 0;
	int frame_height = 0;
	double av_fps = 60.0;
	double av_sample_rate = 32040.0;

	std::vector<float> audio_accum; // pares L,R intercalados

	// estado de input: bitmask por porta (até 2 portas no MVP)
	uint32_t input_state[2] = { 0, 0 };

	// dados do jogo mantidos vivos enquanto o core roda (quando não é fullpath)
	std::vector<uint8_t> game_data;

	// diretórios de sistema/save entregues ao core
	String system_dir;
	String save_dir;
};

} // namespace godot

VARIANT_ENUM_CAST(godot::LibretroHost::Joypad);
VARIANT_ENUM_CAST(godot::LibretroHost::Memory);

#endif // LIBRETROGD_HOST_H
