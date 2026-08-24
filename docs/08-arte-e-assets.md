# 08 — Arte e assets

> **A arte deste projeto é gerada por código, no Blender, dentro deste
> repositório.** Não há serviço externo, não há marketplace, não há
> auto-rigging de terceiro. O que o jogo consome é `.glb` produzido por script.

---

## A decisão, e quando ela foi tomada

**24/08/2026, pelo usuário**, com estas palavras:

> *"esquece meshy/mixamo, baixei o blender, vc vai gerar tudo q a gente precisa
> nele, pode remover qualquer espectativa de meshy/mixamo"*

Este documento tinha 160 linhas descrevendo um pipeline que não existe mais:
concept 2D numa IA de imagem → Meshy ou Tripo para virar 3D → auto-rig da Meshy
ou do Mixamo → ajuste no Blender, com servidores MCP, créditos e prazos de
expiração de URL. Nada disso vale. Ver a decisão 24 em
`docs/02-decisoes-tecnicas.md`.

**Também não é mais "só na Fase 6".** O pipeline antigo era adiado porque
dependia de gastar dinheiro num jogo que ainda não provou ser divertido. Um
gerador que roda local não tem esse custo, então ele já está em uso — e o boneco
de teste é o primeiro artefato dele, não um andaime que será jogado fora.

---

## O que isso ganha, e é a razão de a troca não ser só de fornecedor

**Consistência do personagem vem do 3D, não da IA.** Esse princípio continua
valendo e é por isso que o caminho é 3D e não sprite: gerar o personagem uma vez
e animar o esqueleto torna a coerência quadro a quadro *estruturalmente*
impossível de quebrar, porque é a mesma malha em todos os frames.

O que muda é de onde a malha vem, e o ganho é este:

1. **Toda medida tem origem.** Um modelo comprado tem as proporções que tem; um
   gerado tem as proporções que alguém escreveu. Se elas saírem de uma medição
   do original — e saem, ver `docs/11-direcao-de-arte.md` —, a conferência pode
   reprovar quando o modelo sai da direção. Não dá para conferir um `.fbx`
   baixado contra nada.
2. **Regenerar é barato.** Mudar a altura do elenco inteiro é editar uma
   constante e rodar de novo, em dez segundos. No caminho antigo era refazer o
   personagem e o rigging.
3. **Um rig só, por construção.** A regra crítica abaixo deixa de depender de
   disciplina e passa a ser consequência: todos os personagens saem do mesmo
   `OSSOS`.
4. **O artefato é conferível.** `tools/conferir_numeros.py` lê o `.glb`
   commitado em Python puro e o compara com o código que diz tê-lo gerado. Foi
   assim que se descobriu, uma vez, que o `.glb` no repositório **não vinha do
   gerador no repositório**.

---

## Regra crítica: um rig só

> **Definir altura, proporção e esqueleto padrão ANTES de gerar o primeiro
> personagem, e forçar todos a caberem nele.**

Assim uma animação serve para todos os personagens, e acrescentar personagem
novo custa quase nada. Se cada um vier com esqueleto próprio, o trabalho de
animação é multiplicado pelo número de personagens — **é o erro que mais atrasa
projeto pequeno.**

No caminho gerado isto não é um cuidado, é uma propriedade: o esqueleto está em
`OSSOS`, em `tools/arte/gerar_personagem.py`, e não há outro.

---

## As ferramentas, e o que cada uma responde

Todas rodam **headless**, sem abrir a interface do Blender, e nenhuma depende de
rede.

| Ferramenta | Pergunta que ela responde |
|---|---|
| `tools/arte/censo_do_original.py` | *Quais são os números da referência?* Mede proporção, ritmo, vocabulário e esbeltez nos bundles da instalação da Steam e grava `data/direcao-de-arte.json`. **Números e estrutura entram; asset não.** |
| `tools/arte/gerar_personagem.py` | *Como esses números viram um corpo?* Monta esqueleto, malha e animações e exporta `arte/personagem.glb`. |
| `tools/arte/conferir_personagem.py` | *O corpo saiu dentro da direção?* Proporção, esbeltez, duração, fechamento de ciclo e pé no chão. O gerador o chama sozinho e **só publica se passar**. |
| `tools/arte/renderizar_previa.py` | *Como isso fica na tela?* Folhas de contato em `arte/previa/`, uma por animação. É a única que responde à pergunta que nenhuma medição responde. |
| `tools/conferir_numeros.py` | *O artefato commitado veio deste código?* Lê o `.glb` sem o Blender. |
| `tools/arte/mutar_boneco.py`, `tools/mutar_direcao.py` | *As conferências acima conferem alguma coisa?* Quebram de propósito e exigem vermelho. |

Como rodar cada uma está na seção "Como conferir que nada quebrou" do
`CLAUDE.md`.

---

## O que ainda não está resolvido

**Textura.** Hoje cada região tem uma cor chapada, e o contraste entre elas é
escolhido para a silhueta ler de longe — não há UV, não há mapa, não há
material. Quando houver, ele também deve ser gerado.

**Malha contínua.** O boneco de teste é montado como um sólido por osso, e
sólidos independentes pendurados num esqueleto **se atravessam**: medido em
repouso, oito pares de peças se cruzam sem serem vizinhas, e a mão fica enterrada
na coxa. Um personagem é uma superfície contínua, onde membro e tronco se
encontram na junta. É o próximo trabalho.

**Variação entre personagens.** A Fase 1 declara um modelo para todos. O caminho
gerado torna a variação barata — trocar proporções e cores por campeão é
parâmetro —, mas nada disso existe ainda.

---

## O que NÃO entra neste repositório

Continua valendo `docs/01-visao-e-escopo.md`: do Royal Crown entram **números e
estrutura**, nunca arte, som, código ou texto. O censo mede os bundles da
instalação da Steam e escreve `data/direcao-de-arte.json`; nenhum byte de malha,
textura ou animação do original é copiado, e o repositório não contém asset
extraído de lugar nenhum.
