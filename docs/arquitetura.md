# Arquitetura geral

Protótipo 3D single-player em Godot 4.8 dev4 (ver **Tecnologias e ambiente** no
[`../README.md`](../README.md)). Não há manager global orquestrando a partida:
um mapa é uma cena que instancia terreno, ambiente, jogador, NPCs, veículos,
itens e área de entrega, e os sistemas se falam por **sinais**, **grupos** e
**contratos de método**.

As cenas de entrada e seus responsáveis estão em
[fluxo-de-jogo.md](fluxo-de-jogo.md#etapas-e-quem-responde-por-cada-uma);
a composição dos mapas, em [mundo.md](mundo.md).

## Autoloads

Registrados em `project.godot`, seção `[autoload]`.

| Autoload | Script | Responsabilidade |
| --- | --- | --- |
| `CharacterAppearance` | `scripts/character_appearance.gd` | Perfil de aparência do ET, persistido em `user://character_appearance.cfg`; emite `appearance_changed` |
| `GlobalScore` | `scripts/GlobalScore.gd` | Pontuação e um inventário simples (o inventário ainda não está integrado ao fluxo de coleta) |
| `PhotoAlertSystem` | `scripts/photo_alert_system.gd` | Contagem de fotos (máx. 3) e sinais de resposta: polícia, imprensa, mais fotógrafos, MIB |
| `SceneTransition` | `scripts/scene_transition.gd` | Transições entre cenas (`warp_to`, `abduction_warp_to`) |
| `DebugMenus` | `scenes/Menu/DebugMenu.tscn` | Modos de depuração do `F4` e painel de iluminação do `F6` |
| `BeehaveGlobalMetrics`, `BeehaveGlobalDebugger` | `addons/beehave/` | Exigidos pelo plugin de behavior tree; não remova ao mexer em NPCs |

## Grupos

Grupos são a cola entre sistemas que não se referenciam diretamente. Os cinco
primeiros são **grupos globais** declarados em `project.godot`
(`[global_group]`); os demais são criados nas cenas ou em código.

| Grupo | Quem entra | Quem consulta |
| --- | --- | --- |
| `characters` | Player e personagens jogáveis/carregáveis | Vegetação reativa, sensores de NPC, porta de casa (abre no `interact`) |
| `vehicles` | Veículos dirigíveis | Vegetação reativa |
| `pickup_items` | Destroços coletáveis | `player.gd` (coleta) e `delivery_area.gd` (entrega) |
| `concealment_areas` | Áreas de vegetação que escondem o ET | `scripts/vegetation_concealment.gd` → `player.gd` |
| `photographers` | NPCs que fotografam o ET | `PhotoAlertSystem` |
| `npc_actors` | Todo `NPCActor` (entra sozinho no `_ready`) | Propagação de alerta entre NPCs, rotina social, minimapa, porta de casa (abre por proximidade e leva chave) |
| `carriable_characters` | Personagens carregáveis | `player.gd` busca candidatos para carregar no colo; contrato em [player.md](player.md) |
| `delivery_areas` | Área de entrega do mapa | Minimapa (objetivo) e busca do alvo do feixe |
| `house_doors` | Toda `HouseDoor` (entra sozinha no `_ready`) | `player.gd`, para saber se o `interact` é da porta |
| `country_town_poi` | Pontos de interesse do Country Town | Minimapa (marcos nomeados) |
| `fog_zones` | `FogZone` | `GroundFogLayer` (adensa a névoa local) |
| `volumetric_lights`, `alien_volumetric_lights`, `ufo_lighting` | Luzes | `NightEnvironment` (presets de qualidade e evento alienígena) |
| `alien_interference_sources`, `alien_post_process` | Fontes e filtro do incidente | `AlienIncidentPostProcess` |
| `night_environment`, `ground_fog_layer` | Nós de ambientação | Chamadas por grupo (`call_group`) vindas do mundo e do menu de debug |
| `ship_passengers` | Quem viaja a bordo da nave | `ShipCarryField` |
| `debug_*` (`debug_player`, `debug_environment_lighting`, `debug_house_lighting`, `debug_delivery_lighting`) | Alvos do menu `F6`/`F4` | `scripts/debug_menu.gd` |

## Contratos entre sistemas

- **Coletável** — estar no grupo `pickup_items`, expor `pickup(player)`,
  `drop()`, a propriedade `score_value` e responder `true` a
  `is_available_for_abduction()` (o filtro que `try_pickup()` usa para
  escolher o item mais próximo). Referência: `scripts/spaceship_scraps.gd`. Um
  item em abdução sai do grupo temporariamente (`begin_abduction()`) para não
  ser recolhido antes da entrega. Item sem `two_handed` também implementa
  `store_in_inventory(player)`, para caber no `ExplorationInventory` do Player
  em vez do `CarrySocket` nas mãos — ver [player.md](player.md#inventário-de-exploração).
- **Entrega** — `scripts/delivery_area.gd` só soma o `score_value` ao
  `GlobalScore` quando o feixe termina de sugar o item; emite
  `intervention_requested`, `abduction_started` e `item_delivered`.
- **NPC** — o chassi é `NPCActor` (`scripts/npc/npc_actor.gd`); as folhas de
  comportamento recebem o actor e leem `npc.vision`, `npc.hearing`,
  `npc.routine`. Ver [npcs.md](npcs.md).
- **Alvo de detecção** — `player.gd` expõe `set_vision_contact()`,
  `get_visibility_multiplier()`, `enter_concealment()` / `exit_concealment()`,
  usados por sensores e vegetação.
- **Reserva do `interact`** — antes de coletar, largar ou soltar um ET,
  `player.gd` pergunta aos grupos `delivery_areas` e `house_doors` se algum nó
  quer a tecla, por `reserves_interaction_for(character)`. Quem responde `true`
  trata o `interact` por conta própria. Alvo interativo novo entra num desses
  grupos e implementa o método, em vez de disputar a tecla no `_input`.
- **Depuração por grupo** — `debug_menu.gd` chama métodos como
  `set_debug_lighting_enabled` / `get_debug_lighting_intensity` via grupo; um nó
  novo participa do menu implementando esses métodos e entrando no grupo certo.

## Fluxos principais

```text
Player -> grupo pickup_items -> pickup/drop -> DeliveryArea -> feixe -> GlobalScore
MainMenu -> CharacterCreator -> Orbit -> terminal -> LevelCatalog -> world.tscn -> pad -> feixe de chegada
CharacterAppearance -> CharacterProportions -> Blend Shapes/rig/olhos -> Player e ET no banco do veículo
NPCActor -> NPCVision/NPCHearing -> NPCBehaviorTree (Beehave) -> NPCRoutine/NPCActivity
SmellyFarmer -> visão -> perseguição e disparo -> vida do Player
Photographer -> PhotoAlertSystem -> sinais de polícia/imprensa/MIB (ainda sem consumidores)
Player -> estado físico -> PlayerAnimationController -> AnimationTree -> IK -> ragdoll
NightEnvironment -> presets/névoa/glow -> AlienIncidentPostProcess
FogZone -> grupo fog_zones -> GroundFogLayer
```

## Camadas e física

Definidas em `project.godot` (`[layer_names]`, `[physics]`):

- Física 3D com **Jolt**, rodando em thread separada.
- Colisão 3D: camada 1 é a colisão comum (chão, obstáculos, personagens);
  camada 4 é reservada a itens coletáveis.
- Render 3D nomeadas: 1 terreno, 2 vegetação, 3 luzes/FX, 4 veículos, 5 NPCs,
  6 XRAY (o que deve sumir com os binóculos), 7 destroços, 8 prédios,
  9 jogadores, 10 props comuns, 12 casco da nave (removido da câmera quando o
  ET está dentro — ver `scripts/space/alien_ship.gd`).

## Input

As ações ficam em `project.godot`, seção `[input]`; as teclas para jogar, no
[README](../README.md#controles). A fiação do remapeamento está em
[ui-e-menus.md](ui-e-menus.md#remapeamento-de-teclas).

## Convenções de código

Regras de edição: [AGENTS.md](../AGENTS.md). Convenções locais:

- Nomes de nó e de arquivo seguem o que já existe na pasta; scripts espelham a
  organização das cenas.
- A **frente dos personagens e veículos deste projeto é o `+Z` local**, ao
  contrário do `-Z` padrão do Godot.
- Nas receitas, construa transformações com `Basis`/`Transform3D` e salve
  com `ResourceSaver`, como em `tools/build_house_01.gd`; evite montar
  matrizes serializadas manualmente.
