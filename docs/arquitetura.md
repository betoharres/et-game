# Arquitetura geral

Protótipo 3D single-player em Godot 4.8 dev4 (ver **Tecnologias e ambiente** no
[`../README.md`](../README.md)). Não há manager global orquestrando a partida:
um mapa é uma cena que instancia terreno, ambiente, jogador, NPCs, veículos,
itens e área de entrega, e os sistemas se falam por **sinais**, **grupos** e
**contratos de método**.

## Cenas de entrada

| Cena | Papel |
| --- | --- |
| `scenes/Menu/main_menu.tscn` | Cena principal (`run/main_scene`): menu, opções e remapeamento |
| `scenes/Menu/CharacterCreator.tscn` | Personalização do ET entre o menu e a órbita |
| `scenes/Space/Orbit.tscn` | Nave em órbita com o terminal de seleção de fase |
| `scenes/world.tscn` | Fazenda — o mapa jogável do catálogo |
| `scenes/CountryTown/CountryTown.tscn` | Mapa em construção, **fora do catálogo**; abre direto no editor |
| `scenes/Player.tscn` | ET: câmera, rig, `AnimationTree`, IK, ragdoll, HUD |
| `scenes/NightEnvironment.tscn` | Céu, Lua, névoa, iluminação e filtro de tela |

Cenas isoladas de teste: `scenes/SpaceshipInterior/interior_space_ship_room_1.tscn`
(gravidade radial), `scenes/Portal/portal.tscn`, `scenes/Vehicles/FlyablePlane.tscn`,
`scenes/Buildings/HouseTest.tscn` e `scenes/UI_ParameterPanel.tscn` (demo de água).

## Autoloads

Registrados em `project.godot`, seção `[autoload]`. Use `GlobalScore` (e os
demais) **somente** para estado realmente global; nada de manager novo.

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
| `characters` | Player e personagens jogáveis/carregáveis | Vegetação reativa, sensores de NPC, porta de casa |
| `vehicles` | Veículos dirigíveis | Vegetação reativa, porta de casa |
| `pickup_items` | Destroços coletáveis | `player.gd` (coleta) e `delivery_area.gd` (entrega) |
| `concealment_areas` | Áreas de vegetação que escondem o ET | `scripts/vegetation_concealment.gd` → `player.gd` |
| `photographers` | NPCs que fotografam o ET | `PhotoAlertSystem` |
| `npc_actors` | Todo `NPCActor` (entra sozinho no `_ready`) | Propagação de alerta entre NPCs, rotina social, minimapa, porta de casa |
| `delivery_areas` | Área de entrega do mapa | Minimapa (objetivo) e busca do alvo do feixe |
| `country_town_poi` | Pontos de interesse do Country Town | Minimapa (marcos nomeados) |
| `fog_zones` | `FogZone` | `GroundFogLayer` (adensa a névoa local) |
| `volumetric_lights`, `alien_volumetric_lights`, `ufo_lighting` | Luzes | `NightEnvironment` (presets de qualidade e evento alienígena) |
| `alien_interference_sources`, `alien_post_process` | Fontes e filtro do incidente | `AlienIncidentPostProcess` |
| `night_environment`, `ground_fog_layer` | Nós de ambientação | Chamadas por grupo (`call_group`) vindas do mundo e do menu de debug |
| `ship_passengers` | Quem viaja a bordo da nave | `ShipCarryField` |
| `debug_*` (`debug_player`, `debug_environment_lighting`, `debug_house_lighting`, `debug_delivery_lighting`) | Alvos do menu `F6`/`F4` | `scripts/debug_menu.gd` |

Preservar `characters`, `vehicles` e `pickup_items` é regra do `AGENTS.md`: se
mudar, atualize **todos** os consumidores na mesma alteração.

## Contratos entre sistemas

- **Coletável** — estar no grupo `pickup_items` e expor `pickup(player)`,
  `drop()` e a propriedade `score_value`. Referência:
  `scripts/spaceship_scraps.gd`. Um item em abdução sai do grupo
  temporariamente (`is_available_for_abduction()` / `begin_abduction()`) para
  não ser recolhido antes da entrega.
- **Entrega** — `scripts/delivery_area.gd` só soma o `score_value` ao
  `GlobalScore` quando o feixe termina de sugar o item; emite
  `intervention_requested`, `abduction_started` e `item_delivered`.
- **NPC** — o chassi é `NPCActor` (`scripts/npc/npc_actor.gd`); as folhas de
  comportamento recebem o actor e leem `npc.vision`, `npc.hearing`,
  `npc.routine`. Ver [npcs.md](npcs.md).
- **Alvo de detecção** — `player.gd` expõe `set_vision_contact()`,
  `get_visibility_multiplier()`, `enter_concealment()` / `exit_concealment()`,
  usados por sensores e vegetação.
- **Depuração por grupo** — `debug_menu.gd` chama métodos como
  `set_debug_lighting_enabled` / `get_debug_lighting_intensity` via grupo; um nó
  novo participa do menu implementando esses métodos e entrando no grupo certo.

## Fluxos principais

```text
Player -> grupo pickup_items -> pickup/drop -> DeliveryArea -> feixe -> GlobalScore
MainMenu -> CharacterCreator -> Orbit -> terminal -> LevelCatalog -> world.tscn -> pad -> feixe de chegada
CharacterAppearance -> CharacterProportions -> Skeleton3D/olhos -> Player e ET no banco do veículo
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
- Renderer `Forward Plus` com D3D12 no Windows; MSAA 2x; `max_fps` 75.

## Input

Todas as teclas passam pelo Input Map (`project.godot`, `[input]`). Ações do
jogo: `interact`, `request_abduction`, `toggle_eye_light`, `sprint`, `crouch`,
`jump`, `move_forward`, `move_backward`, `move_left`, `move_right`, `binos`,
`binos_zoom_in`, `binos_zoom_out`, `toggle_first_person`, `debug_vision_map`,
`debug_player_modes`, `debug_lighting_menu`.

Ao criar uma ação: registre em `project.godot`, documente o controle no
`README.md` e acrescente-a ao menu de controles do ESC
(`REBIND_ACTIONS`/`REBIND_LABELS` e `action_buttons` em `scripts/pause_menu.gd`,
com o botão em `scenes/Menu/PauseMenu.tscn`) — ver [ui-e-menus.md](ui-e-menus.md).

## Convenções de código

As regras gerais — GDScript tipado sempre, sinais e grupos antes de referência
direta, não editar `.godot/`/`.uid`/`.import`, não alterar asset importado
quando a sobrescrita local na cena resolve — estão em
[`../AGENTS.md`](../AGENTS.md). O que é específico deste projeto:

- Uma responsabilidade por script e por nó; prefira composição (um `Node` filho
  que faz uma coisa) a herança profunda ou a um script que faz tudo.
- Nomes de nó e de arquivo seguem o que já existe na pasta; scripts espelham a
  organização das cenas.
- A **frente dos personagens e veículos deste projeto é o `+Z` local**, ao
  contrário do `-Z` padrão do Godot.
- `Transform3D` no `.tscn` é gravado **row-major**: escrever os eixos como
  colunas grava a rotação inversa.
