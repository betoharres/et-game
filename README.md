# ET Game

Protótipo 3D single-player em Godot no qual um extraterrestre explora uma
fazenda, coleta destroços de uma nave e os leva até uma área de entrega. O
cenário inclui vegetação reativa, uma caminhonete dirigível, um fazendeiro que
persegue o jogador e um fotógrafo que o expõe.

A documentação por sistema — arquitetura, player, NPCs, veículos, mundo,
casas, animação, ambientação e UI — fica em `docs/`, com o índice em
`docs/README.md`. As regras de trabalho para agentes ficam em `AGENTS.md`.

Este README descreve **o que existe e onde fica**. Valores de ajuste
— velocidades, tempos, distâncias, parâmetros de névoa e de câmera — ficam nos
exports das cenas e nas constantes dos scripts, que são a fonte da verdade. Os
comandos das ferramentas de geração e de checagem ficam em `tools/VALIDACAO.md`.

## Índice

- [Tecnologias e ambiente](#tecnologias-e-ambiente) — versão do Godot, renderer, física e formatos de asset.
- [Estrutura principal](#estrutura-principal) — pastas do projeto e cenas de entrada.
- [Executar](#executar) — abrir no editor e rodar pelo PowerShell.
- [Fluxo atual](#fluxo-atual) — menu, órbita, missão, coleta e entrega.
- [Controles](#controles) — teclas e ações do Input Map.
- [Arquitetura](#arquitetura) — cenas, autoloads, grupos e cadeias de interação.
- [Mapas e cenas geradas](#mapas-e-cenas-geradas) — fazenda, Country Town, casa modular e masmorra.
- [Limitações conhecidas](#limitações-conhecidas) — o que ainda não existe ou é provisório.
- [Qualidade e validação](#qualidade-e-validação) — checagem no editor e ferramentas de `tools/`.
- [Documentação por sistema](#documentação-por-sistema) — o que ler em `docs/` antes de alterar cada sistema.

## Tecnologias e ambiente

- Godot `4.8 dev4` com GDScript e cenas `.tscn`; essa versão é necessária para
  o `Trail3D` nativo da luz viva.
- Renderer `Forward Plus` com Direct3D 12 no Windows, em tela cheia com
  resolução-base `1920×1080`.
- Física 3D com Jolt Physics.
- Terreno com Terrain3D; modelos `.fbx`/`.glb`, com texturas e materiais rurais.
- Behavior Trees dos NPCs com o addon [Beehave](https://github.com/bitbrain/beehave)
  (MIT, vendorado em `addons/beehave/`).
- Export para Windows Desktop `x86_64` em `export_presets.cfg`.

## Estrutura principal

| Pasta | Conteúdo |
| --- | --- |
| `scenes/` | Todas as cenas do jogo, incluindo `Space/`, `CountryTown/`, `Buildings/`, `NPCs/`, `Dungeon/` e `Portal/` |
| `scripts/` | GDScript, espelhando a organização das cenas (`space/`, `levels/`, `npc/`, `dungeon/`, `audio/`) |
| `shaders/` | Céu procedural, névoa rasteira, terreno e efeitos |
| `tools/` | Checagens automatizadas e utilitários de build de asset (ver `tools/VALIDACAO.md`) |
| `animations/mixamo/` | Rig visual único, FBX de origem, GLB gerado e mapeamento |
| `assets/` | Áudio, fontes e música do menu |
| `Texturas/ui/` | Ícones do HUD, gerados por `tools/render_prototype_icons.py` |
| `3dModelos/`, `Texturas/`, `Materiais/` | Assets importados e materiais reutilizáveis |

Cenas de entrada:

| Cena | Papel |
| --- | --- |
| `scenes/Menu/main_menu.tscn` | Cena principal do projeto: menu, opções e remapeamento |
| `scenes/Menu/CharacterCreator.tscn` | Personalização 3D exibida entre Jogar e a órbita |
| `scenes/Space/Orbit.tscn` | Órbita jogável com o terminal de seleção de missão |
| `scenes/world.tscn` | Mapa da fazenda, onde a partida acontece |
| `scenes/Player.tscn` | ET, câmera, rig Mixamo, `AnimationTree` e IK de ação |
| `scenes/Space/AlienShip.tscn` | Nave reutilizada na órbita, na fazenda e no Barn |
| `scenes/NightEnvironment.tscn` | Céu, Lua, névoa, iluminação e filtro de tela da fazenda |

## Executar

Abra `project.godot` no Godot 4.8 dev4 ou mais novo e pressione `F5`. Pelo
PowerShell, use o wrapper do projeto, que procura primeiro o dev4 em
`C:\Godot_v4.8`, depois o dev4 Mono legado e, por último, o Godot no `PATH`:

```powershell
.\tools\godot.cmd --path .            # rodar o jogo
.\tools\godot.cmd --editor --path .   # abrir o editor
```

Depois de exportado, o jogo abre direto por `build/ETs.exe`, sem o editor.

## Fluxo atual

```text
Menu -> criar ET -> nave em orbita -> terminal de missao -> aproximacao -> nave descendo no ceu da fazenda -> raio trator -> coletar -> entregar
```

- O jogador personaliza sete características do ET em valores normalizados de
  `0` a `1`; `Iniciar jogo` salva o perfil em `user://character_appearance.cfg`.
- Na órbita, um terminal lista o catálogo de fases. Adicionar uma fase não
  exige mexer em script: basta um `LevelDefinition.tres` apontando para a cena
  e listado em `level_catalog.tres`.
- Na fase, a nave desce do céu e estaciona sobre o ponto de chegada; pisar no
  pad e interagir aciona a descida pelo feixe. Abrir `world.tscn` direto no
  editor pula esse passo.
- Destroços podem ser carregados e largados. Para entregar, o jogador larga o
  item na plataforma e sustenta o sinal de intervenção alienígena; o feixe suga
  o item até a nave e só então soma o `score_value` ao `GlobalScore`.
- Um spider bot acompanha a nave, desce pelo feixe quando detecta um destroço
  ao alcance e leva o item até a plataforma.
- O fazendeiro patrulha, persegue e atira; o fotógrafo acende até três
  estrelas, que solicitam respostas futuras de polícia, imprensa e MIB.
- A vegetação oscila com o vento, inclina-se perto de personagens e veículos e
  esconde parcialmente o ET, reduzindo o alcance de detecção dos inimigos.
- O ET tem vida, stamina e equilíbrio: colidir correndo ou cair provoca
  tropeço e, no limite, um ragdoll do qual ele se levanta sozinho.
- A pontuação atual aparece apenas no console de depuração.

Cenas de teste isoladas: `interior_space_ship_room_1.tscn` (gravidade radial),
`Portal/portal.tscn` (par de portais com renderização cruzada) e
`FlyablePlane.tscn` (avião controlável).

## Controles

| Ação | Tecla |
| --- | --- |
| Mover o ET / dirigir a caminhonete | `WASD` |
| Câmera | Mouse |
| Correr | `Shift` (consome stamina; bloqueado no ar) |
| Pular / agachar | `Espaço` / segure `C` |
| Coletar ou largar item | `E` |
| Pegar no colo ou soltar um ET caído | `E` |
| Interagir: terminal, pad de descida, entrar e sair da caminhonete | `E` |
| Solicitar a abdução de um item na área de entrega | Segure `E` |
| Luz dos olhos do ET | `F` |
| Primeira pessoa (a pé ou na caminhonete) | `V` |
| Binóculos / zoom | `B` / `+` e `-` do teclado numérico |
| Minimapa circular | `F3` |
| Velocidade e voo (a cada toque) | `F4` |
| Debug de iluminação | `F6` |
| Menu de pausa | `Esc` |

No avião, o mouse move o alvo que orienta o voo; `E` assume ou devolve o
controle perto da cabine.

O `F4` não abre menu: cada toque avança um degrau do ciclo `desligado` ->
`velocidade` (imortalidade, stamina cheia e velocidade 5×) -> `velocidade e
voo` (sem gravidade) -> `desligado`. O menu `F6`, disponível globalmente
durante o jogo, traz o preset de atmosfera e cada fonte de luz da cena atual.

As interações usam uma ação própria para que `Espaço` fique reservado ao pulo.
O menu de opções remapeia as teclas de movimento e o menu de pausa remapeia as
demais ações; os remapeamentos duram a sessão.

## Arquitetura

O projeto é composto por cenas reutilizáveis. Um mapa (`world.tscn`,
`CountryTown.tscn`) monta terreno, ambiente, jogador, NPCs, veículos, destroços
e área de entrega; nenhum manager global orquestra isso.

Esta seção é o resumo; o detalhamento por sistema — responsabilidades, contratos
e decisões — está em `docs/` (ver [Documentação por sistema](#documentação-por-sistema)).

```text
Player -> grupo pickup_items -> pickup/drop -> DeliveryArea -> sinal/abdução -> GlobalScore
MainMenu -> CharacterCreator -> Orbit -> terminal de missão -> LevelCatalog -> world.tscn -> pad de descida -> feixe de chegada
CharacterAppearance -> CharacterProportions -> Skeleton3D/olhos -> Player e ET do veículo
SmellyFarmer/Photographer -> visão -> perseguição/foto -> vida do Player / PhotoAlertSystem
NPCActor -> NPCVision/NPCHearing -> NPCBehaviorTree (Beehave) -> NPCRoutine/NPCActivity
Player -> grupo characters -> vegetação e detecção dos inimigos
DriveableTruck -> grupo vehicles -> direção e reação da vegetação
Player -> estado físico -> PlayerAnimationController -> AnimationTree -> Mixamo -> IK -> ragdoll
NightEnvironment -> AgX/glow/névoa -> filtro de incidente alienígena
FogZone -> grupo fog_zones -> GroundFogLayer -> densidade local da névoa
```

- **Autoloads:** `CharacterAppearance` (características do ET, persistidas),
  `GlobalScore` (pontuação e inventário), `PhotoAlertSystem` (estrelas e
  observadores), `SceneTransition` (transições entre cenas) e `DebugMenus`
  (modos do jogador no `F4` e painel de iluminação no `F6`).
- **Grupos** conectam sistemas sem referência direta: `characters`, `vehicles`,
  `pickup_items`, `ship_passengers`, `fog_zones` e `volumetric_lights`.
- **Contrato de coletáveis:** grupo `pickup_items`, métodos `pickup()` e
  `drop()` e propriedade `score_value`. Um item em abdução deixa o grupo
  temporariamente para não ser recolhido antes da entrega.
- **Jogador:** `player.gd` cuida de input, física, equilíbrio e decisões e envia
  o estado ao `PlayerAnimationController`, que centraliza a máquina de estados
  do `AnimationTree`. O rig é um único `Skeleton3D` Mixamo com as animações
  in-place — o `CharacterBody3D` é a única autoridade de deslocamento. Sobre a
  animação base atuam apenas dois `LookAtModifier3D` e um `TwoBoneIK3D` no
  braço direito. O step-up de degraus fica no próprio controlador
  (`max_step_height`).
- **Proporções do ET:** sem Blend Shapes no GLB, `CharacterProportions` aplica
  escala de bones em um `SkeletonModifier3D` pós-animação, uma barriga
  procedural presa ao bone e shaders para pele e olhos. O perfil é um
  dicionário pequeno; `Player` expõe `get_appearance_replication_payload()` e o
  RPC `sync_appearance()` para uma futura camada multiplayer.
- **Ragdoll reversível:** `player_ragdoll.gd` gera os corpos físicos e serve
  tanto à morte quanto à queda por desequilíbrio.
- **Veículo:** desativa processamento e câmera do jogador, exibe o ET no banco e
  restaura o personagem na saída.
- **NPCs (Beehave):** `NPCActor` é o chassi (navegação, patrulha, velocidades,
  `reaction_mode`); `NPCVision` e `NPCHearing` são os sensores; a árvore
  reativa de `scenes/NPCs/Behaviors/NPCBehaviorTree.tscn` só decide, com uma
  folha por responsabilidade em `scripts/npc/behaviors/`. Fazendeiro, morador e
  policial compartilham essa árvore e mudam apenas exports. `NPCActivity` e
  `NPCRoutine` reservam e liberam as vagas de cada parada. Os clipes Synty só
  funcionam no rig de `Temporarios/Animations/Meshes/PolygonSyntyCharacter.fbx`.
- **HUDs** reutilizam o tema `Materiais/hud_theme.tres` e uma família única de
  ícones gerada dos meshes low-poly `Polygon Prototype`.
- **Minimapa** (`scenes/VisionDebugMap.tscn`, `F3`): cena reutilizável, uma
  instância por mapa, sem nada específico de fase no script. O que muda por
  mapa são exports do nó `Overlay` (`world_radius`, `objective_group`,
  `landmark_group`, `actor_scan_interval`).
- **Ambientação:** `NightEnvironment` concentra presets de qualidade, névoa e
  evento alienígena; `FogZone` adensa a névoa localmente; o chão usa
  `shaders/terrain_natural.gdshader`, derivado do Terrain3D instalado
  (licença MIT no arquivo).

## Mapas e cenas geradas

- **Fazenda** (`scenes/world.tscn`): o mapa jogável do catálogo, montado à mão.
- **Country Town** (`scenes/CountryTown/CountryTown.tscn`): mapa de `600 × 450 m`
  em construção, **fora do catálogo de fases** — abre direto pelo editor. A cena
  mestre só instancia terreno, ambiente, jogador e os distritos de
  `Districts/`, e quase tudo é gerado: relevo, estradas, rio, pontes, talhões,
  vegetação, complementos urbanos e rurais e a população de 12 NPCs saem das
  ferramentas de `tools/`. As receitas ficam nos scripts de layout; edite as
  receitas, não as cenas geradas. A ordem de execução, o efeito de cada
  ferramenta e as checagens correspondentes estão em `tools/VALIDACAO.md`.
- **Casa modular** (`scenes/Buildings/House01.tscn`): primeira casa em que
  Player e NPCs entram, em cena separada e autocontida, com porta automática
  (`scripts/house_door.gd`) e pontos de atividade que o `NPCActor` já conhece.
  `scenes/Buildings/HouseTest.tscn` é a cena de teste. Gerada por
  `tools/build_house_01.gd`.
- **Masmorra** (`scenes/Dungeon/`): corredores procedurais planos, gerados uma
  vez por sessão a partir de uma porta na fazenda; guarda destroços nos becos
  sem saída, no mesmo fluxo de coleta e entrega.

## Limitações conhecidas

- A nave que desce na fazenda e a `SpaceShip` que já existia na cena são
  redundantes, e não há caminho de volta à órbita.
- O catálogo tem só a Fazenda; Cidade e Deserto são exemplos bloqueados.
- O disparo usa dano instantâneo e clarão provisório, sem projétil físico.
- Polícia, imprensa e MIB existem apenas como sinais e mensagens de
  placeholder, sem cenas nem spawn.
- A pontuação não tem HUD, objetivo final nem persistência, e o inventário do
  autoload não está integrado ao fluxo de coleta.
- Opções e remapeamentos não são salvos entre execuções.
- Não há sessão multiplayer nem arquitetura de servidor; apenas o payload e o
  ponto de aplicação das proporções estão prontos para replicação futura.
- A névoa rasteira não recebe luz das fontes do mapa; com a volumetria
  desligada, feixes e holofotes não formam cones de luz no ar.
- A queda não causa dano nem é percebida pelos NPCs, e durante o ragdoll a
  cápsula de colisão fica desabilitada.
- A masmorra não tem objetivo além dos destroços: sem inimigos, salas especiais
  nem variação vertical.
- No Country Town o cenário está fechado e os NPCs já andam, mas faltam
  armadilha, destroço coletável e entrega funcional; a sucata da queda é
  cenário, o portal da mina é só a moldura e o áudio ambiente reusa posições
  fixas da fazenda.
- A `NavigationRegion3D` da fazenda nunca foi bakeada: ali a luz viva voa por
  sonda de chão, sem desvio de obstáculo pela navegação. Dentro da nave, a
  malha cobre apenas a plataforma de `9×9 m`.
- A origem e a licença dos assets em `3dModelos/` e `Texturas/`, do pacote
  `Polygon Prototype` e dos FBX Mixamo não estão confirmadas. Áudio, ícones e
  animações têm procedência registrada em `assets/audio/SOURCE.md`,
  `Texturas/ui/SOURCE.md` e `animations/mixamo/SOURCE.md`; confirme os termos
  antes de redistribuir.

## Qualidade e validação

Depois de alterar GDScript, cenas ou `project.godot`, confirme que não há erros
de importação, parsing ou referências ausentes:

```powershell
.\tools\godot.cmd --headless --path . --editor --quit
```

As verificações automatizadas ficam em `tools/`, uma por sistema. Rode a do
sistema que você alterou:

```powershell
.\tools\godot.cmd --headless --path . --script res://tools/<tool>.gd
```

`tools/VALIDACAO.md` tem o mapa completo de ferramenta por sistema, os
utilitários de geração de asset, os roteiros de teste manual e as regras para
escrever uma verificação nova. No Windows, use o executável terminado em
`_console.exe`: só ele manda `print()` para o stdout. Resultado visual, de
câmera, física, IK, navegação ou gameplay precisa de conferência em uma
execução normal.

## Documentação por sistema

`docs/` guarda a documentação persistente dos sistemas: relações entre eles,
arquivos importantes, responsabilidades e decisões arquiteturais. É o que ler
antes de alterar cada parte do jogo.

| Documento | Cobre |
| --- | --- |
| `docs/arquitetura.md` | Cenas de entrada, autoloads, grupos, contratos, camadas e convenções |
| `docs/fluxo-de-jogo.md` | Menu, órbita, catálogo de fases, chegada, coleta e entrega |
| `docs/player.md` | O ET: movimento, sobrevivência, câmera, aparência, ragdoll |
| `docs/npcs.md` | `NPCActor`, sensores, behavior tree Beehave e rotinas |
| `docs/animacoes.md` | Os dois rigs (Mixamo e Synty) e a máquina de estados |
| `docs/veiculos.md` | Caminhonete, viatura com IA, avião e a nave |
| `docs/mundo.md` | Mapas, terreno, vegetação, masmorra e portais |
| `docs/country-town.md` | O mapa gerado e a ordem das ferramentas |
| `docs/casas-interiores.md` | Casa modular, portas e pontos de atividade |
| `docs/ambiente-e-fx.md` | Noite, névoa, incidente alienígena, shaders e áudio |
| `docs/ui-e-menus.md` | Menus, HUDs, minimapa e menus de depuração |
| `docs/ferramentas.md` | Mapa dos scripts de `tools/` por categoria |

`docs/generated/` está reservada a um snapshot automático do repositório
(Repomix, configurado em `repomix.config.json`); o conteúdo gerado não é
versionado.
