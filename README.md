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
  main_menu.tscn       Menu principal, opções e remapeamento de movimento
  world.tscn           Mapa jogável e composição do cenário
  Player.tscn          Jogador ET, câmera, vida, stamina e alvos de IK
  PlayerHUD.tscn       HUD de vida e stamina do ET
  PhotoAlertHUD.tscn   HUD das 0–3 estrelas de exposição fotográfica
  DebugMenu.tscn       Menu F4 com ferramentas de inspeção da iluminação
  DriveableTruck.tscn  Caminhonete controlável
  VisionDebugMap.tscn  Radar circular opcional de objetivos e ameaças
  SmellyFarmer.tscn    Fazendeiro, navegação e IK
  Photographer.tscn    NPC fotógrafo e câmera provisória
  spaceship_scraps.tscn Item coletável e entregável
  DeliveryArea.tscn    Área que converte itens entregues em pontos
  WheatField.tscn      Trigo com vento e reação a personagens e veículos
  SunflowersPatch.tscn Girassóis com vento e reação ao movimento
scripts/
  menu_atmosphere.gd   Estrelas, nave, fachos, terreno e atmosfera do menu
  night_environment.gd Controla qualidade e animações atmosféricas do mundo
  house_lights.gd      Oscilação discreta das luzes quentes da casa
  player.gd            Movimento, vida, stamina, coleta e entrega
  player_ragdoll.gd    Morte física articulada do ET
  driveable_truck.gd   Direção, entrada, saída e câmeras do veículo
  vision_debug_map.gd  Radar circular com ícones e cones de visão discretos
  debug_menu.gd        Alterna fontes de luz e atmosfera durante a partida
  smelly_farmer.gd     Patrulha, visão, perseguição, disparo e dano
  photographer.gd      Visão, perseguição e captura de fotos do ET
  photo_alert_system.gd Contador global e redução das estrelas
  GlobalScore.gd       Pontuação e inventário globais
  audio/               Passos, ambiente rural e som sintetizado da espingarda
  *_field.gd           Comportamento da vegetação
assets/audio/          Vento, grilos, cães, passos e registro de origem
assets/ui/             Ícones leves derivados dos meshes low-poly do pacote visual
shaders/night_sky.gdshader Céu procedural estrelado e Lua
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
- A fazenda possui céu procedural estrelado, Lua fixa, estrelas cadentes,
  névoa baixa e iluminação ambiente azulada configurável por qualidade.
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
- A pontuação atual é exibida apenas no console de depuração.
- A caminhonete pode ser usada para atravessar o mapa e possui câmeras externa
  e interna.
- O fazendeiro escolhe destinos aleatórios na malha de navegação. Ao enxergar
  o jogador, passa a persegui-lo e entra no estado de disparo quando está
  próximo. Cada tiro causa dano, emite som e exibe um clarão provisório no
  cano da espingarda. A precisão varia com distância, movimento, camuflagem e
  acertos consecutivos; tiros errados seguem um raycast desviado e colidem com
  o cenário.
- O ET possui 100 pontos de vida e 100 pontos de stamina. Correr consome
  stamina; ao esgotá-la por completo, a recuperação fica bloqueada por 3
  segundos antes de voltar gradualmente.
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
- Trigo e girassóis escondem parcialmente o ET: reduzem o alcance e tornam a
  detecção do fazendeiro mais lenta. Agachar dentro da vegetação aumenta a
  camuflagem.
- Trigo e girassóis oscilam com vento e se inclinam perto do jogador ou de
  veículos.
- Vento e grilos formam a camada ambiente contínua. Latidos são reproduzidos
  em posições e intervalos variados ao redor da fazenda.
- Os passos acompanham o movimento do ET, variam amostra e afinação e tentam
  distinguir terra, pedra e madeira pelo objeto sob o personagem.

## Controles

- Movimento do jogador e direção da caminhonete: `WASD`.
- Correr: segure `Shift` enquanto se movimenta; a corrida consome stamina e é
  bloqueada durante a preparação do salto e enquanto o ET estiver no ar.
- Pular: `Espaço`. O ET flexiona rapidamente os joelhos antes do impulso.
- Agachar: segure `C`.
- Câmera: mouse.
- Coletar ou largar item: `E`.
- Solicitar a abdução de um item solto na área de entrega: segure `E` por 3
  segundos.
- Acender ou apagar gradualmente a luz local dos olhos do ET: `F`.
- Entrar ou sair da caminhonete: `E`.
- Alternar câmera externa/interna da caminhonete: `G`.
- Abrir ou fechar o menu de pausa: `Esc`.
- Mostrar ou ocultar o radar circular: `F3`.
- Abrir ou fechar o menu de debug: `F4`. No submenu de iluminação é possível
  alternar Lua, céu, luz ambiente, neblina, casa e nave/feixes, além de regular
  cada intensidade entre 0% e 200%.
- No menu inicial, o botão de áudio no canto inferior esquerdo silencia ou
  reativa a música do menu.

As interações usam uma ação própria para que `Espaço` possa ser reservado ao
pulo. No menu de opções, as quatro teclas de movimento podem ser remapeadas.
Durante a partida, o menu de pausa permite remapear movimento, corrida, pulo,
agachamento e interação. Os remapeamentos duram pela sessão atual.

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
```

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
- IK procedural movimenta membros do ET e do fazendeiro sem concentrar esse
  comportamento nos scripts principais de gameplay.

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
- Não há testes automatizados versionados neste momento.
- A origem e a licença dos assets em `3dModelos/` e `Texturas/` não estão
  documentadas no repositório; confirme-as antes de redistribuir o projeto.
- A biblioteca usada para gerar os ícones da interface não continha uma licença
  específica ao lado de `_SourceFiles`; confirme a licença original do pacote
  `Polygon Prototype` antes de redistribuir os PNGs derivados.
- Os áudios foram fornecidos pelo usuário sem licença anexada. A procedência e
  o uso de cada arquivo estão registrados em `assets/audio/SOURCE.md`.

## Qualidade e validação

Depois de alterar GDScript, cenas ou `project.godot`, abra o projeto no Godot e
verifique se não existem erros de importação, parsing ou referências ausentes.
Uma validação básica sem interface pode ser executada quando o Godot estiver no
`PATH`:

```powershell
godot --headless --path . --editor --quit
```

Mudanças de gameplay, câmera, física, veículo, navegação, IK ou vegetação devem
ser conferidas também em uma execução normal. Não inclua senhas, tokens,
credenciais ou chaves nos arquivos do projeto.
