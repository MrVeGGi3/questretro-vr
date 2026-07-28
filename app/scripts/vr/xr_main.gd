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
## Tamanho, distância, sala, vídeo, áudio e zona morta vivem no ConfigEmu e
## persistem entre sessões; esta cena só reage a `mudou`.
##
## O ambiente em volta da tela é da `Sala` (`vr/sala.gd`), que roda sem XR. O
## que fica aqui é só a negociação de passthrough com o OpenXR.

# ROM demo embutida (homebrew freeware). Vazio => exige -- --rom no desktop.
# O core sai da extensão da ROM (EmuCore.core_para_rom), não daqui.
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


var _cfg: ConfigEmu
var _emu: EmuCore
var _painel: PainelMenu
var _sala: Sala

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

var _guidao := Guidao.new()
var _recentrar_antes := false   # borda do clique do thumbstick esquerdo
var _painel_antes := false      # para recentrar quando o painel fecha

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

	# Não pedimos a permissão no arranque: MANAGE_EXTERNAL_STORAGE não tem
	# diálogo de runtime, e pedi-la aqui jogaria a pessoa para os Ajustes do
	# Android antes mesmo de o jogo aparecer. Quem pede é o botão da página de
	# ROMs, quando ela de fato quer procurar um jogo.
	NavegadorRoms.garantir_pasta_local()

	var ok := _emu.iniciar(_arg("--core", ""), _arg("--rom", ROM_PADRAO))
	if not ok:
		_mostrar("Sem ROM. Segure o botão de menu para escolher uma.")

	# Depois de iniciar: o id do perfil sai do nome da ROM, que só existe agora.
	_cfg.usar_perfil(_emu.id_rom())
	_aplicar_tudo()
	# usar_perfil() já emite `mudou` para o que o perfil sobrescreve, mas isso
	# depende da conexão do sinal logo acima; aplicar à mão aqui tira a ordem de
	# inicialização da conta.
	_aplicar_ajustes_guidao()


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


## Liga com `-- --diag` no desktop, ou pelo interruptor da página Vídeo — que é
## o único caminho no headset, onde não há linha de comando. Mostra se a
## emulação está no ritmo do core: passos/s deve bater com o fps do core, e
## descartado deve ficar em zero.
##
## Vai para a tela **e** para o log: no headset o logcat só existe se alguém
## estiver com o cabo na mão, e a pergunta "esta sala derruba o fps?" tem que ter
## resposta olhando para a frente.
func _diagnostico(delta: float) -> void:
	if not _diag_ligado and not _cfg.obter("video/diag"):
		return
	_diag_t += delta
	if _diag_t < 1.0:
		return
	var linha := "render=%.1f fps | passos do emu=%d/s (core pede %.1f) | audio gerado=%d descartado=%d" % [
		Engine.get_frames_per_second(), _diag_passos, _emu.get_fps(),
		_emu.diag_audio_gerado, _emu.diag_audio_descartado]
	print("DIAG ", linha)
	if not _painel.esta_aberto():
		_mostrar(linha)
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
	# O WorldEnvironment que ficava aqui passou a ser da Sala: o fundo é uma
	# propriedade do ambiente escolhido, e no passthrough ele precisa ser
	# transparente em vez de preto.
	_sala = Sala.new()
	add_child(_sala)

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

	# Filho da cena, e **não** da tela: como filho ele herdava `tela/escala`, e
	# numa tela grande (2,86× medido no headset) o deslocamento de 0,7 virava 2 m
	# — o texto ia parar na altura dos pés, junto com a fonte esticada na mesma
	# proporção. Quem posiciona é `_posicionar_tela()`, em metros de verdade.
	_label = Label3D.new()
	_label.pixel_size = 0.0015
	_label.modulate = Color.WHITE
	_label.outline_size = 12
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


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
	if chave == "sala/modo":
		_aplicar_sala()
	elif chave == "video/diag":
		# Desligar tem de apagar o que ficou escrito: o texto é reescrito uma vez
		# por segundo, então sem isto o último número ficaria parado na tela para
		# sempre, parecendo travamento.
		_mostrar("")
		# E zerar os contadores, senão a primeira amostra depois de ligar despeja
		# tudo o que se acumulou desde o arranque: `_avancar_emulacao` conta
		# sempre, e quem zerava era o `_diagnostico`, que estava saindo cedo.
		# Medido: 51589 passos numa amostra de 1 s, que são os 15 min de app.
		_diag_t = 0.0
		_diag_passos = 0
		_emu.diag_audio_gerado = 0
		_emu.diag_audio_descartado = 0
	elif chave.begins_with("tela/") or chave == "video/aspecto":
		_aplicar_tela()
	elif chave.begins_with("video/"):
		_aplicar_video()
	elif chave.begins_with("audio/"):
		_aplicar_audio()
	elif chave == "input/n64_guidao" or chave.begins_with("input/guidao_"):
		# Só os ajustes; o recentro fica para quando o painel fechar. Aplicar a
		# sensibilidade nova é seguro a qualquer hora — capturar repouso com as
		# mãos no menu não é.
		_aplicar_ajustes_guidao()


func _aplicar_tudo() -> void:
	_aplicar_sala()
	_aplicar_tela()
	_aplicar_video()
	_aplicar_audio()


## Monta o ambiente e, no passthrough, negocia com o OpenXR a composição com a
## imagem das câmeras. Este é o único ponto do projeto que sabe de blend mode —
## a `Sala` inteira roda sem runtime de XR, e é o que a torna testável no desktop.
func _aplicar_sala() -> void:
	var modo := int(_cfg.obter("sala/modo"))
	if Sala.quer_transparencia(modo) and not _ligar_passthrough():
		# Cair no Vazio **avisando**: um passthrough que não sobe e não diz nada
		# é indistinguível de um preto proposital, e a pessoa ficaria mexendo no
		# menu atrás de um modo que o aparelho não tem.
		_mostrar("Passthrough indisponível neste aparelho — usando Vazio.")
		# Também no log: no headset o rótulo some no frame seguinte, e depois só
		# resta um preto que ninguém sabe explicar.
		print("Sala: passthrough indisponível — caindo no Vazio")
		modo = Sala.VAZIO
		_cfg.definir("sala/modo", modo)
		return   # definir() reentra aqui por `mudou`, já com o modo corrigido

	if not Sala.quer_transparencia(modo):
		_desligar_passthrough()
	_sala.aplicar(modo)
	# No log também, e não só na tela: sem esta linha uma captura de DIAG não tem
	# como separar os segundos de um ambiente dos de outro, e a comparação entre
	# salas vira relato em vez de medida — que foi exatamente o que aconteceu na
	# primeira medição de verdade.
	print("Sala: modo ", Sala.NOMES[modo])


## Põe o OpenXR em alpha blend e abre o fundo do viewport. Devolve se conseguiu.
##
## Perguntar antes, por `get_supported_environment_blend_modes()`, e não só
## tentar: num runtime sem alpha blend o `set_` falharia e o modo ficaria preto,
## que é indistinguível de um passthrough que subiu apontado para uma parede
## escura.
func _ligar_passthrough() -> bool:
	if not _xr_ativo:
		return false
	var xr := XRServer.find_interface("OpenXR")
	if xr == null:
		return false
	if not XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr.get_supported_environment_blend_modes():
		print("Sala: o runtime não oferece alpha blend (tem: %s)"
				% str(xr.get_supported_environment_blend_modes()))
		return false
	if not xr.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		print("Sala: o runtime recusou o alpha blend")
		return false
	get_viewport().transparent_bg = true
	print("Sala: passthrough ligado (alpha blend)")
	return true


func _desligar_passthrough() -> void:
	get_viewport().transparent_bg = false
	if not _xr_ativo:
		return
	var xr := XRServer.find_interface("OpenXR")
	if xr != null:
		xr.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_OPAQUE)


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
	_posicionar_label()


## Logo abaixo da borda de baixo da tela, a uma distância fixa **em metros** —
## que é o que faz o texto continuar legível e no mesmo lugar relativo, seja a
## tela portátil ou de cinema.
func _posicionar_label() -> void:
	if _label == null:
		return
	var razao := _cfg.aspecto_como_razao(_aspecto_nativo)
	var meia_altura: float = (LARGURA_BASE / razao) * _cfg.obter("tela/escala") * 0.5
	_label.global_position = _tela.global_position - Vector3(0, meia_altura + 0.12, 0)


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
		# Antes do recentro: o guidão precisa recentrar com os ajustes do jogo
		# novo, não com os do cartucho que acabou de sair.
		_cfg.usar_perfil(_emu.id_rom())
		_painel.fechar()
		_mostrar("")
		# Jogo novo, repouso novo: o centro da sessão anterior foi capturado com
		# o jogador em outra posição, e herdá-lo faria a nave sair torta.
		_centrar_guidao()


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
		_painel_antes = true
		return

	if _painel_antes:
		# Acabou de fechar o painel. Centralizar aqui, e não no instante em que a
		# opção mudou: mexendo no menu a mão direita está esticada apontando para
		# ele, e capturar aquilo como repouso nasce com a arfagem no batente.
		_painel_antes = false
		_centrar_guidao()

	if _emu.sistema == "n64":
		_input_n64()
	else:
		_input_snes()
		# Redimensionar/reposicionar com o thumbstick direito. No N64 esse stick
		# são os C-buttons, e o jogo ganha: a tela se ajusta pelos sliders da
		# página Tela, que é para onde este atalho é um atalho.
		_ajustar_tela_com_stick(_ctrl_dir.get_vector2(&"primary"))


func _ajustar_tela_com_stick(rstick: Vector2) -> void:
	if absf(rstick.y) > 0.15:
		_cfg.definir("tela/escala", clampf(
			_cfg.obter("tela/escala") + rstick.y * 0.03,
			PagTela.ESCALA_MIN, PagTela.ESCALA_MAX))
	if absf(rstick.x) > 0.15:
		_cfg.definir("tela/distancia", clampf(
			_cfg.obter("tela/distancia") - rstick.x * 0.03,
			PagTela.DIST_MIN, PagTela.DIST_MAX))


## SNES: D-pad digital no analógico esquerdo; o resto sai do mapa de botões,
## que a página de Input troca e o perfil do cartucho guarda por jogo.
func _input_snes() -> void:
	# As quatro direções não passam por origem nenhuma: saem do analógico
	# esquerdo, que não é remapeável.
	var dpad := _dpad_do_stick(_ctrl_esq.get_vector2(&"primary"))
	_aplicar_mapa("snes", {
		LibretroHost.JOYPAD_LEFT: dpad.left,
		LibretroHost.JOYPAD_RIGHT: dpad.right,
		LibretroHost.JOYPAD_UP: dpad.up,
		LibretroHost.JOYPAD_DOWN: dpad.down,
	})


## N64: os dois analógicos são eixos de verdade, e é por isso que eles ficam
## aqui em vez de virar linhas do mapa. Os C-buttons não são quatro botões
## digitais para o core, e sim o **segundo manche** (device=ANALOG, index=1:
## "C Buttons X/Y") — é o que faz o stick direito do Touch cair direto neles,
## sem conversão para setores.
##
## Os botões saem do mapa, cujos padrões vêm dos descritores que o mupen declara
## (SET_INPUT_DESCRIPTORS) e não de tabela decorada: lá, JOYPAD_B é o **A** do
## N64, JOYPAD_Y é o **B**, e o Z fica em JOYPAD_L2.
func _input_n64() -> void:
	var manche := _manche_do_n64()
	_emu.set_analog(0, LibretroHost.ANALOG_LEFT, LibretroHost.ANALOG_X, manche.x)
	_emu.set_analog(0, LibretroHost.ANALOG_LEFT, LibretroHost.ANALOG_Y, manche.y)

	var c := _ctrl_dir.get_vector2(&"primary")
	_emu.set_analog(0, LibretroHost.ANALOG_RIGHT, LibretroHost.ANALOG_X, c.x)
	_emu.set_analog(0, LibretroHost.ANALOG_RIGHT, LibretroHost.ANALOG_Y, -c.y)

	_aplicar_mapa("n64", {})


## Escreve no core os botões do frame, para qualquer sistema: o mapa da página
## de Input decide quem vai onde, e `pre` traz os ids que não vêm de botão
## nenhum (as direções que o analógico gera no SNES).
##
## Zera os 16 ids antes de aplicar. Sem isso, um botão que acabou de deixar de
## ser mapeado ficaria preso no último estado que teve — remapear com o dedo no
## gatilho deixaria o tiro travado ligado, e o jogo pareceria quebrado.
func _aplicar_mapa(sistema: String, pre: Dictionary) -> void:
	var mapa := {}
	var pressionadas := {}
	for entrada in MapaInput.ORIGENS:
		var origem: String = entrada[0]
		mapa[origem] = int(_cfg.obter(MapaInput.chave(sistema, origem)))
		pressionadas[origem] = _origem_pressionada(origem)

	var estados := MapaInput.combinar(mapa, pressionadas, pre)
	# O toque curto no botão de menu vale como Start, mesmo que nenhuma origem
	# esteja mapeada nele — é o caminho de quem remapeou o grip para outra coisa.
	estados[LibretroHost.JOYPAD_START] = _start_com_pulso(estados[LibretroHost.JOYPAD_START])
	for id: int in estados:
		_emu.set_button(0, id, estados[id])


## Estado físico de uma origem do Touch. É o único lugar do remap que sabe de
## OpenXR — o resto trabalha em cima do dicionário que sai daqui.
func _origem_pressionada(origem: String) -> bool:
	match origem:
		"dir_ax": return _ctrl_dir.is_button_pressed(&"ax_button")
		"dir_by": return _ctrl_dir.is_button_pressed(&"by_button")
		"esq_ax": return _ctrl_esq.is_button_pressed(&"ax_button")
		"esq_by": return _ctrl_esq.is_button_pressed(&"by_button")
		"esq_trigger": return _ctrl_esq.get_float(&"trigger") > 0.5
		"dir_trigger": return _ctrl_dir.get_float(&"trigger") > 0.5
		"esq_grip": return _ctrl_esq.get_float(&"grip") > 0.5
		"dir_grip": return _ctrl_dir.get_float(&"grip") > 0.5
	return false


## O manche do N64 vem do thumbstick ou da pose dos controles, conforme
## `input/n64_guidao`. Os dois entregam a mesma coisa — eixos em [-1, 1] na
## convenção do libretro, com y crescendo para baixo — então quem chama não
## precisa saber de qual dos dois veio.
func _manche_do_n64() -> Vector2:
	if not _cfg.obter("input/n64_guidao"):
		# O Y do thumbstick cresce para cima; o do libretro, para baixo.
		var stick := _ctrl_esq.get_vector2(&"primary")
		return Vector2(stick.x, -stick.y)

	# Clique do thumbstick esquerdo recentra. Em modo guidão ele está livre —
	# era ele o manche —, então não disputa com nada do mapa do N64.
	var clique := _ctrl_esq.is_button_pressed(&"primary_click")
	if clique and not _recentrar_antes:
		_centrar_guidao("Guidão centralizado")
	_recentrar_antes = clique

	var v := _guidao.eixos(_ctrl_esq.global_transform, _ctrl_dir.global_transform,
			_camera.global_transform)
	if _cfg.obter("input/guidao_diag"):
		_mostrar("guidão  x %+.2f  y %+.2f   %s" % [
			v.x, v.y, "inv Y" if _guidao.inverter_y else "Y normal"])
	return v


## Sensibilidade e sentido dos eixos, direto da página Input. Não mexe no
## repouso: dá para mudar com o jogo rodando, sem o comando saltar.
func _aplicar_ajustes_guidao() -> void:
	_guidao.angulo_max = _cfg.obter("input/guidao_angulo_max")
	_guidao.curso = _cfg.obter("input/guidao_curso")
	_guidao.zona_morta = _cfg.obter("input/guidao_zona_morta")
	_guidao.curva = _cfg.obter("input/guidao_curva")
	_guidao.inverter_y = _cfg.obter("input/guidao_inverter_y")


## Captura a pose atual como repouso. Só faz sentido com as mãos no manche —
## por isso quem chama é o fechamento do painel, a troca de ROM e o clique do
## analógico, e não a mudança de uma opção.
func _centrar_guidao(msg := "") -> void:
	if not _xr_ativo or _camera == null:
		return
	_aplicar_ajustes_guidao()
	_guidao.centrar(_ctrl_esq.global_transform, _ctrl_dir.global_transform,
			_camera.global_transform)
	if not msg.is_empty():
		_mostrar(msg)


## Start segurado pelo grip, ou pulsado pelo toque curto no botão de menu. O
## pulso dura alguns frames porque um só às vezes cai entre polls do core.
func _start_com_pulso(segurado: bool) -> bool:
	if _start_restante > 0:
		_start_restante -= 1
		return true
	return segurado


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
