# 01 — Visão e Escopo

## De onde veio a ideia

O **Royal Crown** era um battle royale isométrico com forte influência de MOBA,
desenvolvido pela coreana **Meerkat Games** e publicado pela **LINE Games**.

### Linha do tempo (verificada)

| Data | Evento |
|---|---|
| 29/04/2020 | Lançamento global em Early Access (Steam, Android, iOS) com cross-play |
| 23/02/2021 | Lançamento pleno; chegada a Coreia, Japão e Taiwan |
| 16/02/2022 | Anúncio do encerramento |
| 24/02/2022 | Remoção das lojas digitais |
| 28/04/2022 | Servidores desligados |

### Características do original (verificadas)

- **Visual chibi cartunizado, vista isométrica 3D travada**
- **Campeões:** 15 no lançamento, expandidos para **20** até 2021, distribuídos
  em 6 classes — Guerreiro, Arqueiro, Assassino, Suporte, Mago, Tanque. Cada um
  com kit de habilidades e passiva próprios
- Começava-se com 3 campeões permanentes e 2 em rotação; os demais se
  desbloqueavam com ouro de partida
- **Jogadores por partida:** até **60** no lançamento; a comunicação de 2021 já
  falava em até **30**. *(Ver nota de escopo abaixo — isto importa.)*
- **Modos:** Solo e Squad de 3
- Cenário de fantasia medieval: vilarejos, cânions, desertos
- **Coleta e crafting:** ingredientes de comida com panelas de cozimento, corte
  de árvores, mineração de minérios
- **Terreno interativo:** derrubar árvores para abrir caminho, arbustos para se
  esconder e emboscar
- **Dragão lendário** que acorda durante a partida
- Progressão de nível **dentro** da partida, subindo ao lutar contra mobs — com
  mobs de nível alto (10) sendo perigosos o bastante para matar quem os
  subestimasse

### Nota de escopo importante

O original rodava com **30 a 60 jogadores simultâneos por partida**. Isso é uma
categoria de problema de netcode substancialmente mais difícil que 8 jogadores:
área de interesse (só sincronizar o que está perto), largura de banda por
cliente, e custo de simulação no servidor.

A Fase 1 continua mirando **4 a 8 jogadores** — é o suficiente para validar se o
combate é divertido, e é o que se consegue chamar de amigos para testar. Mas a
arquitetura do servidor deve ser escrita sabendo que o alvo real é uma ordem de
grandeza maior. Concretamente: **não assumir que todo cliente recebe o estado de
todos os jogadores.**

## O que este projeto NÃO é

**Não é uma tentativa de reviver o jogo original.** Essa possibilidade foi
avaliada e descartada. Motivos:

- O código-fonte nunca foi publicado; é proprietário
- Não existe nenhum projeto de servidor privado ou emulador conhecido
- O jogo é *online-only* e **autoritativo no servidor**: o cliente sozinho não
  simula partida nenhuma — nem offline, nem em LAN
- Reconstruir o servidor exigiria engenharia reversa do protocolo **sem nenhum
  tráfego real gravado** de 2022 para comparar. Não há oráculo: o único
  feedback seria "o cliente crashou ou não crashou"
- A comunidade não tem massa crítica (o jogo estava com pico de 27 jogadores
  simultâneos no Steam nos seis meses antes do anúncio de encerramento — para
  um jogo cujas partidas comportavam 30 a 60 pessoas)

Estimativa realista para aquele caminho: milhares de horas de trabalho
qualificado em engenharia reversa, solo, sem garantia de chegar a lugar nenhum.
**Descartado.**

## O que este projeto É

Um **jogo novo**, original, inspirado nas mecânicas do Royal Crown.

A relação com o original é de **referência de design**, não de código:
- As mecânicas e a estrutura de jogo servem de inspiração
- Os **dados de balanceamento** extraídos do APK original (ver
  `05-extracao-dados-apk.md`) servem de ponto de partida numérico, para não ter
  que inventar tudo do zero
- Assets, código e arte do original **não** entram no build. Continuam sendo
  propriedade da LINE/Meerkat

## Objetivo da Fase 1: validar a ideia

O objetivo não é lançar um jogo. É chegar num estado onde **dá para jogar com
amigos e sentir se é divertido**.

### O que "feio mas funcional" significa aqui

Explicitamente **fora** de escopo na Fase 1:

- Sombras, iluminação elaborada, pós-processamento
- Som e música
- Menus bonitos, telas de loading, animação de UI
- Múltiplos modelos de personagem — **um único boneco serve para todos**
- Texturas próprias (repetir a mesma em tudo é aceitável)
- Otimização de performance

Explicitamente **dentro** de escopo:

- Mapa com obstáculos, áreas e pontos de spawn
- Sistema de itens: loot no chão, inventário, equipar, efeitos nos atributos
- Sistema de atributos completo (ver `03-sistemas-de-jogo.md`)
- Sistema de habilidades: múltiplas habilidades distintas por personagem,
  com cooldown, alcance, área, efeitos
- Combate funcional: ataque básico, dano, morte
- Zona que fecha
- Multiplayer real: várias pessoas na mesma partida, pela internet

**Personagens diferentes = kits de habilidade diferentes, mesmo boneco.**
É exatamente isso que valida a ideia: o que diferencia um personagem do outro
é o que ele faz, não como ele parece.

## Escopo alvo do protótipo

| Item | Fase 1 | Visão final |
|---|---|---|
| Personagens (kits) | 3 | 15–20 |
| Habilidades por personagem | 3–4 | 4 + passiva |
| Jogadores por partida | 4–8 | 30+ (ver nota de escopo) |
| Mapa | 1, pequeno | 1, completo |
| Itens | ~10 | dezenas + crafting |
| Modelos 3D | 1 | 15–20 |
| Modos | Solo | Solo + Squad de 3 |

## Por que essa ordem

O erro clássico é construir o sistema de atributos completo, depois o de
habilidades completo, depois o inventário — e só então tentar integrar. Seis
meses depois: muito código bem escrito, zero minutos de jogo jogado, e a
descoberta de que a arquitetura não aguenta uma mecânica não prevista.

A alternativa é **fatia vertical**: um personagem, três habilidades, dois itens,
um mapa pequeno — mas com o sistema *genérico* por baixo, feito para escalar.
Joga-se com os amigos, sente-se o que está errado, e só então replica-se para os
outros 14 personagens, sabendo que a base funciona.

Mesmo destino final. A diferença é ter feedback desde o primeiro mês.
