# Ferramentas (`tools/`)

A **política** de validação (quando validar, o que nunca fazer) está em
`AGENTS.md`. O **procedimento** — comandos exatos, argumentos, roteiros manuais
e regras para escrever uma checagem nova — está em
[`../tools/VALIDACAO.md`](../tools/VALIDACAO.md). Este documento é só o mapa:
que tipo de script existe e a que sistema cada um pertence.

Padrão do repositório: a ferramenta é um `SceneTree` rodado pelo executável do
Godot, e não roda durante a partida — as exceções são os utilitários que vivem
fora do motor (`build_mixamo_character.py` no Blender,
`render_prototype_icons.py` e `build_snapshots.ps1`). O wrapper é `tools/godot.cmd`, que
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
| `build_country_town_debris.gd` | Destroços alienígenas e o localizador (`AlienDebrisTest.tscn`) | [country-town.md](country-town.md#missão-e-destroços) |
| `build_rural_roads.gd`, `recess_country_town_asphalt.gd` | Piso viário | [country-town.md](country-town.md) |
| `build_tire_tracks.gd`, `build_tire_tread_texture.gd` | Marcas de pneu e a textura de banda | [mundo.md](mundo.md) |
| `build_terrain_surface.gd` | Dados de material do terreno | [mundo.md](mundo.md) |
| `build_house_01.gd` | Casa modular (House01), portas, cena de teste e navegação | [casas-interiores.md](casas-interiores.md) |
| `build_house_02.gd` | Segunda planta modular (House02), com garagem | [casas-interiores.md](casas-interiores.md) |
| `bake_police_patrol_route.gd` | Grafo de ruas da patrulha (colar no `AIDriver`) | [veiculos.md](veiculos.md) |
| `build_mixamo_character.py` + `build_mixamo_animation_library.gd` | `ET_animations.res` (Blender assa os FBXs; Godot grava a biblioteca sem alterar a malha) | [animacoes.md](animacoes.md) |
| `render_prototype_icons.py` | Ícones de `Texturas/ui/` | [ui-e-menus.md](ui-e-menus.md) |

Bibliotecas auxiliares, `RefCounted`, que não rodam sozinhas:
`country_town_road_surface.gd`, `country_town_neighborhood.gd` e
`window_interiors.gd` (cômodo raso atrás de cada vidro de janela dos presets
sem interior do PolygonTown, chamada pelo settlement — ver
[country-town.md](country-town.md#população)).

Fora do jogo: `build_snapshots.ps1` empacota o repositório em snapshots de
leitura para agentes, em `docs/generated/` — ver
[generated/README.md](generated/README.md). Não toca em nada do projeto.

## Checagens automatizadas

O catálogo único de testes, com o comportamento coberto por cada um, está em
[tools/VALIDACAO.md](../tools/VALIDACAO.md#qual-ferramenta-para-cada-sistema).

## Inspeções visuais

Rodam **sem** `--headless` e produzem capturas. Servem para o usuário julgar o
resultado, nunca como critério de aprovação: `inspect_country_town_roads.gd`
(grava em `build/`), `shoot_house_01.gd`, `shoot_country_town_fences.gd` e
`shoot_country_town_windows.gd` (fachadas e vitrines do `TownDistrict`; os três
últimos gravam em `user://`, redirecionável por variável de ambiente —
`HOUSE_SHOT_DIR` para o de janelas).

`tools/_inspect_tmp.gd` é um rascunho de inspeção, não uma ferramenta estável.

## Ao adicionar uma ferramenta

Siga o padrão da categoria. Dependência de rasterização real deve aparecer
no cabeçalho do script (render, screenshot, MultiMesh, culling).
Na revisão de documentação, registre geradores nesta tabela e checagens em
[tools/VALIDACAO.md](../tools/VALIDACAO.md#qual-ferramenta-para-cada-sistema).
Documente no sistema apenas dependências e decisões que o agente precisará
preservar; a política de atualização é a de [AGENTS.md](../AGENTS.md).
