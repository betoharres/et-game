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
- [Arquitetura](#arquitetura) — como as cenas e os sistemas se ligam, em resumo.
- [Mapas e cenas geradas](#mapas-e-cenas-geradas) — fazenda, Country Town, casa modular e masmorra.
- [Limitações conhecidas](#limitações-conhecidas) — o que ainda não existe ou é provisório.
- [Qualidade e validação](#qualidade-e-validação) — quando validar e onde estão os comandos.
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
| `tools/` | Checagens automatizadas e utilitários de build de asset (ver `docs/ferramentas.md` e `tools/VALIDACAO.md`) |
| `animations/mixamo/` | Rig visual único, FBX de origem, GLB gerado e mapeamento |
| `assets/` | Áudio, fontes e música do menu |
| `Texturas/ui/` | Ícones do HUD, gerados por `tools/render_prototype_icons.py` |
| `3dModelos/`, `Texturas/`, `Materiais/` | Assets importados e materiais reutilizáveis |
| `Temporarios/Animations/` | Rig e clipes Synty usados pelos NPCs |
| `Polygon*/`, `SICSFarm/` | Pacotes de asset importados, na forma em que vieram |
| `addons/` | Terrain3D, Beehave e PathMesh3D vendorados |
| `build/` | Cópias isoladas do projeto e saídas de inspeção; fora do versionamento |

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

- O jogador personaliza sete características do ET; `Iniciar jogo` salva o
  perfil em `user://character_appearance.cfg`.
- Na órbita, um terminal lista o catálogo de fases; adicionar uma fase não
  exige mexer em script.
- Na fase, a nave desce do céu e estaciona sobre o ponto de chegada; pisar no
  pad e interagir aciona a descida pelo feixe. Abrir `world.tscn` direto no
  editor pula esse passo.
- Destroços podem ser carregados e largados. Para entregar, o jogador larga o
  item na plataforma e sustenta o sinal de intervenção alienígena até o feixe
  sugá-lo. Um spider bot desce da nave e ajuda na coleta.
- O fazendeiro patrulha, persegue e atira; o fotógrafo acende até três
  estrelas, que solicitam respostas futuras de polícia, imprensa e MIB.
- A vegetação oscila com o vento, inclina-se perto de personagens e veículos e
  esconde parcialmente o ET, reduzindo o alcance de detecção dos inimigos.
- O ET tem vida, stamina e equilíbrio: colidir correndo ou cair provoca
  tropeço e, no limite, um ragdoll do qual ele se levanta sozinho.

Quem responde por cada etapa, o catálogo de fases e os limites do fluxo estão
em [`docs/fluxo-de-jogo.md`](docs/fluxo-de-jogo.md).

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

As interações usam uma ação própria para que `Espaço` fique reservado ao pulo.
O `F4` não abre menu: cada toque avança um degrau do ciclo de depuração. O
menu de opções remapeia as teclas de movimento e o menu de pausa remapeia as
demais ações; os remapeamentos duram a sessão.

O ciclo do `F4`, o painel do `F6` e o processo de acrescentar uma ação ao menu
de rebind estão em [`docs/ui-e-menus.md`](docs/ui-e-menus.md).

## Arquitetura

O projeto é composto por cenas reutilizáveis. Um mapa (`world.tscn`,
`CountryTown.tscn`) monta terreno, ambiente, jogador, NPCs, veículos, destroços
e área de entrega; nenhum manager global orquestra isso. Os sistemas se falam
por **sinais**, **grupos** e **contratos de método**, e o estado realmente
global vive em cinco autoloads: `CharacterAppearance`, `GlobalScore`,
`PhotoAlertSystem`, `SceneTransition` e `DebugMenus`.

O detalhamento — cenas de entrada, tabelas de autoloads e de grupos, contratos
entre sistemas, camadas de física e render, convenções de código e o diagrama
dos fluxos entre sistemas — está em
[`docs/arquitetura.md`](docs/arquitetura.md). Cada sistema tem o seu documento
em [Documentação por sistema](#documentação-por-sistema).

## Mapas e cenas geradas

| Mapa / cena | Situação |
| --- | --- |
| Fazenda (`scenes/world.tscn`) | O mapa jogável do catálogo, montado à mão |
| Country Town (`scenes/CountryTown/CountryTown.tscn`) | Mapa de `600 × 450 m` em construção, **fora do catálogo de fases**: abre direto pelo editor. Quase tudo é gerado pelas ferramentas de `tools/` |
| Casa modular (`scenes/Buildings/House01.tscn`) | Primeira casa em que Player e NPCs entram, autocontida, com porta automática e pontos de atividade. `HouseTest.tscn` é a cena de teste |
| Masmorra (`scenes/Dungeon/`) | Corredores procedurais planos, gerados uma vez por sessão a partir de uma porta na fazenda |

Cena gerada por ferramenta não se edita à mão: a receita no script de `tools/`
é a fonte da verdade. O detalhe de cada mapa está em
[`docs/mundo.md`](docs/mundo.md),
[`docs/country-town.md`](docs/country-town.md) e
[`docs/casas-interiores.md`](docs/casas-interiores.md); a ordem de execução das
ferramentas, em [`tools/VALIDACAO.md`](tools/VALIDACAO.md).

## Limitações conhecidas

- A nave que desce na fazenda e a `SpaceShip` que já existia na cena são
  redundantes, e não há caminho de volta à órbita.
- O catálogo tem só a Fazenda; Cidade e Deserto são exemplos bloqueados.
- O disparo usa dano instantâneo e clarão provisório, sem projétil físico.
- Polícia, imprensa e MIB existem apenas como sinais e mensagens de
  placeholder, sem cenas nem spawn.
- A pontuação não tem HUD (aparece só no console de depuração), objetivo final
  nem persistência, e o inventário do autoload não está integrado ao fluxo de
  coleta.
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

O padrão é não validar: a maior parte das mudanças vai direto. Depois de
alterar GDScript, cenas ou `project.godot`, uma checagem headless do Godot
confirma que não há erro de importação, parsing ou referência ausente, e as
verificações automatizadas de `tools/` cobrem um sistema cada. Resultado
visual, de câmera, física, IK, navegação ou gameplay precisa de conferência em
uma execução normal.

Os comandos exatos, o mapa de ferramenta por sistema, os roteiros de teste
manual e as regras para escrever uma verificação nova estão em
[`tools/VALIDACAO.md`](tools/VALIDACAO.md); a política de quando validar, em
[`AGENTS.md`](AGENTS.md); o mapa das ferramentas por categoria, em
[`docs/ferramentas.md`](docs/ferramentas.md).

## Documentação por sistema

`docs/` guarda a documentação persistente dos sistemas — arquitetura, fluxo de
jogo, player, NPCs, animações, veículos, mundo, Country Town, casas e
interiores, ambientação e FX, UI e menus, e ferramentas. É o que ler antes de
alterar cada parte do jogo: relações entre sistemas, arquivos importantes,
responsabilidades e decisões arquiteturais.

O índice, com o que cada documento cobre e quando lê-lo, está em
[`docs/README.md`](docs/README.md). A pasta `docs/generated/` recebe snapshots
automáticos do repositório (Repomix); o conteúdo gerado não é versionado — ver
[`docs/generated/README.md`](docs/generated/README.md).
