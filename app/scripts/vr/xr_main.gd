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
##   clique do thumbstick direito -> traz tela e sala para a frente
##
## Tamanho, distância, sala, vídeo, áudio e zona morta vivem no ConfigEmu e
## persistem entre sessões; esta cena só reage a `mudou`.
##
## O ambiente em volta da tela é da `Sala` (`vr/sala.gd`), que roda sem XR. O
## que fica aqui é só a negociação de passthrough com o OpenXR.

# Nenhuma ROM vai no APK — jogo é obra de terceiros (ver THIRD-PARTY.md). Então a
# primeira execução não abre nada, e cai na mensagem que manda abrir o menu. Passar
# `-- --rom /caminho` continua valendo, e é como os testes e o desktop rodam.
# O core sai da extensão da ROM (EmuCore.core_para_rom), não daqui.
const ROM_PADRAO := ""

const LARGURA_BASE := 1.4       # metros, largura da tela em escala 1.0

## Quanto segurar o botão de menu para abrir o painel. Toque mais curto que
## isto continua valendo como Start — todos os outros botões já estão no SNES,
## e o botão de sistema do controle direito é reservado pelo Quest.
const MENU_SEGURAR := 0.5

## Índices de `app/mao_aponta`, na ordem que o seletor mostra.
const MAO_DIREITA := 0
const MAO_ESQUERDA := 1
## Frames em que Start fica pressionado no toque curto. Um só às vezes cai
## entre polls do core e o jogo não vê.
const START_PULSO := 3

## Curvatura máxima, em graus de arco, quando tela/curvatura = 1.0.
const ARCO_MAX := 60.0
const ARCO_SEGMENTOS := 24

## Quanto a tela de baixo do DS se inclina para trás, em graus. Um console
## apoiado nas mãos fica deitado, não de pé — e apontar a caneta para uma
## superfície vertical na altura do peito cansa o pulso em minutos.
const INCLINACAO_DS := 35.0

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
## Segunda tela, só nos sistemas de duas telas (hoje o DS). Mostra a metade de
## baixo do mesmo framebuffer, recortada por `uv1_offset`.
var _tela2: MeshInstance3D
var _mat2: StandardMaterial3D
var _duas_telas := false
## Caneta: o raio do controle direito e o alvo colado na tela de baixo.
var _raio_ds: RayCast3D
var _corpo_ds: StaticBody3D
var _laser_ds: MeshInstance3D
var _mira_ds: MeshInstance3D
var _tamanho_tela_ds := Vector2.ONE
## Última leitura da caneta, para o diagnóstico. Existe porque "o laser não
## funciona" tem três desfechos indistinguíveis de dentro do headset: o raio não
## alcança a tela, alcança e cai no lugar errado, ou alcança certo e o gatilho
## não conta. A linha diz qual dos três é.
var _diag_caneta := ""
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
var _centrar_tela_antes := false  # borda do clique do thumbstick direito

## Para onde a tela (e a sala) olham. Zerados, dão exatamente o que a cena sempre
## fez: tela à frente da origem do espaço de jogo, olhando para -Z. `_centrar_tela`
## os captura da câmera. Ver lá por que não persistem entre sessões.
var _ancora_pos := Vector3.ZERO
var _ancora_guinada := 0.0
var _painel_antes := false      # para recentrar quando o painel fecha

var _acumulador := 0.0          # sobra de tempo entre frames emulados
var _diag_ligado := false
var _diag_t := 0.0
var _diag_passos := 0
var _diag_us_process := 0   ## tempo em `_process`, acumulado desde a última amostra


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
	_painel.conectar_xr(_camera, _ctrl_aponta() if _xr_ativo else null)
	_painel.fechar_pedido.connect(func() -> void: _painel.fechar())
	_painel.rom_escolhida.connect(_trocar_rom)
	# Fecha o painel junto: centralizar com ele aberto deixaria a tela nova atrás
	# do menu, e a pessoa não veria o que acabou de pedir.
	_painel.centrar_pedido.connect(func() -> void:
		_centrar_tela("Tela centralizada")
		_painel.fechar()
	)

	_cfg.mudou.connect(_ao_mudar_config)

	# Não pedimos a permissão no arranque: MANAGE_EXTERNAL_STORAGE não tem
	# diálogo de runtime, e pedi-la aqui jogaria a pessoa para os Ajustes do
	# Android antes mesmo de o jogo aparecer. Quem pede é o botão da página de
	# ROMs, quando ela de fato quer procurar um jogo.
	# Antes de qualquer UI: o menu monta o texto no `_init` das páginas, e um
	# locale aplicado depois deixaria a primeira montagem na língua errada.
	Idioma.aplicar(Idioma.indice_valido(_cfg.obter("app/idioma")))

	# A mão que aponta muda de quem são os nós do ponteiro, então precisa valer
	# depois de a cena de XR existir e a cada troca.
	_aplicar_mao()
	_cfg.mudou.connect(func(k: String, _v: Variant) -> void:
		if k == "app/mao_aponta":
			_aplicar_mao()
	)

	NavegadorRoms.garantir_pasta_local()

	var ok := _emu.iniciar(_arg("--core", ""), _arg("--rom", ROM_PADRAO))
	if not ok:
		_mostrar(tr("XR_SEM_ROM_AJUDA"))

	# Depois de iniciar: o id do perfil sai do nome da ROM, que só existe agora.
	_cfg.usar_perfil(_emu.id_rom())
	_aplicar_tudo()
	# usar_perfil() já emite `mudou` para o que o perfil sobrescreve, mas isso
	# depende da conexão do sinal logo acima; aplicar à mão aqui tira a ordem de
	# inicialização da conta.
	_aplicar_ajustes_guidao()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_ler_input_vr(delta)
	_avancar_emulacao(delta)
	_atualizar_tela()
	# Antes do `_diagnostico`, que formata texto e imprime uma vez por segundo:
	# o custo dele não é do frame comum e contá-lo inflaria a amostra em que ele
	# roda. O que sobra entre este número e os 1000 ms do segundo é o motor —
	# desenho, física, OpenXR —, e é o que separa "o nosso `_process` está caro"
	# de "o frame está caro em outro lugar".
	_diag_us_process += Time.get_ticks_usec() - t0
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
## Se o diagnóstico está ligado, por linha de comando (desktop) ou pelo
## interruptor da página Vídeo (o único caminho no headset).
func _diag_ativo() -> bool:
	return _diag_ligado or bool(_cfg.obter("video/diag"))


## Zera os acumuladores de tempo. Eles somam sempre, com o diagnóstico ligado ou
## não, então quem os lê precisa zerá-los junto — senão a primeira amostra
## depois de ligar despeja o app inteiro, que é o mesmo tropeço que os passos do
## emu já deram (51589 num intervalo de 1 s).
func _zerar_tempos() -> void:
	_diag_us_process = 0
	_emu.diag_us_core = 0
	_emu.diag_us_video = 0
	_emu.diag_us_audio = 0


func _diagnostico(delta: float) -> void:
	if not _diag_ativo():
		return
	_diag_t += delta
	if _diag_t < 1.0:
		return
	# `video` e `sala` são constantes enquanto a ROM e o ambiente não trocam, e
	# ainda assim saem em **toda** amostra: é o que faz uma captura de logcat
	# dizer sozinha em que configuração aquele segundo rodou.
	#
	# A sala já tinha o evento `Sala: modo <nome>` do `_aplicar_sala()`, e ele não
	# bastou. Um evento só marca a **mudança**: numa captura que começou com o app
	# já rodando, todas as amostras até a primeira troca ficam sem dono — foram 71
	# de 92 numa medição real, e o A/B inteiro se perdeu. Estado na amostra não
	# tem esse buraco, e ainda dispensa casar horários entre duas linhas.
	var linha := "render=%.1f fps | passos do emu=%d/s (core pede %.1f) | video=%dx%d %s | sala=%s | audio gerado=%d descartado=%d" % [
		Engine.get_frames_per_second(), _diag_passos, _emu.get_fps(),
		_emu.largura, _emu.altura, _emu.formato_video(),
		Sala.NOMES_LOG[int(_cfg.obter("sala/modo"))],
		_emu.diag_audio_gerado, _emu.diag_audio_descartado]
	# Com o painel aberto, um SubViewport de 1280x800 é redesenhado a cada frame
	# (`UPDATE_ALWAYS`) enquanto a emulação continua rodando atrás. Marcar a
	# amostra é o que separa "o menu estava aberto" de "a cena ficou pesada" numa
	# captura de logcat — sem isso as duas dão a mesma queda de render e a
	# comparação vira relato. Mesmo papel do `Sala: modo`, e a razão de a marca
	# ir **na amostra** e não num evento de abrir/fechar: assim cada segundo se
	# classifica sozinho, e o fatiamento não depende de casar horários.
	if _painel.esta_aberto():
		linha += " | MENU ABERTO"
	# Onde o segundo foi gasto. Em ms por segundo, e não por frame, porque é a
	# unidade que se lê direto: 1000 é o segundo inteiro, então `core=520` são
	# 52 % do tempo de parede dentro do `retro_run`. O contador de fps diz *que*
	# o frame ficou longo; estes dizem *onde*.
	#
	# Dividido pela janela **real**, e não por 1 s: a amostra sai quando `_diag_t`
	# passa de 1, e ela passa em cima de um frame — que num segundo ruim é longo.
	# Sem isto a janela estica e os números saem inflados na exata proporção do
	# problema que se quer medir; foi assim que apareceu um `core=1125` num
	# "segundo", que é impossível numa thread só.
	var janela := maxf(_diag_t, 0.001)
	linha += " | ms/s process=%d core=%d video=%d audio=%d" % [
		roundi(_diag_us_process / 1000.0 / janela), roundi(_emu.diag_us_core / 1000.0 / janela),
		roundi(_emu.diag_us_video / 1000.0 / janela), roundi(_emu.diag_us_audio / 1000.0 / janela)]
	if _duas_telas and not _diag_caneta.is_empty():
		linha += "\n" + _diag_caneta
	print("DIAG ", linha)
	if not _painel.esta_aberto():
		_mostrar(linha)
	_diag_t = 0.0
	_diag_passos = 0
	_zerar_tempos()
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
		# Par de teclado do clique do analógico direito. No desktop a câmera não
		# se move, então o efeito é nulo — serve para exercitar o caminho sem
		# headset, que é o que `test_sala` faz.
		if evento.keycode == KEY_C:
			_centrar_tela("Tela centralizada")
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
	_mat = _material_tela()
	_tela = MeshInstance3D.new()
	add_child(_tela)

	# A segunda tela existe sempre, e fica escondida fora do DS. Criá-la sob
	# demanda faria a troca de ROM ter de montar geometria no meio do jogo, e
	# esconder um MeshInstance vazio não custa frame nenhum.
	_mat2 = _material_tela()
	_tela2 = MeshInstance3D.new()
	_tela2.visible = false
	add_child(_tela2)

	# Alvo da caneta: uma caixa fina colada na tela de baixo, e um raio no
	# controle direito. Mesmo arranjo que o `PainelMenu` usa para o laser do
	# menu — e são dois raios separados de propósito, porque quem manda em cada
	# um é diferente: o do menu só existe com o painel aberto, este só com ele
	# fechado.
	_corpo_ds = StaticBody3D.new()
	var forma := CollisionShape3D.new()
	forma.shape = BoxShape3D.new()
	_corpo_ds.add_child(forma)
	_tela2.add_child(_corpo_ds)

	_raio_ds = RayCast3D.new()
	_raio_ds.target_position = Vector3(0, 0, -5.0)
	_raio_ds.collide_with_areas = false
	_raio_ds.enabled = false
	_ctrl_aponta().add_child(_raio_ds)

	# Feixe e mira. **Não** são enfeite: sem eles a caneta é um laser invisível,
	# e mirar vira adivinhação — foi assim que a primeira versão foi para o
	# headset, e de lá não dava para distinguir "não estou acertando a tela" de
	# "acerto mas o toque não chega". Mesmo arranjo do laser do menu.
	var mat_laser := StandardMaterial3D.new()
	mat_laser.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_laser.albedo_color = Color(TemaVR.ACCENT, 0.6)
	mat_laser.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Visível mesmo com a tela de cima entre a mão e a de baixo.
	mat_laser.no_depth_test = true
	mat_laser.render_priority = 2

	var feixe := CylinderMesh.new()
	feixe.top_radius = 0.002
	feixe.bottom_radius = 0.002
	feixe.height = 1.0
	feixe.material = mat_laser
	_laser_ds = MeshInstance3D.new()
	_laser_ds.mesh = feixe
	# O cilindro nasce em pé (eixo Y); deitar no -Z alinha com o controle.
	_laser_ds.rotation_degrees.x = -90
	_laser_ds.visible = false
	_ctrl_aponta().add_child(_laser_ds)

	var esfera := SphereMesh.new()
	esfera.radius = 0.008
	esfera.height = 0.016
	esfera.material = mat_laser
	_mira_ds = MeshInstance3D.new()
	_mira_ds.mesh = esfera
	_mira_ds.visible = false
	add_child(_mira_ds)

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
		_zerar_tempos()
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
	print("Sala: modo ", Sala.NOMES_LOG[modo])


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


func _material_tela() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _aplicar_tela() -> void:
	_duas_telas = NavegadorRoms.tem_duas_telas(_emu.sistema)
	_tela2.visible = _duas_telas
	if not _duas_telas:
		# Trocar de DS para outro console tem de levar o feixe junto, senão ele
		# fica pendurado na mão apontando para uma tela que não existe mais.
		_esconder_caneta()

	var curvatura: float = _cfg.obter("tela/curvatura")
	# Com duas telas, o aspecto de cada quad é o da tela **individual**, não o do
	# framebuffer: o do DS empilhado é 2:3, e usar isso em cada metade sairia com
	# as duas achatadas na altura.
	var razao := _aspecto_de_uma_tela() if _duas_telas \
			else _cfg.aspecto_como_razao(_aspecto_nativo)

	_tela.mesh = _construir_mesh_tela(LARGURA_BASE, LARGURA_BASE / razao, curvatura)
	_tela.mesh.surface_set_material(0, _mat)
	_tela.scale = Vector3.ONE * _cfg.obter("tela/escala")

	# O recorte vem do material, e não da malha: assim `_construir_mesh_tela()`
	# continua servindo aos dois casos sem saber que existe uma segunda tela.
	if _duas_telas:
		_mat.uv1_scale = CanetaDS.UV_ESCALA
		_mat.uv1_offset = CanetaDS.UV_CIMA
		_mat2.uv1_scale = CanetaDS.UV_ESCALA
		_mat2.uv1_offset = CanetaDS.UV_BAIXO
		_tela2.mesh = _construir_mesh_tela(LARGURA_BASE, LARGURA_BASE / razao, curvatura)
		_tela2.mesh.surface_set_material(0, _mat2)
		_tela2.scale = Vector3.ONE * _cfg.obter("tela/ds_escala")
		# O alvo da caneta acompanha o tamanho da malha. Como o colisor é filho
		# da tela, a escala vem junto de graça — mas as dimensões precisam ser
		# reditas quando a proporção muda, senão a caneta acerta uma área que
		# não é a que se vê.
		_tamanho_tela_ds = Vector2(LARGURA_BASE, LARGURA_BASE / razao)
		var forma := _corpo_ds.get_child(0) as CollisionShape3D
		(forma.shape as BoxShape3D).size = Vector3(
				_tamanho_tela_ds.x, _tamanho_tela_ds.y, 0.02)
	else:
		_mat.uv1_scale = Vector3.ONE
		_mat.uv1_offset = Vector3.ZERO

	_posicionar_tela()


## Proporção de **uma** tela do DS: 256×192, ou 4:3.
func _aspecto_de_uma_tela() -> float:
	return 4.0 / 3.0


func _aplicar_video() -> void:
	var filtro := BaseMaterial3D.TEXTURE_FILTER_LINEAR \
			if _cfg.obter("video/filtro_suave") else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Unshaded multiplica a textura pelo albedo, então isto vira brilho.
	var b: float = _cfg.obter("video/brilho")
	for m in [_mat, _mat2]:
		m.texture_filter = filtro
		m.albedo_color = Color(b, b, b)


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
	# Frente da âncora: -Z girado pela guinada guardada. Com a âncora zerada isto
	# dá exatamente (0, y, -distancia), que é onde a tela sempre nasceu.
	var frente := Basis(Vector3.UP, _ancora_guinada) * Vector3.FORWARD

	_tela.global_position = _ancora_pos \
		+ frente * float(_cfg.obter("tela/distancia")) \
		+ Vector3.UP * (altura_olhos + float(_cfg.obter("tela/altura")))
	# Encara a âncora. O +Z da malha é a face visível, e girá-la pela guinada põe
	# essa face de volta apontando para quem centralizou.
	_tela.rotation = Vector3(0.0, _ancora_guinada, 0.0)

	# A tela de baixo tem posição própria, e o padrão a põe onde um DS fica: perto
	# e abaixo da linha dos olhos, ao alcance do braço. É ela que a caneta aponta,
	# então distância aqui é ergonomia, não gosto.
	if _duas_telas:
		_tela2.global_position = _ancora_pos \
			+ frente * float(_cfg.obter("tela/ds_distancia")) \
			+ Vector3.UP * (altura_olhos + float(_cfg.obter("tela/ds_altura")))
		# Levemente inclinada para trás, como um console apoiado nas mãos: de pé
		# ela obrigaria o pulso a apontar reto para baixo o jogo inteiro.
		#
		# Guinada e arfagem juntas: a ordem YXZ do Godot aplica o Y primeiro, que
		# é o que se quer — girar em pé e depois deitar. Trocar a ordem deitaria
		# a tela num eixo já girado, e a caneta erraria o alvo fora do eixo zero.
		_tela2.rotation = Vector3(deg_to_rad(-INCLINACAO_DS), _ancora_guinada, 0.0)

	_posicionar_label()


## Traz tela e sala para a frente de quem está jogando **agora**.
##
## Existe porque a tela nascia amarrada à origem do espaço de jogo: quem virasse
## a cadeira ou se deslocasse ficava com ela de lado, e a única saída era mexer
## nos sliders de distância e altura — que não giram nada. Em VR isso não é
## conforto, é a diferença entre jogar e não jogar.
##
## A **sala vai junto**, e isso não é detalhe: mover só a tela a jogaria para
## dentro de uma parede do fliperama, que é dimensionado a partir do alcance
## dela. Movendo as duas, a relação entre tela e salão — inclusive a asserção de
## `test_sala` de que a parede do fundo fica além da distância máxima —
## permanece verdadeira por construção.
##
## Só a **guinada** entra. Inclinar ou tombar a cabeça no instante do clique não
## pode deixar a tela torta ou no chão, pela mesma razão que o guidão ignora as
## outras duas rotações: olhar em volta não é comandar.
##
## Não persiste em `user://config.cfg` de propósito: a origem do espaço de jogo
## muda entre sessões (e a cada recentragem do próprio Quest), então uma âncora
## guardada apontaria para um lugar que não existe mais.
func _centrar_tela(msg := "") -> void:
	if _xr_ativo and _camera != null:
		var cam := _camera.global_transform
		var frente := -cam.basis.z
		frente.y = 0.0
		if frente.length_squared() < 0.0001:
			# Cabeça apontada reto para cima ou para baixo: a guinada some. Manter
			# a anterior é melhor que escolher uma direção arbitrária.
			return
		_ancora_guinada = atan2(-frente.x, -frente.z)
		_ancora_pos = Vector3(cam.origin.x, 0.0, cam.origin.z)

	# A sala acompanha; ver o comentário acima.
	_sala.position = _ancora_pos
	_sala.rotation = Vector3(0.0, _ancora_guinada, 0.0)
	_posicionar_tela()
	if not msg.is_empty():
		_mostrar(msg)


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
		# A mesma textura nas duas: o que as separa é o recorte de UV, não a
		# imagem. Uma segunda cópia do framebuffer seria um upload por frame a
		# mais, e é justamente disso que o DS não precisa.
		_mat2.albedo_texture = _emu.texture
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
		_esconder_caneta()
		_painel_antes = true
		return

	if _painel_antes:
		# Acabou de fechar o painel. Centralizar aqui, e não no instante em que a
		# opção mudou: mexendo no menu a mão direita está esticada apontando para
		# ele, e capturar aquilo como repouso nasce com a arfagem no batente.
		_painel_antes = false
		_centrar_guidao()

	# Centralizar a tela vale em **todo** sistema, e por isso fica antes do desvio
	# por console. O clique do analógico direito é o atalho: ele não é botão para
	# core nenhum (o mapa de input cobre só ax/by, gatilhos e grips), e o do
	# esquerdo já recentra o guidão — os dois cliques ficam simétricos, cada um
	# recentrando uma coisa.
	var clique_dir := _ctrl_aponta().is_button_pressed(&"primary_click")
	if clique_dir and not _centrar_tela_antes:
		_centrar_tela("Tela centralizada")
	_centrar_tela_antes = clique_dir

	if _duas_telas:
		_input_caneta()

	if _emu.sistema == "n64":
		_input_n64()
	else:
		_input_dpad_digital()
		# Redimensionar/reposicionar com o thumbstick direito. No N64 esse stick
		# são os C-buttons, e o jogo ganha: a tela se ajusta pelos sliders da
		# página Tela, que é para onde este atalho é um atalho.
		_ajustar_tela_com_stick(_ctrl_aponta().get_vector2(&"primary"))


## Controle que **aponta**: caneta do DS, laser do menu e ajustes de tela.
##
## Ser canhoto é propriedade da pessoa, não do jogo — por isso a chave mora em
## `app/` e não em `input/`, que é sobrescrito por perfil de cartucho.
func _ctrl_aponta() -> XRController3D:
	return _ctrl_esq if int(_cfg.obter("app/mao_aponta")) == MAO_ESQUERDA else _ctrl_dir


## O outro: botão de menu e o stick do D-pad. Apontar e abrir o menu com a mesma
## mão é desconfortável, então eles espelham juntos.
func _ctrl_outro() -> XRController3D:
	return _ctrl_dir if int(_cfg.obter("app/mao_aponta")) == MAO_ESQUERDA else _ctrl_esq


## Reparenta o que mora no controle. Chamado no arranque e a cada troca.
func _aplicar_mao() -> void:
	if not _xr_ativo:
		return
	var aponta := _ctrl_aponta()
	for no: Node3D in [_raio_ds, _laser_ds]:
		if no != null and no.get_parent() != null and no.get_parent() != aponta:
			no.reparent(aponta, false)
	if _painel != null:
		_painel.trocar_controle(aponta)


func _ajustar_tela_com_stick(rstick: Vector2) -> void:
	if absf(rstick.y) > 0.15:
		_cfg.definir("tela/escala", clampf(
			_cfg.obter("tela/escala") + rstick.y * 0.03,
			PagTela.ESCALA_MIN, PagTela.ESCALA_MAX))
	if absf(rstick.x) > 0.15:
		_cfg.definir("tela/distancia", clampf(
			_cfg.obter("tela/distancia") - rstick.x * 0.03,
			PagTela.DIST_MIN, PagTela.DIST_MAX))


## A caneta do DS: onde o laser bate na tela de baixo vira ponteiro para o core.
##
## O gatilho direito é a caneta encostando, e por isso ele nasce em **Nada** no
## mapa de botões do DS — mapeado em R, todo toque apertaria R junto.
##
## Só roda com o painel fechado, porque quem chama já garantiu isso: com o painel
## aberto o `_ler_input_vr` sai antes, depois de `limpar_input()`, que agora zera
## o ponteiro também.
func _input_caneta() -> void:
	_raio_ds.enabled = true
	_raio_ds.force_raycast_update()

	# O feixe fica visível sempre que há caneta, mesmo apontando para fora: é ele
	# que mostra **onde** se está apontando, e escondê-lo quando erra o alvo
	# tiraria a informação justamente na hora em que ela é necessária.
	_laser_ds.visible = true

	if not (_raio_ds.is_colliding() and _raio_ds.get_collider() == _corpo_ds):
		# Fora da tela: a caneta se levanta. Manter a última posição encostada
		# arrastaria o traço para onde o jogador só passou o laser de raspão.
		_emu.set_pointer(0, 0.0, 0.0, false)
		_mira_ds.visible = false
		_esticar_laser(1.5)
		if _diag_ativo():
			_diag_caneta = "caneta fora (mão a %.2f m da tela)" % \
					_ctrl_aponta().global_position.distance_to(_tela2.global_position)
		return

	var ponto := _raio_ds.get_collision_point()
	var local := _tela2.global_transform.affine_inverse() * ponto
	var p := CanetaDS.para_ponteiro(local, _tamanho_tela_ds)
	var encostada := _ctrl_aponta().get_float(&"trigger") > 0.6
	_emu.set_pointer(0, p.x, p.y, encostada)

	# O feixe encurta até o ponto de toque, e a mira marca onde a caneta cai.
	_mira_ds.visible = true
	_mira_ds.global_position = ponto
	_esticar_laser(_ctrl_aponta().global_position.distance_to(ponto))

	# Só monta o texto se alguém for lê-lo: isto roda a 72 Hz com um DS
	# carregado, e formatar dois floats por frame para uma linha que quase nunca
	# aparece é trabalho pago em todo frame por um benefício raro.
	if _diag_ativo():
		_diag_caneta = "caneta %+.2f %+.2f %s" % [p.x, p.y, "ENCOSTADA" if encostada else "no ar"]


## Estica o feixe até `comprimento`, saindo **da mão**. O cilindro tem origem no
## centro, então sem o deslocamento de meio comprimento metade dele ficaria para
## trás do controle, atravessando o braço de quem joga.
func _esticar_laser(comprimento: float) -> void:
	_laser_ds.scale.y = comprimento
	_laser_ds.position = Vector3(0, 0, -comprimento * 0.5)


## Recolhe feixe, mira e caneta. Chamada quando o painel abre e quando a ROM
## deixa de ser de duas telas — nos dois casos o `_input_caneta` para de rodar, e
## sem isto o que ele desenhou por último ficaria na tela para sempre.
func _esconder_caneta() -> void:
	if _laser_ds == null:
		return
	_laser_ds.visible = false
	_mira_ds.visible = false
	_raio_ds.enabled = false
	_diag_caneta = ""


## Consoles de D-pad: o analógico esquerdo vira as quatro direções por setores, e
## o resto sai do mapa de botões, que a página de Input troca e o perfil do
## cartucho guarda por jogo. Serve SNES e Mega Drive sem distinção — o que muda
## entre eles é o mapa, que é dado, e não este caminho.
##
## O sistema vem do emulador em vez de ficar escrito aqui: com "snes" fixo, um
## jogo de Mega Drive escreveria no mapa do SNES e leria o do Mega Drive, e o
## controle simplesmente não responderia.
func _input_dpad_digital() -> void:
	# As quatro direções não passam por origem nenhuma: saem do analógico
	# esquerdo, que não é remapeável.
	var dpad := _dpad_do_stick(_ctrl_outro().get_vector2(&"primary"))
	_aplicar_mapa(_emu.sistema, {
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

	var c := _ctrl_aponta().get_vector2(&"primary")
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
		var stick := _ctrl_outro().get_vector2(&"primary")
		return Vector2(stick.x, -stick.y)

	# Clique do thumbstick esquerdo recentra. Em modo guidão ele está livre —
	# era ele o manche —, então não disputa com nada do mapa do N64.
	var clique := _ctrl_outro().is_button_pressed(&"primary_click")
	if clique and not _recentrar_antes:
		_centrar_guidao("Guidão centralizado")
	_recentrar_antes = clique

	# As duas mãos, e a **ordem importa**: `eixos()` decide o sentido do rolamento
	# pela diferença entre elas. Passar sempre esquerda-depois-direita mantém o
	# guidão físico igual para todo mundo — ele é simétrico por natureza, e
	# espelhá-lo faria a nave virar ao contrário para o canhoto.
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
	var agora := _ctrl_outro().is_button_pressed(&"menu_button")

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
