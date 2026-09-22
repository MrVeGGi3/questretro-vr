extends Node
## Prova da sala sem headset: monta cada modo, fotografa o fliperama de dentro e
## afirma o que uma foto não mostraria.
##
##   xvfb-run -a godot --xr-mode off --path app res://cenas/test_sala.tscn
##   # -> user://sala_*.png
##
## Precisa de um renderizador de verdade (o headless não desenha em textura), e
## o `--xr-mode off` não é opcional: o projeto liga OpenXR, e sem runtime ativo
## o Godot trava no arranque sob Xvfb sem imprimir nada.
##
## A `Sala` roda aqui inteira porque não depende de XR — é o mesmo motivo pelo
## qual `guidao.gd` e `mapa_input.gd` têm teste de desktop. O que **não** dá para
## afirmar daqui é se o passthrough sobe no aparelho: isso é headset, e está
## registrado em `docs/EXPORT.md`.

## De onde a câmera olha o salão, e para onde. Duas vistas porque cada uma pega
## um erro diferente: a do jogador mostra o que se vê jogando, e a de cima
## mostra as paredes e o carpete inteiros — uma parede virada para fora some da
## primeira e salta na segunda.
const VISTAS := {
	"jogador": [Vector3(0, 1.6, 1.0), Vector3(0, 1.5, -6.0)],
	"alto": [Vector3(6.0, 4.5, 3.0), Vector3(0, 1.0, -6.0)],
}

const TAM_FOTO := Vector2i(960, 720)

## Quantas conferências este arquivo faz quando roda inteiro. Existe porque um
## erro de compilação em `sala.gd` derruba cada chamada a `Sala` **sem**
## derrubar o teste: as asserções simplesmente não acontecem, e o final imprimia
## "TUDO OK" com o salão sem compilar. Zero falha só vale alguma coisa junto com
## a conta de quantas passaram.
const CONFERENCIAS := 54

## Os métodos de `XRInterface` que o `xr_main` usa para ligar o passthrough.
## Nomes, e não chamadas: sem runtime de XR não há o que chamar aqui.
const API_BLEND := [
	"get_supported_environment_blend_modes",
	"set_environment_blend_mode",
]

var _falhas := 0
var _feitas := 0


func _ready() -> void:
	_testar_api_de_blend()
	_testar_transparencia()
	_testar_geometria_por_modo()
	_testar_troca_nao_vaza()
	_testar_determinismo()
	_testar_cabe_a_tela()
	_testar_persistencia()
	await _testar_centrar_tela()
	await _testar_rotulo_legivel()
	await _testar_rotulo_expira()
	await _fotografar()

	if _feitas != CONFERENCIAS:
		print("  FALHA rodaram %d conferências, esperava %d — veja se algum "
				% [_feitas, CONFERENCIAS] + "SCRIPT ERROR passou acima")
		_falhas += 1

	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


## Que os métodos de blend que o `xr_main` chama **existam**.
##
## Parece trivial e não é: o passthrough só roda com runtime de XR, então nada
## no desktop exercita aquele caminho, e uma chamada a método inexistente chega
## ao headset intacta. Foi o que aconteceu — `is_environment_blend_mode_supported`
## não existe no Godot 4.6.3, e o erro só apareceu depois de export, sideload e
## uma sessão de headset. Perguntar ao ClassDB custa um milissegundo e não
## precisa de XR nenhum, porque a assinatura é da classe e não do aparelho.
## Centralizar a tela: a conta da guinada, exercitada na cena de verdade.
##
## O modo de falhar aqui é de sinal: com a guinada trocada a tela vai parar
## **atrás** de quem centralizou, e de dentro do headset isso não se lê como
## "coordenada invertida" e sim como "a tela sumiu" — não há erro, não há log, e
## o reflexo é procurar o defeito na emulação. Daí valer asserção mesmo sendo
## quatro linhas de trigonometria.
##
## Roda sem XR: a âncora é escrita à mão, que é o que a câmera faria.
func _testar_centrar_tela() -> void:
	var cena: Node3D = load("res://cenas/vr_main.tscn").instantiate()
	add_child(cena)
	await get_tree().process_frame
	await get_tree().process_frame

	for graus in [0.0, 90.0, -90.0, 179.0]:
		cena._ancora_pos = Vector3(2.0, 0.0, -3.0)
		cena._ancora_guinada = deg_to_rad(graus)
		cena._sala.position = cena._ancora_pos
		cena._sala.rotation = Vector3(0.0, cena._ancora_guinada, 0.0)
		cena._posicionar_tela()

		var frente := Basis(Vector3.UP, cena._ancora_guinada) * Vector3.FORWARD
		var da_ancora: Vector3 = cena._tela.global_position - cena._ancora_pos
		da_ancora.y = 0.0
		_conferir(da_ancora.normalized().dot(frente) > 0.99,
				"a %.0f° a tela fica à frente da âncora" % graus)

		var dist: float = cena._cfg.obter("tela/distancia")
		_conferir(absf(da_ancora.length() - dist) < 0.01,
				"a %.0f° a distância é a pedida (%.2f de %.2f m)" % [graus, da_ancora.length(), dist])

		# +Z da malha é a face visível; ela tem de apontar de volta para a âncora.
		var normal: Vector3 = cena._tela.global_transform.basis.z.normalized()
		_conferir(normal.dot(-frente) > 0.99,
				"a %.0f° a tela encara a âncora" % graus)

	_conferir(cena._sala.position == cena._ancora_pos,
			"a sala acompanha a âncora (senão a tela entra na parede do salão)")

	# A outra metade: a guinada saindo da **câmera**, que é onde o erro de sinal
	# de fato moraria. O bloco acima escreve a âncora à mão e não exercita isso.
	# `_xr_ativo` à mão porque no desktop a captura sai cedo — o que se testa aqui
	# é a trigonometria, e ela não sabe se há headset.
	cena._xr_ativo = true
	for graus in [0.0, 45.0, 90.0, -135.0]:
		var olhando := Vector3(sin(deg_to_rad(graus)) * -1.0, 0.0, -cos(deg_to_rad(graus)))
		cena._camera.global_transform = Transform3D(
				Basis.looking_at(olhando, Vector3.UP), Vector3(1.0, 1.6, 4.0))
		cena._centrar_tela()
		var frente: Vector3 = Basis(Vector3.UP, cena._ancora_guinada) * Vector3.FORWARD
		_conferir(frente.dot(olhando.normalized()) > 0.99,
				"a guinada capturada a %.0f° aponta para onde a câmera olhava" % graus)
		var p: Vector3 = cena._ancora_pos
		_conferir(is_equal_approx(p.x, 1.0) and is_equal_approx(p.z, 4.0) and is_zero_approx(p.y),
				"a %.0f° a âncora pega a posição da câmera, e zera a altura" % graus)

	cena.queue_free()
	await get_tree().process_frame


## O rótulo abaixo da tela continua do mesmo tamanho **aparente**, e continua à
## vista, em toda a barra de distância e de escala.
##
## Nasceu de um relato de dentro do headset ("a letra embaixo da tela é pequena
## demais para ler", pior no Quest 2 e piorando ao deslizar a tela para frente e
## para trás). A causa era `pixel_size` fixo, que é tamanho fixo **em metros**: o
## olho lê ângulo, e o mesmo texto a 8,0 m ocupa um décimo do ângulo que ocupava a
## 0,8 m. Nenhum teste podia pegar isso antes porque nenhum media ângulo — e no
## desktop, a uma distância só, os dois comportamentos são idênticos.
##
## Roda sem XR, como o `_testar_centrar_tela` acima: a conta é geometria, e não
## sabe se há headset. O que ele **não** afirma é onde fica o limite do legível —
## isso é pixels por grau do aparelho, e é medição de headset.
func _testar_rotulo_legivel() -> void:
	var cena: Node3D = load("res://cenas/vr_main.tscn").instantiate()
	add_child(cena)
	await get_tree().process_frame
	await get_tree().process_frame

	# A configuração é a do usuário (o `carregar()` do arranque), e o teste mexe
	# nela: guardar e devolver, senão rodar o teste muda a tela de quem joga.
	var dist_antes: float = cena._cfg.obter("tela/distancia")
	var escala_antes: float = cena._cfg.obter("tela/escala")

	cena._ancora_pos = Vector3.ZERO
	cena._ancora_guinada = 0.0
	var olhos := Vector3(0.0, cena._altura_olhos(), 0.0)

	var angulos: Array[float] = []
	var tombos: Array[float] = []
	for dist: float in [PagTela.DIST_MIN, 2.2, PagTela.DIST_MAX]:
		for escala: float in [PagTela.ESCALA_MIN, 1.5, PagTela.ESCALA_MAX]:
			cena._cfg.definir("tela/distancia", dist)
			cena._cfg.definir("tela/escala", escala)
			cena._posicionar_tela()
			var ate_olhos: float = cena._label.global_position.distance_to(olhos)
			# Tamanho aparente: metros por pixel divididos pela distância. É o que
			# o olho recebe, e é o que tem de ser constante.
			angulos.append(cena._label.pixel_size / ate_olhos)
			var do_olho: Vector3 = cena._label.global_position - olhos
			var queda := -do_olho.y
			do_olho.y = 0.0
			tombos.append(rad_to_deg(atan2(queda, do_olho.length())))

	var menor: float = angulos.min()
	var maior: float = angulos.max()
	_conferir(maior / menor < 1.01,
			"o tamanho aparente do rótulo não muda com distância nem escala (%.1f%% de variação em %d combinações)"
					% [(maior / menor - 1.0) * 100.0, angulos.size()])

	var pior: float = tombos.max()
	_conferir(pior <= cena.LABEL_TOMBO_MAX + 0.5,
			"o rótulo nunca desce mais que o limite abaixo da linha dos olhos (%.1f° de %.1f°)"
					% [pior, cena.LABEL_TOMBO_MAX])

	# Tela pequena: o limite não pode ter virado um piso que descola o rótulo da
	# borda de baixo. A conta aqui é a mesma do `_posicionar_label`, de propósito
	# — o que se afirma é que o limite **não pegou**.
	cena._cfg.definir("tela/distancia", 2.2)
	cena._cfg.definir("tela/escala", PagTela.ESCALA_MIN)
	cena._posicionar_tela()
	var razao: float = cena._cfg.aspecto_como_razao(cena._aspecto_nativo)
	var meia: float = (cena.LARGURA_BASE / razao) * PagTela.ESCALA_MIN * 0.5
	var colado: float = cena._tela.global_position.y - (meia + 0.12)
	_conferir(absf(cena._label.global_position.y - colado) < 0.001,
			"em tela pequena ele continua colado na borda de baixo")

	# E o caso que motivou o limite: a maior tela na menor distância, onde a
	# borda de baixo fica 4,2 m abaixo do centro — ou seja, enterrada.
	cena._cfg.definir("tela/distancia", PagTela.DIST_MIN)
	cena._cfg.definir("tela/escala", PagTela.ESCALA_MAX)
	cena._posicionar_tela()
	_conferir(cena._label.global_position.y > 0.3,
			"e na maior tela mais perto ele para antes do chão (%.2f m)"
					% cena._label.global_position.y)

	cena._cfg.definir("tela/distancia", dist_antes)
	cena._cfg.definir("tela/escala", escala_antes)
	cena.queue_free()
	await get_tree().process_frame


func _testar_rotulo_expira() -> void:
	var cena: Node3D = load("res://cenas/vr_main.tscn").instantiate()
	add_child(cena)
	await get_tree().process_frame
	await get_tree().process_frame

	# O caminho de verdade, e não `_mostrar` direto: o que quebrou foi a
	# confirmação de centralizar, e é por `_centrar_tela` que ela passa nos três
	# lugares que a disparam (clique do analógico, botão do menu e tecla C).
	cena._centrar_tela(cena.tr("XR_TELA_CENTRADA"))
	_conferir(cena._label.visible, "a confirmação de centralizar aparece")

	cena._expirar_rotulo(cena.MSG_SEGUNDOS - 0.5)
	_conferir(cena._label.visible, "e continua lá antes do prazo vencer")

	cena._expirar_rotulo(0.6)
	_conferir(not cena._label.visible and cena._label.text.is_empty(),
			"e some sozinha quando o prazo vence (%.1f s)" % cena.MSG_SEGUNDOS)

	# A outra metade, que é o motivo de o prazo ser opcional: erro do core e a
	# ajuda de "sem ROM" descrevem estado, e apagá-los deixaria a pessoa sem o
	# que ler — no headset não há log para consultar depois.
	cena._mostrar("Falha ao carregar a ROM: qualquer coisa")
	cena._expirar_rotulo(60.0)
	_conferir(cena._label.visible, "mensagem sem prazo fica, por mais que o tempo passe")

	# Chave crua na tela é o defeito que a página Input acabou de consertar; o
	# rótulo 3D não passa pelo teste de UI, então a conferência mora aqui.
	var cruas := 0
	for chave in ["XR_TELA_CENTRADA", "XR_GUIDAO_CENTRADO", "XR_PASSTHROUGH_VAZIO"]:
		if cena.tr(chave) == chave:
			cruas += 1
	_conferir(cruas == 0, "as três mensagens do rótulo têm tradução (%d cruas)" % cruas)

	cena.queue_free()
	await get_tree().process_frame


func _testar_api_de_blend() -> void:
	for metodo: String in API_BLEND:
		_conferir(ClassDB.class_has_method("XRInterface", metodo),
				"XRInterface.%s() existe nesta versão do Godot" % metodo)

	# O modo em si: com o enum errado o passthrough sairia aditivo, que no Quest
	# é outra coisa (e mais barata de confundir do que parece).
	_conferir(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND == 2,
			"ALPHA_BLEND continua sendo 2")
	_conferir(XRInterface.XR_ENV_BLEND_MODE_OPAQUE == 0,
			"OPAQUE continua sendo 0")


## Só o passthrough pede fundo transparente, e o Environment do modo tem de
## acompanhar: alpha 1 aqui daria um preto opaco onde deveria entrar a imagem
## das câmeras — e no headset isso pareceria "o passthrough não ligou".
func _testar_transparencia() -> void:
	_conferir(Sala.quer_transparencia(Sala.PASSTHROUGH), "passthrough pede transparência")
	_conferir(not Sala.quer_transparencia(Sala.VAZIO), "vazio não pede")
	_conferir(not Sala.quer_transparencia(Sala.FLIPERAMA), "fliperama não pede")

	var sala := Sala.new()
	add_child(sala)
	sala.aplicar(Sala.PASSTHROUGH)
	var e := _ambiente(sala)
	_conferir(e != null and e.background_color.a == 0.0,
			"no passthrough o fundo fica com alpha 0")

	sala.aplicar(Sala.VAZIO)
	e = _ambiente(sala)
	_conferir(e != null and e.background_color.a == 1.0 and e.background_color.r == 0.0,
			"no vazio o fundo volta a preto opaco")
	sala.queue_free()


func _testar_geometria_por_modo() -> void:
	var sala := Sala.new()
	add_child(sala)

	sala.aplicar(Sala.VAZIO)
	_conferir(sala.nos_de_geometria() == 0, "vazio não constrói geometria")

	sala.aplicar(Sala.PASSTHROUGH)
	_conferir(sala.nos_de_geometria() == 0,
			"passthrough não constrói geometria (o quarto é o de verdade)")

	sala.aplicar(Sala.FLIPERAMA)
	_conferir(sala.nos_de_geometria() > 0, "fliperama constrói geometria")
	# Poucas chamadas de desenho é requisito, não gosto: no Quest a CPU já está
	# ocupada emulando, e cada MeshInstance é uma chamada a mais por olho.
	_conferir(sala.nos_de_geometria() <= 8,
			"o salão cabe em até 8 malhas (é %d)" % sala.nos_de_geometria())

	var vazios := _malhas_vazias(sala)
	_conferir(vazios.is_empty(), "nenhuma malha do salão sai vazia (%s)" % str(vazios))

	sala.queue_free()


## Trocar de modo ida e volta não pode deixar nada para trás. Um vazamento aqui
## só apareceria depois de muitas trocas, no headset, como queda de fps sem
## causa aparente — e é exatamente o que ninguém liga a um menu de ambiente.
func _testar_troca_nao_vaza() -> void:
	var sala := Sala.new()
	add_child(sala)

	sala.aplicar(Sala.VAZIO)
	var base := sala.get_child_count()

	for i in 5:
		sala.aplicar(Sala.FLIPERAMA)
		sala.aplicar(Sala.PASSTHROUGH)
		sala.aplicar(Sala.VAZIO)

	_conferir(sala.get_child_count() == base,
			"15 trocas de modo não somam filhos (%d, base %d)" % [sala.get_child_count(), base])

	sala.aplicar(Sala.FLIPERAMA)
	var com_salao := sala.get_child_count()
	sala.aplicar(Sala.FLIPERAMA)
	_conferir(sala.get_child_count() == com_salao,
			"reaplicar o mesmo modo não empilha um segundo salão")

	sala.queue_free()


## O salão sai da mesma semente todo arranque. Sem isso o PNG de referência
## mudaria sozinho a cada execução e a comparação não valeria nada.
func _testar_determinismo() -> void:
	var a := Sala.new()
	var b := Sala.new()
	add_child(a)
	add_child(b)
	a.aplicar(Sala.FLIPERAMA)
	b.aplicar(Sala.FLIPERAMA)

	var iguais := true
	for i in a.nos_de_geometria():
		var ma := (a.get_node("Fliperama").get_child(i) as MeshInstance3D).mesh
		var mb := (b.get_node("Fliperama").get_child(i) as MeshInstance3D).mesh
		if ma.get_aabb() != mb.get_aabb():
			iguais = false
	_conferir(iguais, "duas salas saem idênticas (semente fixa)")

	a.queue_free()
	b.queue_free()


## O salão é dimensionado a partir do alcance da tela, e não do que pareceria um
## fliperama plausível — senão a tela grande atravessaria a parede do fundo já
## no ajuste médio. Esta é a asserção que segura isso quando alguém "arrumar" as
## proporções do salão.
func _testar_cabe_a_tela() -> void:
	_conferir(-Sala.FUNDO > PagTela.DIST_MAX,
			"a parede do fundo fica além da distância máxima da tela (%.1f > %.1f)"
					% [-Sala.FUNDO, PagTela.DIST_MAX])

	# A tela no preset Cinema, que é o maior tamanho que o menu oferece por
	# botão (o slider vai além, e aí a saída honesta é o modo Vazio).
	var largura_cinema: float = 1.4 * PagTela.PREDEFINICOES["TELA_PRE_CINEMA"][0]
	_conferir(Sala.LARGURA > largura_cinema,
			"o salão é mais largo que a tela no Cinema (%.1f > %.1f)"
					% [Sala.LARGURA, largura_cinema])


func _testar_persistencia() -> void:
	var cfg := ConfigEmu.new()
	add_child(cfg)
	cfg.definir("sala/modo", Sala.FLIPERAMA)
	cfg.salvar()

	var relido := ConfigEmu.new()
	relido.carregar()
	_conferir(int(relido.obter("sala/modo")) == Sala.FLIPERAMA, "o modo persiste")

	relido.restaurar("sala")
	_conferir(int(relido.obter("sala/modo")) == Sala.VAZIO,
			"restaurar devolve o Vazio, que é o padrão")
	relido.free()

	# O modo é preferência de quem joga, não do cartucho: se cair no perfil, o
	# ambiente passaria a trocar sozinho ao mudar de jogo.
	_conferir(not "sala/modo".begins_with(ConfigEmu.PERFIL_PREFIXO),
			"sala/modo fica fora do perfil do cartucho")

	cfg.queue_free()
	DirAccess.remove_absolute(ConfigEmu.ARQUIVO)


## As fotos. "Ficou escuro demais", "a parede está virada para fora" e "o carpete
## virou um xadrez de tabuleiro de xadrez" são coisas que nenhuma asserção pega
## e a imagem entrega de relance.
func _fotografar() -> void:
	var vp := SubViewport.new()
	vp.size = TAM_FOTO
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var sala := Sala.new()
	vp.add_child(sala)
	sala.aplicar(Sala.FLIPERAMA)

	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true

	for nome in VISTAS:
		var v: Array = VISTAS[nome]
		cam.global_position = v[0]
		cam.look_at(v[1])
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var img := vp.get_texture().get_image()
		var arquivo := "user://sala_%s.png" % nome
		img.save_png(arquivo)
		print("SALVO ", arquivo, " ", img.get_width(), "x", img.get_height())
		# Uma foto toda preta é o desfecho provável de um erro de normal ou de
		# câmera, e passaria despercebida num arquivo que ninguém abre.
		_conferir(_fracao_acesa(img) > 0.02,
				"a vista '%s' não saiu preta (%.1f%% acesa)" % [nome, _fracao_acesa(img) * 100.0])

	vp.queue_free()


## Fração de pixels visivelmente acima do preto.
func _fracao_acesa(img: Image) -> float:
	var acesos := 0
	# Amostra a cada 4 px nos dois eixos: 16x menos leitura, e o que se quer
	# saber é se há imagem, não quantos pixels exatos.
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).get_luminance() > 0.02:
				acesos += 1
	var total := (img.get_height() / 4) * (img.get_width() / 4)
	return float(acesos) / float(total)


func _ambiente(sala: Sala) -> Environment:
	for filho in sala.get_children():
		if filho is WorldEnvironment:
			return (filho as WorldEnvironment).environment
	return null


## Nomes das malhas do salão que saíram sem nenhum vértice — o desfecho de um
## laço de construção que não rodou, e que a foto só mostraria se por acaso a
## câmera estivesse apontada para a peça faltando.
func _malhas_vazias(sala: Sala) -> Array:
	var vazias: Array = []
	var raiz := sala.get_node_or_null("Fliperama")
	if raiz == null:
		return ["Fliperama"]
	for filho in raiz.get_children():
		var mi := filho as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0 \
				or mi.mesh.surface_get_array_len(0) == 0:
			vazias.append(filho.name)
	return vazias


func _conferir(condicao: bool, descricao: String) -> void:
	_feitas += 1
	if condicao:
		print("  ok   ", descricao)
	else:
		print("  FALHA ", descricao)
		_falhas += 1
