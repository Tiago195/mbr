# 07 — Primeira Cena (Fase 1.1)

> **Recomendação: faça esta etapa à mão, sem IA.** São ~30 minutos e dá o modelo
> mental da engine. Sem isso não há como revisar com critério o que a IA escreve
> depois.

> **Aviso:** a Godot 4.7 é mais nova que o conhecimento de treino do assistente
> que escreveu isto. Nomes de menu podem ter mudado ligeiramente. Se algo não
> bater, descreva o que está na tela.

## Objetivo

Uma cápsula que anda num plano ao clicar no chão. Câmera isométrica.

Cobre quatro conceitos: cena e nó, script ligado a nó, conversão de clique em
ponto do mundo (raycast), e movimento de corpo com colisão.

---

## Montando a cena

### 1. Nó raiz

Criar cena → **3D Scene** (cria um `Node3D`). Renomear para `Main` (F2).

### 2. O chão

Com `Main` selecionado, `+` na aba Scene → `StaticBody3D`.

Adicionar dois filhos a ele:

- **`MeshInstance3D`** → no Inspector, campo **Mesh** → `New PlaneMesh` →
  clicar nela → Size = `20 x 20`
- **`CollisionShape3D`** → campo **Shape** → `New WorldBoundaryShape3D`
  *(cria um chão infinito — mais simples que ajustar tamanho)*

### 3. O jogador

`Main` selecionado → `+` → `CharacterBody3D`. Renomear para `Player`.

Dois filhos:

- **`MeshInstance3D`** → Mesh → `New CapsuleMesh`
- **`CollisionShape3D`** → Shape → `New CapsuleShape3D`

A cápsula nasce metade enterrada. No Inspector do `Player`, em
**Transform → Position**, definir **Y = 1**.

### 3b. Indicador de direção

Uma cápsula é simétrica — sem isto, é impossível ver para onde o personagem
está virado, e um bug de orientação passa despercebido.

Adicionar um terceiro filho ao `Player`: **`MeshInstance3D`** → Mesh →
`New BoxMesh` → Size = `(0.2, 0.2, 0.6)`. No Transform desse nó,
Position = `(0, 0, -0.7)`.

O **-Z é a frente** na convenção da Godot (`Vector3.FORWARD`), por isso o Z
negativo. Renomear para `FrontMarker`.

### 4. Câmera

`Main` selecionado → `+` → `Camera3D`.

- Position: `(0, 12, 8)`
- Rotation X: `-55`

Esse é o ângulo isométrico. Para conferir, usar o botão **Preview** que aparece
no canto da viewport quando a câmera está selecionada.

### 5. Luz

`Main` selecionado → `+` → `DirectionalLight3D`. Rotation X = `-45`.

Sem isso, tudo fica cinza chapado.

**Salvar** (Ctrl+S).

---

## O script

Botão direito no `Player` → **Attach Script** → Create. Apagar o conteúdo padrão
e usar:

```gdscript
extends CharacterBody3D

@export var speed: float = 5.0
@export var arrival_threshold: float = 0.2

var target_position: Vector3

func _ready() -> void:
	target_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.is_pressed() \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera == null:
			return
		var ray_origin: Vector3 = camera.project_ray_origin(event.position)
		var ray_dir: Vector3 = camera.project_ray_normal(event.position)
		var ground := Plane(Vector3.UP, global_position.y)
		var hit: Variant = ground.intersects_ray(ray_origin, ray_dir)
		if hit is Vector3:
			target_position = hit

func _physics_process(_delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	if to_target.length() > arrival_threshold:
		velocity = to_target.normalized() * speed
		look_at(global_position + to_target, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()
```

**F5** para rodar. Vai pedir para definir a cena principal — escolher a que foi
salva.

---

## O que está acontecendo

### `_unhandled_input` — o raycast

O clique dá um ponto **2D** na tela. A câmera converte isso numa **linha** que
entra na cena em 3D (`project_ray_origin` dá o ponto de partida,
`project_ray_normal` dá a direção).

Cruza-se essa linha com um **plano** na altura do chão, e o resultado é onde no
mundo o jogador clicou.

Essa é exatamente a mecânica de movimento do Royal Crown, e vai ser reusada para
mira de habilidade na Fase 3.

### `_physics_process` — o tick

Roda 60 vezes por segundo com **intervalo fixo**. É o "tick" que aparece na
discussão de servidor autoritativo em `02-decisoes-tecnicas.md`.

Toda lógica de jogo vive aqui. `_process`, que roda a cada frame renderizado com
intervalo variável, fica só para visual e interpolação.

### `look_at` — a convenção de frente

Assinatura completa: `look_at(target, up, use_model_front = false)`.

Por padrão ele rotaciona o nó de modo que o eixo **-Z local** (`Vector3.FORWARD`)
aponte para o alvo. Por isso o argumento é `global_position + to_target`: o
ponto **à frente** do personagem. Usar `- to_target` faria o personagem andar de
costas — parece funcionar, porque a cápsula é simétrica, e é exatamente por isso
que o `FrontMarker` existe.

Se um dia o modelo importado vier orientado ao contrário (alguns pipelines
autoram o personagem virado para +Z), o terceiro argumento resolve:
`look_at(alvo, Vector3.UP, true)`.

`look_at` emite erro se a posição do alvo for igual à do nó, se o vetor `up` for
zero, ou se a direção for paralela ao `up`. A guarda do `arrival_threshold`
cobre o primeiro caso; como `to_target.y` é zerado e `up` é `Vector3.UP`, os
outros dois não ocorrem aqui.

### Duas armadilhas evitadas de propósito

**`if hit is Vector3` em vez de `if hit:`** — `intersects_ray` devolve `Vector3`
ou `null`. Mas em GDScript um `Vector3.ZERO` avalia como **falso**. Com
`if hit:`, clicar exatamente na origem do mundo seria silenciosamente ignorado.
Bug raro, difícil de diagnosticar, e gratuito de evitar.

**`_delta` com underscore** — o parâmetro não é usado neste script, e a Godot
emite aviso de parâmetro não utilizado. O underscore silencia o aviso sem
desabilitá-lo globalmente.

---

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Erro estranho ao colar o script | Indentação com espaço em vez de **Tab** |
| Cápsula afunda no chão | `Position.Y` do Player não foi definido como 1 |
| Tudo cinza chapado | Faltou o `DirectionalLight3D` |
| Nada aparece ao rodar | Cena principal não definida, ou câmera fora de posição |
| Cápsula não se move | Script anexado no nó errado (tem que ser no `Player`) |
| `FrontMarker` aponta para trás do movimento | Sinal trocado no `look_at` |
| Cápsula atravessa o chão e cai infinitamente | `WorldBoundaryShape3D` invertido, ou `CollisionShape3D` sem Shape |
| Erro "look_at() failed" no console | Alvo igual à posição — `arrival_threshold` baixo demais |

---

## Status de verificação deste documento

O código acima **não foi executado**. As APIs usadas foram conferidas contra a
documentação oficial da Godot 4:

- `Camera3D.project_ray_origin(Vector2)` / `project_ray_normal(Vector2)` ✅
- `Plane(normal, d)` e `Plane.intersects_ray(from, dir) -> Vector3|null` ✅
- `Node3D.look_at(target, up, use_model_front)` e a convenção -Z ✅

Nenhum dos *breaking changes* da 4.7 toca nestas APIs (a lista da 4.6→4.7
cobre BlendSpace, analisador de espectro de áudio, IDs de dispositivo de
teclado/mouse, velocidade angular de partículas, preprocessador de shader e
remoção do formato OBB no Android).

Os **nomes de menu e o passo a passo de montagem da cena** não foram
verificados contra a 4.7 — são de memória. Se algo não bater, o script é a
parte confiável; a navegação do editor é a parte a ajustar.

---

## Próximo passo

Fase 1.2 do `04-roadmap.md`: paredes que bloqueiam a passagem.

Um `StaticBody3D` com `BoxMesh` + `BoxShape3D`. O `move_and_slide()` já faz o
personagem deslizar ao encostar, em vez de travar.
