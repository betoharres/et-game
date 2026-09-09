# Mundo: mapas, terreno e vegetação

Um mapa é uma cena que monta terreno, ambiente, jogador, NPCs, veículos,
destroços e área de entrega. Não há manager: o que liga as peças são grupos e
sinais ([arquitetura.md](arquitetura.md)).

| Mapa | Cena | Situação |
| --- | --- | --- |
| Fazenda | `scenes/world.tscn` + `scripts/world.gd` | Único mapa do catálogo de fases; montado à mão |
| Country Town | `scenes/CountryTown/CountryTown.tscn` | Em construção, **fora do catálogo**, quase todo gerado por ferramentas — ver [country-town.md](country-town.md) |
| Casa modular | `scenes/Buildings/House01.tscn` | Interior autocontido — ver [casas-interiores.md](casas-interiores.md) |
| Masmorra | `scenes/Dungeon/` | Corredores procedurais, gerados a partir de uma porta na fazenda |

## Fazenda (`world.tscn`)

Além do jogador, do ambiente e dos NPCs, `scripts/world.gd` conduz a chegada:
posiciona o ET sobre o convés da nave, faz a nave descer pelo céu, troca o
perfil de névoa entre voo e chão, dispara o feixe de chegada e devolve o
controle ao jogador no toque no solo. Quando a fase é aberta direto no editor
(`MissionFlow.arrived_from_orbit == false`), a cutscene roda automaticamente.

Estrutura de topo: `NightEnvironment`, `PauseMenu`, `PhotoAlertHUD`,
`SpaceShip`, `NavigationRegion3D` (com o `Terrain3D` dentro), `PropsHolder`,
prédios, NPCs, veículos, destroços, `DeliveryArea` e o minimapa.

Pontos a saber antes de mexer:

- A `NavigationRegion3D` da fazenda **nunca foi bakeada**. A luz viva voa por
  sonda de chão, sem desvio de obstáculo pela navegação; dentro da nave a malha
  cobre apenas a plataforma.
- Os dados do terreno da fazenda são os `terrain3d_*.res` soltos em
  `res://scenes` — o Country Town tem diretório próprio e os dois nunca se
  misturam.
- A vegetação da fazenda é instanciada nó a nó na cena (milhares de linhas de
  `.tscn`); a do Country Town usa o instancer do Terrain3D. Não copie o padrão
  da fazenda para mapas novos.

## Terreno

- Addon **Terrain3D** (`addons/terrain_3d/`), com o material derivado em
  `shaders/terrain_natural.gdshader` (licença MIT registrada no arquivo).
- `tools/build_terrain_surface.gd` gera **apenas dados de material**: normais e
  rugosidade das texturas locais e a máscara de uso do solo do Country Town.
  Não mexe em relevo, colisão nem vegetação.
- O relevo do Country Town é gerado por `tools/build_country_town_terrain.gd`,
  que reimporta as regiões do zero — por isso qualquer plantio vem depois dele.

## Vegetação

| Peça | Onde |
| --- | --- |
| Plantações reativas (milho, trigo, girassol) | `scripts/reactive_crop.gd` + `scenes/AnimatedCrops/` |
| Árvores, arbustos e tufos de grama | `scenes/Vegetation/` |
| Ocultamento do ET | `scripts/vegetation_concealment.gd`, grupo `concealment_areas` |

`reactive_crop.gd` é a base do milho, do trigo e do girassol: cada filho
`MeshInstance3D` é uma planta que balança com o vento e verga para longe de
quem passa — personagens do grupo `characters` e veículos do grupo `vehicles` —
voltando sozinha ao repouso. O custo por instância é a restrição de projeto:
cada instância carrega `visibility_range` e raio de atividade, porque um talhão
grande é feito de muitas cópias da mesma cena.

A vegetação que esconde o ET registra-se como área de ocultamento e chama
`enter_concealment()` / `exit_concealment()` no Player, reduzindo o alcance de
detecção dos NPCs.

## Estradas e marcas de pneu

- `scripts/terrain/rural_road_profile.gd`: perfil do piso das vias rurais. Hoje
  o chão visível é o próprio terreno; só sobram abas de piso nas cabeceiras de
  ponte, por causa das rampas.
- `scripts/terrain/tire_track_3d.gd` + `scenes/Props/TireTrack3D.tscn`: marcas
  de pneu desenhadas sobre uma `Curve3D` de autoria, assadas no editor e salvas
  na cena — em jogo nada é gerado. Várias instâncias podem se sobrepor: o
  material dissolve as bordas.

## Masmorra procedural

`scenes/Dungeon/` + `scripts/dungeon/`.

- `dungeon.gd` monta um labirinto plano numa grade: um spanning maze garante que
  toda célula é alcançável e algumas ligações extras criam loops.
- O módulo de cada célula é escolhido **inteiramente** pela máscara de conexões
  Norte/Leste/Sul/Oeste. `dungeon_module.gd` é a base; `_h`, `_l`, `_t`, `_u` e
  `_x` só declaram a máscara-base e são girados pelo gerador.
- Destroços são plantados nos becos sem saída, entrando no mesmo fluxo de coleta
  e entrega.
- `dungeon_door.gd` é a porta na fazenda que gera a masmorra uma vez por sessão.
- Ainda não há inimigos, salas especiais nem variação vertical.

## Portais

`scenes/Portal/portal.tscn` + `scripts/portal/portal.gd`: par de portais com
renderização cruzada (`SubViewport` por portal e frustum oblíquo para recortar o
que fica atrás do plano) e teletransporte com cooldown. Cena de teste isolada.

## Ao alterar

1. Mapa novo ou mudança estrutural num mapa: comece pela cena mestre e mantenha
   cada sistema na sua cena reutilizável.
2. Terreno do Country Town: nunca escreva no diretório de dados da fazenda, e
   vice-versa.
3. Vegetação nova em quantidade: pense em custo por instância antes de
   multiplicar cenas (`visibility_range`, raio de atividade, instancer).
4. Validação: `tools/check_country_town_*` para o Country Town
   ([country-town.md](country-town.md)), `tools/test_portal_teleportation.gd`
   para portais. Resultado visual quem julga é o usuário, no editor.
