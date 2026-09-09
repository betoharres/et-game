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

## Receitas e dependências

Localize a receita pela saída em [ferramentas.md](ferramentas.md#geradores-de-asset).
A ordem de execução, os argumentos, os efeitos de regenerar e a escolha de
checagens ficam em [tools/VALIDACAO.md](../tools/VALIDACAO.md#geração-do-country-town).

- O layout define o traçado (`ROAD_RUNS`) e os pontos de interesse; o relevo
  se adapta a esse traçado. Os dados do terreno deste mapa ficam separados
  dos da fazenda.
- O settlement compõe os lotes e complementos. A receita de lotes é
  `tools/country_town_neighborhood.gd` (medidas em metros, frente local `-Z`);
  `tools/country_town_road_surface.gd` monta polígonos do piso. São bibliotecas
  `RefCounted`, não ferramentas executáveis.
- A vegetação do instancer é salva nas regiões do Terrain3D. Recriar o terreno
  remove esse plantio; não o trate como uma cena independente.
- A população usa corredores, pátios e colisões dos distritos para gerar
  `Layout/PedestrianNavigation.res`, `Districts/NPCs.tscn` e atividades.
- As curvas de `TireTrack3D` admitem autoria no editor; o gerador preserva as
  existentes sem `--reseed`. Essa opção descarta a autoria. Confira os
  argumentos antes de regenerar cenas que contêm marcas.

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

## Ao alterar

Comece pela receita da parte afetada, preservando os nomes dos POIs e as
instâncias compartilhadas. Para comandos, dependências de regeneração e
checagens, consulte [tools/VALIDACAO.md](../tools/VALIDACAO.md#geração-do-country-town).

## Limitações atuais

O cenário está fechado e os NPCs andam, mas o mapa ainda não tem gameplay:
faltam armadilha, destroço coletável e entrega funcional. A lista completa, com
o que é cenário e o que reusa a fazenda, está em **Limitações conhecidas**, no
[`../README.md`](../README.md).
