# Country Town — o mapa gerado

`scenes/CountryTown/CountryTown.tscn` é um mapa de **600 × 450 m** em
construção, **fora do catálogo de fases**: abre direto pelo editor.

A regra que organiza tudo aqui: **as receitas são a fonte da verdade, as cenas
são saída**. Editar à mão uma cena gerada é trabalho perdido na próxima
execução da ferramenta. Se algo está errado no mapa, corrija a receita no
script de `tools/` e regere.

## Composição da cena mestre

A cena mestre só instancia terreno, ambiente, jogador e os distritos:

| Nó | Conteúdo |
| --- | --- |
| `NavigationRegion3D` → `Terrain3D` | Relevo, com dados em `scenes/CountryTown/Terrain` (exclusivo deste mapa) |
| `NightEnvironment`, `PauseMenu`, `Player` | Cenas compartilhadas |
| `PointsOfInterest` | Marcadores do grupo `country_town_poi` (`Layout/PointsOfInterest.tscn`) |
| `RoadNetwork`, `SecondaryPaths` | Vias principais e trilhas rurais |
| `RiverDistrict`, `FarmDistrict`, `TownDistrict`, `CrashSiteDistrict`, `MinePortalSite`, `DeliveryYard` | Distritos |
| `Fields`, `Vegetation`, `Detailing`, `NightLights`, `StreetLife` | Talhões, plantio, complementos, luzes e vida de rua |
| `VehiclesHolder` | Duas viaturas em patrulha ([veiculos.md](veiculos.md)) |
| `EnvironmentAudio`, `NPCs`, `Minimap` | Áudio, população e minimapa |

Os pontos de interesse (`Farmhouse`, `Barn`, `CornField`, `MinePortal`,
`AlienCrashSite`, `TownSquare`, `Church`, `GeneralStore`, `DeliveryPoint`,
`BridgeNorth`/`BridgeSouth`, postos de patrulha, `PlayerSpawn`…) são a âncora
comum: o layout, as checagens e o minimapa dependem dos nomes exatos e do grupo
`country_town_poi`.

## Pipeline de geração

Ordem obrigatória — cada etapa consome a saída da anterior:

```text
build_country_town_layout  →  build_country_town_terrain  →
build_country_town_settlement  →  build_country_town_fields  →
build_country_town_vegetation
```

| Ferramenta | O que gera | Observações |
| --- | --- | --- |
| `build_country_town_layout.gd` | Estradas e rio, com interseções assadas sem sobreposição | O traçado autoral (`ROAD_RUNS`) manda; asfalto, terra, calçadas, meios-fios e acostamentos têm materiais separados. Aceita `--headless` |
| `build_country_town_terrain.gd` | Heightmap e regiões do Terrain3D | O relevo se adapta ao layout, não o contrário. **Reimporta as regiões do zero** — por isso vem antes do plantio. Só escreve em `scenes/CountryTown/Terrain` |
| `build_country_town_settlement.gd` | Lotes, prédios e complementos dos distritos | Composição determinística com assets locais; não sobrescreve distritos autorais. Receita de lotes em `tools/country_town_neighborhood.gd` |
| `build_country_town_fields.gd` | Milharal, trigo e girassóis | Poda o que cai perto de estrada, rio ou colisão de prédio. **Precisa rodar sem `--headless`** (MultiMesh) |
| `build_country_town_vegetation.gd` | Grama, arbustos e árvores no `Terrain3DInstancer` | Vegetação vive dentro das regiões do terreno, não como nós de cena. Rodar de novo limpa o plantio anterior. **Sem `--headless`** |
| `build_country_town_population.gd` | `Layout/PedestrianNavigation.res` e `Districts/NPCs.tscn` | Assa navegação de pedestre e a população a partir de corredores, pátios e colisões dos distritos; gera também os `NPCActivity`. Exige editor fechado |

Ferramentas de superfície viária, complementares:

- `build_rural_roads.gd` — tira o piso de terra das vias rurais (o chão passa a
  ser o terreno) e deixa piso só nas cabeceiras de ponte; regrava
  `RoadNetwork.tscn` e `SecondaryPaths.tscn`. Idempotente.
- `build_tire_tracks.gd` — assa as marcas de pneu contra o terreno atual. Sem
  argumento preserva as curvas em cena; `-- --reseed` descarta e semeia tudo de
  novo, apagando edições manuais.
- `build_terrain_surface.gd` — normais/rugosidade das texturas e a máscara de
  uso do solo. Só dados de material.
- `recess_country_town_asphalt.gd` — atualiza só o piso pavimentado e o subsolo.
- `bake_police_patrol_route.gd` — regera o grafo de ruas da patrulha e imprime a
  linha para colar no nó `AIDriver` da viatura. **Obrigatório sempre que
  `ROAD_RUNS` mudar.**

Bibliotecas auxiliares (`RefCounted`, não rodam sozinhas):
`tools/country_town_road_surface.gd` (união de polígonos convexos do piso) e
`tools/country_town_neighborhood.gd` (receita de lotes em metros; frente local
`-Z`).

## População

A `House01` habitável fica no `TownDistrict`, no antigo lote 202 ao norte
da fonte, com a varanda voltada para a praça e acesso à calçada. É uma
instância da cena compartilhada, preservada pelo settlement; a receita de
`country_town_neighborhood.gd` reserva esse lote para não gerar outra casa ali.
A navegação ainda usa a malha anterior à substituição: o bake completo foi
barrado pelas rotas desconectadas entre `SouthFarm` e `Delivery`, de
`FarmerPatrolling4` e `DeliveryWorker`. É preciso resolver essas rotas e reassar
antes de atribuir aos NPCs uma rotina dentro da casa da praça.

`Districts/NPCs.tscn` traz hoje **12 NPCs**: 6 fazendeiros (4 patrulhando,
2 trabalhando parados), 3 moradores e 3 policiais a pé, todos sobre o mesmo
chassi e a mesma behavior tree ([npcs.md](npcs.md)). As paradas de rotina são
`NPCActivity` gerados junto com a cena.

## Checagens

| Checagem | Cobre |
| --- | --- |
| `check_country_town_layout.gd` | Cada POI existe com o nome exato, está no grupo, cai dentro do retângulo do mapa, pousa no terreno e fica acima da linha d'água |
| `check_country_town_clearance.gd` | Edificações e passagem nas vias principais, ruas locais e trilhas |
| `check_country_town_neighborhood.gd` | Escala das casas, divisas e acessos de pedestre/carro nos lotes |
| `check_country_town_roads.gd` | Malhas e colisões salvas do piso viário, rampas, asfalto e folga sobre o terreno |
| `check_country_town_bridge.gd` | Tabuleiro e parapeitos da ponte |
| `check_country_town_fences.gd` | Cercas |
| `inspect_country_town_roads.gd` | Sete capturas em `build/country-road-review/` (rodar **sem** `--headless`) |

## Ao alterar

1. Mudou via urbana ou largura? Regere layout **e** terreno.
2. Mudou só lotes e objetos? Comece pelo settlement.
3. Mudou `ROAD_RUNS`, `SECONDARY_PATHS` ou o preset de via rural? Rode
   `build_rural_roads.gd` + `build_terrain_surface.gd`, depois
   `check_country_town_roads.gd`, e reassar o grafo da patrulha.
4. Campos e vegetação **nunca** com `--headless`.
5. Nunca rode uma segunda instância do Godot com o editor aberto no mesmo
   projeto: as duas concorrem pelo cache em `.godot/`. Use cópia isolada.
6. Comandos exatos, argumentos e roteiros manuais: `tools/VALIDACAO.md`.

## Limitações atuais

O cenário está fechado e os NPCs andam, mas o mapa ainda não tem gameplay:
faltam armadilha, destroço coletável e entrega funcional. A lista completa, com
o que é cenário e o que reusa a fazenda, está em **Limitações conhecidas**, no
[`../README.md`](../README.md).
