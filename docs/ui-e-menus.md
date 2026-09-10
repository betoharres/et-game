# UI, menus e HUDs

Todas as telas compartilham o tema `Materiais/hud_theme.tres` e uma família
única de ícones em `Texturas/ui/`, gerada dos meshes low-poly do pacote
*Polygon Prototype* por `tools/render_prototype_icons.py`. Ícone novo sai
dessa mesma ferramenta, para não quebrar a unidade visual.

## Telas

| Tela | Cena / script | Papel |
| --- | --- | --- |
| Menu principal | `scenes/Menu/main_menu.tscn`, `scripts/main_menu.gd` | Entrada do jogo; opções e remapeamento das teclas de movimento; intro de "sintonia de sinal" |
| Fundo animado do menu | `scenes/Menu/MenuAtmosphere.tscn`, `scripts/menu_atmosphere.gd` | Estrelas em parallax, OVNI e feixes |
| Criador de personagem | `scenes/Menu/CharacterCreator.tscn`, `scripts/character_creator.gd` | Sete características do ET, prévia 3D animada; grava no autoload `CharacterAppearance` |
| Terminal de missão | `scenes/Space/MissionSelectUI.tscn`, `scripts/space/mission_select_ui.gd` | Lista o `LevelCatalog`; adicionar fase não toca no script |
| Menu de pausa | `scenes/Menu/PauseMenu.tscn`, `scripts/pause_menu.gd` | `Esc`; remapeia as demais ações |
| HUD do jogador | `scenes/PlayerHUD.tscn`, `scripts/player_hud.gd` | Vida, stamina (aparece e some), energia e vinheta de dano |
| HUD de fotos | `scenes/PhotoAlertHUD.tscn`, `scripts/photo_alert_hud.gd` | Até três estrelas do `PhotoAlertSystem` |
| Minimapa | `scenes/VisionDebugMap.tscn`, `scripts/vision_debug_map.gd` | `F3` |
| Menus de depuração | `scenes/Menu/DebugMenu.tscn`, `scripts/debug_menu.gd` | Autoload `DebugMenus`: ciclo do `F4` e painel de iluminação do `F6` |
| Transição de cena | `scripts/scene_transition.gd` | Autoload; limpeza circular e a variante de abdução |
| Painel de parâmetros | `scenes/UI_ParameterPanel.tscn` | Demo isolada da água; nada é gravado em disco |

## Remapeamento de teclas

Duas telas dividem o trabalho: o **menu de opções** remapeia o movimento e o
**menu de pausa** remapeia o resto. Os remapeamentos duram a sessão (não são
salvos).

Ao criar uma ação no Input Map, acrescente-a nos três lugares de
`scripts/pause_menu.gd` + cena:

1. `REBIND_ACTIONS` (a ação),
2. `REBIND_LABELS` (o rótulo em português, na mesma ordem),
3. `action_buttons` (a fiação),
4. o botão correspondente em `scenes/Menu/PauseMenu.tscn`, dentro de
   `ControlsPanel/Actions` — o painel é um `ScrollContainer`, para caber a
   lista crescente de ações sem estourar a tela.

Sem isso a tecla existe mas o jogador não a vê nem consegue trocá-la — é regra
do `AGENTS.md`. A escuta de rebind aceita tanto `InputEventKey` quanto
`InputEventMouseButton` (usado pelos slots do inventário de exploração, que
ciclam com a roda do mouse); ação nova que só faz sentido no teclado não
precisa desse cuidado, mas o rebind em si não distingue.

## Minimapa (`F3`)

`scripts/vision_debug_map.gd` é uma **cena reutilizável, uma instância por
mapa**, sem nada específico de fase no script. O que muda por mapa são exports
do nó `Overlay`:

| Export | Para que serve |
| --- | --- |
| `world_radius` | Alcance em metros (fazenda usa o padrão curto; Country Town, 140) |
| `objective_group` | Grupo do objetivo desenhado (padrão `delivery_areas`) |
| `landmark_group` | Grupo dos marcos nomeados (Country Town: `country_town_poi`) |
| `uniform_npc_markers`, `npc_marker_size`, `npc_color` | Aparência dos NPCs no radar |
| `actor_scan_interval` | Frequência da varredura por atores |

Os NPCs desenhados vêm do grupo `npc_actors`, com cone de visão, e ficam
vermelhos ao avistar o ET. Se um mapa precisa de algo novo no radar, o caminho
é **um export a mais**, nunca um `if` por nome de fase.

## Menus de depuração

- `F4` não abre menu: cada toque avança um degrau do ciclo
  `desligado` → `velocidade` (imortalidade, stamina cheia, velocidade 5×) →
  `velocidade e voo` (sem gravidade) → `desligado`. O alvo é encontrado pelo
  grupo `debug_player`.
- `F6` abre o painel de iluminação, disponível durante o jogo em qualquer mapa:
  preset de atmosfera e cada fonte de luz da cena atual. O painel encontra os
  alvos pelos grupos `debug_environment_lighting`, `debug_house_lighting`,
  `ufo_lighting` e `debug_delivery_lighting`, e conversa com eles por métodos
  (`set_debug_lighting_enabled`, `set_debug_lighting_intensity`,
  `get_debug_lighting_intensity`, `is_debug_lighting_enabled`).

Para um nó novo aparecer no `F6`: implemente esses métodos e entre no grupo
certo — não edite o menu para conhecê-lo.

## Ao alterar

1. Elemento visual novo: reaproveite `hud_theme.tres` e os ícones existentes.
2. Texto: o jogo é em português; siga o tom das telas já escritas.
3. Tecla nova: Input Map + `README.md` + menu de rebind (acima).
4. Validação: `tools/test_minimap.gd` (busca por grupos, escala e fiação) e
   `tools/test_player_debug_modes.gd` (ciclo do `F4`). Layout e legibilidade
   quem julga é o usuário.
