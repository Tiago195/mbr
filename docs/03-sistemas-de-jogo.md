# 03 — Sistemas de Jogo

Este é o documento de design. Ele descreve **o que os sistemas precisam fazer**,
não como implementá-los.

---

## Princípio arquitetural central

> **Lógica de jogo não conhece render.**

Nenhuma classe de combate, atributo, habilidade ou item pode importar
`MeshInstance3D`, tocar em nó visual ou depender de câmera. Isso é o que permite:

1. Rodar a mesma lógica no servidor headless
2. Testar unitariamente sem abrir a engine
3. Trocar a camada visual sem reescrever regra

O nó visual **observa** o estado e desenha. Nunca decide.

---

## Sistema de atributos

### Atributos base

| Atributo | Descrição |
|---|---|
| `max_health` | Vida máxima |
| `health_regen` | Regeneração por segundo |
| `attack_damage` | Dano de ataque físico |
| `ability_power` | Poder de habilidade |
| `armor` | Redução de dano físico |
| `magic_resist` | Redução de dano mágico |
| `attack_speed` | Ataques por segundo |
| `attack_range` | Alcance do ataque básico |
| `move_speed` | Velocidade de movimento |
| `crit_chance` | Chance de acerto crítico (0.0–1.0) |
| `crit_damage` | Multiplicador do crítico (ex.: 1.75) |
| `lifesteal` | Fração do dano físico convertida em cura |
| `spell_vamp` | Fração do dano de habilidade convertida em cura |
| `cooldown_reduction` | Redução de tempo de recarga |

### Modificadores

Um atributo final é composto de várias fontes: base do personagem, nível,
itens equipados, buffs temporários, auras.

O sistema precisa suportar:

- **Modificador flat**: `+30 attack_damage`
- **Modificador percentual**: `+15% attack_damage`
- **Ordem de aplicação definida e documentada** (convenção usual: soma todos os
  flats, depois aplica os percentuais)
- **Origem rastreável**: cada modificador sabe de onde veio (item X, buff Y),
  para poder ser removido quando a fonte sai
- **Duração**: modificadores temporários expiram sozinhos
- **Stacking**: definir por modificador se acumula, e se tem limite de stacks

> Nota de implementação: recalcular o valor final a cada consulta é simples e
> correto; cachear com invalidação é mais rápido. Comece pelo simples.

---

## Cálculo de dano

Uma função pura. Entra situação, sai número.

```
calcular_dano(atacante, alvo, dano_bruto, tipo) -> resultado
```

### Etapas

1. **Dano bruto** — da fonte (ataque básico usa `attack_damage`, habilidade usa
   sua fórmula própria com escalonamento)
2. **Crítico** — sorteia contra `crit_chance`; se acertar, multiplica por
   `crit_damage`. *(Convenção a definir: crítico aplica-se a habilidades?)*
3. **Redução por defesa** — armadura contra físico, resistência mágica contra
   mágico. Fórmula usual de MOBA: `multiplicador = 100 / (100 + armor)`, que dá
   retornos decrescentes sem nunca chegar a imunidade
4. **Penetração** — se o atacante tiver, reduz a defesa efetiva antes do passo 3
5. **Modificadores de dano recebido/causado** — buffs, escudos
6. **Aplicação** — subtrai da vida; se houver escudo, consome escudo primeiro
7. **Retorno** — o resultado carrega: dano final, se foi crítico, quanto foi
   absorvido por escudo, se matou

### Roubo de vida

Calculado **sobre o dano final aplicado**, não sobre o bruto. `lifesteal` para
dano físico, `spell_vamp` para dano de habilidade.

### Tipos de dano

- `PHYSICAL` — reduzido por `armor`
- `MAGIC` — reduzido por `magic_resist`
- `TRUE` — ignora ambos

### Testabilidade

Este sistema é **lógica de negócio pura**. Deve ter cobertura de teste
unitário: dano com armadura zero, com armadura alta, crítico, escudo parcial,
dano verdadeiro, roubo de vida, morte exata.

O que consome tempo aqui **não é escrever, é balancear** — descobrir que 200 de
armadura deixa o jogo chato, que roubo de vida está quebrado. Isso é jogar,
ajustar, jogar de novo. Motivo a mais para ter o jogo de pé cedo.

---

## Sistema de habilidades

> **Este é o trabalho pesado do projeto.** Dezenas de sessões vão morar aqui.

### O insight que torna isso viável

**Habilidade número 40 custa uma fração da habilidade número 1** — desde que o
sistema seja construído para isso.

As dez primeiras habilidades são caras porque estão *inventando o sistema*.
Depois disso, se estiver bem feito, uma habilidade nova é um arquivo de
configuração de ~20 linhas.

> **Regra:** quando uma habilidade nova exigir escrever uma classe nova, o
> sistema está errado. Generalize antes de continuar.

### Habilidade como dado

Uma habilidade se declara, não se programa. A declaração combina peças de um
vocabulário fechado:

**Ativação**
- Custo (recurso, se houver), cooldown, tempo de conjuração
- Pode ser cancelada? Move-se durante a conjuração?

**Alvo** — como o jogador aponta
- `SELF` — sem mira
- `POINT` — clica num ponto do chão
- `DIRECTION` — aponta uma direção
- `UNIT` — clica num alvo
- Alcance máximo

**Forma** — a região que efetivamente atinge
- `CIRCLE` (raio)
- `CONE` (ângulo + alcance)
- `LINE` / `RECTANGLE` (largura + comprimento)
- `PROJECTILE` (velocidade, se atravessa ou para no primeiro alvo, se colide
  com parede)

**Filtro** — quem é afetado
- Inimigos, aliados, o próprio, mobs neutros
- Número máximo de alvos

**Efeitos** — uma lista, aplicada em ordem
- `DAMAGE` (valor base + escalonamento com atributo + tipo)
- `HEAL`
- `SHIELD` (valor + duração)
- `STAT_MOD` (qual atributo, quanto, duração)
- `CROWD_CONTROL` (stun, root, silence, slow — valor + duração)
- `DISPLACEMENT` (dash, knockback, pull — direção + distância)
- `SUMMON`
- `TRIGGER` (aplica um efeito condicional a um evento futuro)

Com esse vocabulário, a maioria das habilidades de um MOBA se expressa sem
código novo. As exceções — habilidades genuinamente únicas — ganham um efeito
customizado, e esse efeito passa a fazer parte do vocabulário.

### Estados e interações

O sistema precisa responder consistentemente a:

- O que acontece se o personagem é **stunado** durante a conjuração?
- Habilidades podem ser usadas **enquanto se move**?
- Uma habilidade **cancela** a anterior?
- O que tem **prioridade** quando dois efeitos conflitam (slow + speed boost)?

Definir essas regras **uma vez, no sistema** — não por habilidade.

### Fonte dos números

Não é preciso inventar valores nem kits: eles vêm das tabelas extraídas do jogo
original. Ver `05-extracao-dados-apk.md`.

---

## Sistema de itens

### Loot

- Itens espalhados pelo mapa em pontos de spawn
- Raridade / tiers
- Coletar → vai para o inventário

### Inventário

- Número limitado de slots
- Equipar / desequipar
- Ao equipar: adiciona modificadores de atributo com origem rastreável
- Ao desequipar: remove exatamente aqueles modificadores

### Efeitos além de atributo

Alguns itens fazem mais que somar número: efeito passivo, efeito ativo com
cooldown próprio. Isso reaproveita o mesmo vocabulário de efeitos das
habilidades — **não construa um segundo sistema paralelo**.

### Crafting

Fora do escopo da Fase 1. Mas o modelo de item deve prever combinação (item A +
item B = item C) para não exigir reescrita depois.

---

## Sistema de partida

### Zona

- Encolhe em fases, com tempo de aviso e tempo de encolhimento
- Dano por segundo a quem está fora, escalando por fase

### Mobs neutros

- Spawn em pontos definidos, dão recompensa ao morrer
- IA simples: alcance de agressão, perseguir, atacar, voltar ao ponto de origem
  se afastado demais

### Progressão dentro da partida

- XP e nível durante a partida (de mobs, de jogadores, de tempo)
- Nível aumenta atributos base e libera pontos de habilidade

### Condição de vitória

Último jogador (ou último time) vivo.
