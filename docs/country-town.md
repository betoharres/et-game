# Country Town — o mapa gerado

`scenes/CountryTown/CountryTown.tscn` é um mapa de **600 × 450 m** em
construção, no catálogo de fases (`level_country_town.tres`, disponível) como
a missão de resgate — ver [fluxo de jogo](fluxo-de-jogo.md#missão-de-resgate-country-town).
Ainda abre direto pelo editor para iteração rápida.

A regra que organiza tudo aqui: **as receitas são a fonte da verdade, as cenas
são saída**. Editar à mão uma cena gerada é trabalho perdido na próxima
execução da ferramenta. Se algo está errado no mapa, corrija a receita no
script de `tools/` e regere.

## Composição da cena mestre

A cena mestre é dona de um script de raiz próprio, `scripts/country_town.gd`
(objetivo e cutscene de chegada — ver [Missão e destroços](#missão-e-destroços)),
e instancia terreno, ambiente, jogador e os distritos:

| Nó | Conteúdo |
| --- | --- |
| `NavigationRegion3D` → `Terrain3D` | Relevo, com dados em `scenes/CountryTown/Terrain` (exclusivo deste mapa) |
| `NightEnvironment`, `PauseMenu`, `Player` | Cenas compartilhadas |
| `PointsOfInterest` | Marcadores do grupo `country_town_poi` (`Layout/PointsOfInterest.tscn`), inclui o `AlienCrashSite` que revela os destroços |
| `RoadNetwork`, `SecondaryPaths` | Vias principais e trilhas rurais |
| `RiverDistrict`, `FarmDistrict`, `TownDistrict`, `CrashSiteDistrict`, `MinePortalSite`, `DeliveryYard` | Distritos |
| `Fields`, `Vegetation`, `Detailing`, `NightLights`, `StreetLife` | Talhões, plantio, complementos, luzes e vida de rua |
| `VehiclesHolder` | Duas viaturas em patrulha ([veiculos.md](veiculos.md)) |
| `EnvironmentAudio`, `NPCs`, `Minimap` | Áudio, população e minimapa |
| `AlienDebrisTest`, `RecoveryPoint` | Destroços coletáveis e ponto de entrega da missão — ver [Missão e destroços](#missão-e-destroços) |

Os pontos de interesse (`Farmhouse`, `Barn`, `CornField`, `MinePortal`,
`AlienCrashSite`, `TownSquare`, `Church`, `GeneralStore`, `DeliveryPoint`,
`BridgeNorth`/`BridgeSouth`, postos de patrulha, `PlayerSpawn`…) são a âncora
comum: o layout, as checagens e o minimapa dependem dos nomes exatos e do grupo
`country_town_poi`.

## Receitas e dependências

Localize a receita pela saída em [ferramentas.md](ferramentas.md#geradores-de-asset).
A ordem de execução, os argumentos, os efeitos de regenerar e a escolha de
checagens ficam em [tools/VALIDACAO.md](../tools/VALIDACAO.md#geração-do-country-town).

- O layout define o traçado (`ROAD_RUNS`) e os pontos de interesse; o relevo
  se adapta a esse traçado. Os dados do terreno deste mapa ficam separados
  dos da fazenda.
- O settlement compõe os lotes e complementos. A receita de lotes é
  `tools/country_town_neighborhood.gd` (medidas em metros, frente local `-Z`);
  `tools/country_town_road_surface.gd` monta polígonos do piso;
  `tools/window_interiors.gd` decora as janelas dos presets sem interior. São
  bibliotecas `RefCounted`, não ferramentas executáveis.
- A vegetação do instancer é salva nas regiões do Terrain3D. Recriar o terreno
  remove esse plantio; não o trate como uma cena independente.
- A população usa corredores, pátios e colisões dos distritos para gerar
  `Layout/PedestrianNavigation.res`, `Districts/NPCs.tscn` e atividades.
- As curvas de `TireTrack3D` admitem autoria no editor; o gerador preserva as
  existentes sem `--reseed`. Essa opção descarta a autoria. Confira os
  argumentos antes de regenerar cenas que contêm marcas.

## População

A `House01` original habitável fica no `TownDistrict`, no antigo lote 202 ao
norte da fonte, com a varanda voltada para a praça e acesso à calçada. É uma
instância da cena compartilhada, preservada pelo settlement; a receita de
`country_town_neighborhood.gd` reserva esse lote para não gerar outra casa ali.
A leste dela, no vão até o lote 204, o distrito instancia a mesma cena de novo
como `House01Aberta`, com o `starts_locked` da porta de entrada sobrescrito para
`false`: é a casa em que se entra sem depender da moradora que tem a chave. Essa
segunda instância não tem lote na receita — existe só no `TownDistrict`, com uma
cópia do caminho de entrada. A sobrescrita depende do caminho do nó dentro da
cena gerada: renomear a porta na receita de `build_house_01.gd` desfaz a tranca
aberta sem avisar.

Além dessas duas, oito lotes de `LOTS` (204, 206, 203, 208, 210, 212, 302, 304
— o preset em `recipe[6] == LIVEABLE`, valor `0`) também instanciam `House01`
em vez da casca decorativa do kit PolygonTown, cada uma vestida por
`HouseVariant` com `variant_seed = number` — ver
[casas-interiores.md](casas-interiores.md). A tranca da entrada varia por
`number % 3 == 0`; o restante (luzes, cortinas, móveis) é aleatório por
semente. Os demais lotes continuam com a casca `SM_Bld_House_Preset_XX` sem
interior; cada uma delas, mais as fachadas de comércio (`Padaria`, `Mercearia`,
`Cafe`, via `_build_shop`), ganham um cômodo raso atrás de cada vidro
(`tools/window_interiors.gd`, biblioteca `RefCounted`) para não parecerem
ocas por dentro quando vistas da rua — ver
[ferramentas.md](ferramentas.md#geradores-de-asset). `decorate()`/
`decorate_tree()` devolvem quantos cômodos criaram; zero marca a geração como
falha (vitrine ausente), sem interromper o resto da montagem.

A navegação ainda usa a malha anterior à substituição: o bake completo foi
barrado pelas rotas desconectadas entre `SouthFarm` e `Delivery`, de
`FarmerPatrolling4` e `DeliveryWorker`. É preciso resolver essas rotas e reassar
antes de atribuir aos NPCs uma rotina dentro da casa da praça.

`Districts/NPCs.tscn` traz hoje **12 NPCs**: 6 fazendeiros (4 patrulhando,
2 trabalhando parados), 3 moradores e 3 policiais a pé, todos sobre o mesmo
chassi e a mesma behavior tree ([npcs.md](npcs.md)). As paradas de rotina são
`NPCActivity` gerados junto com a cena.

## Missão e destroços

O objetivo desta fase — achar a nave caída e recuperar a tecnologia — é
controlado por `scripts/country_town.gd`, o script de raiz da cena (não
`world.gd`, usado pelas outras fases). Fluxo completo, incluindo o embarque na
órbita, em [fluxo de jogo](fluxo-de-jogo.md#missão-de-resgate-country-town).

- Todo nó do grupo `alien_debris` nasce oculto (`AlienDebris.set_discovered(false)`)
  no `_ready()` da cena; aproximar-se do marcador `AlienCrashSite` (raio de
  14 m, ponto de interesse já existente em `Layout/PointsOfInterest.tscn`)
  revela os oito destroços e o `DebrisLocator` de `AlienDebrisTest.tscn`.
- `AlienDebrisTest.tscn` é gerada por `tools/build_country_town_debris.gd`: a
  receita fixa oito posições XZ manuais (poço, girassóis, celeiro/silo,
  estrada, quintal, casa, comércio e o motor) e projeta a altura no
  `Terrain3D` real. **Regenere essa cena em vez de editá-la** se mudar
  posição, tipo ou contagem de destroços — ver
  [ferramentas.md](ferramentas.md#geradores-de-asset).
  As definições de item (`resources/alien_items/*.tres`, `AlienItemDefinition`)
  são dados puros: mesh, forma de colisão, `slot_cost`, `score_value`,
  `is_locator` e `transportable`. O `engine_wreck` é o único não
  transportável (`transportable = false`) — não pode ser guardado no
  inventário nem pego na mão, só existe como obstáculo/trófeu maior
  (`score_value = 100`, contra 10 dos demais).
- `DebrisLocator` (`scripts/debris_locator.gd`, `RefCounted`) é o algoritmo do
  "detector de metais": acha o `AlienDebris` mais próximo, com histerese de
  direção (8 setores) e de força (5 níveis) para não oscilar com o jogador
  quase parado. `scripts/debris_locator_hud.gd` (`DebrisLocatorHUD.tscn`,
  instanciada por `player_hud.gd`) só aparece enquanto o equipamento
  "Debris Locator" está selecionado no inventário de exploração.
- **Entrega**: `scenes/RecoveryPoint.tscn` reúne uma `RecoveryZone`
  (`scripts/recovery_zone.gd`, área de "ponto de coleta") e uma `RecoveryShip`
  (`scripts/recovery_ship.gd`, reaproveita o visual de `space_ship.tscn`).
  O jogador só **larga** o item dentro do círculo; a nave sobrevoa
  periodicamente, recolhe quem tiver a meta `recovery_dropped` (setada em
  `spaceship_scraps.gd.drop()`) e pontua no `GlobalScore` sozinha — sem exigir
  presença contínua do jogador, ao contrário do `delivery_area.gd` (segurar
  `interact`). `RecoveryZone` também entra no grupo `delivery_areas` para
  participar da arbitragem de `interact` do Player, mas não implementa
  `reserves_interaction_for` — nunca reserva a tecla, só é encontrável pela
  busca por grupo.

## Ao alterar

Comece pela receita da parte afetada, preservando os nomes dos POIs e as
instâncias compartilhadas. Para comandos, dependências de regeneração e
checagens, consulte [tools/VALIDACAO.md](../tools/VALIDACAO.md#geração-do-country-town).

## Limitações atuais

O cenário está fechado, os NPCs andam e a missão de resgate (destroços,
localizador e entrega pela `RecoveryShip`) já é jogável; falta uma armadilha
de ameaça própria desta fase. A lista completa, com o que é cenário e o que
reusa a fazenda, está em **Limitações conhecidas**, no
[`../README.md`](../README.md).
