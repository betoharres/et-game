# ET Game

Protótipo 3D em Godot, com fluxo single-player e arena co-op de até quatro
jogadores. No fluxo single-player, um extraterrestre explora uma
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
- [Co-op de portais](#co-op-de-portais) — lobby, missão compartilhada, dinheiro da equipe e recuperação de colegas.
- [Controles](#controles) — teclas e ações do Input Map.
- [Arquitetura](#arquitetura) — como as cenas e os sistemas se ligam, em resumo.
- [Mapas e cenas geradas](#mapas-e-cenas-geradas) — fazenda, Country Town, casa modular e masmorra.
- [Limitações conhecidas](#limitações-conhecidas) — o que ainda não existe ou é provisório.
- [Qualidade e validação](#qualidade-e-validação) — quando validar e onde estão os comandos.
- [Documentação por sistema](#documentação-por-sistema) — o que ler em `docs/` antes de alterar cada sistema.

## Tecnologias e ambiente

- Godot `4.8 dev7` com GDScript e cenas `.tscn`; Godot 4.7 não é garantido,
  pois a luz viva usa `Trail3D` nativo.
- Renderer `Forward Plus` com Direct3D 12 no Windows, em tela cheia com
  resolução-base `1920×1080`.
- Física 3D com Jolt Physics.
- Terreno com Terrain3D; modelos `.fbx`/`.glb`, com texturas e materiais rurais.
- Behavior Trees dos NPCs com o addon [Beehave](https://github.com/bitbrain/beehave)
  (MIT, vendorado em `addons/beehave/`).
- Export para Windows Desktop `x86_64` em `export_presets.cfg`.

## Estrutura principal

| Pasta                                   | Conteúdo                                                                                                   |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `scenes/`                               | Todas as cenas do jogo, incluindo `Space/`, `CountryTown/`, `Buildings/`, `NPCs/`, `Dungeon/` e `Portal/`  |
| `scripts/`                              | GDScript, espelhando a organização das cenas (`space/`, `levels/`, `npc/`, `dungeon/`, `audio/`)           |
| `shaders/`                              | Céu procedural, névoa rasteira, terreno e efeitos                                                          |
| `tools/`                                | Checagens automatizadas e utilitários de build de asset (ver `docs/ferramentas.md` e `tools/VALIDACAO.md`) |
| `animations/mixamo/`                    | Rig visual único, FBX de origem, GLB gerado e mapeamento                                                   |
| `assets/`                               | Áudio, fontes e música do menu                                                                             |
| `Texturas/ui/`                          | Ícones do HUD, gerados por `tools/render_prototype_icons.py`                                               |
| `3dModelos/`, `Texturas/`, `Materiais/` | Assets importados e materiais reutilizáveis                                                                |
| `Temporarios/Animations/`               | Rig e clipes Synty usados pelos NPCs                                                                       |
| `Polygon*/`, `SICSFarm/`                | Pacotes de asset importados, na forma em que vieram                                                        |
| `addons/`                               | Terrain3D, Beehave e PathMesh3D vendorados                                                                 |
| `build/`                                | Cópias isoladas do projeto e saídas de inspeção; fora do versionamento                                     |

A cena principal é `scenes/Menu/main_menu.tscn`; a fazenda é
`scenes/world.tscn`. O mapa de cenas e scripts de cada etapa está em
[fluxo-de-jogo.md](docs/fluxo-de-jogo.md#etapas-e-quem-responde-por-cada-uma).

## Executar

Abra `project.godot` no Godot 4.8 dev7 e pressione `F5`. Pelo
PowerShell, use o wrapper do projeto (`tools/godot.cmd`):

```powershell
.\tools\godot.cmd --path .            # rodar o jogo
.\tools\godot.cmd --editor --path .   # abrir o editor
```

O wrapper ainda procura executáveis dev4 ou `godot` no PATH. Se apenas o dev7
estiver instalado, invoque seu executável diretamente; caminhos e comandos
ficam em [tools/VALIDACAO.md](tools/VALIDACAO.md#comandos).

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
  editor inicia automaticamente a descida pelo feixe, sem a etapa do pad.
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

## Co-op de portais

No menu principal, escolha **CO-OP (4 JOGADORES)** para abrir
`scenes/Multiplayer/CampaignCoop.tscn`. No lobby, todos selecionam o mesmo
modo: **SP campaign - Orbit**, **Portal arena** (`PortalCoop.tscn`) ou
**Farm prototype** (`FarmCoop.tscn`). Um jogador escolhe **Host game**;
os demais informam o IP do host e escolhem **Join game**, usando a mesma porta
(padrão `7000`, UDP). No mesmo computador, use `127.0.0.1`; na mesma rede, use
o IP local do host. Para internet, use o IP público do host; ele precisa liberar
Godot no firewall e encaminhar essa porta UDP no roteador. Não há matchmaking
ou relay; redes sem encaminhamento acessível podem impedir a conexão direta.
Informe seu nome, confirme **Toggle ready** em cada jogador e deixe o host
escolher **Start expedition**. Um convidado pode entrar durante a coleta;
durante a partida, `Esc` abre o painel de sessão.

A campanha começa na órbita: reúna toda a equipe viva a bordo e escolha a
fazenda no console. Repare a nave para desbloquear o resgate em Country Town;
o diálogo de resgate leva a equipe ao mapa. Qualquer colega pode descobrir o
acidente, revelando os destroços para todos. Entregue na fazenda usando o sinal
de abdução; no Country Town, largue os destroços no ponto de recuperação para
a nave recolher. Vendas consomem esses objetos uma única vez. Lançamento retorna
à órbita; saldo, compras, Radon e inventário guardado acompanham a equipe.

Aproxime-se de um destroço azul ou dos scraps provenientes das cenas SP e pressione `E` para coletar; `G` ou
`E` enquanto carrega larga o objeto. Ele acompanha o ET pelos portais, incluindo
as cópias fatiadas. Cada ET pode carregar um objeto; vários jogadores podem
carregar objetos diferentes. Itens menores entram no inventário, respeitando
capacidade; objetos de duas mãos e corpos ocupam as mãos. Se o portador morrer
ou desconectar, seus objetos são largados.

Nos mapas protótipo, largue o objeto no pad verde **TEAM DELIVERY** para creditar dinheiro e pontos
à equipe. Ele reaparece no spawn para repetir o ciclo. Os valores de entrega
ficam na cena do coletável. O HUD mostra saldo, pontos e número de entregas;
convidados que entram depois recebem o estado atual.

`Esc` abre a loja e o menu da sessão, sem pausar os demais. Todos compram da
mesma reserva de dinheiro; equipamento ou melhoria vai para o comprador.
A loja inclui movimento, stamina, recuperação, escudo, óculos de raio X e
relógio predador. Escudo e invisibilidade têm estado e energia controlados pelo
host; raio X funciona no mundo do dono, com óculos visíveis nas réplicas e sem
ativação simultânea com invisibilidade. A sessão começa sem
dinheiro e não persiste saldo ou compras em disco. Sair não reembolsa compras;
reentrar pela mesma instância da sessão recupera compras e vida, sem cura gratuita.
Recriar a cena ou fechar o jogo perde essa identidade de reconexão.
Se o host sair, a partida pausa e o convidado de menor slot assume usando o
último checkpoint. Antes de entrar, configure **Your hosting IP** e **Hosting
UDP** se necessário; porta zero escolhe automaticamente uma porta exibida após
a conexão. Para migração pela internet, cada possível sucessor precisa liberar
Godot e encaminhar sua própria porta UDP. Falha de conexão retorna ao painel;
perda abrupta do host pode perder progresso posterior ao último checkpoint.

Use a máquina junto à nave para comprar equipamento, repor Radon, reparar e
lançar a expedição. Venda scraps para financiar o reparo; após reparar, reúna
todos os jogadores vivos no terminal para liberar o lançamento. A equipe recebe
resultados e troca de mapa em conjunto, preservando dinheiro, compras e Radon;
o reparo precisa ser feito novamente na próxima rodada. Radon esgotado é fatal.

Na fazenda protótipo, guarda, fazendeiro e fotógrafos detectam qualquer colega
visível; o host controla IA, ataques e fotos. A criatura luminosa reage aos
colegas próximos. Qualquer ET pode iniciar a quest do Gorilla e outro entregar
a caixa de bananas; progresso e recompensa pertencem à equipe. Porta do celeiro
e veículos também são compartilhados. `E` entra/sai: caminhonete tem motorista,
passageiro e dois lugares na caçamba; avião aceita somente piloto.

Não existe respawn imediato. Carregue o corpo de um colega como um scrap e
largue junto ao console do **SHIP REVIVAL TANK**: o host debita **$200** do dinheiro da
equipe e inicia um processamento de **20 segundos** em um dos quatro tanques.
Ao terminar, revive o ET junto à nave, preservando compras. Sem saldo suficiente,
o corpo aguarda enquanto os sobreviventes coletam scraps. Cair fora do mapa
mata. Se todos os ETs conectados morrerem, o run é zerado e todos permanecem
conectados no lobby para confirmar readiness e iniciar outra expedição.

O estado da equipe é independente do dinheiro e progresso single-player,
mesmo quando a campanha reutiliza seus mapas.
Arquitetura e limites: [docs/multiplayer.md](docs/multiplayer.md).

## Controles

No modo co-op, `Esc` abre o menu de sessão e loja, sem pausar os outros jogadores.

| Ação                                                              | Tecla                                      |
| ----------------------------------------------------------------- | ------------------------------------------ |
| Mover o ET / dirigir a caminhonete                                | `WASD`                                     |
| Câmera                                                            | Mouse                                      |
| Correr                                                            | `Shift` (consome stamina; bloqueado no ar) |
| Pular / agachar                                                   | `Espaço` / segure `C`                      |
| Coletar ou largar item                                            | `E`                                        |
| Pegar no colo ou soltar um ET caído                               | `E`                                        |
| Interagir: portas, terminal, pad de descida, caminhonete e veículos co-op | `E`                                        |
| Solicitar a abdução de um item na área de entrega                 | Segure `E`                                 |
| Selecionar slot do inventário de exploração                       | `1`-`4`                                    |
| Trocar de slot do inventário de exploração                        | Roda do mouse                              |
| Largar item carregado ou o slot selecionado do inventário          | `G` (ou `C` (agachar) + `E`)               |
| Luz dos olhos do ET                                               | `F`                                        |
| Primeira pessoa (a pé ou na caminhonete)                          | `V`                                        |
| Binóculos / zoom                                                  | `B` / `+` e `-` do teclado numérico        |
| Minimapa circular                                                 | `F3`                                       |
| Manto de invisibilidade: ativar/desativar                          | `H`                                        |
| Velocidade e voo (a cada toque)                                   | `F4`                                       |
| Debug de iluminação                                               | `F6`                                       |
| Menu de pausa                                                     | `Esc`                                      |

## Arquitetura

Cada mapa monta cenas reutilizáveis que se comunicam por sinais, grupos e
contratos de método. [docs/arquitetura.md](docs/arquitetura.md) localiza os
contratos e autoloads; [docs/README.md](docs/README.md) indica por onde começar
em cada sistema.

## Mapas e cenas geradas

| Mapa / cena                                          | Situação                                                                                                                                       |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Fazenda (`scenes/world.tscn`)                        | O mapa jogável do catálogo, montado à mão                                                                                                      |
| Country Town (`scenes/CountryTown/CountryTown.tscn`) | Mapa de `600 × 450 m` em construção, no catálogo de fases como a missão de resgate; ainda abre direto pelo editor para iteração rápida. Quase tudo é gerado pelas ferramentas de `tools/` |
| Casa modular (`scenes/Buildings/House01.tscn`)       | Primeira casa em que Player e NPCs entram, autocontida, com portas trancáveis e pontos de atividade. `HouseTest.tscn` é a cena de teste        |
| Masmorra (`scenes/Dungeon/`)                         | Corredores procedurais planos, gerados uma vez por sessão a partir de uma porta na fazenda                                                     |

Cena gerada por ferramenta não se edita à mão: a receita no script de `tools/`
é a fonte da verdade. O detalhe de cada mapa está em
[`docs/mundo.md`](docs/mundo.md),
[`docs/country-town.md`](docs/country-town.md) e
[`docs/casas-interiores.md`](docs/casas-interiores.md); a ordem de execução das
ferramentas, em [`tools/VALIDACAO.md`](tools/VALIDACAO.md).

## Limitações conhecidas

- Não há caminho de volta da fazenda (nem do Country Town) à órbita.
- O catálogo tem a Fazenda e o Country Town (missão de resgate); Cidade e
  Deserto são exemplos bloqueados.
- O disparo usa dano instantâneo e clarão provisório, sem projétil físico.
- Polícia, imprensa e MIB existem apenas como sinais e mensagens de
  placeholder, sem cenas nem spawn.
- No fluxo single-player, a pontuação não tem HUD (aparece só no console de depuração), objetivo final
  nem persistência, e o inventário do autoload não está integrado ao fluxo de
  coleta.
- Opções e remapeamentos não são salvos entre execuções.
- O multiplayer tem campanha compartilhada entre órbita, fazenda e Country Town,
  além de arena/fazenda protótipo, com recuperação, quest, NPCs e veículos adaptados.
  A adaptação não cobre automaticamente scripts novos; spider bots e o sistema
  SP de scavenging ficam desativados na campanha. NPCs e veículos não atravessam
  portais; ocupantes não têm animação específica de sentar.
  Movimento do ET é simulado pelo cliente dono; coletáveis,
  combate, veículos e economia ficam no host. Validação de snapshots não é
  anticheat; simulação de atraso/perda nos testes cobre snapshots de movimento.
  Não há split-screen, matchmaking, relay ou persistência em disco. Migração
  exige um sucessor acessível por IP/UDP e usa o último checkpoint recebido.
- A névoa rasteira não recebe luz das fontes do mapa; com a volumetria
  desligada, feixes e holofotes não formam cones de luz no ar.
- A queda não causa dano nem é percebida pelos NPCs, e durante o ragdoll a
  cápsula de colisão fica desabilitada.
- A masmorra não tem objetivo além dos destroços: sem inimigos, salas especiais
  nem variação vertical.
- No Country Town o cenário está fechado, os NPCs já andam e a missão de
  resgate (destroços, localizador e entrega automática) já é jogável, mas
  falta uma armadilha de ameaça própria da fase; a sucata da queda é cenário,
  o portal da mina é só a moldura, o áudio ambiente reusa posições fixas da
  fazenda e o motor alienígena (maior pontuação) não tem via de entrega, pois
  não pode ser transportado pelo jogador.
- A `NavigationRegion3D` da fazenda nunca foi bakeada: ali a luz viva voa por
  sonda de chão, sem desvio de obstáculo pela navegação. Dentro da nave, a
  malha cobre apenas a plataforma de `9×9 m`.
- A origem e a licença dos assets em `3dModelos/` e `Texturas/`, do pacote
  `Polygon Prototype` e dos FBX Mixamo não estão confirmadas. Áudio, ícones e
  animações têm procedência registrada em `assets/audio/SOURCE.md`,
  `Texturas/ui/SOURCE.md` e `animations/mixamo/SOURCE.md`; confirme os termos
  antes de redistribuir.

## Qualidade e validação

A política de quando validar fica em [AGENTS.md](AGENTS.md#validação).
Comandos e seleção de testes ficam em [tools/VALIDACAO.md](tools/VALIDACAO.md).
Checagem headless não comprova aparência, física ou experiência de jogo;
os roteiros manuais estão nesse mesmo documento.

## Documentação por sistema

Use [docs/README.md](docs/README.md) para localizar o documento e o código
responsável pela tarefa. [AGENTS.md](AGENTS.md) concentra as regras de trabalho.
Os snapshots de `docs/generated/` são exportações opcionais de contexto,
não documentação adicional a carregar durante o desenvolvimento.
