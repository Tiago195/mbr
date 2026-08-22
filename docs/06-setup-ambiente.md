# 06 — Setup do Ambiente

## Godot

- **Versão:** 4.7.2 stable, win64, build **standard** (não .NET/Mono — .NET é
  para quem usa C#; aqui é GDScript)
- **Não tem instalador.** O `.exe` já é o programa completo
- Usar `Godot_v4.7.2-stable_win64.exe`. O `_console.exe` é o mesmo programa mas
  abre uma janela de terminal com os logs — serve para depurar problema de
  inicialização, situação rara. Pode ficar guardado
- Manter numa pasta fixa (`C:\Godot\`), não em Downloads
- Como cada versão é um arquivo independente, várias podem coexistir sem
  conflito

## Escolha do renderer

Decidida na criação do projeto:

| GPU | Renderer |
|---|---|
| Dedicada (NVIDIA / AMD) | **Forward+** |
| Integrada (Intel) | **Compatibility** (OpenGL) |

Godot 4 usa Vulkan no Forward+, e o editor fica pesado em gráficos integrados.
O Compatibility é mais leve e mais que suficiente para o visual simples
planejado.

**Como verificar a GPU:** buscar `dxdiag` no menu Iniciar → aba "Exibição".

---

## A armadilha do WSL2 — importante

WSL2 e Windows compartilham arquivos nas duas direções, mas o acesso **através
da fronteira** passa por uma camada de rede (9P) que é **ordens de magnitude
mais lenta** que acesso nativo.

Isso importa porque projeto Godot tem milhares de arquivos pequenos, e tanto o
editor quanto o Claude Code varrem a pasta constantemente. Do lado errado, o
editor trava e as buscas demoram uma eternidade.

### A regra

> **O projeto fica no filesystem do Windows** (`C:\dev\rc-like`), porque a
> Godot roda no Windows e é quem mais mexe nos arquivos.

O Claude Code no WSL acessa via `/mnt/c/dev/rc-like` e paga o custo de
travessia — ele é mais tolerante a latência que o editor.

**Nunca** colocar o projeto dentro do WSL (`~/projetos/...`) e abrir pela Godot
via `\\wsl$\`. Isso torna o editor inutilizável.

### Alternativa recomendada

**Instalar o Claude Code no Windows também.** Ele roda nativamente no Windows, e
nesse cenário a fronteira desaparece: editor e agente do mesmo lado, acesso
nativo, zero latência.

O WSL continua existindo para todo o resto. É só uma segunda instalação, na
mesma assinatura.

Ressalvas honestas:
- O terminal no Windows é um pouco menos confortável — usar **Windows Terminal
  com PowerShell**, não o `cmd`
- MCPs e configurações do WSL precisam ser refeitos

### Godot dentro do WSL com WSLg

Tecnicamente funciona. Na prática: aceleração 3D via WSLg é instável, o
desempenho do editor é ruim, e o tempo vai para depurar driver gráfico em vez de
fazer o jogo. **Não vale.**

---

## Git

### .gitignore

Usar um `.gitignore` de Godot 4. O essencial:

```gitignore
# Godot 4
.godot/
/android/

# Exports
export_presets.cfg
*.exe
*.pck
*.zip

# Windows
Thumbs.db
desktop.ini
```

`.godot/` é cache regenerável e **enorme**. Commitá-lo incha o repositório
rápido.

> Atenção: `export_presets.cfg` pode conter caminhos locais e eventuais
> credenciais de assinatura. Se o projeto for para repositório público, mantenha
> ignorado.

### .gitattributes — se usar Git nos dois lados

Git configurado no Windows e no WSL sobre o mesmo repositório causa conflito de
fim de linha (CRLF vs LF). Prevenir desde o primeiro commit:

```gitattributes
* text=auto eol=lf
```

Cinco segundos agora, meia hora de confusão evitada depois.

---

## Convenções do projeto

### GDScript

- Godot **4.x** — a API mudou muito da 3.x
- Indentação com **Tab** (não espaços) — igual Python, e erro comum ao colar
  código
- Tipagem estática sempre: `var speed: float = 5.0`, `func foo() -> void:`
- `_physics_process` para lógica de jogo (tick fixo)
- `_process` só para visual e interpolação

### Nomenclatura

- Nós: `PascalCase` (`PlayerCharacter`)
- Arquivos e variáveis: `snake_case` (`player_character.gd`)
- Constantes: `SCREAMING_SNAKE_CASE`

### Estrutura de pastas sugerida

```
res://
├── scenes/          # cenas .tscn
├── scripts/
│   ├── core/        # lógica pura — sem dependência de nó
│   │   ├── combat/
│   │   ├── abilities/
│   │   └── items/
│   ├── gameplay/    # nós que usam core
│   └── net/         # rede
├── data/            # habilidades, itens, personagens (configuração)
├── assets/          # modelos, texturas
└── tests/           # testes unitários de scripts/core
```

A separação `core/` vs `gameplay/` é o que garante o princípio de
`03-sistemas-de-jogo.md`: **nada em `core/` pode importar nó da engine.**
