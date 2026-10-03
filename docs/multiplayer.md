# Multiplayer — portais e fazenda co-op

O modo cooperativo é uma sessão ENet por IP direto, com um host jogável e até
três convidados. `PortalCoop.tscn` e `FarmCoop.tscn` compartilham o controlador
de sessão, com ciclo de vida próprio; não há autoload multiplayer. O seletor
do lobby troca de mapa antes da conexão. Host e convidados precisam escolher
o mesmo mapa e usar o mesmo conjunto de IDs de coletáveis. Como entrar, controles e limitações do
produto: [README](../README.md#co-op-de-portais).

## Arquivos e responsabilidades

| Arquivo | Responsabilidade |
| --- | --- |
| `scenes/Multiplayer/PortalCoop.tscn` | Arena, portais, chão, área de entrega, containers de jogadores e coletável |
| `scenes/Multiplayer/FarmCoop.tscn` | Fazenda protótipo, quatro destroços, entrega, portais e guarda |
| `scenes/Multiplayer/CoopBarn.tscn`, `CoopGuard.tscn` | Assets autocontidos com geometria nativa; guarda composto com visão e Beehave |
| `scripts/multiplayer/portal_session.gd` | Host/join, roster, RPCs, filas de interação, dinheiro/pontos da equipe, compras e UI da sessão |
| `scenes/Multiplayer/NetworkPlayer.tscn` | Herda a montagem de `Player.tscn` e troca o script pelo controlador multiplayer |
| `scripts/multiplayer/network_player.gd` | Input e física do jogador local; interpolação, animação e compras pessoais das réplicas |
| `scenes/Multiplayer/SharedScrap.tscn` | Destroço de duas mãos, com visual e colisão nativos |
| `scripts/multiplayer/shared_scrap.gd` | Contrato de coletável, sinais de pedido, aplicação de posse e movimento do objeto solto |
| `scripts/multiplayer/network_npc.gd`, `npc_attack.gd` | NPCActor com alvo no roster da sessão, simulação no host, ataque pela árvore e réplica nos convidados |
| `tools/test_portal_multiplayer.gd` | Integração de peers ENet em mundos separados; ver [validação](../tools/VALIDACAO.md#multiplayer-de-portais) |

## Jogadores e câmeras

O host aceita o registro do convidado, escolhe um slot livre e publica o roster.
Cada jogador tem nome igual ao peer ID sob `Players` e recebe sua autoridade
multiplayer antes de entrar na árvore. O novo peer recebe também aparência,
estado de cada coletável, vida/escudo/morte e economia atuais.

O dono simula seu personagem e envia snapshots ao host, que os encaminha aos
outros convidados. As réplicas interpolam o transform e alimentam o
`PlayerAnimationController` com velocidade e estados de locomoção. O contador
`epoch` faz uma travessia de portal saltar para a saída, sem interpolar o
trajeto entre os dois pontos. Essa autoridade de movimento pertence ao cliente;
o host valida o formato dos snapshots, mas não reconstitui os comandos de movimento.

Só o jogador local captura input, mantém HUD visível e ativa sua câmera.
Os portais consultam a câmera ativa do viewport local: cada computador cria
suas próprias texturas e vistas recursivas. Nenhuma imagem é transmitida pela
rede. As camadas reservadas à recursão estão em
[mundo — portais](mundo.md#portais); não são camadas atribuídas a peers.

## Coletável e entrega

`SharedScrap` herda o contrato de `spaceship_scraps.gd`: continua no grupo
`pickup_items`, mas `pickup()` e `drop()` emitem pedidos em vez de alterar posse
imediatamente. `NetworkPlayer.get_pickup_candidate()` escolhe o item disponível
mais próximo no registro da própria sessão, sem escolher itens de outro `World3D`.

O host enfileira pedidos com o peer ID obtido do remetente do RPC. No tick de
física, valida distância, linha de visão e disponibilidade para coletar;
somente o dono pode largar. A posse é publicada de forma confiável, com uma
revisão crescente por item. Cada instância tem `network_id` único e spawn próprio;
posses independentes permitem vários portadores simultâneos, com um objeto por ET.
Só o host simula a física dos objetos soltos; convidados recebem poses em lote
num canal separado e ignoram movimento de revisões anteriores daquele item.

Carregar reparenta o corpo para o jogador e atualiza `carried_item`, animação e
HUD. Assim, o objeto acompanha o transform do ET e entra nas malhas fatiadas e
clonadas pelos portais. `refresh_traveller_visual()` refaz essa lista quando a
posse muda dentro do limiar do portal. Ao largar, o corpo volta ao container
original, sem depender de `SceneTree.current_scene`.

A entrega é verificada pelo host no tick de física: somente o objeto solto,
com seu centro dentro da caixa de `DeliveryZone`, conta. O host credita os
valores `cash_value` e `score_value`, incrementa `deliveries` e reposiciona o
mesmo objeto no spawn. O reposicionamento imediato evita pagar novamente no
tick seguinte. Não se usa o feixe de `delivery_area.gd` nesta arena.

## Economia e compras

`team_money`, `team_score`, `deliveries` e `purchases` pertencem à sessão.
`GlobalScore` continua sendo o estado do fluxo single-player; a arena não
altera seu dinheiro, inventário ou níveis de melhoria.

O menu da sessão permite comprar melhorias de movimento, stamina e recuperação,
além de escudo, óculos de raio X e relógio predador. O cliente solicita apenas o
ID do produto. O host calcula o custo a partir do catálogo e das compras daquele
peer, verifica saldo/limite, debita uma vez e publica o novo estado. A fila
serializa compras concorrentes; equipamento já adquirido não pode ser comprado
novamente. Preços e níveis são definidos no código, não nesta documentação.

O dinheiro é compartilhado, mas a melhoria ou equipamento pertence ao comprador.
`NetworkPlayer` sobrescreve a consulta e aplicação das compras do controlador
single-player para ler `purchases[peer_id]`, sem conceder itens em `GlobalScore`.
Abrir o menu bloqueia só o personagem local; não pausa a partida inteira.

## Dano, morte e respawn

O host é a autoridade de vida e escudo. `damage_player()` aceita chamadas locais
do host; não existe RPC que permita ao convidado escolher dano ou vítima.
`NetworkPlayer.take_damage()` delega no host e ignora chamadas nos convidados.
Recuperação do escudo também roda no host, inclusive para jogadores remotos.
Estados confiáveis publicam vida, escudo, direção de impacto, revisão e geração
da vida. Cair para fora do mapa é fatal; quedas comuns continuam sem dano.

A morte usa o ragdoll existente em cada peer, desabilita movimento/input e solta
o item no host. O HUD multiplayer desconecta o handler de derrota single-player:
o menu da sessão oferece **Respawn**, sem recarregar a cena. O pedido identifica
o remetente; o host só recria personagens mortos. Slot, aparência, compras e
economia são preservados. A geração cresce a cada respawn e impede snapshots
de movimento ou combate da vida anterior de afetarem o personagem novo.
O convidado tardio recebe a geração e o estado de morte atuais.

O evento de morte é compartilhado; posições de ossos físicos são simuladas
localmente e podem divergir entre peers. Não há revive por colega nem custo
de respawn. Efeitos transitórios de outros equipamentos permanecem locais.

## NPC da fazenda co-op

O guarda é um `NPCActor` composto com `NPCVision` e árvore Beehave autocontida.
Os ramos priorizam ataque, perseguição, observação inicial e patrulha. O host
seleciona o jogador vivo visível mais próximo no roster da sessão, respeitando
cone, oclusão e furtividade, e preserva a memória do alvo quando perde contato.
O ataque de proximidade passa por `damage_player()`; convidados não decidem
alvos, movimento ou dano. Sem navmesh, o protótipo usa movimento direto com
colisão e a recuperação de caminho bloqueado do chassi existente.

Snapshots em canal próprio replicam pose, velocidade, estado e peer alvo.
Convidados interpolam a pose e mantêm sensores e árvore desativados. A sessão
desliga a simulação no lobby e restaura o spawn do guarda ao desconectar.
O timer de dormência e o vínculo com `PhotoAlertSystem` single-player ficam
desligados neste NPC; os sensores usam o roster, evitando alvos de outro mundo.
Este guarda usa uma cápsula nativa; não replica os NPCs legados de `world.tscn`,
não atravessa portais e não tem vida/arma de jogador ou animação esquelética.

## Desconexão e escopo

Quando um convidado sai carregando o objeto, o host o larga antes de remover
o jogador. A saída remove também as compras pessoais daquele peer, sem devolver
o dinheiro gasto. Reentrar cria um novo registro, não restaura compras anteriores.
Se o host sai, os convidados retornam ao painel de conexão. Encerrar/desconectar
a sessão zera economia e compras locais; não há persistência nem migração de host.

O fluxo menu → órbita → missão, os mapas single-player e suas lojas ainda não
usam essa sessão. A fazenda co-op é um mapa separado, não uma conversão de
`world.tscn`. Veículos, missões, NPCs single-player e efeitos transitórios de
equipamento além do escudo ainda não estão sincronizados. Movimento continua
sob autoridade do cliente; a validação de snapshots não constitui anticheat.
Os quatro coletáveis são instâncias fixas de cena, com respawn; não há protocolo
de criação dinâmica, persistência ou transição compartilhada de fase.
