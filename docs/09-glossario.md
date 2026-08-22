# 09 — Glossário

Termos de game dev que aparecem na documentação, traduzidos para quem vem de
desenvolvimento web/back-end.

---

## Engine e Godot

**Nó (Node)**
A unidade básica da Godot. Tudo é nó: um modelo 3D, uma câmera, uma luz, um
script. Nós formam uma árvore, e um nó filho herda a posição do pai.

**Cena (Scene)**
Uma árvore de nós salva em arquivo (`.tscn`). Funciona como um componente
reutilizável: pode ser instanciada várias vezes, ou aninhada dentro de outra
cena. Aproximação mental: um componente React, mas para objetos do mundo.

**Sinal (Signal)**
O mecanismo de eventos da Godot. Um nó emite, outros escutam. Equivale a um
event emitter.

**GDScript**
Linguagem própria da Godot, sintaxe parecida com Python. Indentação com Tab.

**Inspector**
O painel lateral onde se editam as propriedades do nó selecionado.

**`@export`**
Anotação que faz uma variável do script aparecer no Inspector, editável sem
tocar no código. Útil para ajustar valores enquanto o jogo roda.

**Headless**
Rodar a engine sem interface gráfica — o modo usado no servidor dedicado.

**Forward+ / Compatibility**
Os renderers da Godot 4. Forward+ usa Vulkan e pede GPU dedicada; Compatibility
usa OpenGL e roda em hardware fraco.

---

## Tempo e loop

**Frame**
Um quadro renderizado. A 60 FPS, 60 frames por segundo.

**Tick**
Um passo da simulação, com **intervalo fixo**. Diferente de frame, que varia
conforme a carga.

**`_process` vs `_physics_process`**
`_process` roda a cada frame (intervalo variável) — para visual.
`_physics_process` roda a cada tick (intervalo fixo) — para lógica de jogo.
Regra: se afeta o resultado do jogo, vai em `_physics_process`.

**Delta**
O tempo decorrido desde a última chamada. Multiplica-se movimento por delta para
o jogo se comportar igual em qualquer FPS.

---

## Espaço e colisão

**Raycast**
Lançar uma linha imaginária no espaço e descobrir o que ela atinge. Usado para
converter um clique 2D na tela em um ponto 3D no mundo, e para checar linha de
visão.

**Hitbox**
A região que define onde um personagem pode ser atingido. Geralmente mais
simples que o modelo visual.

**Colisor (CollisionShape)**
A forma usada para cálculo de colisão. Separada da malha visual — uma cápsula
invisível pode representar um personagem detalhado.

**NavMesh**
Malha de navegação: um mapa das áreas caminháveis, usado por pathfinding para
achar o caminho contornando obstáculos.

**Pathfinding**
O algoritmo que calcula a rota de A até B evitando paredes.

---

## Modelagem e animação

**Malha (Mesh)**
A geometria do objeto 3D — os vértices e faces.

**Topologia**
Como a malha é organizada internamente. Topologia limpa deforma bem ao animar;
topologia ruim gera artefatos.

**Rig / Rigging**
Colocar um "esqueleto" de ossos dentro do modelo, permitindo dobrar braços e
pernas.

**Skinning / Weight painting**
Definir quanto cada osso influencia cada parte da malha. É o que faz o cotovelo
dobrar de forma convincente.

**Máquina de animação (AnimationTree)**
O sistema que decide qual animação toca e como fazer a transição entre elas —
sair de "andar" para "atacar" sem dar tranco.

**PBR (Physically Based Rendering)**
Padrão de texturização com mapas separados para cor, rugosidade, metalicidade e
relevo.

**Low poly**
Modelo com poucos polígonos. Mais leve, e a estética funciona bem em jogo
estilizado.

**LOD (Level of Detail)**
Versões mais simples do modelo, usadas quando o objeto está longe da câmera.

---

## Rede

**Servidor autoritativo**
O servidor é a fonte da verdade. O cliente envia **intenção** ("quero ir para
X"), nunca resultado ("estou em X"). Impede cheat e evita divergência de estado.

**Predição de cliente (client-side prediction)**
O cliente simula o próprio movimento imediatamente, sem esperar o servidor, para
o comando parecer instantâneo. **Fora de escopo na Fase 1.**

**Reconciliação**
Quando a resposta do servidor discorda da predição do cliente, corrigir sem que
o jogador perceba um pulo. A parte complexa da predição.

**Interpolação**
Suavizar o movimento dos outros jogadores entre as atualizações recebidas. Sem
isso, com servidor a 20 ticks/s, tudo se move aos trancos. Barato e resolve
muito.

**Lag compensation**
Considerar o ping do jogador ao validar um acerto, para que mirar num alvo em
movimento funcione com ping alto.

**RPC (Remote Procedure Call)**
Chamar uma função que executa na outra ponta da conexão. O mecanismo básico de
rede da Godot.

**Tick rate**
Quantas vezes por segundo o servidor simula e envia estado. 20–30 é suficiente
para este tipo de jogo.

---

## Design de jogo

**Fatia vertical (vertical slice)**
Uma parte pequena do jogo, mas **completa de ponta a ponta**. O oposto de
construir cada sistema inteiro em paralelo.

**Kit**
O conjunto de habilidades de um personagem.

**Cooldown**
Tempo de recarga entre usos de uma habilidade.

**Cast time**
Tempo entre apertar o botão e a habilidade sair.

**Recovery**
Tempo depois da habilidade sair em que o personagem ainda não pode agir.

**CC (Crowd Control)**
Efeitos que limitam a ação do alvo: stun (atordoa), root (prende no lugar),
silence (impede habilidades), slow (reduz velocidade).

**Escalonamento (scaling / ratio)**
Quanto uma habilidade cresce com os atributos. "70 + 45% de AP" significa 70 de
base mais 45% do poder de habilidade.

**Kiting**
Atacar enquanto recua, mantendo distância do oponente corpo-a-corpo.

**Loot**
Itens espalhados pelo mapa para serem coletados.
