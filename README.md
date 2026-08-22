# Projeto RC-like — Documentação

Jogo battle royale isométrico com elementos de MOBA, inspirado no Royal Crown.
Godot 4 + GDScript.

## Como usar estes arquivos

1. **Copie tudo para a raiz do projeto Godot** (`C:\dev\rc-like\`), mantendo a
   estrutura:

   ```
   C:\dev\rc-like\
   ├── CLAUDE.md
   ├── README.md
   ├── docs\
   ├── project.godot
   └── ...
   ```

2. O `CLAUDE.md` na raiz é lido **automaticamente** pelo Claude Code ao abrir o
   projeto. É o contexto permanente — não precisa colar nada em cada sessão.

3. Comece cada sessão pelo `docs/04-roadmap.md`, que diz qual é a próxima etapa.

## Índice

| Arquivo | Quando ler |
|---|---|
| `CLAUDE.md` | Contexto permanente — lido pelo Claude Code |
| `docs/01-visao-e-escopo.md` | Para entender o que o jogo é e o que não é |
| `docs/02-decisoes-tecnicas.md` | Quando bater dúvida sobre o stack |
| `docs/03-sistemas-de-jogo.md` | Antes das Fases 2 e 3 |
| `docs/04-roadmap.md` | **Toda sessão** |
| `docs/05-extracao-dados-apk.md` | Quando for recuperar os dados do original |
| `docs/06-setup-ambiente.md` | Agora, antes do primeiro commit |
| `docs/07-primeira-cena.md` | Fase 1.1 |
| `docs/08-arte-e-assets.md` | Só na Fase 6 |
| `docs/09-glossario.md` | Sempre que aparecer um termo desconhecido |

## Antes de começar

Checklist do `docs/06-setup-ambiente.md`:

- [ ] Godot 4.7.2 numa pasta fixa (`C:\Godot\`)
- [ ] GPU verificada (`dxdiag`) e renderer escolhido
- [ ] Projeto criado em `C:\...`, **nunca** dentro do WSL
- [ ] `.gitignore` de Godot 4 com `.godot/` ignorado
- [ ] `.gitattributes` com `* text=auto eol=lf` se for usar Git nos dois lados
- [ ] Primeiro commit

## Primeira tarefa

`docs/07-primeira-cena.md` — cápsula andando num plano.

Recomendação: fazer à mão, sem IA. São 30 minutos e é o que transforma a engine
de abstração em ferramenta.
