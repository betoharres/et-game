# Fluxo de jogo

```text
Menu → criar o ET → nave em órbita → terminal de missão → aproximação →
nave descendo no céu da fase → raio trator → explorar → coletar → entregar
```

Nenhum manager global conduz isso: cada etapa é uma cena que sabe apenas o
suficiente para chamar a próxima.

## Etapas e quem responde por cada uma

| Etapa | Cena / script | Notas |
| --- | --- | --- |
| Menu | `scenes/Menu/main_menu.tscn`, `scripts/main_menu.gd` | Cena principal do projeto; opções e remapeamento de movimento |
| Criação do ET | `scenes/Menu/CharacterCreator.tscn`, `scripts/character_creator.gd` | Sete características normalizadas de `0` a `1`; "Iniciar jogo" grava o perfil no autoload `CharacterAppearance` (`user://character_appearance.cfg`) |
| Órbita | `scenes/Space/Orbit.tscn`, `scripts/space/orbit.gd` | O ET fica **dentro** da nave, que gira devagar; quem o carrega junto é o `ShipCarryField` |
| Seleção de fase | `scripts/space/mission_select_ui.gd` + `scripts/levels/` | O terminal lê o `LevelCatalog`; confirmar arma o feixe central, e a troca de cena só começa quando o ET entra nele |
| Transição | autoload `SceneTransition` | `warp_to()` / `abduction_warp_to()` |
| Chegada na fase | `scripts/world.gd` | A nave desce do céu, estaciona sobre o ponto de chegada e o jogador aciona o pad |
| Descida | `scripts/spaceship_interior.gd` → `scenes/FX/ArrivalBeam.tscn` + `scripts/arrival_beam.gd` | O pad emite `descend_requested`; o feixe leva o ET ao chão |
| Coleta | `scripts/player.gd` + itens do grupo `pickup_items` | Contrato em [arquitetura.md](arquitetura.md) |
| Entrega | `scripts/delivery_area.gd` | Larga o item na plataforma, segura o sinal de intervenção, o feixe suga e **só então** soma ao `GlobalScore` |

## Catálogo de fases

`scripts/levels/level_definition.gd` (`LevelDefinition`) descreve uma fase:
nome, briefing, `scene_path`, disponibilidade e motivo do bloqueio.
`scripts/levels/level_catalog.gd` (`LevelCatalog`) é a lista.

Os recursos vivem em `scenes/Space/Levels/`: `level_catalog.tres`,
`level_farm.tres`, `level_city.tres`, `level_desert.tres` (as duas últimas
bloqueadas, como exemplo) e `level_country_town.tres` (disponível).

**Adicionar uma fase não exige tocar em script**: crie um `LevelDefinition.tres`
apontando para a cena e liste-o em `level_catalog.tres`. Escolher o Country
Town no terminal é um caso à parte: `orbit.gd` desvia esse `scene_path`
específico para o diálogo do `MissionGiverNPC` em vez de abrir o feixe de
transporte — ver [Missão de resgate](#missão-de-resgate-country-town) abaixo.

## Missão de resgate (Country Town)

Na órbita, além do terminal, o tripulante `MissionGiver`
(`scripts/space/mission_giver_npc.gd`, uma especialização de
`ship_crew_alien.gd` — ver [veículos](veiculos.md#nave-alienígena)) oferece a
missão de resgate diretamente, com um marcador flutuante `!` enquanto não
aceita. `E` perto dele abre `scripts/space/mission_dialogue.gd`
(`MissionDialogueUI`, cena `MissionDialogue.tscn`), uma UI de diálogo
sequencial genérica que termina em Aceitar/Recusar.

- **Aceitar não parte na hora**: abre uma segunda pergunta ("Ir agora" / "Ir
  depois"). Recusar qualquer uma das duas não perde a missão — o NPC lembra
  `_rescue_accepted` e, na próxima conversa, pula direto para a pergunta de
  partida sem repetir o briefing.
- **O catálogo também lista o Country Town** (`level_country_town.tres`).
  Escolhê-lo pelo terminal (`orbit.gd._on_level_chosen`) fecha o terminal e
  chama o mesmo fluxo do NPC, em vez de abrir o feixe da `AlienShip` — as
  outras fases continuam pelo feixe normal.
- **Partida**: em vez do feixe da `AlienShip`, o jogo instancia a
  `MissionSaucer` (`scenes/Space/MissionSaucer.tscn`) e teleporta o jogador
  para dentro da cabine (`mission_saucer.gd.board()`, via `apply_carry()`, o
  mesmo contrato do `ShipCarryField`). Segue a mesma cutscene de aproximação à
  Terra que o terminal usa (`orbit.gd._play_approach`), com um deslocamento de
  câmera extra específico da saucer. `MissionFlow.arrived_from_orbit` e a nova
  `MissionFlow.arrival_by_saucer` marcam a chegada para a fase decidir a
  cutscene certa.
- **Chegada**: `CountryTown.tscn` tem script de raiz próprio
  (`scripts/country_town.gd`), não `world.gd`. Se `arrival_by_saucer` estiver
  ligado, ele instancia **uma nova `MissionSaucer` só visual** acima do
  jogador (não é a mesma nave da órbita) para a cutscene de descida pelo
  `ArrivalBeam`, depois a destrói.
- **Objetivo**: todo nó do grupo `alien_debris` nasce oculto
  (`set_discovered(false)`); aproximar-se do marcador `AlienCrashSite`
  (raio 14 m, já existente em `Layout/PointsOfInterest.tscn`) revela os
  destroços espalhados pelo mapa. Coleta, `DebrisLocator` e entrega pela
  `RecoveryZone`/`RecoveryShip`: ver
  [Country Town — missão e destroços](country-town.md#missão-e-destroços).

`scripts/levels/mission_flow.gd` guarda o único estado que atravessa a troca de
cena — `arrived_from_orbit`. É um `RefCounted` com `static var`, de propósito:
não precisa de árvore de cena nem de ciclo de vida, e por isso **não** é
autoload. Com ele em `false` (abrir `world.tscn` direto no editor), a fase roda
a cutscene automática de chegada, o que serve para teste rápido.

## Durante a partida

- **Spider bot** (`scripts/spider_bot/`): acompanha a nave, desce pelo feixe ao
  detectar um destroço ao alcance e leva o item até a plataforma.
- **Ameaças**: o fazendeiro patrulha, persegue e atira; o fotógrafo acende até
  três estrelas no `PhotoAlertSystem`, que emite os sinais de polícia, imprensa,
  mais fotógrafos e MIB — **hoje sem consumidores**, só mensagens de placeholder.
- **Masmorra**: uma porta na fazenda gera, uma vez por sessão, os corredores
  procedurais de `scenes/Dungeon/`, que guardam destroços nos becos sem saída,
  no mesmo fluxo de coleta e entrega. Ver [mundo.md](mundo.md).
- **Furtividade**: vegetação esconde parcialmente o ET e reduz o alcance de
  detecção dos inimigos.

## Limites atuais do fluxo

Consulte [Limitações conhecidas](../README.md#limitações-conhecidas) para o
estado do catálogo, pontuação, retorno à órbita e respostas ao alerta de fotos.

## Ao alterar

1. Fase nova: `LevelDefinition.tres` + entrada no catálogo. Se a fase precisar
   de comportamento próprio na chegada, o lugar é o script da cena do mapa
   (como `world.gd` faz), não um autoload novo.
2. Etapa nova entre menu e fase: use o `SceneTransition` já existente.
3. Estado que precise atravessar cenas: pese antes se cabe em `MissionFlow`
   (estático, sem ciclo de vida) em vez de virar autoload.
4. Validação: roteiro manual de coleta e entrega em `tools/VALIDACAO.md`;
   `tools/test_mission_departure.gd` cobre o diálogo do `MissionGiverNPC`, a
   escolha de partida e a chegada via `MissionSaucer`.
