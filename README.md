# ET Game

Protótipo 3D single-player em Godot no qual um extraterrestre explora uma
fazenda, coleta destroços de uma nave e os leva até uma área de entrega. O
cenário inclui vegetação reativa, uma caminhonete dirigível e um fazendeiro que
patrulha o mapa, persegue o jogador e causa dano com a espingarda.

## Tecnologias e ambiente

- Godot `4.7`, conforme configurado em `project.godot`.
- GDScript e cenas `.tscn`.
- Renderer `Forward Plus` com Direct3D 12 no Windows.
- Inicialização em tela cheia, com resolução-base Full HD (`1920×1080`).
- Física 3D com Jolt Physics.
- Modelos `.fbx` e `.glb`, texturas e materiais para o ambiente rural.
- Export preset para Windows Desktop `x86_64` em `export_presets.cfg`.

## Estrutura principal

```text
project.godot          Configuração, Input Map, cena principal e autoload
export_presets.cfg     Exportação para Windows Desktop
scenes/
  MenuAtmosphere.tscn   Fundo noturno extraterrestre animado do menu
  NightEnvironment.tscn Céu, Lua, névoa, partículas e iluminação da fazenda
  GroundFogLayer.tscn  Névoa rasteira otimizada em camadas de planos com shader
  FogZone.tscn         Marcador que adensa a névoa rasteira em uma área
  main_menu.tscn       Menu principal, opções e remapeamento de movimento
  world.tscn           Mapa jogável e composição do cenário
  Player.tscn          Jogador ET, câmera, rig Mixamo, AnimationTree e IK de ação
  PlayerHUD.tscn       HUD de vida e stamina do ET
  PhotoAlertHUD.tscn   HUD das 0–3 estrelas de exposição fotográfica
  DebugMenu.tscn       Menu F4 com ferramentas de inspeção da iluminação
  DriveableTruck.tscn  Caminhonete controlável
  FlyablePlane.tscn    Protótipo separado de avião controlável
  VisionDebugMap.tscn  Radar circular opcional de objetivos e ameaças
  SmellyFarmer.tscn    Fazendeiro, navegação e IK
  Photographer.tscn    NPC fotógrafo e câmera provisória
  spaceship_scraps.tscn Item coletável e entregável
  DeliveryArea.tscn    Área que converte itens entregues em pontos
  WheatField.tscn      Trigo com vento e reação a personagens e veículos
  SunflowersPatch.tscn Girassóis com vento e reação ao movimento
  SICSVegetationInstances.tscn Instâncias editáveis copiadas da vegetação Terrain3D
  DungeonDoor.tscn      Porta na fazenda que dá acesso à masmorra
  Dungeon.tscn          Porão de madeira procedural (GridMap) e portal de volta
  interior_space_ship_room_1.tscn Teste isolado de caminhada com gravidade radial
  Portal/portal.tscn  Par visual de portais com renderização cruzada por SubViewport
scripts/
  menu_atmosphere.gd   Estrelas, nave, fachos, terreno e atmosfera do menu
  night_environment.gd Presets de atmosfera, névoa híbrida e eventos alienígenas
  ground_fog_layer.gd  Camadas de névoa rasteira que seguem a câmera e o chão
  fog_zone.gd          Reforço local de névoa em campos, milharais e estradas
  cinematic_camera_rig.gd Seguimento, enquadramento e colisão da câmera do ET
  alien_incident_post_process.gd Mistura o filtro normal e a interferência ET
  alien_interference_source.gd Fonte espacial reutilizável de interferência
  house_lights.gd      Oscilação discreta das luzes quentes da casa
  player.gd            Movimento, vida, stamina, equilíbrio, coleta e entrega
  player_animation_controller.gd Estado visual central e transições do AnimationTree
  player_ragdoll.gd    Queda física do ET: morte definitiva e tombo reversível
  ragdoll_recovery_modifier.gd Alinha brevemente o ragdoll ao início do get-up
  ik_target_container.gd IK do braço direito apenas para ações específicas
  driveable_truck.gd   Direção, entrada, saída e câmeras do veículo
  vision_debug_map.gd  Radar circular com ícones e cones de visão discretos
  debug_menu.gd        Alterna fontes de luz e atmosfera durante a partida
  smelly_farmer.gd     Patrulha, visão, perseguição, disparo e dano
  photographer.gd      Visão, perseguição e captura de fotos do ET
  dungeon_door.gd       Porta da masmorra: gera o layout uma vez e teleporta
  dungeon.gd             Geração procedural da masmorra e portal de retorno
  photo_alert_system.gd Contador global e redução das estrelas
  GlobalScore.gd       Pontuação e inventário globais
  audio/               Passos, ambiente rural e som sintetizado da espingarda
  *_field.gd           Comportamento da vegetação
assets/audio/          Vento, grilos, cães, passos e registro de origem
assets/ui/             Ícones leves derivados dos meshes low-poly do pacote visual
animations/mixamo/     Rig visual único, fontes FBX, GLB gerado e mapeamento
shaders/night_sky.gdshader Céu procedural estrelado e Lua
shaders/ground_fog.gdshader Névoa rasteira animada, com zonas e soft depth
tools/build_mixamo_character.py Gera o GLB in-place usado pelo Player
tools/test_player_animation.gd Smoke test dos estados visuais do Player
tools/test_player_jump_stamina.gd Smoke test do impulso e consumo de stamina
tools/test_player_reversal.gd Smoke test de freada e pivô em reversões bruscas
tools/test_player_ragdoll.gd Smoke test do ragdoll e da recuperação
tools/test_cinematic_camera.gd Smoke test do enquadramento e colisão da câmera
tools/test_portal_teleportation.gd Smoke test da travessia, velocidade e recorte dos portais
tools/test_player_debug_modes.gd Smoke test dos modos Deus e Voo
tools/test_alien_interference.gd Smoke test do filtro alienígena dinâmico
tools/test_atmosphere_presets.gd Smoke test dos presets de névoa e do evento ET
tools/measure_atmosphere_cost.gd Mede FPS e tempo de render por preset
tools/render_prototype_icons.py Utilitário para regenerar os ícones do HUD
3dModelos/             Modelos 3D importados
Texturas/              Texturas do cenário e dos modelos
Materiais/             Materiais reutilizáveis do Godot
AGENTS.md              Instruções para agentes que alterarem o projeto
README.md              Visão geral, execução e arquitetura
```

## Executar

Abra `project.godot` no Godot 4.7 e pressione `F5`. A cena inicial é
`scenes/main_menu.tscn`; o botão de jogar carrega `scenes/world.tscn`.

Se o executável do Godot estiver disponível no `PATH`, também é possível usar
o PowerShell:

```powershell
godot --path "C:\dev\etnovo\et-game"
```

Para abrir o editor:

```powershell
godot --editor --path "C:\dev\etnovo\et-game"
```

Também é possível executar com a instalação portátil disponível nesta máquina,
sem configurar variáveis de ambiente:

Comando recomendado para iniciar o jogo diretamente pelo PowerShell:

```powershell
& "C:\Godot_v4.7.1\Godot_v4.7.1-stable_win64.exe" --path "C:\dev\etnovo\et-game"
```

Depois de exportado, o jogo pode ser aberto diretamente por `build/ETs.exe`,
sem iniciar o editor do Godot.

## Fluxo atual

```text
Menu -> fazenda -> localizar destroços -> coletar -> área de entrega -> pontos
```

- O jogador começa no mapa rural com câmera em terceira pessoa.
- A câmera usa enquadramento sobre o ombro com FOV de 60 graus, seguimento e
  rotação suavizados, colisão volumétrica contra o cenário e movimentos
  orgânicos discretos ao caminhar, girar ou permanecer parado.
- A fazenda possui céu procedural estrelado, Lua fixa, estrelas cadentes,
  névoa baixa e iluminação ambiente azulada configurável por qualidade.
- A névoa tem duas camadas. Perto, uma manta rente ao chão feita de planos com
  shader que seguem a câmera e a altura do terreno; campos e milharais a
  adensam por meio de `FogZone`. Longe, o fog atmosférico do `Environment` em
  modo Depth, que fecha opaco entre 350 m e 400 m e serve de orçamento de
  renderização: é ele que esconde a borda do mapa. O volumetric fog continua
  desligado em todos os presets, por custo.
- Atenção ao mexer no fog em modo Depth do Godot 4.7: `Environment.fog_density`
  deixa de ser densidade e passa a multiplicar a rampa de profundidade. Um
  valor de modo exponencial (0.01) reduz a névoa a 1% e ela some. O controle
  correto é `atmospheric_fog_opacity` em `night_environment.gd`, que fica em
  1.0. `fog_height_density` também multiplica o depth fog, e por isso está em
  0.0: quem faz a névoa de perto é o `GroundFogLayer`.
- Alcance visual: as câmeras do jogador e do caminhão têm `far` 450 m, à frente
  dos 400 m onde a névoa já está opaca. Ao pilotar, o avião troca para um
  perfil de névoa mais aberto (550 m a 950 m) com `far` 1200 m, para que dê
  para enxergar a fazenda inteira do alto. A troca é automática, feita por
  `NightEnvironment.set_fog_profile()` a partir de `flyable_plane.gd`, e é
  suave. Não há controle novo para o jogador.
- O terreno usa fundo procedural (`world_background = Noise` no
  `Terrain3DMaterial`) com relevo baixo, casado com as bordas planas das
  regiões, e `auto_shader` ligado para que o fundo receba a mesma grama do
  mapa. As 20 regiões cobrem 640 x 512 m; fora delas o Terrain3D continua
  gerando terreno até o plano distante da câmera, e a névoa fecha antes.
- O tratamento visual combina sombras azul-petróleo, luzes humanas âmbar e
  emissões alienígenas ciano-esverdeadas. Um filtro sutil acrescenta grão,
  vinheta, aberração cromática periférica e eleva levemente os pretos; o glow
  do ambiente fornece bloom/halation sem comprometer a leitura do gameplay.
- Nave, feixe de chegada e abdução funcionam como fontes espaciais de
  interferência. Ao se aproximar, o filtro aumenta suavemente grão e separação
  cromática, introduz microdistorção e uma oscilação mínima de exposição. A
  sequência de abdução também dispara um pulso curto, sem afetar a HUD.
- Destroços próximos podem ser carregados e largados.
- Para entregar um destroço, o jogador deve largá-lo na plataforma. Um aviso
  piscante aparece na HUD; próximo ao item, segure `E` por 3 segundos para
  completar o sinal de intervenção alienígena.
- Enquanto o sinal carrega, o ET leva a mão direita à cabeça e a nave se
  posiciona sobre a plataforma. Soltar `E` antes do fim cancela a chamada. Ao
  completar o sinal, um feixe ciano com o mesmo material dos fachos da nave,
  reforçado por um núcleo cilíndrico emissivo, suga o item por 10 segundos;
  somente ao
  chegar à nave ele desaparece e soma seu `score_value` ao `GlobalScore`.
- O spider bot permanece oculto e acompanha a nave. Quando detecta um destroço
  dentro do raio configurado, desce até o terreno pelo mesmo feixe da chegada
  do jogador, coleta o item e o transporta até a plataforma. Depois que a
  entrega confirma a pontuação, ele retorna à posição atual da nave, sobe pelo
  feixe e volta a ficar oculto.
- A pontuação atual é exibida apenas no console de depuração.
- A caminhonete pode ser usada para atravessar o mapa e possui câmeras externa
  e interna.
- A visão X-ray dos binóculos usa um passe separado sobre os mesmos meshes, com
  material temporário e máscara de câmera completa, sem duplicar a geometria.
- O fazendeiro escolhe destinos aleatórios na malha de navegação. Ao enxergar
  o jogador, passa a persegui-lo e entra no estado de disparo quando está
  próximo. Cada tiro causa dano, emite som e exibe um clarão provisório no
  cano da espingarda. A precisão varia com distância, movimento, camuflagem e
  acertos consecutivos; tiros errados seguem um raycast desviado e colidem com
  o cenário.
- O ET possui 100 pontos de vida e 100 pontos de stamina. Correr consome
  stamina; ao esgotá-la por completo, a recuperação fica bloqueada por 3
  segundos antes de voltar gradualmente.
- A locomoção usa 3 m/s ao caminhar, 5,5 m/s ao correr e 1,6 m/s agachado.
  Os ciclos Mixamo acompanham essas velocidades com playback calibrado por
  tipo de movimento para reduzir o deslizamento dos pés sem deixar os passos
  rápidos demais.
- A HUD compacta no canto inferior esquerdo mantém a vida visível; a stamina
  aparece somente durante uso ou recuperação. Dano pulsa a barra e produz uma
  vinheta vermelha breve.
- Um fotógrafo patrulha a fazenda, aproxima-se do ET quando o enxerga e tira
  fotos após focar a câmera. O rastreador compacto no canto superior direito
  mostra de zero a três registros, emite um som breve ao atualizar e reduz a
  opacidade depois de alguns segundos sem mudança.
- Cada estrela representa uma foto. Sem ser visto por nenhum fotógrafo, uma
  estrela é removida após 30 segundos contínuos; ser visto reinicia o tempo.
- O radar circular começa visível no canto inferior direito, mostra a indicação
  `F3` abaixo do círculo e pode ser ocultado ou exibido novamente pela tecla.
- Uma, duas e três estrelas solicitam, respectivamente, respostas futuras da
  polícia, imprensa e MIB. Essas respostas existem somente como métodos e
  sinais: nenhum veículo, agente ou fotógrafo adicional é criado atualmente.
- Os disparos empurram o ET por aproximadamente 0,5 m. Ao chegar a zero de
  vida, os controles são desativados, o corpo entra em ragdoll e um pequeno
  menu permite recomeçar a cena atual.
- Parado no chão, o ET reproduz um idle autoral do Mixamo e escolhe entre duas
  variações em intervalos aleatórios. A entrada e a saída dessas variações usam
  0,4 segundo de mistura para não trocar a pose bruscamente. Cabeça e torso
  ainda acompanham o `HeadTarget` com influência pequena, como ajuste sobre a
  animação base.
  Durante o sinal de intervenção ou ao carregar um item, somente o braço
  direito passa gradualmente para o IK específico da ação.
- Bater em obstáculos enquanto se movimenta consome equilíbrio. A perda é
  proporcional à velocidade com que o ET entra na superfície, e não ao simples
  contato: encostar ou empurrar uma parede não gasta equilíbrio nenhum, andar
  contra ela quase não gasta, e correr contra ela provoca um tropeço visível.
- Enquanto tropeça, o ET toca uma reação Mixamo coerente com a direção do
  impacto, ganha um empurrão residual, perde parte do controle de movimento e
  da velocidade de giro e vai se recuperando aos poucos. Novos impactos ainda
  somam ao desequilíbrio anterior.
- Ao inverter bruscamente a direção enquanto já está em movimento, o ET não
  troca mais a velocidade de forma instantânea. A velocidade anterior freia,
  um pivot Mixamo de 180° gira o corpo e a aceleração no novo sentido só começa
  depois do apoio do pé. Caminhada e corrida usam clips e durações próprios;
  pulo, crouch, hit, stumble e ragdoll podem interromper a manobra.
- Pedir a direção oposta partindo do idle usa o mesmo princípio: o personagem
  planta os pés e completa um único giro de 180° antes de começar a caminhar.
  O yaw interno dos clips de turn é removido na geração do GLB para não se
  somar à rotação física do `CharacterBody3D`.
- Mudanças menores de direção, inclusive soltar a frente e apertar um lado,
  permanecem em uma animação de locomoção enquanto o corpo gira. Apenas uma
  reversão ampla aciona o pivô que planta os pés antes de voltar a andar.
- Cair de altura também derruba. A velocidade vertical no instante em que o ET
  toca o chão é comparada com `min_landing_speed` e `landing_ragdoll_speed`:

```text
pulo normal, até 1,5 m   nada
1,8 m a 2,2 m            cambaleia ao pousar, cada vez mais
2,4 m em diante          cai no chão
```

  O tombo cresce com a altura: por volta de 2,5 m o ET desaba praticamente no
  lugar e fica pouco tempo caído, enquanto uma queda de 12 m é o tombo completo.
  Um pulo em terreno plano toca o chão a cerca de 5,5 m/s e nunca custa nada,
  mas pular de uma beirada soma o impulso do pulo à altura da queda.
- Se o equilíbrio zerar, ou se um único impacto for forte demais, o ET cai num
  ragdoll exagerado: os pés são varridos para trás, o tronco e a cabeça vão
  para a frente e os braços se agitam. A queda não causa dano. Um tropeço deixa
  o ET cerca de 0,9 segundo no chão e um tombo de altura cerca de 1,8; em
  seguida ele escolhe uma animação de levantar de costas ou de bruços conforme
  a orientação final do ragdoll e recupera o controle ao terminar. Não é
  preciso apertar nada. O controle é liberado 0,25 segundo antes do fim do clip,
  durante o trecho em que o ET já está visualmente de pé.
- A queda tem intensidade. Bater correndo, ou ficar sem equilíbrio, produz uma
  queda pequena: o ET tropeça e desaba praticamente no lugar, ficando pouco
  tempo no chão. Só o tombo de altura usa a força total, que joga o corpo
  longe. A mesma intensidade controla o impulso do ragdoll e o tempo caído.
- Correr é limitado a `sprint_speed` (5,5 m/s) e `fall_impact_speed` é 5,15 m/s,
  logo bater de frente numa parede em velocidade máxima derruba; chegar de
  raspão, ou apenas andando, continua sendo tropeço ou nada.
- Trigo e girassóis escondem parcialmente o ET: reduzem o alcance e tornam a
  detecção do fazendeiro mais lenta. Agachar dentro da vegetação aumenta a
  camuflagem.
- Trigo e girassóis oscilam com vento e se inclinam perto do jogador ou de
  veículos.
- Vento e grilos formam a camada ambiente contínua. Latidos são reproduzidos
  em posições e intervalos variados ao redor da fazenda.
- Os passos acompanham o movimento do ET, variam amostra e afinação e tentam
  distinguir terra, pedra e madeira pelo objeto sob o personagem.
- Uma porta (`DungeonDoor.tscn`) na fazenda dá acesso a um porão de madeira
  gerado proceduralmente num `GridMap`: salas retangulares sem sobreposição,
  conectadas em sequência por corredores, com paredes de altura inteira nas
  bordas de cada célula de chão e teto fechado sobre toda a área caminhável.
  Piso, paredes e teto usam materiais de madeira em tons diferentes, e cada
  sala recebe uma lâmpada quente presa ao teto. A masmorra é construída
  apenas uma vez por sessão,
  na primeira vez que a porta é tocada; os toques seguintes só teleportam
  para o layout já existente. Dentro da masmorra, destroços coletáveis
  (`spaceship_scraps.tscn`) aparecem em algumas das salas geradas e seguem o
  mesmo fluxo de coleta e entrega do restante do jogo. Um portal de retorno
  aparece na sala de entrada e teleporta o jogador de volta à posição da
  porta na fazenda.
- `interior_space_ship_room_1.tscn` é uma cena de teste isolada: uma `Area3D`
  aplica gravidade constante em direção ao centro da esfera, enquanto o
  jogador adapta seu eixo vertical, movimento, salto, câmera e animações à
  normal radial da superfície.
- `Portal/portal.tscn` contém um par fechado de superfícies: cada portal exibe
  em tempo real a vista da câmera posicionada no portal oposto. Personagens
  que atravessam uma superfície reaparecem no outro portal, preservando a
  posição relativa, a orientação e a velocidade. As câmeras internas usam um
  frustum assimétrico alinhado à saída, fazendo o plano de corte coincidir com
  o portal sem alterar a câmera principal do jogador.

## Controles

- Movimento do jogador e direção da caminhonete: `WASD`.
- Correr: segure `Shift` enquanto se movimenta; a corrida consome stamina e é
  bloqueada enquanto o ET estiver no ar.
- Pular: `Espaço`. O impulso físico é imediato e entra diretamente no clip de
  subida, sem agachamento automático, atraso ou uma segunda abertura dos braços.
- Agachar: segure `C`.
- Câmera: mouse.
- Coletar ou largar item: `E`.
- Solicitar a abdução de um item solto na área de entrega: segure `E` por 3
  segundos.
- Acender ou apagar gradualmente a luz local dos olhos do ET: `F`.
- Entrar ou sair da caminhonete: `E`.
- Alternar câmera externa/interna da caminhonete: `G`.
- Avião: o mouse move o alvo que orienta o voo. Ao compor o avião com o
  jogador, `E` assume ou devolve o controle perto da cabine. Ao executar
  `FlyablePlane.tscn` isoladamente, o controle é ativado automaticamente.
- Abrir ou fechar o menu de pausa: `Esc`.
- Ativar ou desativar os binóculos: `B`. Com os binóculos ativos, `+`/`-` do
  teclado numérico ajustam o zoom.
- Mostrar ou ocultar o radar circular: `F3`.
- Abrir ou fechar o menu de debug: `F4`. No submenu de iluminação é possível
  trocar o preset de atmosfera entre Baixo, Médio e Alto, alternar Lua, céu, luz
  ambiente, neblina, casa e nave/feixes, além de regular cada intensidade entre
  0% e 200%.
- No painel principal do `F4`, `Modo Deus` torna o ET imortal, mantém a stamina
  cheia e multiplica velocidade e aceleração por cinco. `Modo Voo` remove a
  gravidade: use `WASD` para deslocar, `Espaço` para subir e `C` para descer.
  Os dois modos são independentes e podem permanecer ativos ao mesmo tempo.
- No menu inicial, o botão de áudio no canto inferior esquerdo silencia ou
  reativa a música do menu.

As interações usam uma ação própria para que `Espaço` possa ser reservado ao
pulo. No menu de opções, as quatro teclas de movimento podem ser remapeadas.
Durante a partida, o menu de pausa permite remapear movimento, corrida, pulo,
agachamento, interação, chamada da nave, luz dos olhos, radar, binóculos
(ativar e os dois zooms) e o menu de debug. Os remapeamentos duram pela sessão
atual.

## Arquitetura

O projeto é organizado em cenas reutilizáveis. `world.tscn` compõe o terreno,
a fazenda, a nave, vegetação, objetos, jogador, inimigo, veículo, destroços e
área de entrega.

```text
Player -> grupo pickup_items -> pickup/drop -> DeliveryArea -> sinal/abdução -> GlobalScore
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
NightEnvironment -> preset -> fog atmosférico + GroundFogLayer + volumetric fog
FogZone -> grupo fog_zones -> GroundFogLayer -> densidade local da névoa
Evento ET -> set_alien_fog_intensity() -> névoa/scattering/feixes/interferência
Nave/feixe/evento -> AlienInterferenceSource -> AlienIncidentPostProcess
```

## Ajustes de câmera e visual

- FOV, distância e colisão: `Camera3D.fov` e `SpringArm3D` em
  `scenes/Player.tscn`.
- Offset, smoothing, sway e respiração: exports de
  `scripts/cinematic_camera_rig.gd`.
- Grain, vignette, aberração, contraste e black lift: grupo `Base Look` do
  `IncidentPostProcess` em `scenes/NightEnvironment.tscn`.
- Bloom/halation: propriedades `glow_*` do `Environment` na mesma cena.
- Intensidade e resposta global da interferência: grupo `Alien Interference`
  do `IncidentPostProcess`.
- Alcance, intensidade e pulso por nave/feixe/evento: exports de cada
  `AlienInterferenceSource` nas respectivas cenas.
- Cores alienígenas: materiais e luzes em `space_ship.tscn`,
  `DeliveryArea.tscn`, `ArrivalBeam.tscn` e `SpaceShipInterior.tscn`.

### Névoa e presets de atmosfera

O `NightEnvironment` controla três fontes de névoa independentes. Hoje só a
primeira está ligada; as outras duas ficam prontas para serem religadas:

| Fonte | O que é | Estado | Custo |
| --- | --- | --- | --- |
| Névoa rasteira | Planos com `shaders/ground_fog.gdshader` que seguem a câmera | Ativa | Fill-rate |
| Fog atmosférico | `fog_*` do `Environment`, de tela cheia | Desligado | Quase nulo |
| Volumetric fog | `volumetric_fog_*` e o `FogVolume` rasteiro | Desligado | O mais caro |

Para religar o fog atmosférico, marque `atmospheric_fog_enabled` no Inspector do
`NightEnvironment`. Para religar a volumetria — e com ela os cones de luz da nave
e da abdução visíveis no ar —, ponha `volumetric_enabled` como `true` no preset
desejado dentro de `QUALITY_PRESETS`, no topo de
`scripts/night_environment.gd`; `fog_volume_enabled` faz o mesmo com o
`FogVolume` rasteiro. Todos os parâmetros de cada preset (`length`, resolução do
froxel grid, filtro, densidade) continuam lá.

Os presets diferem na qualidade e no alcance da manta rasteira:

- **Baixo** — uma camada, alcance de 46 m, sem soft depth, sem detalhe fino, sem
  domain warp, sem zonas, sem partículas atmosféricas e sem sombra nos feixes da
  nave.
- **Médio** — uma camada com soft depth, detalhe parcial e até quatro zonas;
  alcance de 55 m.
- **Alto** — duas camadas, detalhe completo e até seis zonas; alcance de 64 m.

Se a volumetria for religada, fora do preset Alto só a alimentam as luzes do grupo
`volumetric_lights` (Lua, holofotes da nave, feixe de abdução e feixe de
chegada). As demais têm `light_volumetric_fog_energy` zerado e restaurado quando
o preset volta a Alto; o valor original de cada luz fica guardado em metadata.

Ajustes disponíveis no Inspector do `NightEnvironment`:

- grupo `Quality`: `quality_level`, `particles_enabled`, `ground_fog_enabled`;
- grupo `Fog and Atmosphere`: `atmospheric_fog_enabled` (liga o fog de tela
  cheia), `fog_color` (fog atmosférico e volumetria), `ground_fog_color`
  (névoa rasteira, propositalmente mais clara), `atmospheric_fog_density`,
  `atmospheric_fog_height`, `atmospheric_fog_height_density` e
  `ground_fog_density` (só o `FogVolume`);
- grupo `Alien Atmosphere`: `alien_fog_color`, `alien_fog_response` (velocidade
  da transição), `alien_volumetric_density_boost`, `alien_fog_density_boost`,
  `alien_anisotropy`, `alien_emission_energy`, `alien_beam_fog_boost` e
  `alien_interference`.

A altura da manta vem de `layer_heights`, no `GroundFogLayer`: por padrão
0,25 m, 0,7 m e 1,4 m, ou seja, névoa rente ao chão. Suba esses valores para
uma névoa mais alta. No mesmo nó é possível ajustar `layer_noise_scales`,
`layer_opacities`, `forward_bias`, os intervalos de sondagem do terreno e das
zonas, e o comportamento alienígena (`alien_response`, `alien_drift_boost`,
`alien_opacity_boost`). Forma, movimento e cor da névoa ficam nos parâmetros do
`ShaderMaterial` compartilhado pelas três camadas em `scenes/GroundFogLayer.tscn`
(`noise_scale`, `coverage`, `softness`, `drift_speed`, `near_fade`, `far_fade_*`,
`height_fade_*` e `soft_depth`).

Cada camada é um plano, então perto do seu horizonte o desvanecimento por
distância se comprimiria em poucos pixels e apareceria como uma linha reta. Para
evitar isso, o shader também desvanece pela inclinação do raio de visão
(`horizon_fade`, em radianos aproximados, e `horizon_min_height`, a separação
mínima considerada para a névoa não sumir com a câmera dentro dela), o que
distribui o degradê de forma uniforme na tela. O raio dos planos é derivado de
`far_fade_end` para que o fade sempre termine antes da borda geométrica, e o
shader ainda zera o alfa na moldura do plano como garantia. Por isso
`forward_bias` fica em 0: deslocar o centro obriga a ampliar o plano na mesma
proporção, sem ganho.

Para adensar a névoa em um lugar específico — estrada, campo aberto, beira de
mata — basta instanciar `scenes/FogZone.tscn` na posição desejada e ajustar
`radius` e `strength`. `WheatField.tscn` e `SunflowersPatch.tscn` já trazem a sua
própria zona. O `GroundFogLayer` envia ao shader apenas as zonas mais próximas
da câmera, respeitando o limite do preset.

Por código, `NightEnvironment.set_alien_fog_intensity(valor)` recebe de 0 a 1 e
interpola suavemente densidade, tonalidade ciano-esverdeada, scattering,
velocidade da névoa, energia dos feixes no ar e interferência do filtro de tela.
Chame com `0.0` para voltar ao normal e use `get_alien_fog_intensity()` para ler
o valor atual. `set_quality_preset(nivel)` troca o preset em runtime.

Por código, o grupo `alien_post_process` expõe `set_manual_interference()`,
`clear_manual_interference()` e `pulse_interference()`. Cada fonte espacial
pode ser ligada ou desligada com `set_interference_enabled()`.

- `GlobalScore` é um autoload e mantém pontuação e uma lista simples de itens.
- `PhotoAlertSystem` é um autoload e mantém as estrelas, observadores ativos,
  contagem de tempo oculto e sinais para respostas futuras.
- Grupos do Godot conectam sistemas sem referências diretas: `characters`,
  `vehicles` e `pickup_items`.
- Os HUDs reutilizam o tema `Materiais/hud_theme.tres`, com tipografia Oxanium,
  margens seguras e painéis responsivos ancorados à tela.
- Menu, vida, stamina, fotografias, intervenção e radar usam uma família única
  de ícones 2D gerada dos meshes low-poly `Polygon Prototype`. A origem e o
  processo de geração estão registrados em
  `assets/ui/prototype_icons/SOURCE.md`.
- O jogador procura o item coletável mais próximo dentro de dois metros. Um
  item em abdução deixa temporariamente o grupo `pickup_items` para não poder
  ser recolhido antes da conclusão da entrega.
- O veículo desativa temporariamente o processamento e a câmera do jogador,
  exibe o ET no banco do motorista e restaura o personagem na saída.
- O fazendeiro usa os estados `WANDERING`, `CHASING` e `SHOOTING`, mantém a
  última posição vista por um curto período e respeita obstáculos entre seus
  olhos e o ET.
- Dano, intervalo entre tiros, alcance, precisão, dispersão, tempo de detecção
  e perda de visão são parâmetros exportados no fazendeiro.
- O ET usa um único `Skeleton3D` Mixamo de 49 ossos. O GLB reúne o mesh e 31
  clips nomeados; as translações horizontais do quadril foram removidas para
  que todas as animações sejam in-place e `CharacterBody3D` continue sendo a
  única autoridade de deslocamento e colisão.
- `PlayerAnimationController` constrói e centraliza a máquina de estados do
  `AnimationTree`: idle e variações, walk/run, strafes, agachamento, turn,
  pivôs móveis de 180°, run-stop, salto/queda/pouso, hit, stumble e duas
  orientações de get-up. A velocidade de reprodução da locomoção acompanha a
  velocidade física.
- `player.gd` continua cuidando de input, gravidade, colisão, impacto,
  equilíbrio, knockback e da decisão entre reação e queda. Ele apenas envia o
  estado físico ao controlador visual e dispara ações pontuais.
- Sobre a animação base permanecem dois `LookAtModifier3D`, com influência
  limitada, para cabeça e torso. O único `TwoBoneIK3D` do Player controla o
  braço direito e começa com influência zero; ele só entra ao carregar um item
  ou executar o sinal de intervenção. Pernas, quadril e movimento principal
  não são gerados por código.
- A entrada em ragdoll foi extraída para `_enter_ragdoll()`, sem os efeitos
  colaterais de morte. `_die()` chama essa função e acrescenta cursor visível,
  desligamento dos processos e o sinal `died`; a queda por desequilíbrio chama
  a mesma função e apenas conta o tempo até levantar.
- `player_ragdoll.gd` gera corpos físicos para a hierarquia Mixamo e é
  reversível. Ao entrar em queda, o `AnimationTree` e os modifiers visuais são
  suspensos; ao sair, a orientação do peito escolhe `get_up_back` ou
  `get_up_front` e a simulação entrega a pose final ao controlador.
- `RagdollRecoveryModifier`, último nó da pilha do esqueleto, mantém a pose
  caída somente por `ragdoll_pose_blend_duration` (0,25 s por padrão) e a
  dissolve sobre o começo do clip autoral. Ele serve para alinhamento curto,
  não para fabricar matematicamente o movimento de levantar.
- A pose caída também não pode ser lida do esqueleto, pelo mesmo motivo. Ela é
  reconstruída a partir do `global_transform` de cada `PhysicalBone3D`,
  corrigido pelo `body_offset`, antes de a simulação parar.
- Enquanto está caído, o `CharacterBody3D` acompanha a posição do quadril
  projetada no chão por raycast, para que a câmera siga o corpo. A cápsula de
  colisão fica desabilitada nesse período, já que os ossos físicos colidem com
  a máscara 1 e empurrariam o próprio personagem.
- A masmorra fica isolada, longe das duas `NavigationRegion3D` da fazenda, e
  não possui `NavigationRegion3D` própria: ela não participa da navegação do
  fazendeiro nem do fotógrafo, que continuam restritos à fazenda. O estado
  "já gerada" vive apenas em memória, como variável do próprio nó
  `Dungeon.tscn` (sem autoload dedicado), e é perdido ao recarregar a cena
  atual — por exemplo, ao reiniciar após a morte do ET.

## Estado do protótipo e pendências

- O disparo atual usa dano instantâneo, clarão provisório e empurrão no alvo;
  ainda não há projétil físico ou animação final de disparo.
- Polícia, van de reportagem, fotógrafos adicionais e MIB ainda não possuem
  cenas ou spawn; os respectivos métodos apenas emitem sinais e mensagens de
  placeholder.
- A pontuação não possui HUD, objetivo final nem persistência.
- O inventário do autoload existe, mas não está integrado ao fluxo atual de
  coleta e entrega.
- As opções e os remapeamentos feitos no menu não são salvos entre execuções.
- O projeto não possui multiplayer nem arquitetura de servidor.
- Há smoke tests automatizados dos estados de animação, do salto e da stamina,
  da reversão física, do ciclo reversível de ragdoll e dos presets de atmosfera
  em `tools/test_player_animation.gd`, `tools/test_player_jump_stamina.gd`,
  `tools/test_player_reversal.gd`, `tools/test_player_ragdoll.gd` e
  `tools/test_atmosphere_presets.gd`.
- A névoa rasteira é uma aproximação em camadas planas: ela não recebe luz das
  fontes do mapa. Com o volumetric fog desligado, feixes e holofotes não
  aparecem como cones de luz no ar.
- A origem e a licença dos assets em `3dModelos/` e `Texturas/` não estão
  documentadas no repositório; confirme-as antes de redistribuir o projeto.
- A biblioteca usada para gerar os ícones da interface não continha uma licença
  específica ao lado de `_SourceFiles`; confirme a licença original do pacote
  `Polygon Prototype` antes de redistribuir os PNGs derivados.
- Os áudios foram fornecidos pelo usuário sem licença anexada. A procedência e
  o uso de cada arquivo estão registrados em `assets/audio/SOURCE.md`.
- Os FBX Mixamo foram fornecidos pelo usuário sem licença anexada. Inventário,
  seleção, mapeamento e processo de geração estão registrados em
  `animations/mixamo/SOURCE.md`; confirme os termos antes de redistribuí-los.
- O clip de levantar de bruços é consideravelmente mais longo que o de costas.
  Ele começa a 3,2× para tirar os braços do chão sem demora e desacelera
  suavemente até 1,9× antes da parte de erguer o corpo, equilibrando o ritmo.
  O alinhamento inicial é uma mistura curta da pose física; ainda não há
  correção dinâmica de mãos e pés para terrenos inclinados.
- A queda não causa dano nem é registrada por nenhum sistema: fazendeiro,
  fotógrafo e vegetação continuam tratando o ET caído como um alvo normal.
- Durante a queda a cápsula de colisão fica desabilitada, então o ET pode
  atravessar geometria fina se o ragdoll escorregar para dentro dela; ao
  levantar não há verificação de espaço livre acima da cabeça.
- A masmorra procedural não tem objetivo além de coletar os destroços que
  aparecem nela; não há inimigos, iluminação atmosférica dedicada nem
  variação visual entre salas além dos materiais reaproveitados da fazenda.

## Qualidade e validação

Depois de alterar GDScript, cenas ou `project.godot`, abra o projeto no Godot e
verifique se não existem erros de importação, parsing ou referências ausentes.
Uma validação básica sem interface pode ser executada quando o Godot estiver no
`PATH`:

```powershell
godot --headless --path . --editor --quit
```

Os smoke tests dos presets de névoa e do evento alienígena rodam sem interface:

```powershell
godot --headless --path . --script res://tools/test_atmosphere_presets.gd
```

Para conferir o custo da atmosfera antes e depois de mexer na névoa, use o
medidor, que percorre os presets em `world.tscn` e imprime FPS, tempo de GPU e
tempo de CPU de renderização por frame:

```powershell
godot --path . --script res://tools/measure_atmosphere_cost.gd
```

Ele mede a referência sem névoa no início e no fim, porque a nave gira e muda
quantos feixes aparecem em tela: compare as duas para saber se a deriva entre as
amostras é pequena o bastante. Os números medidos com o volumetric fog ainda
ativo ficaram em +0,20 ms de GPU no preset Baixo, +0,57 ms no Médio e +0,86 ms
no Alto, sobre uma referência de ~6,5 ms por frame; com a volumetria desligada e
a manta mais baixa e curta, o custo atual é menor que isso — rode o medidor para
confirmar na sua máquina.

Mudanças de gameplay, câmera, física, veículo, navegação, IK ou vegetação devem
ser conferidas também em uma execução normal. Não inclua senhas, tokens,
credenciais ou chaves nos arquivos do projeto.
