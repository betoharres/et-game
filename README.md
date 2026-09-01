# ET Game

Protótipo 3D single-player em Godot no qual um extraterrestre explora uma
fazenda, coleta destroços de uma nave e os leva até uma área de entrega. O
cenário inclui vegetação reativa, uma caminhonete dirigível, um fazendeiro que
persegue o jogador e um fotógrafo que o expõe.

Este README descreve **o que existe e onde fica**. Valores de ajuste
— velocidades, tempos, distâncias, parâmetros de névoa e de câmera — ficam nos
exports das cenas e nas constantes dos scripts, que são a fonte da verdade.

## Índice

- [Tecnologias e ambiente](#tecnologias-e-ambiente) — versão do Godot, renderer, física e formatos de asset.
- [Estrutura principal](#estrutura-principal) — pastas do projeto e cenas de entrada.
- [Executar](#executar) — abrir no editor e rodar pelo PowerShell.
- [Fluxo atual](#fluxo-atual) — menu, órbita, missão, coleta e entrega.
- [Controles](#controles) — teclas e ações do Input Map.
- [Arquitetura](#arquitetura) — cenas, autoloads, grupos e cadeias de interação.
- [Onde ajustar o visual](#onde-ajustar-o-visual) — em que cena ou script mora cada parâmetro.
- [Limitações conhecidas](#limitações-conhecidas) — o que ainda não existe ou é provisório.
- [Qualidade e validação](#qualidade-e-validação) — checagem no editor e ferramentas de `tools/`.

## Tecnologias e ambiente

- Godot `4.7` com GDScript e cenas `.tscn`.
- Renderer `Forward Plus` com Direct3D 12 no Windows, em tela cheia com
  resolução-base `1920×1080`.
- Física 3D com Jolt Physics.
- Terreno com Terrain3D; modelos `.fbx`/`.glb`, com texturas e materiais rurais.
- Export para Windows Desktop `x86_64` em `export_presets.cfg`.

## Estrutura principal

| Pasta | Conteúdo |
| --- | --- |
| `scenes/` | Todas as cenas do jogo, incluindo `Space/`, `Dungeon/` e `Portal/` |
| `scripts/` | GDScript, espelhando a organização das cenas (`space/`, `levels/`, `dungeon/`, `audio/`) |
| `shaders/` | Céu procedural e névoa rasteira |
| `tools/` | Checagens automatizadas e utilitários de build de asset |
| `animations/mixamo/` | Rig visual único, FBX de origem, GLB gerado e mapeamento |
| `assets/` | Áudio, fontes e música do menu |
| `Texturas/ui/` | Ícones do HUD, gerados por `tools/render_prototype_icons.py` |
| `3dModelos/`, `Texturas/`, `Materiais/` | Assets importados e materiais reutilizáveis |

Cenas de entrada:

| Cena | Papel |
| --- | --- |
| `scenes/Menu/main_menu.tscn` | Cena principal do projeto: menu, opções e remapeamento |
| `scenes/Space/Orbit.tscn` | Órbita jogável com o terminal de seleção de missão |
| `scenes/world.tscn` | Mapa da fazenda, onde a partida acontece |
| `scenes/Player.tscn` | ET, câmera, rig Mixamo, `AnimationTree` e IK de ação |
| `scenes/Space/AlienShip.tscn` | Nave reutilizada na órbita, na fazenda e no Barn |
| `scenes/NightEnvironment.tscn` | Céu, Lua, névoa, iluminação e filtro de tela da fazenda |

## Executar

Abra `project.godot` no Godot 4.7 ou 4.8 e pressione `F5`. Pelo PowerShell, use
o wrapper do projeto, que procura a instalação antiga 4.7, a instalação 4.8 em
`D:\Program Files\Godot\Godot_v4.8` e, por último, o Godot no `PATH`:

```powershell
.\tools\godot.cmd --path .            # rodar o jogo
.\tools\godot.cmd --editor --path .   # abrir o editor
```

Depois de exportado, o jogo abre direto por `build/ETs.exe`, sem o editor.

## Fluxo atual

```text
Menu -> nave em orbita -> terminal de missao -> aproximacao -> nave descendo no ceu da fazenda -> raio trator -> coletar -> entregar
```

- O jogador começa a bordo da nave, em órbita da Terra. Um terminal de missão
  lista o catálogo de fases; hoje só a Fazenda está disponível, com entradas de
  exemplo bloqueadas. Adicionar uma fase não exige mexer em script: basta um
  `LevelDefinition.tres` apontando para a cena e listado em
  `level_catalog.tres`.
- Ao chegar na fase, o ET nasce sobre a nave, que desce do céu e estaciona
  acima do ponto de chegada. Pisar no pad central e interagir aciona a cutscene
  de descida pelo feixe. Abrir `world.tscn` direto no editor pula esse passo.
- Destroços próximos podem ser carregados e largados. Para entregar, o jogador
  larga o item na plataforma e sustenta o sinal de intervenção alienígena; um
  feixe suga o item até a nave e só então soma o `score_value` ao
  `GlobalScore`. Soltar o botão antes do fim cancela a chamada.
- Um spider bot acompanha a nave, desce pelo feixe quando detecta um destroço
  ao alcance, leva o item até a plataforma e volta a ficar oculto.
- A caminhonete atravessa o mapa e tem câmeras externa e interna. Os binóculos
  têm zoom e uma visão X-ray feita com um passe separado sobre os mesmos
  meshes, sem duplicar geometria.
- O fazendeiro patrulha a malha de navegação, persegue o ET ao avistá-lo e
  passa a atirar de perto. A precisão varia com distância, movimento,
  camuflagem e acertos consecutivos.
- Um fotógrafo persegue e fotografa o ET. Cada foto acende uma estrela, até
  três; ficar sem ser visto por tempo suficiente remove uma estrela. As
  estrelas solicitam respostas futuras de polícia, imprensa e MIB.
- Trigo e girassóis oscilam com o vento, inclinam-se perto de personagens e
  veículos e escondem parcialmente o ET, reduzindo o alcance de detecção do
  fazendeiro. Agachar na vegetação aumenta a camuflagem.
- O ET tem vida e stamina. Correr consome stamina e esgotá-la bloqueia a
  recuperação por alguns segundos. Colidir correndo ou cair de altura consome
  equilíbrio, provoca tropeço e, no limite, um ragdoll do qual ele se levanta
  sozinho. Zerar a vida entra em ragdoll definitivo, com menu para reiniciar.
- Uma porta na fazenda leva a uma masmorra procedural plana, montada a partir
  de módulos de corredor. Ela é gerada uma vez por sessão e guarda destroços
  nos becos sem saída, que seguem o mesmo fluxo de coleta e entrega.
- A pontuação atual aparece apenas no console de depuração.

Cenas de teste isoladas: `interior_space_ship_room_1.tscn` (gravidade radial
dentro de uma esfera), `Portal/portal.tscn` (par de portais com renderização
cruzada e travessia contínua) e `FlyablePlane.tscn` (avião controlável).

## Controles

| Ação | Tecla |
| --- | --- |
| Mover o ET / dirigir a caminhonete | `WASD` |
| Câmera | Mouse |
| Correr | `Shift` (consome stamina; bloqueado no ar) |
| Pular / agachar | `Espaço` / segure `C` |
| Coletar ou largar item | `E` |
| Interagir: terminal, pad de descida, entrar e sair da caminhonete | `E` |
| Solicitar a abdução de um item na área de entrega | Segure `E` |
| Luz dos olhos do ET | `F` |
| Alternar câmera da caminhonete | `G` |
| Binóculos / zoom | `B` / `+` e `-` do teclado numérico |
| Radar circular | `F3` |
| Debug do jogador | `F4` |
| Debug de iluminação | `F6` |
| Menu de pausa | `Esc` |

No avião, o mouse move o alvo que orienta o voo; `E` assume ou devolve o
controle perto da cabine.

O menu `F4` reúne somente o `Modo Deus` (imortalidade, stamina cheia e mais
velocidade) e o `Modo Voo` (sem gravidade, subindo com `Espaço` e descendo com
`C`). O menu `F6`, disponível globalmente durante o jogo mesmo após trocar de
mapa, traz o preset de atmosfera e o controle de cada fonte de luz disponível
na cena atual.

As interações usam uma ação própria para que `Espaço` fique reservado ao pulo.
O menu de opções remapeia as teclas de movimento e o menu de pausa remapeia
movimento, corrida, pulo, agachamento, interação, chamada da nave, luz dos
olhos, radar, binóculos, debug do jogador e debug de iluminação. Os
remapeamentos duram a sessão.

## Arquitetura

O projeto é composto por cenas reutilizáveis. `world.tscn` monta terreno,
fazenda, nave, vegetação, objetos, jogador, inimigos, veículo, destroços e área
de entrega.

```text
Player -> grupo pickup_items -> pickup/drop -> DeliveryArea -> sinal/abdução -> GlobalScore
MainMenu -> Orbit -> terminal de missão -> LevelCatalog -> aproximação -> world.tscn -> AlienShip descendo do céu -> pad de descida -> feixe de chegada
SmellyFarmer -> visão/linha de visão -> perseguição/disparo -> vida do Player
Photographer -> visão/foto -> PhotoAlertSystem -> HUD/solicitações futuras
Player -> grupo characters -> vegetação e detecção do inimigo
WheatField/SunflowersPatch -> área de camuflagem -> visibilidade do Player
DriveableTruck -> grupo vehicles -> direção e reação da vegetação
Player -> colisão de parede -> equilíbrio -> stumble/queda -> PlayerRagdoll
Player -> estado físico -> PlayerAnimationController -> AnimationTree -> Mixamo
Mixamo -> LookAt/IK de ação -> reação -> ragdoll (prioridade crescente)
Player -> CinematicCameraRig -> SpringArm3D -> Camera3D
NightEnvironment -> AgX/glow/névoa -> filtro de incidente alienígena
FogZone -> grupo fog_zones -> GroundFogLayer -> densidade local da névoa
Nave/feixe/evento -> AlienInterferenceSource -> AlienIncidentPostProcess
```

- **Autoloads:** `GlobalScore` mantém pontuação e inventário;
  `PhotoAlertSystem`, estrelas e observadores; `SceneTransition`, as transições
  entre cenas; e `DebugMenus`, os painéis globais de debug do jogador (`F4`) e
  de iluminação (`F6`).
- **Grupos** conectam sistemas sem referência direta: `characters`, `vehicles`,
  `pickup_items`, `ship_passengers`, `fog_zones` e `volumetric_lights`.
- **Contrato de coletáveis:** grupo `pickup_items`, métodos `pickup()` e
  `drop()` e propriedade `score_value`. Um item em abdução deixa o grupo
  temporariamente para não ser recolhido antes da entrega.
- **Jogador:** `player.gd` cuida de input, física, equilíbrio e decisões, e
  envia o estado ao `PlayerAnimationController`, que centraliza a máquina de
  estados do `AnimationTree`. O rig é um único `Skeleton3D` Mixamo com as
  animações in-place — o `CharacterBody3D` é a única autoridade de
  deslocamento. Sobre a animação base atuam apenas dois `LookAtModifier3D` de
  influência limitada e um `TwoBoneIK3D` no braço direito, que só entra ao
  carregar um item ou executar o sinal.
- **Ragdoll reversível:** `player_ragdoll.gd` gera os corpos físicos e é usado
  tanto pela morte quanto pela queda por desequilíbrio; ao sair, a orientação
  do peito decide entre levantar de costas ou de bruços.
- **Veículo:** desativa processamento e câmera do jogador, exibe o ET no banco
  e restaura o personagem na saída.
- **Fazendeiro:** estados `WANDERING`, `CHASING` e `SHOOTING`, com memória
  curta da última posição vista e checagem de obstáculos.
- **NPC genérico da nave:** `GenericNPC.tscn` usa o mesmo corpo e cápsula para
  personagens Polygon. O comportamento exportado alterna entre `IDLE` e
  `PATROL`; a patrulha percorre os marcadores em `Behaviors/Patrol/Points`.
  Ela funciona diretamente no interior da nave e pode usar o
  `NavigationAgent3D` quando uma malha de navegação for adicionada à nave.
- **Masmorra:** isolada das `NavigationRegion3D` da fazenda, não participa da
  navegação dos NPCs. O estado "já gerada" vive em memória no próprio nó e se
  perde ao recarregar a cena.
- **HUDs** reutilizam o tema `Materiais/hud_theme.tres` e uma família única de
  ícones gerada dos meshes low-poly `Polygon Prototype`.

## Onde ajustar o visual

| Para mudar | Vá em |
| --- | --- |
| FOV, distância e colisão da câmera | `Camera3D` e `SpringArm3D` em `scenes/Player.tscn` |
| Seguimento, offset, sway e respiração | Exports de `scripts/cinematic_camera_rig.gd` |
| Grão, vinheta, aberração, contraste, black lift | `IncidentPostProcess` em `scenes/NightEnvironment.tscn` |
| Bloom e halation | Propriedades `glow_*` do `Environment` na mesma cena |
| Presets de qualidade, névoa e evento alienígena | Exports do `NightEnvironment` e `QUALITY_PRESETS` em `scripts/night_environment.gd` |
| Forma e movimento da névoa rasteira | `scenes/FX/GroundFogLayer.tscn` e `shaders/ground_fog.gdshader` |
| Névoa mais densa em um lugar | Instancie `scenes/FX/FogZone.tscn` e ajuste raio e força |
| Interferência por nave, feixe ou evento | Exports de cada `AlienInterferenceSource` |
| Cores alienígenas | Materiais e luzes de `AlienShip.tscn`, `DeliveryArea.tscn`, `ArrivalBeam.tscn` e `SpaceShipInterior.tscn` |

A névoa tem duas escalas: uma manta rasteira de planos com shader, que segue a
câmera, e o fog atmosférico do `Environment`, que fecha ao longe e esconde a
borda do mapa. O volumetric fog está desligado em todos os presets, por custo,
e pode ser religado nos presets de `night_environment.gd`.

Armadilha do Godot 4.7: no fog em modo Depth, `Environment.fog_density` deixa
de ser densidade e passa a multiplicar a rampa de profundidade — um valor de
modo exponencial faz a névoa sumir. O controle certo é
`atmospheric_fog_opacity`, em `night_environment.gd`.

Por código, `NightEnvironment.set_alien_fog_intensity()` recebe de 0 a 1 e
interpola densidade, tonalidade, scattering, energia dos feixes e interferência
de tela; `set_quality_preset()` troca o preset em runtime. O grupo
`alien_post_process` expõe interferência manual e pulso.

## Limitações conhecidas

- A nave que desce na fazenda e a `SpaceShip` que já existia na cena são
  redundantes; consolidá-las é trabalho futuro. Não há caminho de volta à
  órbita.
- O catálogo tem só a Fazenda; Cidade e Deserto são exemplos bloqueados.
- O disparo usa dano instantâneo e clarão provisório, sem projétil físico.
- Polícia, imprensa e MIB existem apenas como sinais e mensagens de
  placeholder, sem cenas nem spawn.
- A pontuação não tem HUD, objetivo final nem persistência, e o inventário do
  autoload não está integrado ao fluxo de coleta.
- Opções e remapeamentos não são salvos entre execuções.
- Não há multiplayer nem arquitetura de servidor.
- A névoa rasteira não recebe luz das fontes do mapa; com a volumetria
  desligada, feixes e holofotes não formam cones de luz no ar.
- A queda não causa dano nem é percebida pelos NPCs. Durante o ragdoll a
  cápsula de colisão fica desabilitada, então o ET pode atravessar geometria
  fina, e não há verificação de espaço livre ao levantar.
- A masmorra não tem objetivo além dos destroços: sem inimigos, salas
  especiais nem variação vertical.
- A origem e a licença dos assets em `3dModelos/` e `Texturas/`, do pacote
  `Polygon Prototype` e dos FBX Mixamo não estão confirmadas. Áudio, ícones e
  animações têm procedência registrada em `assets/audio/SOURCE.md`,
  `Texturas/ui/SOURCE.md` e `animations/mixamo/SOURCE.md`; confirme os
  termos antes de redistribuir.

## Qualidade e validação

Depois de alterar GDScript, cenas ou `project.godot`, abra o projeto no editor
e confirme que não há erros de importação, parsing ou referências ausentes. Uma
checagem sem interface:

```powershell
.\tools\godot.cmd --headless --path . --editor --quit
```

As verificações automatizadas ficam em `tools/`, uma por sistema (animação,
salto e stamina, reversão, ragdoll, câmera, portais, modos de debug,
interferência e presets de atmosfera). Rode a do sistema que você alterou:

```powershell
.\tools\godot.cmd --headless --path . --script res://tools/<tool>.gd
```

Omita `--headless` quando a checagem depender de rasterização de verdade, como
render, screenshot ou culling. No Windows, use o executável terminado em
`_console.exe`: só ele manda `print()` para o stdout.

Para medir o custo da atmosfera antes e depois de mexer na névoa,
`tools/measure_atmosphere_cost.gd` percorre os presets e imprime FPS e tempo de
render por frame. Ele mede a referência sem névoa no início e no fim, porque a
nave gira e muda quantos feixes aparecem em tela.

Mudanças de gameplay, câmera, física, veículo, navegação, IK ou vegetação
também devem ser conferidas em uma execução normal. Não inclua senhas, tokens,
credenciais ou chaves nos arquivos do projeto.
