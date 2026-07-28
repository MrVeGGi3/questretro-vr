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
const CONFERENCIAS := 24

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
	var largura_cinema: float = 1.4 * PagTela.PREDEFINICOES["Cinema"][0]
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
