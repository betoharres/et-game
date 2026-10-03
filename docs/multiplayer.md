# Multiplayer — portais e fazenda co-op

Sessão ENet por IP direto, com host jogável e até três convidados, sem autoload
multiplayer. `PortalCoop.tscn` e `FarmCoop.tscn` mantêm a raiz `CoopSession` e
seus caminhos de RPC durante trocas de mapa. Entrada, controles e regras de
revival: [README](../README.md#co-op-de-portais).

## Arquivos e responsabilidades

| Arquivo | Responsabilidade |
| --- | --- |
| `scenes/Multiplayer/PortalCoop.tscn`, `FarmCoop.tscn` | Mapas co-op, portais, entrega e containers |
| `CoopBarn.tscn`, `CoopGuard.tscn`, `CoopBarnDoor.tscn`, `RevivalTank.tscn` em `scenes/Multiplayer/` | Assets autocontidos do protótipo |
| `scripts/multiplayer/portal_session.gd` | Conexão, nomes/readiness, roster, registros de itens/NPCs, economia, combate e missão |
| `NetworkPlayer.tscn`, `scripts/multiplayer/network_player.gd` | Player herdado, input/câmera locais, snapshots, compras e combate |
| `SharedScrap.tscn`, `scripts/multiplayer/shared_scrap.gd` | Pedidos de coleta/drop, posse e réplica de objetos soltos |
| `CoopShopTerminal.tscn`, `scripts/multiplayer/coop_ship_shop.gd` | Interface derivada da loja SP; ações e dinheiro da equipe |
| `scripts/multiplayer/coop_recovery.gd` | Corpos compartilhados e revival no tanque |
| `scripts/multiplayer/coop_vehicle.gd` | Componente `CoopSeats`: assentos, comandos, física e réplica |
| `scripts/multiplayer/coop_door.gd` | Pedidos validados no host, tranca e folha |
| `scripts/multiplayer/coop_banana_trade.gd` | Quest compartilhada, consumo da caixa e recompensa |
| `scripts/multiplayer/network_npc.gd`, `npc_attack.gd` | NPCActor com roster, Beehave e simulação no host |
| `scripts/multiplayer/network_farm_enemy.gd`, `network_living_light.gd` | Papéis da fazenda e criatura luminosa |
| `tools/test_portal_multiplayer.gd`, `tools/network_fault_session.gd` | Integração ENet e falhas em snapshots; [validação](../tools/VALIDACAO.md#multiplayer-de-portais) |

## Jogadores e câmeras

O registro valida mapa e manifesto estático de IDs; corpos e recompensas
dinâmicas ficam fora desse manifesto. O host escolhe um slot e publica roster,
aparência, combate, gerações, itens, economia, missão, quest e assentos atuais.
Nós em `Players` usam peer ID; nomes de exibição ficam separados. No lobby,
todos confirmam readiness e somente o host inicia a expedição.

O dono simula seu personagem e envia snapshots ao host para encaminhamento.
Réplicas interpolam transform e alimentam o `PlayerAnimationController`.
`epoch` faz a travessia de portal saltar à saída; sequência crescente rejeita
pacotes atrasados e `life_generation` separa vidas. O host valida tipos,
valores finitos, limites de posição/velocidade e escala da base, mas não
reconstitui comandos de movimento. Essa validação não constitui anticheat.

Só o jogador local captura input, mostra HUD e ativa sua câmera. Cada computador
renderiza suas próprias texturas recursivas; nenhuma imagem trafega pela rede.
Camadas de recursão: [mundo — portais](mundo.md#portais). Não são camadas por peer.

## Coletável e entrega

`shared_scrap.gd` herda `spaceship_scraps.gd`, preservando `pickup_items`.
`pickup()`/`drop()` emitem pedidos; o candidato vem do registro da sessão e do
mesmo `World3D`. O host identifica o remetente e valida alcance, oclusão,
disponibilidade e mãos livres no tick de física. Só o dono pode largar.
Cada item tem `network_id`, revisão de posse e spawn próprios.

Há instâncias de teste e scraps provenientes das cenas SP, preservando suas
propriedades de entrega/transporte. `_setup_farm_content()` e `_setup_vehicles()`
montam conteúdo adicional. Ao trocar scripts de assets existentes, preserve
exports necessários, incluindo a lista de recompensas do `BananaTrade`.

Só o host simula objetos soltos. Poses são enviadas em pequenos lotes num canal
separado; réplicas ignoram revisões antigas. Carregar reparenta o objeto ao ET,
atualiza mãos/animação/HUD e inclui suas malhas nos clones dos portais.
`refresh_traveller_visual()` refaz essa lista quando a posse muda no limiar.
Ao largar, o item volta ao container original.

O centro do objeto solto precisa estar dentro de `DeliveryZone`. O host credita
seus valores, incrementa entregas e o reposiciona imediatamente no spawn,
evitando pagamento duplicado. `rejected_by_delivery` impede venda de corpos e
caixa de bananas. Esse fluxo não usa o feixe SP.

## Economia e compras

Dinheiro, pontos, entregas, `purchases` e Radon pertencem à sessão. `GlobalScore`
e progresso SP não são alterados. Compras debitam o mesmo saldo; equipamento e
melhorias pertencem ao comprador. O host calcula preço/limites pelo catálogo e
serializa pedidos concorrentes. `NetworkPlayer` lê `purchases[peer_id]`.

Menu de sessão e máquina física compartilham esse estado. `coop_ship_shop.gd`
reutiliza a interface SP, mas encaminha equipamento, reparo, Radon e lançamento
ao host. Ações da máquina exigem jogador vivo, próximo e missão em coleta.
Abrir um menu bloqueia somente o personagem local.

Escudo e relógio predador têm recuperação/carga e ativação controladas pelo
host. Camuflagem e energia são replicadas e alimentam a detecção dos NPCs.
O cheat de dinheiro credita a equipe. Raio X permanece no catálogo; sua revisão
específica multiplayer foi adiada. Preços e limites ficam no código.

## Ciclo compartilhado de missão

O lobby inicia a coleta com a equipe pronta. Vendas financiam o reparo da nave;
reparo habilita lançamento, que exige todos os jogadores vivos junto ao
terminal. Radon é compartilhado e comprado na máquina; seu esgotamento causa
dano fatal pelo host.

Lançamento publica resultados e bloqueia movimento/interações. Depois, os
peers alternam entre os mapas co-op usando `_commit_round()`: raiz, conexão,
container de jogadores e UI permanecem; conteúdo e registros do mundo são
reconstruídos e ETs substituídos com nova geração. Saldo, compras e Radon
continuam; reparo e contadores da rodada são reiniciados.

Se todos os jogadores conectados morrerem, `_reset_run()` mantém a conexão,
zera economia/compras e progresso da expedição, recria conteúdo/jogadores e
retorna ao lobby com readiness desmarcado. Não há retry preservando saldo.
A regra vale também para sessões com menos de quatro ETs.

## Dano, morte e recuperação

`damage_player()` é uma chamada local do host; não há RPC para o convidado
escolher dano ou vítima. `NetworkPlayer.take_damage()` ignora autoria dos
convidados. Estados confiáveis replicam vida, escudo, direção, camuflagem,
energia, revisão e geração. Cair para fora do mapa é fatal.

Morte solta o item e desabilita movimento/input. O handler de derrota SP fica
desconectado e o respawn imediato é recusado. `coop_recovery.gd` cria um corpo
`corpse_<peer_id>` como coletável compartilhado de duas mãos, simulado pelo
host; o visual original é ocultado e seu ragdoll interrompido. Com renderer,
malhas esqueléticas podem ser congeladas na pose atual; headless usa fallback.
Transporte usa o protocolo dos scraps, inclusive nos portais. Carregar
personagens pelo caminho SP fica desativado para evitar um segundo corpo local.

Corpo solto no tanque e saldo suficiente permitem ao host debitar o custo,
remover o item e recriar o ET junto à nave, preservando compras. Sem saldo, o
corpo aguarda enquanto sobreviventes coletam scraps. Gerações rejeitam snapshots
da vida anterior. Late join recebe corpos antes das mensagens de posse;
desconectar remove o corpo daquele peer.

## NPC da fazenda co-op

Guarda, fazendeiro e fotógrafos usam NPCActor, NPCVision e Beehave no host.
O alvo é o jogador vivo visível mais próximo do roster, respeitando cone,
oclusão e furtividade, com memória de contato perdido. O guarda ataca perto;
o fazendeiro dispara com dano pelo host. Fotógrafos acumulam foco, replicam
contagem/flash e alertam outros NPCActors da sessão. Vínculo com
`PhotoAlertSystem` SP e dormência global ficam desligados nessas adaptações.

Convidados interpolam pose/estado/alvo sem executar sensores ou árvore.
Sem navmesh, o protótipo usa movimento direto com colisão e recuperação de
caminho bloqueado. A living light preserva seu comportamento próprio, escolhe
o colega vivo detectável mais próximo e replica pose, velocidade e estado.

O Gorilla fica estacionário no protótipo. Qualquer colega inicia ou continua
sua quest e outro pode entregar a caixa. O host valida interação e posse,
marca a caixa consumida e publica uma única recompensa compartilhada.
Late join recebe progresso e recompensa antes das poses dos itens.

## Veículos e porta

`CoopSeats` é acrescentado às cenas existentes de caminhonete e avião. Input,
física e câmeras SP são desativados; ocupantes mantêm suas próprias câmeras.
O host valida proximidade, vida, mãos livres e assento disponível. Caminhonete
aceita motorista, passageiro e dois ocupantes da caçamba; avião, somente piloto.
Apenas o primeiro assento envia direção. Comandos remotos vencidos são neutralizados.

O host simula veículos e replica poses; ocupantes acompanham offsets de
assentos, sem colisão própria. Snapshots individuais são ignorados enquanto
embarcados. Morte, saída e transição liberam assentos. Não há animação específica
de sentar; as poses usam o visual existente.

`coop_door.gd` adapta `HouseDoor`: convidados pedem interação, o host valida
alcance e vida e publica tranca confiável e ângulo da folha. Réplicas ajustam
a colisão; late join recebe estado inicial da porta.

## Desconexão e escopo

Sair carregando larga o objeto; compras deixam o roster ativo sem reembolso.
O host guarda compras, vida, escudo e carga do relógio por token da instância
de sessão. Reentrar com o mesmo token durante a expedição restaura esse estado,
sem cura gratuita; ET morto reentra morto com corpo recuperável. O token não
é conta/autenticação e não persiste ao recriar a cena ou o processo. Encerrar
a sessão ou resetar a expedição apaga os registros de recuperação.

Se o host sair, convidados retornam ao painel de conexão. Não há migração de
host, matchmaking, relay ou persistência. IP direto depende de alcance de rede.
O teste de falhas injeta atraso/perda somente em snapshots de movimento;
não valida a internet nem simula perda em todo o transporte ENet.

A fazenda co-op é separada: reutiliza assets e papéis SP, mas não converte
`world.tscn`, Country Town, órbita ou todo o conteúdo SP para rede. NPCs e
veículos não têm travessia de portal implementada. Movimento do ET permanece
sob autoridade do dono e a revisão específica de raio X está pendente.
