class_name PainelMenu
extends Node3D
## O menu como objeto no espaço: um SubViewport 2D desenhado num quad, apontado
## com o laser do controle direito.
##
## Reaproveitar Control/Theme do Godot num viewport custa muito menos que
## construir widgets 3D à mão, e o preço é este arquivo: traduzir o raycast em
## eventos de mouse para o viewport.
##
## Sem OpenXR (rodando no desktop) o mouse controla o painel direto, para dar
## para iterar a UI sem build + sideload a cada mudança.

signal fechar_pedido
signal rom_escolhida(caminho: String)

const LARGURA := 1.0                ## metros
const DIST := 1.6                   ## à frente do jogador quando abre
const ABERTURA := 0.14              ## segundos da animação de escala

var menu: MenuRaiz

var _viewport: SubViewport
var _tela: MeshInstance3D
var _mat: StandardMaterial3D
var _corpo: StaticBody3D
var _raio: RayCast3D
var _laser: MeshInstance3D
var _mira: MeshInstance3D

var _camera: XRCamera3D
var _controle: XRController3D
var _aberto := false
var _gatilho_antes := false
var _ultimo_pos := Vector2(-1, -1)


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	_montar_viewport(cfg, emu)
	_montar_quad()
	visible = false


## Liga o painel aos nós de XR. Chamado pelo xr_main depois de montar a cena;
## `controle` pode ser nulo no fallback de desktop.
func conectar_xr(camera: XRCamera3D, controle: XRController3D) -> void:
	_camera = camera
	_controle = controle
	if controle != null:
		_montar_ponteiro(controle)


func esta_aberto() -> bool:
	return _aberto


func alternar() -> void:
	if _aberto:
		fechar()
	else:
		abrir()


func abrir() -> void:
	_aberto = true
	visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	menu.ao_abrir()
	_posicionar()
	_animar(Vector3.ONE)
	if _laser != null:
		_laser.visible = true


func fechar() -> void:
	_aberto = false
	if _laser != null:
		_laser.visible = false
	if _mira != null:
		_mira.visible = false
	var tw := _animar(Vector3(0.01, 0.01, 0.01))
	tw.finished.connect(func() -> void:
		if not _aberto:
			visible = false
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	)


func _process(_delta: float) -> void:
	if not _aberto:
		return
	_encarar_camera()
	if _controle != null:
		_apontar()


# ---------------------------------------------------------------------------
# Montagem
# ---------------------------------------------------------------------------
func _montar_viewport(cfg: ConfigEmu, emu: EmuCore) -> void:
	_viewport = SubViewport.new()
	_viewport.size = TemaVR.PAINEL
	_viewport.transparent_bg = true
	# Fechado, não redesenha: 1280x800 por frame é caro demais no GPU do Quest
	# para uma imagem que ninguém está vendo.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Sem isto o SubViewport nunca recebe os eventos que empurramos nele.
	_viewport.handle_input_locally = true
	_viewport.gui_embed_subwindows = true
	add_child(_viewport)

	# MenuRaiz já se ancora em full rect, então o SubViewport dimensiona sozinho.
	menu = MenuRaiz.new(cfg, emu)
	menu.fechar_pedido.connect(func() -> void: fechar_pedido.emit())
	menu.rom_escolhida.connect(func(caminho: String) -> void: rom_escolhida.emit(caminho))
	_viewport.add_child(menu)


func _montar_quad() -> void:
	var altura := LARGURA * float(TemaVR.PAINEL.y) / float(TemaVR.PAINEL.x)

	var quad := QuadMesh.new()
	quad.size = Vector2(LARGURA, altura)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_texture = _viewport.get_texture()
	# Desenha por cima de tudo. A tela do emulador vai de 0,8 m a 8 m enquanto o
	# painel abre a 1,6 m fixos, então em Portátil (1,0 m) ela ficava na frente e
	# tapava o menu. Reposicionar um em função do outro seria frágil, porque a
	# tela muda de tamanho e distância justamente enquanto o menu está aberto.
	_mat.no_depth_test = true
	_mat.render_priority = 1
	quad.material = _mat

	_tela = MeshInstance3D.new()
	_tela.mesh = quad
	add_child(_tela)

	# Alvo do raycast: uma caixa fina colada atrás do quad.
	_corpo = StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(LARGURA, altura, 0.02)
	forma.shape = caixa
	_corpo.add_child(forma)
	_tela.add_child(_corpo)


func _montar_ponteiro(controle: XRController3D) -> void:
	_raio = RayCast3D.new()
	_raio.target_position = Vector3(0, 0, -5.0)
	_raio.collide_with_areas = false
	controle.add_child(_raio)

	# Um cilindro fino como feixe. Fica escondido enquanto o menu está fechado.
	var feixe := CylinderMesh.new()
	feixe.top_radius = 0.002
	feixe.bottom_radius = 0.002
	feixe.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(TemaVR.ACCENT, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Pelo mesmo motivo do painel: o laser e a mira precisam ser vistos mesmo
	# com a tela do emulador entre o controle e o menu.
	mat.no_depth_test = true
	mat.render_priority = 2
	feixe.material = mat

	_laser = MeshInstance3D.new()
	_laser.mesh = feixe
	# O cilindro nasce em pé (eixo Y); deitar no -Z alinha com o controle.
	_laser.rotation_degrees.x = -90
	_laser.visible = false
	controle.add_child(_laser)

	var esfera := SphereMesh.new()
	esfera.radius = 0.008
	esfera.height = 0.016
	esfera.material = mat
	_mira = MeshInstance3D.new()
	_mira.mesh = esfera
	_mira.visible = false
	add_child(_mira)


# ---------------------------------------------------------------------------
# Posição
# ---------------------------------------------------------------------------
func _posicionar() -> void:
	if _camera == null:
		global_position = Vector3(0, 1.4, -DIST)
		return
	# Nasce à frente de onde a pessoa está olhando, na altura dos olhos, mas
	# ignorando a inclinação da cabeça — um painel tortinho enjoa.
	var frente := -_camera.global_transform.basis.z
	frente.y = 0.0
	if frente.length_squared() < 0.001:
		frente = Vector3.FORWARD
	frente = frente.normalized()
	global_position = _camera.global_position + frente * DIST


func _encarar_camera() -> void:
	if _camera == null:
		return
	var alvo := _camera.global_position
	alvo.y = global_position.y      # só gira no eixo vertical
	if alvo.distance_squared_to(global_position) > 0.0001:
		look_at(alvo, Vector3.UP)
		rotate_object_local(Vector3.UP, PI)  # o quad olha para +Z


func _animar(escala: Vector3) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "scale", escala, ABERTURA).set_trans(Tween.TRANS_CUBIC)
	return tw


# ---------------------------------------------------------------------------
# Ponteiro -> eventos do viewport
# ---------------------------------------------------------------------------
func _apontar() -> void:
	if _raio == null:
		return
	_raio.force_raycast_update()

	var acertou := _raio.is_colliding() and _raio.get_collider() == _corpo
	_mira.visible = acertou
	if not acertou:
		# Soltar o botão fora do painel evita deixar um clique preso.
		if _gatilho_antes:
			_gatilho_antes = false
		return

	var ponto := _raio.get_collision_point()
	_mira.global_position = ponto
	var local := _tela.global_transform.affine_inverse() * ponto
	var pos := _para_viewport(local)

	if pos != _ultimo_pos:
		var mover := InputEventMouseMotion.new()
		mover.position = pos
		mover.global_position = pos
		mover.relative = pos - _ultimo_pos if _ultimo_pos.x >= 0.0 else Vector2.ZERO
		_viewport.push_input(mover)
		_ultimo_pos = pos

	var gatilho := _controle.get_float(&"trigger") > 0.6
	if gatilho != _gatilho_antes:
		var clique := InputEventMouseButton.new()
		clique.button_index = MOUSE_BUTTON_LEFT
		clique.pressed = gatilho
		clique.position = pos
		clique.global_position = pos
		_viewport.push_input(clique)
		_gatilho_antes = gatilho


## Ponto no espaço local do quad -> pixel do SubViewport. O quad é centrado na
## origem e +Y aponta para cima; o viewport conta de cima para baixo.
func _para_viewport(local: Vector3) -> Vector2:
	var tam: Vector2 = (_tela.mesh as QuadMesh).size
	var u := (local.x / tam.x) + 0.5
	var v := 0.5 - (local.y / tam.y)
	return Vector2(
		clampf(u, 0.0, 1.0) * TemaVR.PAINEL.x,
		clampf(v, 0.0, 1.0) * TemaVR.PAINEL.y)


# ---------------------------------------------------------------------------
# Desktop: mouse direto no viewport, para iterar a UI sem headset
# ---------------------------------------------------------------------------
func entrada_desktop(evento: InputEvent) -> void:
	if _aberto:
		_viewport.push_input(evento)
