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
- [Mapa Country Town](#mapa-country-town) — mapa novo em construção, fora do catálogo de fases.
- [Limitações conhecidas](#limitações-conhecidas) — o que ainda não existe ou é provisório.
- [Qualidade e validação](#qualidade-e-validação) — checagem no editor e ferramentas de `tools/`.

## Tecnologias e ambiente

- Godot `4.8 dev4` com GDScript e cenas `.tscn`; essa versão é necessária para
  o `Trail3D` nativo da luz viva.
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

- Depois de escolher `Jogar`, o jogador personaliza cabeça, barriga, pernas,
  braços, ombros, altura e olhos em valores normalizados de `0` a `1`. O ET
  animado pode ser girado com o mouse, aproximado com a roda e reproduzir uma
  animação pelos botões agrupados à esquerda. O modo `Aleatório`, selecionado
  por padrão, troca a animação automaticamente a cada 5 segundos; `Iniciar jogo` salva o perfil em
  `user://character_appearance.cfg` e segue para a órbita.
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
| Pegar no colo ou soltar um ET caído | `E` |
| Interagir: terminal, pad de descida, entrar e sair da caminhonete | `E` |
| Solicitar a abdução de um item na área de entrega | Segure `E` |
| Luz dos olhos do ET | `F` |
| Alternar câmera da caminhonete | `G` |
| Binóculos / zoom | `B` / `+` e `-` do teclado numérico |
| Radar circular | `F3` |
| Velocidade e voo (a cada toque) | `F4` |
| Debug de iluminação | `F6` |
| Menu de pausa | `Esc` |

No avião, o mouse move o alvo que orienta o voo; `E` assume ou devolve o
controle perto da cabine.

O `F4` não abre menu: cada toque avança um degrau do ciclo `desligado` ->
`velocidade` (imortalidade, stamina cheia e velocidade 5×) -> `velocidade e
voo` (sem gravidade, subindo com `Espaço` e descendo com `C`) -> `desligado`.
O estado é lido do próprio jogador a cada toque, então continua correto depois
de trocar de mapa, e o resultado sai no console. O menu `F6`, disponível
globalmente durante o jogo mesmo após trocar de mapa, traz o preset de
atmosfera e o controle de cada fonte de luz disponível na cena atual.

As interações usam uma ação própria para que `Espaço` fique reservado ao pulo.
O menu de opções remapeia as teclas de movimento e o menu de pausa remapeia
movimento, corrida, pulo, agachamento, interação, chamada da nave, luz dos
olhos, radar, binóculos, velocidade e voo, e debug de iluminação. Os
remapeamentos duram a sessão.

## Arquitetura

O projeto é composto por cenas reutilizáveis. `world.tscn` monta terreno,
fazenda, nave, vegetação, objetos, jogador, inimigos, veículo, destroços e área
de entrega.

```text
Player -> grupo pickup_items -> pickup/drop -> DeliveryArea -> sinal/abdução -> GlobalScore
MainMenu -> CharacterCreator -> Orbit -> terminal de missão -> LevelCatalog -> aproximação -> world.tscn -> AlienShip descendo do céu -> pad de descida -> feixe de chegada
CharacterAppearance -> CharacterProportions -> Skeleton3D/olhos -> Player e ET do veículo
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

- **Autoloads:** `CharacterAppearance` mantém e persiste as sete características
  normalizadas do ET; `GlobalScore` mantém pontuação e inventário;
  `PhotoAlertSystem`, estrelas e observadores; `SceneTransition`, as transições
  entre cenas; e `DebugMenus`, o atalho global dos modos do jogador (`F4`) e o
  painel de iluminação (`F6`).
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
- **Proporções do ET:** o GLB atual não possui Blend Shapes. Por isso,
  `CharacterProportions` usa escala de bones em um `SkeletonModifier3D`
  pós-animação para cabeça, barriga, peito, quadril, membros e ombros, escala
  visual para altura, um elipsoide abdominal procedural fechado preso ao bone,
  shaders para as dobras/sombreamento e um shader restrito à superfície separada
  dos olhos. A geometria arredondada é gerada em runtime e não altera nem adiciona
  arquivos de modelo. O perfil da barriga continua normalizado de `0` a `1`,
  mas o máximo visual corresponde ao antigo formato de `0.86`, evitando a
  deformação instável do extremo anterior. A barriga procedural é fechada, tem
  a traseira rasa embutida no tronco e usa normais suaves e a mesma cor/acabamento
  da pele. Há compensações nos bones filhos para não transformar o ET em uma
  esfera. O mesmo
  modificador soma offsets pós-animação nos ombros, braços, cotovelos e mãos para
  contornar a barriga, além de inclinar discretamente o tronco nos extremos; as
  rotações autorais continuam sendo a base da pose. O perfil é um
  dicionário pequeno e independente de transporte; `Player` expõe
  `get_appearance_replication_payload()` e o RPC `sync_appearance()` para uma
  futura camada multiplayer. Roupas skinnadas no mesmo esqueleto acompanham os
  bones automaticamente; acessórios rígidos devem usar `BoneAttachment3D`.
- **Ragdoll reversível:** `player_ragdoll.gd` gera os corpos físicos e é usado
  tanto pela morte quanto pela queda por desequilíbrio; ao sair, a orientação
  do peito decide entre levantar de costas ou de bruços.
- **Veículo:** desativa processamento e câmera do jogador, exibe o ET no banco
  e restaura o personagem na saída.
- **Fazendeiro:** estados `WANDERING`, `CHASING` e `SHOOTING`, com memória
  curta da última posição vista e checagem de obstáculos.
- **NPC genérico da nave:** `GenericNPC.tscn` usa o mesmo corpo e cápsula para
  personagens Polygon. O comportamento exportado alterna entre `IDLE` e
  `PATROL`; a patrulha escolhe destinos aleatórios diretamente na
  `NavigationRegion3D` indicada em `navigation_region_path`. NPCs filhos da
  nave acompanham-na pela hierarquia; `ship_passengers` reserva o transporte
  manual para corpos que estejam fora dessa hierarquia.
- **Luz viva da nave e da fazenda:** `LivingLight.tscn` compartilha a região de
  navegação do NPC genérico e alterna entre `WANDER`, `CURIOUS`, `SCARED` e
  `REST`. O script
  controla diretamente dois `Trail3D` nativos do Godot 4.8 dev4 — um externo,
  largo, com gradiente âmbar-esverdeado, e um interno, fino e quase branco —,
  ambos com o material de `shaders/living_light_trail.gdshader`, que refaz o
  billboard do rastro e faz a energia correr por dentro dele. Completam o
  visual um halo billboard aditivo, motes orbitando o núcleo e uma pulsação
  irregular de vagalume; marcadores no
  grupo `living_light_rest_points` servem como pontos de descanso. Na fazenda,
  uma instância começa perto do ponto onde o jogador desce da nave. Ela foge
  continuamente enquanto o jogador permanece no raio de percepção, sem ficar
  limitada ao círculo de passeio, e nunca sobe mais que
  `maximum_height_above_navigation` acima da superfície abaixo dela. Onde a
  `NavigationRegion3D` não tem malha bakeada — hoje, a fazenda inteira — o
  script ignora a navegação, mira o destino em linha e tira a altura de
  referência de uma sonda de raycast para baixo, feita cinco vezes por segundo.
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
| Movimento, personalidade, luz e rastro da luz viva | Exports de `LivingLight` em `scenes/Space/AlienShip.tscn` |

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

## Mapa Country Town

Mapa novo, em construção, com fazenda e cidade rural em `scenes/CountryTown/`.
Ele **não entra no catálogo de fases**: `scenes/Space/Levels/` e
`scripts/world.gd` não o conhecem, e por enquanto ele é aberto direto pelo
editor, em `scenes/CountryTown/CountryTown.tscn`.

| Arquivo | Papel |
| --- | --- |
| `CountryTown.tscn` | Cena mestre: só instancia terreno, ambiente, jogador e distritos |
| `Terrain/` | `data_directory` exclusivo do Terrain3D deste mapa |
| `Layout/PointsOfInterest.tscn` | Um `Marker3D` por ponto do mapa, todos no grupo `country_town_poi` |
| `Districts/RoadNetwork.tscn` | Malhas nativas de asfalto, terra, calçadas, meio-fio, acostamentos e sinalização |
| `Districts/RiverWater.tscn` | Lâmina d'água do rio, barreira só visual, gerada por script |
| `Districts/RiverDistrict.tscn` | Instancia a água, as duas pontes, o ancoradouro e a névoa do leito |
| `Districts/Fields.tscn` | Milharal sobre sulcos, talhões de trigo e girassóis, gerada |
| `Districts/Vegetation.tscn` | Árvores e arbustos de cena, juncos e seixos das margens |
| `Districts/Detailing.tscn` | Cercas, fardos, caixas, placas, sebes e canteiros |
| `Districts/NightLights.tscn` | Postes, luminárias de fachada e luzes de janela |
| `Districts/UrbanInfill.tscn` | Construções adicionais, calçadas, quintais, cargas e postes, instanciada em `TownDistrict` |
| `Districts/RuralInfill.tscn` | Pátios de trabalho, pomares, fardos, silos pequenos e manchas de margem, instanciada em `FarmDistrict` |
| `Districts/SecondaryPaths.tscn` | Trilhas rurais unificadas e acostamentos sobre o relevo existente |
| `Districts/*.tscn` restantes | Fazenda, cidade, queda, mina e pátio de entrega |
| `Blocks/*.tscn` | Blocos reutilizáveis, cada um com a própria colisão dentro |

O mapa mede `600 × 450 m`, com origem no canto noroeste, X para leste e Z para
sul. Nem as estradas nem o relevo são feitos à mão:

- `tools/build_country_town_layout.gd` guarda a grade principal (`ROAD_RUNS`),
  as ruas locais (`SECONDARY_PATHS`) e o rio (`RIVER_PATH`). Gera
  `RoadNetwork.tscn` e `RiverWater.tscn`; agora aceita `--headless`.
  `country_town_road_surface.gd` une as pegadas das vias antes de triangular:
  cruzamentos em T e de quatro vias compartilham o piso; curvas e pontas usam
  contornos arredondados. As ruas urbanas, inclusive o acesso da queda, usam
  asfalto escuro texturizado de 9 m; as vias principais da fazenda usam terra
  de 8 m, com trilhas menores. A troca de material acontece nas duas pontes.
  Rampas de encontro acompanham o tabuleiro existente, de 5 m de largura.
  O piso fica 6 cm acima do terreno; as ruas locais urbanas recebem o mesmo
  aplainamento das principais. Calçadas de cerca de 2 m e meio-fio baixo
  ficam somente fora da malha viária, com recortes nos cruzamentos. Faixas
  centrais discretas identificam as vias principais. As malhas têm colisão
  própria, materiais locais com ruído determinístico e nenhuma peça FBX de rua.
- `tools/build_country_town_terrain.gd` lê esses dados e os marcadores da cena
  de POIs, gera o heightmap, achata as zonas construídas, abre uma clareira sob
  cada marcador e sob cada peça de estrada, escava o canal do rio por último e
  salva as regiões em `scenes/CountryTown/Terrain/`. O heightmap cobre
  1280 × 1280 m a partir de `TERRAIN_ORIGIN` (−256 m em X e em Z, múltiplo do
  `region_size` do Terrain3D): as colinas de borda começam para dentro do mapa
  e só saturam bem depois dele, e sem essa folga negativa o terreno acabava no
  meio da subida a oeste e ao norte — um precipício em vez de montanha.

- `tools/build_country_town_fields.gd` planta o milharal, os talhões de trigo
  e os canteiros de girassol, e gera `Districts/Fields.tscn`. Os talhões são
  retângulos em `CROP_FIELDS`, no script de layout; o script poda o que cai
  sobre estrada, rio ou prédio. Os 13 talhões compartilham essas áreas com
  as cercas, o solo trabalhado e a exclusão da vegetação de fundo.
  O que limita o tamanho de um talhão é a malha, não a área — um pé de milho
  Synty tem 1438 triângulos e a cena `corn_field_root` empilha dez deles em
  2,2 × 5,2 m —, então cada instância sai com `visibility_range` e
  `active_radius` ajustados. Quem cuida disso é `scripts/reactive_crop.gd`,
  base comum das três plantações: fora do raio ativo o talhão dorme e o
  `_process` sai no primeiro `if`; além do alcance de visibilidade as plantas
  derretem em vez de sumir de uma vez. Blocos de 20 m com hastes geométricas
  simples assumem a silhueta à distância: os campos continuam compondo a
  paisagem além do alcance das malhas reativas, sem sensores ou scripts nesses
  blocos distantes. Os sulcos também amostram o terreno e evitam os corredores.
- O talhÃ£o `CornField` Ã© propositalmente grande e usa `CORN_MAZE` como uma receita fixa: cÃ©lulas `#` recebem milho alto e `.` ficam como corredores. Para trocar depois por um labirinto aleatÃ³rio, substitua essa matriz mantendo a mesma grade.
- `tools/build_country_town_settlement.gd` monta os complementos urbanos e
  rurais usando os assets locais PolygonTown/PolygonFarm e a malha da nave
  existente. `LOTS` define 14 construções autorais; `_build_frontages` preenche
  as frentes de rua usando a pegada real dos presets, com variação determinística
  de casas e lojas. O número de fachadas depende das reservas de circulação e da pegada
  dos assets; a geração informa o total no console. O
  preenchimento reserva a praça, as colisões existentes e as faixas de
  circulação. Ruas locais delimitam os quarteirões e a frente do rio; solo de
  lote, calçadas e quintais conectam as fachadas. As propriedades rurais têm
  seis pátios de trabalho, três pomares, galpões de colheita, tratores de cenário,
  fardos, lenha e cercas com aberturas. O depósito de entrega ganhou limites e
  alas de armazenamento. Não há geração procedural durante a partida.
  `SECONDARY_PATHS`, no script de layout, guarda larguras e pontos das ruas,
  becos e trilhas; `SETTLEMENT_CLEARINGS` reserva os pátios e a praça. As
  trilhas rurais amostram o terreno e são unidas sem sobreposição visual, com
  acostamentos e pontas arredondadas. As ruas urbanas integram `RoadNetwork`.
  Campos e vegetação respeitam esses corredores.
  O plantio de fundo também evita as colisões da decoração e dos campos,
  deixando o núcleo urbano para os jardins montados nas cenas.
  Os blocos `CargoStack`, `RuralWorkyard`, `FarmSilo`, `CrashedSaucer`,
  `GrainMill` e `DockShelter` são reutilizáveis. O moinho de grãos usa torre
  facetada e quatro velas, animadas por `AnimationPlayer`; substitui a bomba
  eólica apenas neste mapa. O ancoradouro tem cobertura de madeira. A nave
  inclinada da queda é cenário com colisão, sem scripts
  da nave jogável ou coleta. Quatro postes adicionais usam `house_lights.gd`
  e o grupo `debug_house_lighting`, com luzes sem sombra.
  Alguns FBX rurais são importados como `PackedScene`, embora as cenas antigas
  os solicitassem como `ArrayMesh`. O gerador extrai suas malhas para
  `Blocks/Meshes/`, corrigindo abrigo, bebedouro, estufa, banca, banheiro e
  silo apenas neste mapa, sem alterar os imports ou as cenas da fazenda antiga.
- `tools/build_country_town_vegetation.gd` planta grama, arbustos e árvores de
  fundo no instancer do Terrain3D, desviando de estrada, rio e de qualquer
  colisão dos distritos. Cada espécie é um `Terrain3DMeshAsset` apontando para
  uma cena de `scenes/Vegetation/` — ids 1 e 2 para arbusto/árvore e ids 3 a 7
  para as cinco variantes de grama —, com os alcances de LOD apertados. A
  escolha da variante é determinística e ponderada, então a geração permanece
  estável sem repetir sempre o mesmo tufo. O id 0 do `ArrayTrees.tres` é o
  cartão gerado que já existia, sem textura no material: **não plante nele**,
  ele desenha uma cruz branca saindo do chão.

Mexeu no layout, rode na ordem:

```powershell
.\tools\godot.cmd --headless --path . --script res://tools/build_country_town_layout.gd
.\tools\godot.cmd --headless --path . --script res://tools/build_country_town_terrain.gd
.\tools\godot.cmd --headless --path . --script res://tools/build_country_town_settlement.gd
.\tools\godot.cmd --path . --script res://tools/build_country_town_fields.gd --resolution 320x240
.\tools\godot.cmd --path . --script res://tools/build_country_town_vegetation.gd --resolution 320x240
.\tools\godot.cmd --headless --path . --script res://tools/check_country_town_layout.gd
.\tools\godot.cmd --headless --path . --script res://tools/check_country_town_clearance.gd
.\tools\godot.cmd --headless --path . --script res://tools/check_country_town_bridge.gd
.\tools\godot.cmd --headless --path . --script res://tools/check_country_town_roads.gd
```

A ordem importa: o build do terreno reimporta as regiões do zero e levaria a
vegetação junto, então o plantio vem depois dele. O de vegetação **não**
roda com `--headless`, pois grava buffers de `MultiMesh`.

Se mudou apenas lotes ou decoração, rode settlement e depois campos e
vegetação. Mudanças em ruas urbanas, larguras ou traçados exigem a sequência
completa acima, pois piso, reservas e terreno precisam concordar.
Edite as receitas para preservar ajustes entre gerações. Feche o editor antes
dos comandos ou use uma cópia isolada, conforme `tools/VALIDACAO.md`.

`check_country_town_roads.gd` verifica as colisões salvas por amostragem da
largura das vias, as rampas das pontes, o material e a folga sobre o terreno.
Para inspeção visual solicitada, `inspect_country_town_roads.gd`, sem
`--headless`, grava sete vistas em `build/country-road-review/`, com iluminação
diurna de inspeção e sem jogador. Acrescente `-- --scene-lighting` para conferir
com a iluminação real do mapa. Não altera o ambiente salvo.

A vegetação de fundo — cerca de 12.000 tufos de grama, 310 arbustos e 920
árvores — não gasta um nó sequer: vive no instancer, dentro das próprias
regiões do terreno. Instâncias de cena ficam para o que tem comportamento ou o
jogador encosta: as plantações de `scenes/AnimatedCrops/`, com
`concealment_area` e `fog_zone` próprios, e as árvores dos quintais. É o
oposto de `world.tscn`, que tem cerca de 7.500 linhas só de tufo de grama
instanciado um a um.

As duas travessias usam `Blocks/RiverBridge.tscn`, montada com módulos do
PolygonCity. Cada módulo tem a sua própria cota de origem: o `Underside` entrega
o piso no topo, o `Edge` entrega o piso um palmo abaixo do parapeito, e
`Support` e `Pillar` são estrutura, que mora **sob** o tabuleiro. Errar a cota
de um deles não quebra nada — só deixa um degrau ou uma viga furando o chão da
ponte. `tools/check_country_town_bridge.gd` amostra a faixa de rolamento e cobra
piso contínuo, plano e desobstruído, mais os dois parapeitos de ponta a ponta.
A ponte tem 35 m, o tamanho exato do vão que a grade abre entre as duas peças
de ponta da estrada, e os encontros fecham os 37 cm que sobram de cada lado.

A ambientação segue a da fazenda: `NightEnvironment.tscn` sem alterar o preset,
`FogZone` no leito do rio, no milharal e na cratera, e as luzes registradas no
grupo `debug_house_lighting`, que o menu `F6` liga e desliga.

As ruas são malhas estáticas agrupadas por superfície e não projetam sombra;
os planos de água só se sobrepõem o
necessário para fechar o canto de cada curva, e o rio usa
`Materiais/ea_water_countryTown.tres` — o mesmo `ea_coolwater`, com refração,
cáusticas e brilhos desligados pelos interruptores `enable_refraction`,
`enable_caustics` e `enable_foam` do shader, que existem para isso. A espuma de
margem fica ligada, é ela que desenha a silhueta do rio contra a ribanceira.

A água corre para a foz por conta dos uniformes `flow_speed` e `flow_stretch`
do `ea_coolwater`. A direção não é configurada plano a plano: o shader lê o
eixo `+Z` local da malha, que o gerador já deixa apontando para jusante em cada
trecho, então as curvas acompanham sozinhas. `flow_speed = 0` devolve a água
parada dos outros materiais (`lagoon`, `tropical`, `deepBlue`), que não
declaram esses parâmetros. O custo é de dois produtos escalares por pixel: as
normais, a espuma e os brilhos passam a ser amostrados nesse referencial em vez
de um novo passe.

O terreno da fazenda continua em `res://scenes`, com os `terrain3d_*.res`
soltos lá — os dois mapas nunca compartilham diretório.

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
- Não há sessão multiplayer nem arquitetura de servidor; apenas o payload e o
  ponto de aplicação das proporções estão prontos para replicação futura.
- A névoa rasteira não recebe luz das fontes do mapa; com a volumetria
  desligada, feixes e holofotes não formam cones de luz no ar.
- A queda não causa dano nem é percebida pelos NPCs. Durante o ragdoll a
  cápsula de colisão fica desabilitada, então o ET pode atravessar geometria
  fina, e não há verificação de espaço livre ao levantar.
- A masmorra não tem objetivo além dos destroços: sem inimigos, salas
  especiais nem variação vertical.
- O cenário do mapa Country Town está fechado — terreno, rio, estradas, pontes,
  edificações, vegetação e ambientação noturna — mas ele não tem lógica
  nenhuma: sem NPC, armadilha, destroço coletável ou entrega funcional. A
  sucata do local da queda é cenário, fora do grupo `pickup_items` e sem
  `score_value`. O portal da mina é só a moldura da entrada, sem ligação com
  `scenes/Dungeon/`. A `NavigationRegion3D` não foi bakeada e o mapa não é
  alcançável pelo menu: abre direto pelo editor.
- O áudio ambiente do Country Town reusa `farm_environment_audio.gd`, cujas
  posições de latido de cachorro são fixas nas coordenadas da fazenda e caem
  fora deste mapa. Vento e grilos, que não são posicionais, tocam normalmente.
- A malha de navegação interna da nave cobre hoje apenas a plataforma de
  `9×9 m` junto ao NPC genérico; a luz viva fica limitada a essa área até a
  região ser rebakeada para o restante do interior. A `NavigationRegion3D` da
  fazenda existe mas nunca foi bakeada, então ali a luz viva voa por sonda de
  chão, sem desvio de obstáculo pela navegação — só a colisão do corpo a segura.
  No Godot 4.8 dev4,
  `Trail3D.color` é empacotado como RGBA8 e não aceita HDR overbright; o brilho
  forte vem do uniforme `energy` do shader do rastro, e um `StandardMaterial3D`
  em modo unshaded ignora a emissão, então núcleo e halo pulsam via albedo HDR.
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
