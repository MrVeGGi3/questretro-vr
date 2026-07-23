extends Node3D
## Fase 1 — cena VR (Meta Quest 3S via OpenXR).
##
## Exibe o framebuffer do emulador num quad 3D flutuante e redimensionável:
## de uma telinha portátil a uma tela de cinema. Se não houver runtime OpenXR
## (ex: rodando no PC sem headset), cai para uma câmera plana para ainda dar
## para testar a emulação e o posicionamento da tela.
##
## Controles (Meta Touch):
##   thumbstick esquerdo         -> D-pad
##   A / B (botões direitos)     -> A / B do SNES
##   X / Y (botões esquerdos)    -> X / Y do SNES
##   gatilhos L/R                -> L / R do SNES
##   menu                        -> Start ; botão-thumbstick esq. -> Select
##   thumbstick direito  Y       -> aumenta/diminui a tela
##   thumbstick direito  X       -> aproxima/afasta a tela

# Core por plataforma: o binário aarch64 no Quest, o x86_64 no desktop.
const CORE_ANDROID := "res://cores/snes9x_libretro_android.so"
const CORE_DESKTOP := "res://cores/snes9x_libretro.so"
# ROM demo embutida (homebrew freeware). Vazio => exige -- --rom no desktop.
const ROM_PADRAO := "res://roms/demo.smc"

func _core_padrao() -> String:
	return CORE_ANDROID if OS.has_feature("android") else CORE_DESKTOP

const LARGURA_BASE := 1.4       # metros, largura da tela em escala 1.0
const DIST_MIN := 0.8
const DIST_MAX := 8.0
const ESCALA_MIN := 0.3
const ESCALA_MAX := 8.0

var _emu: EmuCore
var _origin: XROrigin3D
var _camera: XRCamera3D
var _ctrl_esq: XRController3D
var _ctrl_dir: XRController3D
var _tela: MeshInstance3D
var _mat: StandardMaterial3D
var _quad: QuadMesh
var _label: Label3D

var _xr_ativo := false
var _escala := 1.5
var _distancia := 2.2
var _aspecto := 4.0 / 3.0


func _ready() -> void:
	_montar_cena()
	_iniciar_xr()

	_emu = EmuCore.new()
	add_child(_emu)
	_emu.falhou.connect(func(msg): _mostrar(msg))
	_emu.iniciado.connect(func(w, h, fps):
		_aspecto = float(w) / float(h) if h > 0 else 4.0 / 3.0
		_mostrar("")
	)
	var ok := _emu.iniciar(_arg("--core", _core_padrao()), _arg("--rom", ROM_PADRAO))
	if not ok:
		_mostrar("Sem ROM. Passe -- --rom /caminho/jogo.sfc")


func _process(_delta: float) -> void:
	_ler_input_vr()
	_emu.step()
	_atualizar_tela()


# ---------------------------------------------------------------------------
# Construção da cena
# ---------------------------------------------------------------------------
func _montar_cena() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.environment = e
	add_child(env)

	_origin = XROrigin3D.new()
	add_child(_origin)

	_camera = XRCamera3D.new()
	_origin.add_child(_camera)

	_ctrl_esq = XRController3D.new()
	_ctrl_esq.tracker = &"left_hand"
	_origin.add_child(_ctrl_esq)

	_ctrl_dir = XRController3D.new()
	_ctrl_dir.tracker = &"right_hand"
	_origin.add_child(_ctrl_dir)

	# A "tela": quad unshaded com o framebuffer do emulador.
	_quad = QuadMesh.new()
	_quad.size = Vector2(LARGURA_BASE, LARGURA_BASE / _aspecto)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad.material = _mat
	_tela = MeshInstance3D.new()
	_tela.mesh = _quad
	add_child(_tela)

	_label = Label3D.new()
	_label.pixel_size = 0.002
	_label.modulate = Color.WHITE
	_label.outline_size = 12
	_tela.add_child(_label)
	_label.position = Vector3(0, -0.7, 0.01)

	_posicionar_tela()


func _iniciar_xr() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		get_viewport().use_xr = true
		_xr_ativo = true
		print("XR: OpenXR inicializado — modo VR")
	else:
		# Fallback plano: uma câmera comum para rodar no desktop sem headset.
		_xr_ativo = false
		var flat := Camera3D.new()
		flat.position = Vector3(0, 0, 0)
		add_child(flat)
		flat.make_current()
		print("XR: OpenXR indisponível — fallback de câmera plana")


# ---------------------------------------------------------------------------
# Tela: posição e tamanho
# ---------------------------------------------------------------------------
func _posicionar_tela() -> void:
	var altura_cabeca := _camera.global_position.y if _xr_ativo else 1.4
	_tela.global_position = Vector3(0, altura_cabeca, -_distancia)
	_quad.size = Vector2(LARGURA_BASE, LARGURA_BASE / _aspecto)
	_tela.scale = Vector3(_escala, _escala, 1.0)


func _atualizar_tela() -> void:
	if _emu.texture != null:
		_mat.albedo_texture = _emu.texture
	_posicionar_tela()


func _mostrar(msg: String) -> void:
	if _label != null:
		_label.text = msg
		_label.visible = not msg.is_empty()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _ler_input_vr() -> void:
	if _emu == null:
		return

	if _xr_ativo:
		# D-pad no thumbstick esquerdo
		var lstick := _ctrl_esq.get_vector2(&"primary")
		_emu.set_button(0, LibretroHost.JOYPAD_LEFT, lstick.x < -0.4)
		_emu.set_button(0, LibretroHost.JOYPAD_RIGHT, lstick.x > 0.4)
		_emu.set_button(0, LibretroHost.JOYPAD_UP, lstick.y > 0.4)
		_emu.set_button(0, LibretroHost.JOYPAD_DOWN, lstick.y < -0.4)

		_emu.set_button(0, LibretroHost.JOYPAD_A, _ctrl_dir.is_button_pressed(&"ax_button"))
		_emu.set_button(0, LibretroHost.JOYPAD_B, _ctrl_dir.is_button_pressed(&"by_button"))
		_emu.set_button(0, LibretroHost.JOYPAD_X, _ctrl_esq.is_button_pressed(&"ax_button"))
		_emu.set_button(0, LibretroHost.JOYPAD_Y, _ctrl_esq.is_button_pressed(&"by_button"))
		_emu.set_button(0, LibretroHost.JOYPAD_L, _ctrl_esq.get_float(&"trigger") > 0.5)
		_emu.set_button(0, LibretroHost.JOYPAD_R, _ctrl_dir.get_float(&"trigger") > 0.5)
		# Start/Select nos grips (aperto lateral): livres e disponíveis nos dois
		# controles. O botão de sistema do controle direito é reservado pelo Quest
		# e nunca chega ao app; só o menu (menu_button) do esquerdo funciona, e o
		# mantemos como atalho alternativo para Start.
		var start := _ctrl_dir.get_float(&"grip") > 0.5 or _ctrl_esq.is_button_pressed(&"menu_button")
		_emu.set_button(0, LibretroHost.JOYPAD_START, start)
		_emu.set_button(0, LibretroHost.JOYPAD_SELECT, _ctrl_esq.get_float(&"grip") > 0.5)

		# Redimensionar/reposicionar com o thumbstick direito
		var rstick := _ctrl_dir.get_vector2(&"primary")
		if absf(rstick.y) > 0.15:
			_escala = clampf(_escala + rstick.y * 0.03, ESCALA_MIN, ESCALA_MAX)
		if absf(rstick.x) > 0.15:
			_distancia = clampf(_distancia - rstick.x * 0.03, DIST_MIN, DIST_MAX)
	else:
		# Fallback teclado no desktop
		_emu.set_button(0, LibretroHost.JOYPAD_LEFT, Input.is_key_pressed(KEY_LEFT))
		_emu.set_button(0, LibretroHost.JOYPAD_RIGHT, Input.is_key_pressed(KEY_RIGHT))
		_emu.set_button(0, LibretroHost.JOYPAD_UP, Input.is_key_pressed(KEY_UP))
		_emu.set_button(0, LibretroHost.JOYPAD_DOWN, Input.is_key_pressed(KEY_DOWN))
		_emu.set_button(0, LibretroHost.JOYPAD_A, Input.is_key_pressed(KEY_X))
		_emu.set_button(0, LibretroHost.JOYPAD_B, Input.is_key_pressed(KEY_Z))
		_emu.set_button(0, LibretroHost.JOYPAD_START, Input.is_key_pressed(KEY_ENTER))
		_emu.set_button(0, LibretroHost.JOYPAD_SELECT, Input.is_key_pressed(KEY_SHIFT))
		if Input.is_key_pressed(KEY_EQUAL):
			_escala = clampf(_escala + 0.05, ESCALA_MIN, ESCALA_MAX)
		if Input.is_key_pressed(KEY_MINUS):
			_escala = clampf(_escala - 0.05, ESCALA_MIN, ESCALA_MAX)


func _arg(nome: String, padrao: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == nome:
			return args[i + 1]
	return padrao
