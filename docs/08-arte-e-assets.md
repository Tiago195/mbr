# 08 — Arte e Assets

> **Só é relevante na Fase 6.** Até lá, cápsulas e formas primitivas.
> Fazer arte antes de o jogo provar que é divertido é a forma mais comum de
> matar um projeto pequeno.

---

## O princípio

**Consistência do personagem vem do 3D, não da IA.**

Geradores de imagem 2D são péssimos em coerência quadro a quadro — cada imagem é
gerada do zero, sem "lembrar" da anterior. Pede-se oito frames de um ciclo de
caminhada e vêm oito personagens *parecidos*: o cinto muda de posição, a cor do
cabelo oscila, um detalhe da armadura some.

A solução não é uma IA melhor. É **gerar o personagem uma vez, em 3D, e animar o
esqueleto**. Assim a consistência não é *mantida* — é estruturalmente impossível
de quebrar, porque é a mesma malha em todos os frames.

Analogia: um boneco de ação em cem poses diferentes é obviamente o mesmo boneco,
porque literalmente é.

---

## Pipeline

### 1. Concept 2D

Gerar a arte do personagem numa IA de imagem: **pose T ou A, vista de frente,
fundo neutro**. Iterar até gostar. Etapa barata e rápida.

### 2. Imagem → 3D

| Ferramenta | Nota |
|---|---|
| **Meshy** | Pipeline mais completo num lugar só; auto-rigging nativo |
| **Tripo** | Rápido, boa reconstrução image-to-3D; rigging separado |
| **Rodin (Hyper3D)** | Mais detalhe, foco em objeto hero |

Para personagens estilizados vistos de cima em isométrico, os defeitos típicos
dessas ferramentas (mão feia, detalhe borrado) praticamente somem — a câmera
está longe.

Usar o **Low Poly Mode** do Meshy (ou equivalente), que dá topologia limpa com
contagem de polígonos controlada.

### 3. Rig + animação

Duas opções:

- **Auto-rig do Meshy/Tripo** — no mesmo fluxo
- **Mixamo** (Adobe, gratuito) — exportar FBX, subir lá. Auto-rig humanoide
  funciona bem em bípede estilizado, e a biblioteca de ciclos prontos (andar,
  correr, pular, atacar) é enorme

Mixamo continua sendo o melhor custo-benefício para indie.

### 4. Ajuste no Blender

Quando precisar de algo específico (uma habilidade, um cast). Aqui se anima à
mão, mas **sobre um rig que já existe** — ordens de magnitude mais barato que
animar do zero.

---

## Regra crítica: um rig só

> **Definir altura, proporção e esqueleto padrão ANTES de gerar o primeiro
> personagem, e forçar todos a caberem nele.**

Assim uma animação serve para os 15 personagens, e adicionar personagem novo
custa quase nada.

Se cada um vier com esqueleto próprio do auto-rig, o trabalho de animação é
multiplicado por 15. **Esse é o erro que mais atrasa projeto pequeno.**

---

## Integração com Claude Code via MCP

### Meshy — MCP oficial

Servidor MCP open source, publicado no npm como `@meshy-ai/meshy-mcp-server`,
mantido pela própria Meshy. Cerca de 20 ferramentas: geração texto/imagem→3D,
remesh, retextura, rigging, animação, gerenciamento de tarefas.

As duas mais relevantes aqui: `meshy_rig` (adiciona esqueleto a humanoide) e
`meshy_animate` (aplica animação a personagem riggado).

Instalação no Claude Code:

```bash
claude mcp add meshy -- npx -y @meshy-ai/meshy-mcp-server -e MESHY_API_KEY=SUA_CHAVE
```

Existe também `add-mcp`, que detecta os clientes de IA instalados na máquina e
configura em todos de uma vez.

Alternativa mais leve: o skill pack `meshy-3d-agent`, com workflows Meshy
pré-escritos, sem precisar rodar servidor MCP.

**Detalhes operacionais:**
- Modelos gerados via MCP **não aparecem no workspace web** da Meshy — trabalha-
  se com os links de download
- Essas URLs **expiram em ~3 dias**. Baixar logo
- Gerações via MCP consomem créditos da conta igual ao app web

### BlenderMCP

Conecta o Blender ao Claude via MCP: modelagem e manipulação de cena por prompt.
Inclui integração com PolyHaven (texturas, HDRIs), Sketchfab e geração via
Hyper3D Rodin.

Útil quando for preciso ajustar algo no Blender sem saber onde clicar.

**Ressalva honesta:** a integração é confiável para formas primitivas,
posicionamento, cenas com múltiplos objetos e materiais básicos, mas tem
dificuldade com geometria orgânica complexa, dimensões precisas e **rigging**.

Ou seja: rigging fica com a Meshy; BlenderMCP para ajustes e cena.

### Ordem de instalação

Instalar **só o Meshy MCP primeiro** e fazer um personagem de teste. Se
funcionar bem, aí adicionar o BlenderMCP. Instalar os dois de uma vez, sem saber
o que cada um resolve, costuma virar duas coisas quebradas em vez de uma
funcionando.

---

## Custos

O MCP é encanamento, não passe livre: a assinatura do Claude paga o Claude; os
créditos Meshy pagam os modelos.

Custos por operação são baixos: rig = 5 créditos, animate = 3, remesh = 5,
convert = 1. O tier gratuito dá para fazer o primeiro personagem inteiro sem
pagar nada.

**Licenciamento:** no tier gratuito do Meshy os modelos ficam **públicos sob CC
BY 4.0** — qualquer um pode usar e é preciso creditar se publicar. Para projeto
entre amigos, irrelevante. Se um dia virar algo sério, migrar para o plano pago
**antes** de gerar os assets definitivos, não depois.

**Segurança:** tratar a API key como segredo — quem tiver acesso gera contra o
saldo da conta. Variável de ambiente, nunca dentro do repositório.

---

## Alternativa considerada e descartada

**3D renderizado para sprite sheet** (o método de Diablo 2 e Ragnarok): modelo
3D animado, cada frame renderizado de um ângulo isométrico fixo, gerando sprites
2D. Consistência garantida pela origem 3D, visual 2D, custo de runtime baixo.

Descartado aqui porque o jogo tem câmera que gira um pouco e personagens que
precisam olhar em 360° — manter 3D de verdade é mais simples que renderizar 8 ou
16 direções de cada animação.
