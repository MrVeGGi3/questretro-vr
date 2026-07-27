extends Node
## Prova a conta do guidão sem headset nenhum. É aritmética pura, então roda em
## `--headless` (ao contrário do test_troca_rom, que precisa de GPU):
##
##   godot --headless --xr-mode off --path app res://test_guidao.tscn
##
## Roda como cena e não com `-s` pelo mesmo motivo do test_ui: script de
## MainLoop trava na inicialização com a GDExtension carregada.
##
## O caso que mais importa aqui é o do corpo girado. Um referencial errado
## (usar os eixos do mundo em vez da guinada da câmera) passa despercebido em
## qualquer teste feito de frente — e é assim que se testa no headset, de pé,
## olhando para a tela. Aqui ele não escapa.

## Meia distância entre as mãos ao segurar a barra. As poses de teste são
## montadas a partir dela.
const MEIA_BARRA := 0.2

var _falhas := 0


func _ready() -> void:
	_nivelado_e_centrado_da_zero()
	_inclinar_a_barra_rola()
	_empurrar_e_puxar_arfa()
	_inverter_y_troca_so_o_y()
	_corpo_girado_nao_muda_nada()
	_cabeca_inclinada_nao_muda_nada()
	_satura_em_um()
	_zona_morta_e_exatamente_zero()
	_sem_centrar_nao_comanda()
	_curva_rende_mais_no_comeco()
	_curva_nao_tira_alcance()
	_curva_nao_entorta_a_diagonal()

	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


func _nivelado_e_centrado_da_zero() -> void:
	var g := _guidao()
	var p := _pose()
	g.centrar(p.esq, p.dir, p.cam)
	_perto(g.eixos(p.esq, p.dir, p.cam), Vector2.ZERO, "barra nivelada e no centro dá zero")


func _inclinar_a_barra_rola() -> void:
	var g := _guidao()
	var p := _pose()
	g.centrar(p.esq, p.dir, p.cam)

	# Guidão gira como volante: mão direita sobe e esquerda desce é o giro
	# anti-horário, ou seja, comando de **esquerda** (-x). A primeira versão
	# afirmava o contrário aqui, e passava — o teste estava errado junto com o
	# código, e só pilotar revelou.
	var d := _pose(0.0, deg_to_rad(20.0))
	var dir_cima := g.eixos(d.esq, d.dir, d.cam)
	_verdade(dir_cima.x < -0.4, "direita acima da esquerda vira para a esquerda, -x (deu %.2f)" % dir_cima.x)

	# E o espelho tem que dar o oposto, com a mesma força.
	var e := _pose(0.0, deg_to_rad(-20.0))
	var esq_cima := g.eixos(e.esq, e.dir, e.cam)
	_perto(Vector2(esq_cima.x, 0), Vector2(-dir_cima.x, 0), "inclinação espelhada dá x espelhado")


func _empurrar_e_puxar_arfa() -> void:
	var g := _guidao()
	var p := _pose()
	g.centrar(p.esq, p.dir, p.cam)

	var frente := _pose(-0.15)
	var tras := _pose(0.15)
	var y_frente := g.eixos(frente.esq, frente.dir, frente.cam).y
	var y_tras := g.eixos(tras.esq, tras.dir, tras.cam).y
	_verdade(y_frente > 0.3, "empurrar dá +y (deu %.2f)" % y_frente)
	_verdade(y_tras < -0.3, "puxar dá -y (deu %.2f)" % y_tras)


func _inverter_y_troca_so_o_y() -> void:
	var p := _pose(-0.15, deg_to_rad(20.0))

	var normal := _guidao()
	normal.centrar(_pose().esq, _pose().dir, _pose().cam)
	var a := normal.eixos(p.esq, p.dir, p.cam)

	var invertido := _guidao()
	invertido.inverter_y = true
	invertido.centrar(_pose().esq, _pose().dir, _pose().cam)
	var b := invertido.eixos(p.esq, p.dir, p.cam)

	_perto(Vector2(b.x, b.y), Vector2(a.x, -a.y), "inverter_y troca só o y")


## O teste que justifica a câmera entrar na conta.
func _corpo_girado_nao_muda_nada() -> void:
	var de_frente := _pose(-0.12, deg_to_rad(18.0))
	var g1 := _guidao()
	g1.centrar(_pose().esq, _pose().dir, _pose().cam)
	var esperado := g1.eixos(de_frente.esq, de_frente.dir, de_frente.cam)

	# Mesma pose relativa, o jogador inteiro girado. Não é só a câmera: as mãos
	# giram junto, porque o corpo girou.
	for graus in [90.0, -90.0, 180.0, 37.0]:
		var girado := _pose(-0.12, deg_to_rad(18.0), deg_to_rad(graus))
		var g2 := _guidao()
		var zero := _pose(0.0, 0.0, deg_to_rad(graus))
		g2.centrar(zero.esq, zero.dir, zero.cam)
		_perto(g2.eixos(girado.esq, girado.dir, girado.cam), esperado,
				"corpo girado %d° dá o mesmo comando" % int(graus))


func _cabeca_inclinada_nao_muda_nada() -> void:
	var p := _pose(-0.12, deg_to_rad(18.0))
	var g := _guidao()
	g.centrar(_pose().esq, _pose().dir, _pose().cam)
	var esperado := g.eixos(p.esq, p.dir, p.cam)

	# Mesma guinada, cabeça olhando para baixo e tombada: não é comando.
	var cam := Transform3D(Basis.from_euler(
			Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(15.0))), p.cam.origin)
	_perto(g.eixos(p.esq, p.dir, cam), esperado, "inclinar a cabeça não vira comando")


func _satura_em_um() -> void:
	var g := _guidao()
	g.centrar(_pose().esq, _pose().dir, _pose().cam)
	# Muito além do ângulo e do curso cheios.
	var p := _pose(-1.5, deg_to_rad(80.0))
	var v := g.eixos(p.esq, p.dir, p.cam)
	_verdade(v.length() <= 1.0001, "não passa de 1 no módulo (deu %.3f)" % v.length())
	# Direita levantada e mãos empurradas: esquerda (-x, ver a convenção de
	# volante acima) e para cima (+y).
	_verdade(v.x < -0.6 and v.y > 0.6, "satura para o canto certo (%.2f, %.2f)" % [v.x, v.y])


func _zona_morta_e_exatamente_zero() -> void:
	var g := _guidao()
	g.centrar(_pose().esq, _pose().dir, _pose().cam)
	# Um tremor de mão: 1° de inclinação e 5 mm de curso.
	var p := _pose(-0.005, deg_to_rad(1.0))
	_perto(g.eixos(p.esq, p.dir, p.cam), Vector2.ZERO, "tremor dentro da zona morta dá zero exato")


func _sem_centrar_nao_comanda() -> void:
	var g := _guidao()
	var p := _pose(-0.15, deg_to_rad(20.0))
	_perto(g.eixos(p.esq, p.dir, p.cam), Vector2.ZERO, "sem centrar, pose nenhuma comanda")


## A promessa da curva: meio caminho de movimento rende mais que meio eixo.
func _curva_rende_mais_no_comeco() -> void:
	var meio := _pose(-0.06)     # pouco menos de meio curso

	var linear := _guidao()
	linear.centrar(_pose().esq, _pose().dir, _pose().cam)
	var y_linear := linear.eixos(meio.esq, meio.dir, meio.cam).y

	var agressiva := _guidao()
	agressiva.curva = 2.0
	agressiva.centrar(_pose().esq, _pose().dir, _pose().cam)
	var y_agressiva := agressiva.eixos(meio.esq, meio.dir, meio.cam).y

	_verdade(y_agressiva > y_linear + 0.1,
			"curva 2.0 rende mais no começo (%.2f contra %.2f)" % [y_agressiva, y_linear])

	var fina := _guidao()
	fina.curva = 0.5
	fina.centrar(_pose().esq, _pose().dir, _pose().cam)
	var y_fina := fina.eixos(meio.esq, meio.dir, meio.cam).y
	_verdade(y_fina < y_linear - 0.1,
			"curva 0.5 rende menos no começo (%.2f contra %.2f)" % [y_fina, y_linear])


## Curva nenhuma pode custar alcance: no fim do curso o eixo tem que chegar
## cheio, senão mexer nela viraria uma nave que não vira direito.
func _curva_nao_tira_alcance() -> void:
	for c in [0.5, 1.0, 2.0, 3.0]:
		var g := _guidao()
		g.curva = c
		g.centrar(_pose().esq, _pose().dir, _pose().cam)
		var longe := _pose(-1.0)
		var y := g.eixos(longe.esq, longe.dir, longe.cam).y
		_verdade(y > 0.99, "curva %.1f ainda alcança o eixo cheio (deu %.3f)" % [c, y])


## A curva é radial. Aplicada eixo a eixo, ela mudaria a proporção entre x e y
## e a diagonal sairia torta — a nave viraria mais do que subiria num gesto que
## pede os dois igualmente.
func _curva_nao_entorta_a_diagonal() -> void:
	var p := _pose(-0.08, deg_to_rad(15.0))

	var linear := _guidao()
	linear.centrar(_pose().esq, _pose().dir, _pose().cam)
	var a := linear.eixos(p.esq, p.dir, p.cam)

	var curvada := _guidao()
	curvada.curva = 2.5
	curvada.centrar(_pose().esq, _pose().dir, _pose().cam)
	var b := curvada.eixos(p.esq, p.dir, p.cam)

	_verdade(b.length() > a.length() + 0.05, "a curva de fato mudou o módulo")
	_verdade(absf(a.angle() - b.angle()) < 0.01,
			"e manteve a direção (%.3f rad contra %.3f)" % [a.angle(), b.angle()])


# ---------------------------------------------------------------------------
# Montagem das poses
# ---------------------------------------------------------------------------
## Um jogador segurando a barra. `avanco` empurra as mãos para frente (metros,
## negativo é para frente em Godot), `tombo` inclina a barra (radianos, positivo
## levanta a direita) e `guinada` gira o jogador inteiro — corpo, cabeça e mãos.
func _pose(avanco := 0.0, tombo := 0.0, guinada := 0.0) -> Dictionary:
	var altura := Vector3(0.0, 1.2, 0.0)          # mãos na altura do peito
	var frente := Vector3(0.0, 0.0, -0.35)        # braços à frente do corpo
	var meia := Vector3(MEIA_BARRA, 0.0, 0.0)

	# A barra tomba em torno do eixo que aponta para frente do jogador.
	var giro_barra := Basis(Vector3.FORWARD, -tombo)
	var esq := altura + frente + giro_barra * -meia + Vector3(0, 0, avanco)
	var dir := altura + frente + giro_barra * meia + Vector3(0, 0, avanco)

	var giro := Basis(Vector3.UP, guinada)
	var olho := Vector3(0.0, 1.6, 0.0)
	return {
		"esq": Transform3D(Basis(), giro * esq),
		"dir": Transform3D(Basis(), giro * dir),
		"cam": Transform3D(giro, giro * olho),
	}


## Parâmetros do teste, fixados de propósito em vez de herdados do produto.
##
## As poses daqui foram escolhidas para cair na faixa linear destes valores. Se
## o teste usasse os padrões de `Guidao`, baixar o curso (como foi feito depois
## que alguém pilotou e achou a arfagem lerda) faria o y saturar em ±1 — e aí os
## casos de corpo girado passariam comparando 1.0 com 1.0, sem poder de pegar
## erro nenhum no eixo y. O teste ficaria verde e cego ao mesmo tempo.
func _guidao() -> Guidao:
	var g := Guidao.new()
	g.angulo_max = 35.0
	g.curso = 0.25
	g.zona_morta = 0.08
	return g


# ---------------------------------------------------------------------------
# Asserções
# ---------------------------------------------------------------------------
func _perto(deu: Vector2, esperado: Vector2, o_que: String) -> void:
	if deu.distance_to(esperado) < 0.02:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s — esperava (%.3f, %.3f), deu (%.3f, %.3f)" % [
			o_que, esperado.x, esperado.y, deu.x, deu.y])
		_falhas += 1


func _verdade(ok: bool, o_que: String) -> void:
	if ok:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s" % o_que)
		_falhas += 1
