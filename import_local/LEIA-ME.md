# Andaime de teste — não vai para o build

Esta pasta guarda assets extraídos da instalação local do Royal Crown
(`C:\Program Files (x86)\Steam\steamapps\common\Royal Crown`), para o
desenvolvedor conseguir **testar o motor vendo um personagem** em vez de uma
cápsula.

## O que é, e o que não é

- **Não é conteúdo do jogo.** São propriedade da LINE/Meerkat e não vão para o
  build, exatamente como as 113 tabelas XML de `C:\Godot\rc-referencia\xml\`.
- **Não entra no repositório.** O `.gitignore` desta pasta ignora tudo menos
  ele mesmo e este arquivo.
- **É temporário.** O caminho definitivo para personagem é Meshy + Mixamo, na
  Fase 6 (`docs/08-arte-e-assets.md`). Quando chegar, esta pasta some inteira.

## Como foi extraído

Os `.pak` de `RoyalCrown_Data/StreamingAssets/` são AssetBundles Unity
**sem criptografia** — a cifra DES-CBC registrada em `docs/05` era do conteúdo
XML dentro do bundle, não do bundle. `UnityPy` lê direto.

As malhas de personagem estão em `_prefabs.pak`, como `SkinnedMeshRenderer`.
Saíram Violet (corpo, corpo alternativo e cabeça); Leo, Morgan e Selkie
referenciam arquivos de outros bundles e exigem carregar a pasta inteira.

`_animation.pak` tem **1350 AnimationClips** com nomes legíveis
(`song_of_hope`, `throw`, `land`) e 93 controladores, um por personagem. As
DURAÇÕES deles são dado de timing, e essas sim poderiam informar o nosso
vocabulário sem trazer arte junto.

## Como sair daqui

Apagar a pasta. Nada em `scripts/` depende dela: a cena de teste que a usa é
`scenes/teste_local.tscn`, também ignorada, e `scenes/main.tscn` continua com o
boneco articulado nosso.
