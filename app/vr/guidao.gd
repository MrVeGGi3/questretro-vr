class_name Guidao
extends RefCounted
## Converte a pose dos dois controles num par de eixos analógicos: segurar os
## Touch como o guidão de uma nave e inclinar para pilotar.
##
## A linha entre as duas mãos é a barra. Inclinar a barra (mão direita sobe,
## esquerda desce) rola; empurrar e puxar o ponto médio arfa.
##
## **Sem XR aqui dentro.** Entra `Transform3D`, sai `Vector2` — nada de
## `XRController3D` nem de nó de cena. Não é purismo: é o que deixa a conta ser
## verificada em `test_guidao.tscn` sem vestir o headset, e erro de sinal, de
## referencial ou de normalização é exatamente o tipo de coisa que passa
## despercebida numa sessão de VR e some num teste de trinta linhas.
##
## Tudo é medido no referencial de **guinada da câmera**, nunca no do mundo. Se
## o jogador virar o corpo, "para a direita" tem que continuar sendo à direita
## dele. É o erro clássico deste mapeamento, e o motivo de a câmera entrar em
## todas as chamadas em vez de a conta usar os eixos globais.

## Centro capturado por `centrar()`, no referencial da guinada de então. É a
## única coisa que a instância guarda; sem ele a conta seria pura de verdade.
var _centro := Vector3.ZERO
var _centrado := false

var angulo_max := 35.0      ## graus de inclinação da barra que valem eixo cheio
## Metros de empurra-e-puxa que valem eixo cheio. Bem menor que o palpite
## inicial de 25 cm: rolar 35° é coisa de pulso, mas empurrar 25 cm é esticar o
## braço inteiro, e a assimetria fazia a arfagem parecer lerda ao lado da
## rolagem. 12 cm cabe no cotovelo.
var curso := 0.12
var zona_morta := 0.08      ## abaixo disto, zero — mão parada não é mão firme
var inverter_y := false


## Marca a pose atual como o repouso. Chamar ao ligar o modo, ao carregar uma
## ROM e quando o jogador pedir: o centro depende de como ele está sentado, e
## não sobrevive nem a uma troca de cadeira.
func centrar(esq: Transform3D, dir: Transform3D, cam: Transform3D) -> void:
	_centro = _base(cam).inverse() * _meio(esq, dir)
	_centrado = true


## Eixos em [-1, 1]: x rola, y arfa. Convenção do libretro — y cresce para
## baixo —, a mesma que `xr_main._input_n64()` já aplica ao thumbstick.
func eixos(esq: Transform3D, dir: Transform3D, cam: Transform3D) -> Vector2:
	if not _centrado:
		# Sem centro não há "parado": qualquer pose viraria comando. Zero até
		# alguém calibrar é o único desfecho honesto.
		return Vector2.ZERO

	var base := _base(cam)
	# As mãos vistas de dentro do referencial do jogador. A partir daqui a
	# orientação do corpo dele não aparece mais na conta.
	var local_esq := base.inverse() * esq.origin
	var local_dir := base.inverse() * dir.origin
	var d := local_dir - local_esq

	# Rolagem: quanto a barra pende, comparada com o comprimento dela. Usar o
	# ângulo (e não a diferença de altura crua) faz o resultado não depender de
	# quão separadas as mãos estão.
	#
	# O sinal é negativo porque guidão gira como volante: para ir à **esquerda**
	# a mão direita sobe e a esquerda desce (giro anti-horário). Mão direita
	# acima, portanto, é comando de esquerda. Eu tinha escrito o contrário, e o
	# teste passava porque afirmava a mesma convenção errada — foi pilotando que
	# apareceu.
	var horizontal := Vector2(d.x, d.z).length()
	var rolagem := -rad_to_deg(atan2(d.y, horizontal))

	# Arfagem: o ponto médio afastando ou aproximando do corpo. -z é para
	# frente em Godot, então empurrar dá valor positivo aqui.
	var meio := base.inverse() * _meio(esq, dir)
	var arfagem := -(meio.z - _centro.z)

	var x := _normalizar(rolagem, angulo_max)
	var y := _normalizar(arfagem, curso)
	if inverter_y:
		y = -y
	return _com_zona_morta(Vector2(x, y))


## Base do jogador: só a guinada da câmera. Inclinar ou tombar a cabeça não pode
## mexer no comando — olhar para o instrumento não é pilotar.
func _base(cam: Transform3D) -> Transform3D:
	var frente := -cam.basis.z
	frente.y = 0.0
	if frente.length_squared() < 0.0001:
		# Cabeça apontada direto para cima ou para baixo: o "para frente" da
		# guinada some. O -y da base é o que mais se parece com frente aí.
		frente = -cam.basis.y
		frente.y = 0.0
		if frente.length_squared() < 0.0001:
			frente = Vector3.FORWARD
	frente = frente.normalized()
	# frente × up, nesta ordem: em coordenadas destras com -z para frente, o
	# produto invertido daria a esquerda.
	var direita := frente.cross(Vector3.UP).normalized()
	# Origem na câmera para o centro guardado ser relativo ao jogador, e não a
	# um ponto do quarto.
	return Transform3D(Basis(direita, Vector3.UP, -frente), cam.origin)


func _meio(esq: Transform3D, dir: Transform3D) -> Vector3:
	return (esq.origin + dir.origin) * 0.5


func _normalizar(valor: float, cheio: float) -> float:
	if cheio <= 0.0:
		return 0.0
	return clampf(valor / cheio, -1.0, 1.0)


## Zona morta radial, não por eixo: cortar eixo a eixo deixaria um quadrado de
## repouso, e a diagonal pequena escaparia por ele.
func _com_zona_morta(v: Vector2) -> Vector2:
	var mag := v.length()
	if mag <= zona_morta:
		return Vector2.ZERO
	# Reescala para a saída começar em zero na borda da zona morta, em vez de
	# saltar para o valor cheio assim que sai dela.
	return v.normalized() * minf((mag - zona_morta) / (1.0 - zona_morta), 1.0)
