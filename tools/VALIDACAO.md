# Como validar uma alteração no ET Game

Procedimento de validação do projeto, válido para qualquer agente ou pessoa.
As regras de política ficam em `AGENTS.md`, na seção Validação; aqui está o
como fazer.

O padrão é não validar: a maior parte das mudanças vai direto. Rode algo
apenas nos casos listados em `AGENTS.md`, uma vez, depois da última edição, e
repita só se o código mudar depois da checagem ou se o ciclo rodar/medir fizer
parte da depuração.

## Comandos

Checagem de parsing, importação e referências ausentes:

```powershell
.\tools\godot.cmd --headless --path . --editor --quit
```

Uma ferramenta de `tools/`:

```powershell
.\tools\godot.cmd --headless --path . --script res://tools/<tool>.gd
```

No Country Town, os geradores de layout e settlement usam malhas nativas e
aceitam `--headless`. Campos e vegetação ainda usam `MultiMesh` e precisam de
rasterização real. `RoadNetwork.tscn` deve conter `AsphaltRoadBed`,
`Sidewalks`, `Curbs` e `TireTracks`, mais o `DirtRoadBed` reduzido às abas das
pontes; as marcas das trilhas rurais ficam no `TireTracks` de `SecondaryPaths`.

Omita `--headless` quando a checagem depender de rasterização de verdade —
render, screenshot, culling — porque o driver dummy não desenha nada:

```powershell
.\tools\godot.cmd --path . --script res://tools/<tool>.gd --resolution 1280x720
```

**No Windows, use o executável terminado em `_console.exe`**: só ele manda
`print()` para o stdout. O wrapper `tools/godot.cmd` procura, nesta ordem:

1. `C:\Godot_v4.8\Godot_v4.8-dev4_win64_console.exe`;
2. `D:\Program Files\Godot\Godot_v4.8\Godot_v4.8-dev4_mono_win64_console.exe`;
3. `godot` disponível no `PATH`.

Não rode uma segunda instância do Godot enquanto o editor estiver aberto no
mesmo projeto: as duas concorrem pelo cache em `.godot/`.

## Qual ferramenta para cada sistema

| Sistema alterado | Ferramenta |
| --- | --- |
| Estados visuais e `AnimationTree` do Player | `tools/test_player_animation.gd` |
| Pulo e consumo de stamina | `tools/test_player_jump_stamina.gd` |
| Subida/descida de degraus, teto livre e limite de step | `tools/test_player_steps.gd` |
| Freada e pivô em reversões bruscas | `tools/test_player_reversal.gd` |
| Ragdoll e recuperação | `tools/test_player_ragdoll.gd` |
| Tripulante da nave caído no chão | `tools/test_ship_crew_downed.gd` |
| Ciclo de velocidade e voo do `F4` | `tools/test_player_debug_modes.gd` |
| Enquadramento e colisão da câmera | `tools/test_cinematic_camera.gd` |
| Travessia, velocidade e recorte dos portais | `tools/test_portal_teleportation.gd` |
| Presets de névoa e evento alienígena | `tools/test_atmosphere_presets.gd` |
| Filtro de interferência alienígena | `tools/test_alien_interference.gd` |
| Casco interno da nave (frestas) | `tools/check_tapered_shell.gd` |
| Patrulha do NPC genérico na nave | `tools/test_generic_npc_navigation.gd` |
| IA de NPCs com Beehave (fazendeiro, componentes de visão/audição/rotina) | `tools/test_farmer_npc_behavior.gd` |
| Animação Idle/Walk dos NPCs (rig e trilhas) | `tools/test_npc_animation.gd` |
| Custo de render da atmosfera | `tools/measure_atmosphere_cost.gd` (sem `--headless`) |
| Layout do mapa Country Town | `tools/check_country_town_layout.gd` |
| Edificacoes e passagem nas estradas principais, ruas locais e trilhas do Country Town | `tools/check_country_town_clearance.gd` |
| Escala das casas, divisas e acessos de pedestres/carros nos lotes | `tools/check_country_town_neighborhood.gd` |
| Tabuleiro e parapeitos da ponte do Country Town | `tools/check_country_town_bridge.gd` |
| Piso viário salvo, rampas, asfalto e folga sobre o terreno | `tools/check_country_town_roads.gd` |
| Marcas de pneu de autoria sobre as vias | `tools/build_tire_tracks.gd` |

`tools/bake_police_patrol_route.gd` regera o grafo de ruas que a viatura de
polícia patrulha (o `road_nodes` do nó `AIDriver` em
`scenes/Vehicles/PoliceCarDriveable.tscn`). A IA não consegue ler
`build_country_town_layout.gd` em tempo de execução, então os centros dos tiles
ficam gravados na cena; rode esta ferramenta e cole a linha impressa sempre que
`ROAD_RUNS` mudar, senão a patrulha continua dirigindo pela grade antiga.

`tools/build_mixamo_character.py`, `tools/render_prototype_icons.py`,
`tools/build_country_town_layout.gd`, `tools/build_country_town_terrain.gd`,
`tools/build_country_town_fields.gd`, `tools/build_country_town_settlement.gd`
e `tools/build_country_town_vegetation.gd`
são utilitários de geração de asset, não checagens. Campos e vegetação precisam
rodar sem `--headless`, porque o driver dummy não preserva buffers de MultiMesh.
A ordem completa é layout, terreno, settlement, campos e vegetação. O terreno
reimporta as regiões do zero, por isso o plantio vem depois.

`tools/build_rural_roads.gd` tira o piso de terra das vias rurais e das trilhas
— o rastro é feito por `build_tire_tracks.gd` — e regrava `RoadNetwork.tscn` e `SecondaryPaths.tscn`.
Aceita `--headless`, mas carrega o terreno: as fitas assentam na altura real do
chão. Rode depois de mudar `ROAD_RUNS`, `SECONDARY_PATHS` ou o preset
`Materiais/rural_road_gentle.tres`, junto com `build_terrain_surface.gd` — uma
faz as marcas, a outra a faixa de terra que o terreno pinta sob elas — e antes de
`check_country_town_roads.gd`. O recorte das abas de ponte é idempotente: a malha
original do piso fica guardada em `rural_base_mesh`.

`tools/build_tire_tracks.gd` assa as marcas de pneu
(`scenes/Props/TireTrack3D.tscn`) dos distritos contra o terreno atual, remove o
`WheelTracks` antigo e regrava as cenas. Aceita `--headless` e carrega o
terreno. Sem argumento ela preserva as curvas que já estão em cena; com
`-- --reseed` descarta o nó `TireTracks` e semeia tudo de novo a partir do
layout, o que apaga edições manuais. Só é necessária quando o relevo mudar ou
quando uma curva for editada sem o editor aberto — no editor, o próprio nó
reassa a marca ao mexer na curva ou nos parâmetros, e o botão *Reassar marca*
força a reconstrução. A textura de banda
(`Texturas/tire_tread.res`) vem de `tools/build_tire_tread_texture.gd`, que só
precisa rodar se o desenho do pneu mudar.

`tools/build_terrain_surface.gd` gera apenas dados de material: normais/rugosidade
das três texturas locais e a máscara de uso do solo do Country Town. Aceita
`--headless`, não carrega o mundo e não altera relevo, colisão ou vegetação.
Execute após mudar texturas-base, traçado, talhões, clareiras ou marcadores de
pátios, em cópia isolada se o editor estiver aberto. Para conferir o visual,
observe pasto/estrada/cultivo no nível do jogador e do alto; não use headless
como comprovação da aparência ou do custo de GPU.

Alterações em vias urbanas ou larguras exigem regenerar layout e terreno.
Alterações apenas em lotes e objetos começam pelo settlement. A checagem de
passagem informa o caminho completo dos objetos que obstruem as vias.

Quando o usuário solicitar inspeção visual, use uma cópia isolada e execute:

```powershell
.\tools\godot.cmd --path . --script res://tools/inspect_country_town_roads.gd --windowed --resolution 1600x1000
```

As sete capturas ficam em `build/country-road-review/`. O script usa iluminação
de inspeção e remove o jogador apenas da instância temporária; não altera o
ambiente salvo. Acrescente `-- --scene-lighting` para usar a iluminação real.
Confira também a cor da terra na fazenda, além da cidade e das duas pontes.

Os complementos gerados usam `country_town_composition` para identificar
agrupamentos e `country_town_block` para identificar objetos: a altura é
conferida por objeto, sem usar o centro do distrito inteiro como se fosse um
prédio. Avisos de vãos pequenos entre móveis e cargas continuam sendo emitidos.

## Roteiros manuais

Resultado visual, de câmera, física, IK, navegação, interação ou gameplay quem
julga é o usuário, no editor que ele já tem aberto. Não abra o jogo para isso;
diga o que ele deve conferir, usando os roteiros abaixo.

- **Coleta e entrega:** pegue, largue e entregue um item solto e um item
  carregado; confirme a pontuação no console.
- **Veículo:** entrada, direção, troca de câmera, saída e devolução do controle
  ao jogador.
- **Fazendeiro:** patrulha, detecção, perseguição, perda do alvo e estado de
  disparo.
- **NPCs do Country Town (Beehave):** abra `CountryTown.tscn`, confira que os
  12 NPCs (6 fazendeiros, 3 moradores, 3 policiais) ficam de pé em idle e
  trocam para a caminhada ao se deslocar; observe o fazendeiro
  patrulhador do núcleo original
  (`Farmhouse → Barn → CornField → FarmerTractorSpot`) e os outros cinco
  espalhados pelos demais núcleos de fazenda; aproxime-se de um para ver
  `Alert` virar `Chase`, afaste-se e confira `Search` seguido do retorno
  sozinho à rotina; confira também os três moradores (fogem) e os três
  policiais patrulhando `GeneralStore`/`TownSquare`/`Church`.
- **Country Town:** confira fachadas e calçadas em volta da praça, percorra
  as ruas locais e as trilhas do curral ao moinho/ancoradouro e observe o
  assentamento dos pátios nas encostas, a silhueta do silo e da nave caída.

## Escrever uma verificação nova

- Imprima diagnóstico em texto e saia com `quit(1)` ao falhar.
- Em falhas espaciais, informe as coordenadas do mundo.
- Screenshot serve só como inspeção visual final, nunca como o critério.
- Testes de unidade, se forem adicionados: prefira GUT, em `test/unit` e
  `test/integration`.
- Nunca remova nem enfraqueça uma validação para esconder falha.
- Nunca declare algo testado sem ter executado.
