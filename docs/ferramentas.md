# Ferramentas (`tools/`)

A **política** de validação (quando validar, o que nunca fazer) está em
`AGENTS.md`. O **procedimento** — comandos exatos, argumentos, roteiros manuais
e regras para escrever uma checagem nova — está em
[`../tools/VALIDACAO.md`](../tools/VALIDACAO.md). Este documento é só o mapa:
que tipo de script existe e a que sistema cada um pertence.

Padrão do repositório: toda ferramenta é um `SceneTree` rodado pelo executável
do Godot, e não roda durante a partida. O wrapper é `tools/godot.cmd`, que
procura o Godot em locais conhecidos e, no Windows, o executável
`_console.exe` — só ele manda `print()` para o stdout.

## Geradores de asset

Escrevem cenas e recursos. **A saída é descartável, a receita não**: nunca
edite à mão o que um gerador regrava.

| Ferramenta | Gera | Sistema |
| --- | --- | --- |
| `build_country_town_layout.gd` | Estradas e rio | [country-town.md](country-town.md) |
| `build_country_town_terrain.gd` | Relevo e regiões do Terrain3D | [country-town.md](country-town.md) |
| `build_country_town_settlement.gd` | Lotes, prédios e complementos | [country-town.md](country-town.md) |
| `build_country_town_fields.gd` | Talhões (sem `--headless`) | [country-town.md](country-town.md) |
| `build_country_town_vegetation.gd` | Plantio no instancer (sem `--headless`) | [country-town.md](country-town.md) |
| `build_country_town_population.gd` | Navegação de pedestre e os NPCs do mapa | [npcs.md](npcs.md) |
| `build_rural_roads.gd`, `recess_country_town_asphalt.gd` | Piso viário | [country-town.md](country-town.md) |
| `build_tire_tracks.gd`, `build_tire_tread_texture.gd` | Marcas de pneu e a textura de banda | [mundo.md](mundo.md) |
| `build_terrain_surface.gd` | Dados de material do terreno | [mundo.md](mundo.md) |
| `build_house_01.gd` | Casa modular, portas, cena de teste e navegação | [casas-interiores.md](casas-interiores.md) |
| `bake_police_patrol_route.gd` | Grafo de ruas da patrulha (colar no `AIDriver`) | [veiculos.md](veiculos.md) |
| `build_mixamo_character.py` | `ET_animated.glb` (roda no Blender) | [animacoes.md](animacoes.md) |
| `render_prototype_icons.py` | Ícones de `Texturas/ui/` | [ui-e-menus.md](ui-e-menus.md) |

Bibliotecas auxiliares, `RefCounted`, que não rodam sozinhas:
`country_town_road_surface.gd` e `country_town_neighborhood.gd`.

## Checagens automatizadas

Imprimem diagnóstico e saem com `quit(1)` ao falhar. Rode **a do sistema que
você alterou**, uma vez, depois da última edição — nunca a bateria inteira.

| Sistema | Ferramenta |
| --- | --- |
| Player: animação, pulo/stamina, degraus, reversão, ragdoll, modos do `F4` | `test_player_animation.gd`, `test_player_jump_stamina.gd`, `test_player_steps.gd`, `test_player_reversal.gd`, `test_player_ragdoll.gd`, `test_player_debug_modes.gd` |
| Câmera | `test_cinematic_camera.gd` |
| NPCs | `test_farmer_npc_behavior.gd`, `test_npc_animation.gd`, `test_generic_npc_navigation.gd`, `test_ship_crew_downed.gd` |
| Minimapa | `test_minimap.gd` |
| Portais | `test_portal_teleportation.gd` |
| Ambientação | `test_atmosphere_presets.gd`, `test_alien_interference.gd`, `measure_atmosphere_cost.gd` (sem `--headless`) |
| Nave | `check_tapered_shell.gd`, `validate_alien_ship_authored_geometry.gd` |
| Casa modular | `check_house_01.gd` |
| Country Town | `check_country_town_layout.gd`, `check_country_town_clearance.gd`, `check_country_town_neighborhood.gd`, `check_country_town_roads.gd`, `check_country_town_bridge.gd`, `check_country_town_fences.gd` |

## Inspeções visuais

Rodam **sem** `--headless` e produzem capturas em `build/`. Servem para o
usuário julgar o resultado, nunca como critério de aprovação:
`inspect_country_town_roads.gd`, `shoot_house_01.gd`,
`shoot_country_town_fences.gd`.

`tools/_inspect_tmp.gd` é um rascunho de inspeção, não uma ferramenta estável.

## Ao adicionar uma ferramenta

1. Decida a categoria: gerador, checagem ou inspeção — e siga o padrão da
   categoria (checagem imprime diagnóstico e falha com `quit(1)`, informando
   coordenadas de mundo em falhas espaciais).
2. Registre-a na tabela de `tools/VALIDACAO.md` ligada ao sistema que ela cobre,
   e cite-a no documento do sistema aqui em `docs/`.
3. Se ela depender de rasterização real (render, screenshot, MultiMesh,
   culling), diga isso no cabeçalho do script: o driver dummy não desenha nada.
4. Nunca remova ou enfraqueça uma validação para esconder falha; nunca declare
   algo testado sem ter executado.
