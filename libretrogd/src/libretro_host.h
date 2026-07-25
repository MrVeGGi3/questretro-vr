#ifndef LIBRETROGD_HOST_H
#define LIBRETROGD_HOST_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
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

	// Tipos de controle RETRO_DEVICE_*. ANALOG é um superconjunto de JOYPAD:
	// além dos eixos, o core continua lendo os botões pela mesma porta.
	enum Device {
		DEVICE_JOYPAD = 1,
		DEVICE_ANALOG = 5,
	};

	// Qual manche (RETRO_DEVICE_INDEX_ANALOG_*). O N64 só tem o esquerdo; o
	// direito existe para cores de console com dois.
	enum AnalogIndex {
		ANALOG_LEFT = 0,
		ANALOG_RIGHT = 1,
	};

	// Eixo dentro do manche. Convenção do libretro: X cresce para a direita e
	// **Y cresce para baixo** — o oposto do Vector2 do thumbstick no Godot.
	enum AnalogAxis {
		ANALOG_X = 0,
		ANALOG_Y = 1,
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
	// Eixo analógico (RETRO_DEVICE_ANALOG). `valor` em [-1,1]; ver AnalogAxis
	// para o sentido do Y.
	void set_analog(int p_port, int p_index, int p_axis, double p_value);
	// Anuncia ao core que tipo de controle está ligado na porta. O N64 precisa
	// de DEVICE_ANALOG; o SNES fica em DEVICE_JOYPAD.
	void set_controller_device(int p_port, int p_device);
	void clear_input();

	// Opções do core. Ficam disponíveis logo após load_core() — o core as
	// declara de dentro de retro_set_environment —, então dá para ajustá-las
	// antes do load_rom(), que é quando várias delas passam a valer.
	// get_options() devolve um Array de Dictionary com chave/desc/info/valores.
	Array get_options() const;
	String get_option(const String &p_key) const;
	void set_option(const String &p_key, const String &p_value);

	// O mapa de controle que o core declarou (SET_INPUT_DESCRIPTORS): para cada
	// entrada, que botão do console é aquele id do joypad libretro. É a fonte
	// da verdade para montar o mapa do Touch e para a página de Input — o
	// mesmo JOYPAD_L2 é "Z" no N64 e não existe no SNES.
	// Array de Dictionary: port, device, index, id, desc.
	Array get_input_descriptors() const;

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

	// --- opções do core ---
	// Uma opção como o core a declarou, mais o valor vigente. O valor é mantido
	// também como CharString porque GET_VARIABLE devolve um `const char *` que o
	// core lê *depois* de a chamada retornar: precisa apontar para um buffer que
	// sobreviva a nós. Trocar o valor invalida o ponteiro antigo, e é por isso
	// que set_option() marca options_dirty — o core então reconsulta tudo.
	struct CoreOption {
		String key;
		String desc;
		String info;
		PackedStringArray values;  // ids aceitos, na ordem em que o core declarou
		PackedStringArray labels;  // rótulo legível de cada id (cai no id se não houver)
		String default_value;
		String value;
		CharString value_utf8;
	};

	CoreOption *find_option(const String &p_key);
	const CoreOption *find_option(const String &p_key) const;
	// Registra (ou atualiza) uma opção preservando o valor já escolhido.
	void register_option(const String &p_key, const String &p_desc, const String &p_info,
			const PackedStringArray &p_values, const PackedStringArray &p_labels,
			const String &p_default);
	// Um parser por formato: SET_VARIABLES (16), SET_CORE_OPTIONS (53) e
	// SET_CORE_OPTIONS_V2 (67). Cores modernos mandam só o mais novo que o
	// frontend declarar suportar, mas os três chegam na prática.
	void parse_variables(const struct retro_variable *p_vars);
	void parse_options_v1(const struct retro_core_option_definition *p_defs);
	void parse_options_v2(const struct retro_core_option_v2_definition *p_defs);

	std::vector<CoreOption> options;
	bool options_dirty = false;

	// Mapa de controle declarado pelo core, já convertido para Variant.
	Array input_descriptors;

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
	void (*p_retro_set_controller_port_device)(unsigned, unsigned) = nullptr;
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
	// eixos analógicos: [porta][manche][eixo], já na escala do libretro
	int16_t analog_state[2][2][2] = {};

	// dados do jogo mantidos vivos enquanto o core roda (quando não é fullpath)
	std::vector<uint8_t> game_data;

	// diretórios de sistema/save entregues ao core
	String system_dir;
	String save_dir;
};

} // namespace godot

VARIANT_ENUM_CAST(godot::LibretroHost::Joypad);
VARIANT_ENUM_CAST(godot::LibretroHost::Memory);
VARIANT_ENUM_CAST(godot::LibretroHost::Device);
VARIANT_ENUM_CAST(godot::LibretroHost::AnalogIndex);
VARIANT_ENUM_CAST(godot::LibretroHost::AnalogAxis);

#endif // LIBRETROGD_HOST_H
