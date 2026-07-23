extends Node3D
## Fase 1/2 — cena VR (Meta Quest 3S via OpenXR).
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
##   grips                       -> Start (dir.) / Select (esq.)
##   botão de menu (toque)       -> Start ; (segurar 0,5 s) -> abre o menu
##   thumbstick direito  Y       -> aumenta/diminui a tela
##   thumbstick direito  X       -> aproxima/afasta a tela
##
## Tamanho, distância, vídeo, áudio e zona morta vivem no ConfigEmu e
## persistem entre sessões; esta cena só reage a `mudou`.

# Core por plataforma: o binário aarch64 no Quest, o x86_64 no desktop.
const CORE_ANDROID := "res://cores/snes9x_libretro_android.so"
const CORE_DESKTOP := "res://cores/snes9x_libretro.so"
# ROM demo embutida (homebrew freeware). Vazio => exige -- --rom no desktop.
const ROM_PADRAO := "res://roms/demo.smc"

const LARGURA_BASE := 1.4       # metros, largura da tela em escala 1.0

## Quanto segurar o botão de menu para abrir o painel. Toque mais curto que
## isto continua valendo como Start — todos os outros botões já estão no SNES,
## e o botão de sistema do controle direito é reservado pelo Quest.
const MENU_SEGURAR := 0.5
## Frames em que Start fica pressionado no toque curto. Um só às vezes cai
## entre polls do core e o jogo não vê.
const START_PULSO := 3

## Curvatura máxima, em graus de arco, quando tela/curvatura = 1.0.
const ARCO_MAX := 60.0
const ARCO_SEGMENTOS := 24

## Teto de frames emulados por frame renderizado. Impede a espiral da morte:
## se emular ficar mais caro que o tempo real, o acumulador cresceria sem fim.
const MAX_PASSOS := 4


func _core_padrao() -> String:
	return CORE_ANDROID if OS.has_feature("android") else CORE_DESKTOP


var _cfg: ConfigEmu
var _emu: EmuCore
var _painel: PainelMenu

var _origin: XROrigin3D
var _camera: XRCamera3D
var _ctrl_esq: XRController3D
var _ctrl_dir: XRController3D
var _tela: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label3D

var _xr_ativo := false
var _aspecto_nativo := 4.0 / 3.0
var _dpad_ativo := false        # estado da histerese do dead zone

var _menu_antes := false
var _menu_desde := 0.0
var _menu_consumido := false
var _start_restante := 0

var _acumulador := 0.0          # sobra de tempo entre frames emulados
var _diag_ligado := false
var _diag_t := 0.0
var _diag_passos := 0


func _ready() -> void:
	_diag_ligado = "--diag" in OS.get_cmdline_user_args()

	_cfg = ConfigEmu.new()
	add_child(_cfg)

	_montar_cena()
	_iniciar_xr()

	_emu = EmuCore.new()
	add_child(_emu)
	_emu.falhou.connect(func(msg: String) -> void: _mostrar(msg))
	_emu.iniciado.connect(func(w: int, h: int, _fps: float) -> void:
		_aspecto_nativo = float(w) / float(h) if h > 0 else 4.0 / 3.0
		_aplicar_tela()
		_mostrar("")
	)

	_painel = PainelMenu.new(_cfg, _emu)
	add_child(_painel)
	_painel.conectar_xr(_camera, _ctrl_dir if _xr_ativo else null)
	_painel.fechar_pedido.connect(func() -> void: _painel.fechar())
	_painel.rom_escolhida.connect(_trocar_rom)

	_cfg.mudou.connect(_ao_mudar_config)

	# O diálogo do Android é assíncrono; pedir cedo dá tempo de a pessoa
	# responder antes de abrir a página de ROMs.
	if NavegadorRoms.precisa_permissao() and not NavegadorRoms.tem_permissao():
		NavegadorRoms.pedir_permissao()

	var ok := _emu.iniciar(_arg("--core", _core_padrao()), _arg("--rom", ROM_PADRAO))
	if not ok:
		_mostrar("Sem ROM. Segure o botão de menu para escolher uma.")

	_aplicar_tudo()


func _process(delta: float) -> void:
	_ler_input_vr(delta)
	_avancar_emulacao(delta)
	_atualizar_tela()
	_diagnostico(delta)


## Avança a emulação no ritmo do core, não no do display.
##
## O Quest renderiza a 72 Hz e o SNES roda a 60,1 fps. Chamar step() uma vez por
## frame renderizado fazia o jogo correr 1,2x rápido e o core gerar 1,2x mais
## áudio do que o AudioStreamGenerator consome — o excedente era descartado em
## _bombear_audio(), ~16% das amostras por segundo, que é o som picotado.
func _avancar_emulacao(delta: float) -> void:
	var fps := _emu.get_fps()
	if fps <= 0.0:
		return
	var passo := 1.0 / fps
	_acumulador += delta

	var passos := 0
	while _acumulador >= passo and passos < MAX_PASSOS:
		_emu.step()
		_acumulador -= passo
		passos += 1
		_diag_passos += 1

	# Se travou tempo demais (carregar ROM, app suspenso), não tenta recuperar o
	# atraso: acelerar o jogo para "alcançar" é pior que perder o tempo perdido.
	if passos == MAX_PASSOS:
		_acumulador = 0.0


## Liga com `-- --diag`. Mostra se a emulação está no ritmo do core: passos/s
## deve bater com o fps do core, e descartado deve ficar em zero.
func _diagnostico(delta: float) -> void:
	if not _diag_ligado:
		return
	_diag_t += delta
	if _diag_t < 1.0:
		return
	print("DIAG render=%.1f fps | passos do emu=%d/s (core pede %.1f) | audio gerado=%d descartado=%d" % [
		Engine.get_frames_per_second(), _diag_passos, _emu.get_fps(),
		_emu.diag_audio_gerado, _emu.diag_audio_descartado])
	_diag_t = 0.0
	_diag_passos = 0
	_emu.diag_audio_gerado = 0
	_emu.diag_audio_descartado = 0


func _unhandled_input(evento: InputEvent) -> void:
	if _xr_ativo:
		return
	# Atalhos de desktop: iterar a UI sem build + sideload a cada mudança.
	if evento is InputEventKey and evento.pressed and not evento.echo:
		if evento.keycode == KEY_TAB:
			_painel.alternar()
			get_viewport().set_input_as_handled()
			return
	if evento is InputEventMouse:
		_painel.entrada_desktop(evento)


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

	# A "tela": malha unshaded com o framebuffer do emulador.
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tela = MeshInstance3D.new()
	add_child(_tela)

	_label = Label3D.new()
	_label.pixel_size = 0.002
	_label.modulate = Color.WHITE
	_label.outline_size = 12
	_tela.add_child(_label)
	_label.position = Vector3(0, -0.7, 0.01)


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
		print("XR: OpenXR indisponível — fallback de câmera plana (Tab abre o menu)")


# ---------------------------------------------------------------------------
# Configuração -> cena
# ---------------------------------------------------------------------------
func _ao_mudar_config(chave: String, _valor: Variant) -> void:
	if chave.begins_with("tela/") or chave == "video/aspecto":
		_aplicar_tela()
	elif chave.begins_with("video/"):
		_aplicar_video()
	elif chave.begins_with("audio/"):
		_aplicar_audio()


func _aplicar_tudo() -> void:
	_aplicar_tela()
	_aplicar_video()
	_aplicar_audio()


func _aplicar_tela() -> void:
	var razao := _cfg.aspecto_como_razao(_aspecto_nativo)
	var curvatura: float = _cfg.obter("tela/curvatura")
	_tela.mesh = _construir_mesh_tela(LARGURA_BASE, LARGURA_BASE / razao, curvatura)
	_tela.mesh.surface_set_material(0, _mat)
	_tela.scale = Vector3.ONE * _cfg.obter("tela/escala")
	_posicionar_tela()


func _aplicar_video() -> void:
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR \
			if _cfg.obter("video/filtro_suave") else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Unshaded multiplica a textura pelo albedo, então isto vira brilho.
	var b: float = _cfg.obter("video/brilho")
	_mat.albedo_color = Color(b, b, b)


func _aplicar_audio() -> void:
	_emu.aplicar_audio(_cfg.obter("audio/volume"), _cfg.obter("audio/mudo"))


# ---------------------------------------------------------------------------
# Tela: malha, posição
# ---------------------------------------------------------------------------
## Plano quando curvatura = 0; senão, um arco cilíndrico cujas bordas vêm em
## direção ao jogador. Comprimento do arco = largura, para o tamanho aparente
## não mudar ao curvar.
func _construir_mesh_tela(largura: float, altura: float, curvatura: float) -> Mesh:
	if curvatura < 0.01:
		var quad := QuadMesh.new()
		quad.size = Vector2(largura, altura)
		return quad

	var arco := deg_to_rad(ARCO_MAX) * curvatura
	var raio := largura / arco
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in ARCO_SEGMENTOS:
		for canto in [[i, 0], [i, 1], [i + 1, 1], [i, 0], [i + 1, 1], [i + 1, 0]]:
			var t := float(canto[0]) / float(ARCO_SEGMENTOS)
			var a := -arco * 0.5 + arco * t
			var y := (0.5 - float(canto[1])) * altura
			st.set_uv(Vector2(t, float(canto[1])))
			st.add_vertex(Vector3(raio * sin(a), y, raio * (1.0 - cos(a))))

	st.generate_normals()
	return st.commit()


func _posicionar_tela() -> void:
	var altura_olhos := _camera.global_position.y if _xr_ativo else 1.4
	_tela.global_position = Vector3(
		0.0,
		altura_olhos + _cfg.obter("tela/altura"),
		-_cfg.obter("tela/distancia"))


func _atualizar_tela() -> void:
	if _emu.texture != null and _mat.albedo_texture != _emu.texture:
		_mat.albedo_texture = _emu.texture
	_posicionar_tela()


func _mostrar(msg: String) -> void:
	if _label != null:
		_label.text = msg
		_label.visible = not msg.is_empty()


func _trocar_rom(caminho: String) -> void:
	if _emu.trocar_rom(caminho):
		_cfg.registrar_recente(caminho)
		_painel.fechar()
		_mostrar("")


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _ler_input_vr(delta: float) -> void:
	if _emu == null:
		return

	if not _xr_ativo:
		_input_teclado()
		return

	# O toggle do menu é lido sempre, inclusive com o painel aberto — é o que
	# fecha o painel.
	_ler_toggle_menu(delta)

	if _painel.esta_aberto():
		# Com o menu aberto o gatilho direito é clique, não R: congela o jogo.
		_emu.limpar_input()
		return

	# D-pad no thumbstick esquerdo, via setores angulares (preciso pra SNES)
	var dpad := _dpad_do_stick(_ctrl_esq.get_vector2(&"primary"))
	_emu.set_button(0, LibretroHost.JOYPAD_LEFT, dpad.left)
	_emu.set_button(0, LibretroHost.JOYPAD_RIGHT, dpad.right)
	_emu.set_button(0, LibretroHost.JOYPAD_UP, dpad.up)
	_emu.set_button(0, LibretroHost.JOYPAD_DOWN, dpad.down)

	_emu.set_button(0, LibretroHost.JOYPAD_A, _ctrl_dir.is_button_pressed(&"ax_button"))
	_emu.set_button(0, LibretroHost.JOYPAD_B, _ctrl_dir.is_button_pressed(&"by_button"))
	_emu.set_button(0, LibretroHost.JOYPAD_X, _ctrl_esq.is_button_pressed(&"ax_button"))
	_emu.set_button(0, LibretroHost.JOYPAD_Y, _ctrl_esq.is_button_pressed(&"by_button"))
	_emu.set_button(0, LibretroHost.JOYPAD_L, _ctrl_esq.get_float(&"trigger") > 0.5)
	_emu.set_button(0, LibretroHost.JOYPAD_R, _ctrl_dir.get_float(&"trigger") > 0.5)
	# Start/Select nos grips (aperto lateral): livres e disponíveis nos dois
	# controles. O botão de sistema do controle direito é reservado pelo Quest
	# e nunca chega ao app.
	var start := _ctrl_dir.get_float(&"grip") > 0.5
	if _start_restante > 0:
		start = true
		_start_restante -= 1
	_emu.set_button(0, LibretroHost.JOYPAD_START, start)
	_emu.set_button(0, LibretroHost.JOYPAD_SELECT, _ctrl_esq.get_float(&"grip") > 0.5)

	# Redimensionar/reposicionar com o thumbstick direito
	var rstick := _ctrl_dir.get_vector2(&"primary")
	if absf(rstick.y) > 0.15:
		_cfg.definir("tela/escala", clampf(
			_cfg.obter("tela/escala") + rstick.y * 0.03,
			PagTela.ESCALA_MIN, PagTela.ESCALA_MAX))
	if absf(rstick.x) > 0.15:
		_cfg.definir("tela/distancia", clampf(
			_cfg.obter("tela/distancia") - rstick.x * 0.03,
			PagTela.DIST_MIN, PagTela.DIST_MAX))


## Toque curto no botão de menu = Start; segurar = abre/fecha o painel.
func _ler_toggle_menu(delta: float) -> void:
	var agora := _ctrl_esq.is_button_pressed(&"menu_button")

	if agora:
		if not _menu_antes:
			_menu_desde = 0.0
			_menu_consumido = false
		else:
			_menu_desde += delta
			if not _menu_consumido and _menu_desde >= MENU_SEGURAR:
				_painel.alternar()
				_menu_consumido = true
	elif _menu_antes and not _menu_consumido:
		# Soltou antes do tempo: vale como Start.
		_start_restante = START_PULSO

	_menu_antes = agora


func _input_teclado() -> void:
	if _painel.esta_aberto():
		_emu.limpar_input()
		return
	_emu.set_button(0, LibretroHost.JOYPAD_LEFT, Input.is_key_pressed(KEY_LEFT))
	_emu.set_button(0, LibretroHost.JOYPAD_RIGHT, Input.is_key_pressed(KEY_RIGHT))
	_emu.set_button(0, LibretroHost.JOYPAD_UP, Input.is_key_pressed(KEY_UP))
	_emu.set_button(0, LibretroHost.JOYPAD_DOWN, Input.is_key_pressed(KEY_DOWN))
	_emu.set_button(0, LibretroHost.JOYPAD_A, Input.is_key_pressed(KEY_X))
	_emu.set_button(0, LibretroHost.JOYPAD_B, Input.is_key_pressed(KEY_Z))
	_emu.set_button(0, LibretroHost.JOYPAD_START, Input.is_key_pressed(KEY_ENTER))
	_emu.set_button(0, LibretroHost.JOYPAD_SELECT, Input.is_key_pressed(KEY_SHIFT))


# Converte o vetor do analógico em 4 booleanos de D-pad usando setores
# angulares com dead zone radial + histerese. Garante no máximo 2 direções
# adjacentes (uma diagonal), nunca opostas nem três ao mesmo tempo.
func _dpad_do_stick(v: Vector2) -> Dictionary:
	var r := {"up": false, "down": false, "left": false, "right": false}
	var mag := v.length()
	# Histerese: engaja num limiar alto, só solta num limiar baixo.
	if _dpad_ativo:
		if mag < _cfg.obter("input/dpad_solta"):
			_dpad_ativo = false
	elif mag >= _cfg.obter("input/dpad_engaja"):
		_dpad_ativo = true
	if not _dpad_ativo:
		return r
	# Ângulo do stick: direita=0°, cima=90°, esquerda=180°, baixo=-90°.
	var meia: float = _cfg.obter("input/dpad_meia_cardeal")
	var deg := rad_to_deg(atan2(v.y, v.x))
	r.right = absf(_dif_ang(deg, 0.0)) <= meia
	r.up = absf(_dif_ang(deg, 90.0)) <= meia
	r.left = absf(_dif_ang(deg, 180.0)) <= meia
	r.down = absf(_dif_ang(deg, -90.0)) <= meia
	return r


# Menor diferença angular (em graus) entre a e b, no intervalo [-180, 180].
func _dif_ang(a: float, b: float) -> float:
	return wrapf(a - b, -180.0, 180.0)


func _arg(nome: String, padrao: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == nome:
			return args[i + 1]
	return padrao
