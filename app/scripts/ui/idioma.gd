class_name Idioma
extends RefCounted
## Qual língua o app fala, e como trocá-la.
##
## **O português é uma tradução como outra qualquer**, e não o texto embutido no
## código: as chaves ficam no `.text` dos Controls (`"MENU_ROMS"`) e o motor
## traduz na hora de desenhar. É isso que faz um terceiro idioma ser uma coluna a
## mais em `traducoes/ui.csv` em vez de uma refatoração — e que faz a troca valer
## sem reconstruir o menu, porque `auto_translate_mode` refaz o desenho sozinho
## quando o locale muda.
##
## O que o motor **não** alcança é string montada com `%`: aquilo é uma String
## comum depois de formatada. Quem usa formatação chama `tr()` e é redesenhado
## pelo `atualizar()` da página — ver `MenuRaiz`.

## Índices guardados em `ConfigEmu` na chave `app/idioma`. O `segmentado` grava
## inteiro, então a ordem aqui **é** o valor persistido: acrescentar idioma novo
## vai no fim, nunca no meio.
enum { AUTO, PT_BR, EN }

## Locale de cada índice. "" em AUTO significa "decidir pelo aparelho".
const LOCALES := ["", "pt_BR", "en"]

## O que aparece no seletor. Sem tradução de propósito: nome de idioma se escreve
## na própria língua, e é assim que alguém acha o seu numa lista que não lê.
const ROTULOS := ["Auto", "Português", "English"]

## Para onde AUTO cai quando o aparelho não fala nenhuma das nossas línguas.
const PADRAO := "en"


## Locale a usar de fato, resolvendo AUTO contra o idioma do aparelho.
static func locale_de(indice: int) -> String:
	if indice > AUTO and indice < LOCALES.size():
		return String(LOCALES[indice])
	return do_aparelho()


## Português se o Quest estiver em português, inglês em qualquer outro caso.
##
## `OS.get_locale()` devolve coisas como `pt_BR`, `pt_PT` ou `pt`; compará-las por
## igualdade erraria em duas das três. O que interessa é a língua, não a região —
## um Quest em `pt_PT` deve abrir em português.
static func do_aparelho() -> String:
	var lang := OS.get_locale_language()
	return "pt_BR" if lang == "pt" else PADRAO


## Aplica no motor. Chamado no arranque e a cada troca; é o único lugar que fala
## com o TranslationServer.
static func aplicar(indice: int) -> void:
	TranslationServer.set_locale(locale_de(indice))


## Índice a partir do que está guardado, tolerando valor fora da faixa — um
## `config.cfg` de versão futura, ou editado à mão, não deve deixar o app sem
## idioma nenhum.
static func indice_valido(valor: Variant) -> int:
	var i := int(valor)
	return i if i >= 0 and i < LOCALES.size() else AUTO
