class_name Sala
extends Node3D
## O ambiente em volta da tela do emulador.
##
## Três modos: **Vazio** (só a tela, o resto preto), **Fliperama** (um salão de
## arcade construído aqui, em geometria procedural) e **Passthrough** (o quarto
## de verdade, pelas câmeras do headset).
##
## Sem nenhuma dependência de XR, como `guidao.gd` e `mapa_input.gd`: entra um
## modo, sai uma árvore de nós. Isso é o que deixa o `test_sala` montar o salão
## inteiro e fotografá-lo sem headset nenhum — e o passthrough, que é a única
## parte que precisa falar com o OpenXR, sai daqui por `quer_transparencia()`
## para o `xr_main` executar.
##
## Tudo é construído **na troca de modo**, nunca por frame: o salão é estático,
## e reconstruí-lo a 72 Hz seria gastar CPU que a emulação precisa.
##
## Nada de luz em tempo real, sombra dinâmica ou glow: `project.godot` fixa
## `gl_compatibility` nos dois alvos, onde isso é caro ou não existe. O salão é
## unshaded com **cor por vértice** — a iluminação está pintada na malha, que num
## fliperama escuro é justamente o efeito que se quer.

enum { VAZIO, FLIPERAMA, PASSTHROUGH }

## Nomes na ordem do enum. A página de Sala mostra esta lista, então acrescentar
## um modo aqui e no enum é o que basta para ele aparecer no menu.
## Chaves de tradução: o `.text` do botão recebe a chave e o motor traduz.
const NOMES := ["SALA_VAZIO", "SALA_FLIPERAMA", "SALA_PASSTHROUGH"]

## Para o **log**, que não é traduzido: procurar por "Passthrough" no `logcat` é
## como se diagnostica isto, e uma linha que mudasse de língua com o idioma da
## interface tornaria toda instrução de diagnóstico dependente do aparelho.
const NOMES_LOG := ["Vazio", "Fliperama", "Passthrough"]

# --- Dimensões do salão -----------------------------------------------------
# Saem do alcance da tela, e não do que pareceria um fliperama plausível: a tela
# vai de portátil a cinema (`PagTela.ESCALA_MAX` × `LARGURA_BASE` = 11,2 m de
# largura, a até `DIST_MAX` = 8 m). Um salão de proporção realista teria a tela
# grande atravessando a parede do fundo já no ajuste médio.
const LARGURA := 18.0        ## X: de parede a parede
const FRENTE := 4.0          ## Z: parede atrás do jogador
const FUNDO := -14.0         ## Z: parede atrás da tela, além de DIST_MAX
const ALTURA := 6.0          ## Y: pé-direito, com o chão em y = 0

const CELULA := 1.5          ## lado do quadrado do carpete, em metros

## Afastamento do que é colado numa superfície (neon na parede, tela no
## gabinete). Coplanar, os dois disputam profundidade e o de trás pisca por cima
## — ou some de vez, que é o que aconteceu com o neon na primeira montagem.
const FOLGA := 0.03

# --- Paleta -----------------------------------------------------------------
const COR_FUNDO_SALAO := Color(0.015, 0.012, 0.03)
const CARPETE_A := Color(0.055, 0.03, 0.10)
const CARPETE_B := Color(0.085, 0.04, 0.14)
const COR_PAREDE_BASE := Color(0.03, 0.025, 0.06)   ## junto ao chão
const COR_PAREDE_TOPO := Color(0.10, 0.05, 0.18)    ## onde o neon bate
const COR_TETO := Color(0.01, 0.01, 0.02)
const NEON_CIANO := Color(0.2, 1.6, 1.9)
const NEON_MAGENTA := Color(1.9, 0.25, 1.2)
const COR_GABINETE := Color(0.045, 0.035, 0.075)
const COR_TELA_GABINETE := Color(0.35, 0.55, 1.1)

## Semente fixa: o salão precisa sair igual a cada arranque, senão o PNG de
## referência do teste mudaria sozinho e a comparação não valeria nada.
const SEMENTE := 20260728


var _modo := VAZIO
var _env: WorldEnvironment
var _geo: Node3D                ## raiz da geometria do modo; trocada inteira


func _init() -> void:
	_env = WorldEnvironment.new()
	_env.environment = Environment.new()
	add_child(_env)
	_aplicar_ambiente(VAZIO)


## Modo em uso.
func modo() -> int:
	return _modo


## Troca o ambiente. Desmonta o anterior inteiro e monta o novo — é a troca que
## custa, e ela acontece quando alguém toca no menu.
func aplicar(modo: int) -> void:
	if modo < 0 or modo >= NOMES.size():
		push_warning("Sala: modo desconhecido (%d), caindo no Vazio" % modo)
		modo = VAZIO
	_modo = modo

	if _geo != null:
		# free() e não queue_free(): a liberação diferida deixaria a árvore com a
		# geometria dos dois modos por um frame, e o teste que conta filhos para
		# achar vazamento não teria instante nenhum em que a conta fecha.
		remove_child(_geo)
		_geo.free()
		_geo = null

	_aplicar_ambiente(modo)

	if modo == FLIPERAMA:
		_geo = _montar_fliperama()
		add_child(_geo)


## Se este modo precisa que o fundo seja transparente para a imagem das câmeras
## aparecer. Quem sabe pedir isso ao OpenXR é o `xr_main` — aqui só se responde,
## e é por isso que esta classe continua rodando sem runtime de XR.
static func quer_transparencia(modo: int) -> bool:
	return modo == PASSTHROUGH


## Quantidade de nós de geometria no modo atual. O teste usa para afirmar que
## trocar de modo ida e volta não deixa nada para trás — um vazamento aqui só
## apareceria depois de muitas trocas, e no headset.
func nos_de_geometria() -> int:
	return 0 if _geo == null else _geo.get_child_count()


func _aplicar_ambiente(modo: int) -> void:
	var e := _env.environment
	e.background_mode = Environment.BG_COLOR
	match modo:
		PASSTHROUGH:
			# Alpha zero é o que abre buraco para a imagem das câmeras. Sozinho
			# não basta: o `xr_main` ainda precisa ligar `transparent_bg` no
			# viewport e pôr o OpenXR em alpha blend.
			e.background_color = Color(0, 0, 0, 0)
		FLIPERAMA:
			e.background_color = COR_FUNDO_SALAO
		_:
			# Preto puro, e não o quase-preto que a cena usava antes: no Vazio o
			# que se quer é que só a tela exista.
			e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.3, 0.35)


# ---------------------------------------------------------------------------
# O fliperama
# ---------------------------------------------------------------------------
## Um salão escuro com carpete, neon nas quinas altas e gabinetes encostados nas
## paredes laterais. Os gabinetes são uma malha só, e não um nó por gabinete:
## são dezenas de caixas, e no Quest o que pesa é a chamada de desenho, não o
## polígono.
func _montar_fliperama() -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Fliperama"

	# Um material para o salão inteiro: nada aqui usa textura, e o que separa
	# carpete de neon é a cor dos vértices. Seis cópias idênticas só dariam ao
	# renderizador seis motivos para trocar de estado à toa.
	var mat := _material()

	raiz.add_child(_no("Carpete", _malha_carpete(), mat))
	raiz.add_child(_no("Teto", _malha_teto(), mat))
	raiz.add_child(_no("Paredes", _malha_paredes(), mat))
	raiz.add_child(_no("Neon", _malha_neon(), mat))

	var gabinetes := _malhas_gabinetes()
	raiz.add_child(_no("Gabinetes", gabinetes[0], mat))
	raiz.add_child(_no("TelasGabinetes", gabinetes[1], mat))

	return raiz


## Unshaded com cor por vértice: a "iluminação" do salão está pintada na malha.
## Um material só serve a tudo porque nada aqui usa textura — o que varia de uma
## superfície para outra é a cor dos vértices.
func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m


func _no(nome: String, malha: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nome
	mi.mesh = malha
	mi.material_override = mat
	# Sem sombra: gl_compatibility no Quest não a daria de graça, e um salão
	# estático sem luz em tempo real não teria o que sombrear.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Carpete de fliperama: xadrez de dois tons, cada quadra com um desvio próprio
## de brilho. É o que dá textura ao chão sem carregar textura nenhuma — e o
## desvio importa: xadrez limpo lê como tabuleiro, e não como carpete gasto.
func _malha_carpete() -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMENTE

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x0 := -LARGURA * 0.5
	var colunas := int(LARGURA / CELULA)
	var linhas := int((FRENTE - FUNDO) / CELULA)

	for cx in colunas:
		for cz in linhas:
			var base := CARPETE_A if (cx + cz) % 2 == 0 else CARPETE_B
			var cor := base * rng.randf_range(0.75, 1.25)
			var ax := x0 + cx * CELULA
			var az := FUNDO + cz * CELULA
			# Anti-horário visto de cima: é de cima que se pisa nele.
			_quad(st, cor,
					Vector3(ax, 0, az),
					Vector3(ax, 0, az + CELULA),
					Vector3(ax + CELULA, 0, az + CELULA),
					Vector3(ax + CELULA, 0, az))

	return st.commit()


func _malha_teto() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := LARGURA * 0.5
	# Ordem invertida em relação ao chão: o teto é visto por baixo.
	_quad(st, COR_TETO,
			Vector3(-x, ALTURA, FUNDO),
			Vector3(x, ALTURA, FUNDO),
			Vector3(x, ALTURA, FRENTE),
			Vector3(-x, ALTURA, FRENTE))
	return st.commit()


## As quatro paredes, vistas por dentro. O gradiente de baixo para cima finge a
## luz do neon escorrendo pela parede — o efeito que uma luz de verdade daria, se
## gl_compatibility a desse barato.
func _malha_paredes() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := LARGURA * 0.5

	# Fundo (atrás da tela) e frente (atrás do jogador).
	_parede(st, Vector3(-x, 0, FUNDO), Vector3(x, 0, FUNDO))
	_parede(st, Vector3(x, 0, FRENTE), Vector3(-x, 0, FRENTE))
	# Laterais.
	_parede(st, Vector3(-x, 0, FRENTE), Vector3(-x, 0, FUNDO))
	_parede(st, Vector3(x, 0, FUNDO), Vector3(x, 0, FRENTE))

	return st.commit()


## Uma parede do chão ao teto, de `a` a `b` (ambos no nível do chão). A ordem de
## `a` para `b` decide para que lado ela olha.
func _parede(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var topo := Vector3(0, ALTURA, 0)
	_quad_gradiente(st, COR_PAREDE_BASE, COR_PAREDE_TOPO,
			a, b, b + topo, a + topo)


## Fitas de neon: uma faixa contínua na quina alta das quatro paredes, e tiras
## verticais nos cantos. Ciano no fundo e nas laterais, magenta atrás do jogador
## — duas cores porque uma só, num salão inteiro, lê como iluminação de emergência.
func _malha_neon() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := LARGURA * 0.5 - FOLGA
	var zf := FUNDO + FOLGA
	var zt := FRENTE - FOLGA
	var y := ALTURA - 0.45
	var esp := 0.12

	# Faixa horizontal em três lados, em ciano.
	_fita(st, NEON_CIANO, Vector3(-x, y, zf), Vector3(x, y, zf), esp)
	_fita(st, NEON_CIANO, Vector3(-x, y, zt), Vector3(-x, y, zf), esp)
	_fita(st, NEON_CIANO, Vector3(x, y, zf), Vector3(x, y, zt), esp)
	# E magenta atrás do jogador, que é o que se vê ao virar o corpo.
	_fita(st, NEON_MAGENTA, Vector3(x, y, zt), Vector3(-x, y, zt), esp)

	# Montantes verticais nos quatro cantos, do chão à faixa. Cada um é um **L**:
	# uma aba na parede de X e outra na de Z. Não é capricho — é o que um tubo
	# de neon dobrado num canto faz, e resolve o canto ser visto tanto de frente
	# quanto de lado sem depender de qual das duas abas está virada para você.
	for canto: Vector3 in [Vector3(-x, 0, zf), Vector3(x, 0, zf),
			Vector3(-x, 0, zt), Vector3(x, 0, zt)]:
		var cor := NEON_MAGENTA if canto.z == zt else NEON_CIANO
		# Do canto para o centro do salão, em cada eixo.
		var dentro := Vector3(-signf(canto.x) * esp, 0, -signf(canto.z) * esp)
		var pe := canto + Vector3(0, 0.2, 0)
		var topo := Vector3(0, y - 0.2, 0)
		var so_x := Vector3(dentro.x, 0, 0)
		var so_z := Vector3(0, 0, dentro.z)
		# Cada aba olha para o centro pelo eixo perpendicular a ela.
		_quad_para(st, cor, pe, pe + so_x, pe + so_x + topo, pe + topo,
				Vector3(0, 0, dentro.z))
		_quad_para(st, cor, pe, pe + so_z, pe + so_z + topo, pe + topo,
				Vector3(dentro.x, 0, 0))

	return st.commit()


## Fita horizontal de `a` a `b`, virada para dentro do salão. Fica afastada da
## parede por `FOLGA`: coplanar com ela, o neon disputa profundidade e some —
## que foi exatamente o que a primeira foto do salão mostrou.
func _fita(st: SurfaceTool, cor: Color, a: Vector3, b: Vector3, esp: float) -> void:
	var alto := Vector3(0, esp, 0)
	_quad(st, cor, a, b, b + alto, a + alto)


## Gabinetes de arcade encostados nas duas paredes laterais. Devolve duas
## malhas: os corpos e as telas — separadas porque a tela é a única parte
## acesa, e uma malha por gabinete seria dezenas de chamadas de desenho.
func _malhas_gabinetes() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEMENTE + 1

	var corpos := SurfaceTool.new()
	corpos.begin(Mesh.PRIMITIVE_TRIANGLES)
	var telas := SurfaceTool.new()
	telas.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x := LARGURA * 0.5 - 0.45   # meia profundidade do gabinete
	var z := FUNDO + 1.5
	while z < FRENTE - 1.5:
		# Um vão de vez em quando: uma fileira sem falha lê como parede, não
		# como fliperama.
		if rng.randf() > 0.22:
			_gabinete(corpos, telas, Vector3(-x, 0, z), 1, rng)
		if rng.randf() > 0.22:
			_gabinete(corpos, telas, Vector3(x, 0, z), -1, rng)
		z += 1.1

	return [corpos.commit(), telas.commit()]


## Um gabinete: uma caixa e uma tela acesa na face que olha para o corredor.
## `lado` é +1 para a parede da esquerda (a face olha para +X) e -1 para a
## direita.
func _gabinete(corpos: SurfaceTool, telas: SurfaceTool, pe: Vector3, lado: int,
		rng: RandomNumberGenerator) -> void:
	var alt := rng.randf_range(1.6, 1.9)
	var larg := 0.75      # ao longo do corredor (Z)
	var prof := 0.9       # da parede para o corredor (X)
	var cor := COR_GABINETE * rng.randf_range(0.8, 1.3)

	var meia := larg * 0.5
	var face := pe.x + prof * 0.5 * lado      # X da frente do gabinete
	var costas := pe.x - prof * 0.5 * lado

	# O sentido em Z que deixa a frente virada para o corredor depende de qual
	# parede é: percorrido num sentido só, o mesmo desenho dá normal +X numa
	# fileira e -X na outra, e uma das duas seria cullada inteira — o salão
	# pareceria ter gabinetes de um lado só.
	var z0 := pe.z + meia * lado
	var z1 := pe.z - meia * lado
	var recuo := signf(z1 - z0) * 0.1     # encolhe a tela para dentro do corpo

	# Frente e topo, os dois lados que se veem do corredor. As faces contra a
	# parede não entram: ninguém as vê, e cada uma seria polígono pago em todo
	# frame.
	_quad(corpos, cor,
			Vector3(face, 0, z0), Vector3(face, 0, z1),
			Vector3(face, alt, z1), Vector3(face, alt, z0))
	_quad(corpos, cor * 1.25,
			Vector3(face, alt, z0), Vector3(face, alt, z1),
			Vector3(costas, alt, z1), Vector3(costas, alt, z0))

	# A tela, à frente da face pela mesma FOLGA do neon: colada nela, as duas
	# disputariam profundidade.
	var tx := face + FOLGA * lado
	var brilho := rng.randf_range(0.45, 1.0)
	_quad(telas, COR_TELA_GABINETE * brilho,
			Vector3(tx, alt - 0.95, z0 + recuo),
			Vector3(tx, alt - 0.95, z1 - recuo),
			Vector3(tx, alt - 0.35, z1 - recuo),
			Vector3(tx, alt - 0.35, z0 + recuo))


# ---------------------------------------------------------------------------
# Primitivas
# ---------------------------------------------------------------------------
## Quad de cor única, em dois triângulos.
##
## **Convenção**: `a→b→c→d` na ordem anti-horária vista do lado que se quer
## enxergar — a regra da mão direita, com a normal apontando para quem olha.
##
## Não é o que o motor pede: o Godot trata **winding horário** como face
## frontal, então esta função inverte a ordem ao emitir. Isso está medido, não
## deduzido — um quad em anti-horário visto da câmera sai cullado. Vale a
## inversão aqui para os quinze pontos de construção lá em cima poderem ser
## lidos pela regra da mão direita, que é como se pensa a geometria.
##
## Nada de `CULL_DISABLED` para escapar disso: desenhar as duas faces de um
## salão inteiro seria pagar o dobro por superfícies que ninguém vê de trás, e
## esconderia a face invertida em vez de corrigi-la.
func _quad(st: SurfaceTool, cor: Color, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	_quad_gradiente(st, cor, cor, a, b, c, d)


## Quad emitido com a face visível olhando para `olhar`, seja qual for a ordem
## em que os cantos chegaram.
##
## Existe porque a ordem certa depende de qual parede o pedaço está, e conferir
## isso à mão em cada canto do salão foi como metade dos montantes de neon saiu
## faltando: geometria presente, invisível, e sem erro nenhum no console. Onde a
## orientação vem de uma conta em vez de uma posição escrita à mão, é esta que
## se usa.
func _quad_para(st: SurfaceTool, cor: Color, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, olhar: Vector3) -> void:
	if (b - a).cross(c - a).dot(olhar) >= 0.0:
		_quad(st, cor, a, b, c, d)
	else:
		_quad(st, cor, a, d, c, b)


## Quad com cor de baixo (`a`, `b`) diferente da de cima (`c`, `d`).
func _quad_gradiente(st: SurfaceTool, baixo: Color, cima: Color, a: Vector3,
		b: Vector3, c: Vector3, d: Vector3) -> void:
	for canto in [[a, baixo], [c, cima], [b, baixo], [a, baixo], [d, cima], [c, cima]]:
		st.set_color(canto[1])
		st.add_vertex(canto[0])
