# NPCs

Os NPCs terrestres usam `NPCActor`, sensores compartilhados e a árvore Beehave
`NPCBehaviorTree.tscn`. Isso inclui fazendeiro, fotógrafo, guarda de teste e
reforços Police/SWAT/MIB. Criaturas e máquinas com scripts próprios continuam
fora dessa composição; veja [NPCs com comportamento próprio](#npcs-com-comportamento-próprio).

## Arquitetura atual (composição + Beehave)

| Arquivo | Papel |
| --- | --- |
| `scripts/npc/npc_actor.gd` (`NPCActor`) | Chassi: navegação, movimento, patrulha, velocidades, `reaction_mode`, estado e propagação de alerta. Entra sozinho no grupo `npc_actors` |
| `scripts/npc/npc_vision.gd` (`NPCVision`) | Visibilidade do ET, cone, raycast, detecção e memória; `can_see_target()` consulta candidatos sem mudar o alvo do sensor |
| `scripts/npc/npc_hearing.gd` (`NPCHearing`) | Eventos de `PlayerNoise`, ruídos de outras fontes e relatos; memória e investigação |
| `scripts/npc/npc_navigation.gd` (`NPCNavigation`) | Localiza regiões com malha salva no mesmo `World3D` e aguarda sincronização do servidor |
| `scripts/npc/npc_routine.gd` (`NPCRoutine`) | Percorre as atividades do NPC e cuida da conversa entre vizinhos |
| `scripts/npc/npc_activity.gd` (`NPCActivity`) | `Marker3D` de parada com vagas (`slots`), duração e reserva/liberação por ocupante |
| `scripts/npc/npc_animation.gd` (`NPCAnimation`) | Idle/Walk a partir dos clipes Synty — ver [animacoes.md](animacoes.md) |
| `scenes/NPCs/Behaviors/NPCBehaviorTree.tscn` | A árvore de decisão, **compartilhada por todos os papéis** |
| `scripts/npc/behaviors/*.gd` | Uma folha por responsabilidade (condição ou ação) |

Papéis: `FarmerNPC`, `TownspersonNPC` e `PoliceNPC` (`scripts/npc/`) apenas
fixam exports no `_ready()` (modo de reação, sociabilidade, lanterna) e chamam
`super()`. Cenas: `scenes/NPCs/Farmer.tscn`, `Townsperson.tscn`,
`PoliceOfficer.tscn` — as três instanciam a mesma árvore.

### Montagem de um NPC

```text
CharacterBody3D (FarmerNPC / TownspersonNPC / PoliceNPC)
├── Character (modelo Synty) → Skeleton3D → mesh
├── CollisionShape3D
├── NavigationAgent3D
├── NPCVision, NPCHearing
├── AnimationPlayer + NPCAnimation
├── NPCRoutine (opcional; só quem tem atividades)
└── NPCBehaviorTree (instância de NPCBehaviorTree.tscn)
```

### A árvore

`Root` é um `SelectorReactive` — reavalia a prioridade a cada tick. Os ramos,
em ordem de prioridade:

| Ramo | Tipo | Condições → ação |
| --- | --- | --- |
| `EnemyAttack` | Ação | chama `attack_target()` quando o papel oferece esse método |
| `RangedAttack` | Ação | `NPCCombat` pode engajar → mira e dispara |
| `Chase` | `SequenceReactive` | vê o ET **e** `reaction_mode == CHASE` → persegue |
| `Flee` | `SequenceReactive` | vê o ET **e** `reaction_mode == FLEE` → foge para o refúgio |
| `Alert` | `SequenceReactive` | está notando o ET (detecção parcial) → pose de alerta |
| `Search` | `SequenceReactive` | tem última posição vista → procura ali, depois volta à patrulha |
| `Investigate` | `SequenceReactive` | ouviu ruído → investiga a posição, depois volta à patrulha |
| `WaitForTraffic` | Ação | aguarda o tráfego quando necessário |
| `Routine` | `Selector` | `TalkToNeighbor` → `DailyRoutine` → `Idle` → `Patrol` |

Padrões que a árvore assume:

- As folhas **só decidem e delegam**: quem move, vira e navega é o `NPCActor`
  (`move_toward_point`, `face_direction`, `stop_moving`, `set_state`).
- `DailyRoutine` é um adaptador fino: repassa o tick ao `NPCRoutine` e
  devolve `RUNNING`; o `interrupt()` da folha libera a vaga da atividade.
- `Patrol` sucede **a cada parada**, não ao fim da volta, para que o
  `Selector` de rotina reavalie a conversa entre vizinhos com frequência.
- Ramos reativos usam `SequenceReactive`/`SelectorReactive` (não `Sequence`
  puro): trocar o tipo muda quando as condições são reavaliadas e é a causa
  clássica de NPC "grudado" num comportamento.
- Toda folha que chama `move_toward_point()` devolve `FAILURE` quando
  `npc.navigation_failed` fica `true` (destino inalcançável ou NPC preso),
  em vez de `RUNNING` para sempre: `Patrol` pula para o próximo ponto,
  `Chase`/`Flee`/`Idle`/`ReturnToPatrol` liberam o `Selector` para o próximo
  ramo. `move_toward_point()` mantém a falha por 2 s depois de marcá-la,
  então a folha não tenta o mesmo destino outra vez no tick seguinte.
- No `.tscn`, cada nó da árvore é `type="Node"` + `script` do Beehave; e os
  autoloads `BeehaveGlobalMetrics`/`BeehaveGlobalDebugger` precisam continuar
  registrados em `project.godot`.

### Rotina, atividades e vagas

`NPCActivity` é um `Marker3D` com `activity`, `duration_min`/`duration_max` e
`slots` (posições relativas). `NPCRoutine` **reserva** uma vaga ao chegar e
**libera** ao sair ou ao ser interrompido, o que evita dois NPCs no mesmo lugar.
No Country Town as atividades são geradas por `tools/build_country_town_population.gd`;
dentro da casa modular elas ficam no nó `Atividades` de `House01.tscn` (cama,
sofá, cozinha, mesa de jantar, varanda) — ver [casas-interiores.md](casas-interiores.md).

### Colocação, navegação e patrulha

Instancie `SmellyFarmer.tscn`, `Photographer.tscn`, `Multiplayer/CoopGuard.tscn`
ou `Pursuit/PursuitAgent.tscn` em um nível com navegação salva. O nome da pasta
`Multiplayer` não impede o guarda de funcionar em single-player. Farmer e
fotógrafo herdam `network_npc.gd` por `network_farm_enemy.gd`: sem sessão,
simulam localmente; com sessão, usam roster e autoridade do host. Reforços
usam `PursuitNPC`, `PursuitProfile` e o adaptador `CoopSync` na campanha co-op.

- `require_navigation` é `true` por padrão. Não ocorre bake de navegação em
  runtime. A malha deve ser assada e salva no editor ou por ferramenta de autoria.
- `navigation_region_path` escolhe uma `NavigationRegion3D` explicitamente.
  Sem esse caminho, `NPCNavigation` procura regiões habilitadas com polígonos
  no mesmo `World3D`, escolhendo o mapa mais próximo com superfície a até 3 m
  da origem do NPC. Aguarda a sincronização antes de decidir que falta navegação.
- Sem região adequada, o NPC emite warning e falha nas tentativas de movimento
  que exigem navegação. `PursuitSystem/Navigation` usa a mesma descoberta e não
  permite novos reforços sem malha disponível. Seu caminho explícito é relativo
  ao nó `Navigation`. Níveis sem cobertura salva precisam de autoria no editor.
- Para patrulha, defina `patrol_markers_path` para um container com filhos diretos
  `Marker3D`, ou crie um filho `PatrolPoints` no NPC. Marcadores internos são
  convertidos em posições fixas na primeira consulta, para não seguirem o NPC.
  Containers externos são consultados em coordenadas globais. Na ausência de
  marcadores, `patrol_points` continua aceitando posições absolutas do mundo.
- O guarda traz dois marcadores locais. Sem rota, o NPC fica ocioso até reagir
  a visão ou ruído. Tipos Police/SWAT/MIB são escolhidos pelo `profile` da cena
  de reforço; o diretor configura alvo, rota inicial e mapa ao gerar uma unidade.

### Percepção e alerta

Todos esses inimigos usam `NPCVision.can_see_target()`: valida alvo vivo no
mesmo `World3D`, aplica visibilidade, cone e oclusão por raycast. A seleção
co-op consulta candidatos sem sobrescrever `vision.player` durante a busca.
O multiplicador do Player reduz tanto o alcance quanto a velocidade de
confirmação da detecção; agachamento também reduz o ângulo do cone. Visibilidade
zero impede contato visual, inclusive com o manto predador.

As áreas dos cultivos chamam `enter_concealment()` e `exit_concealment()` no ET.
Os multiplicadores atuais são `0.5` no milho, `0.35` no trigo e `0.5` nos
girassóis. O Player combina isso com seu valor de stealth e agachamento;
ao sair da área, restaura a visibilidade sem esse cultivo. O host aplica as
mesmas áreas às réplicas dos colegas.

`PlayerNoise` emite passos por movimento: agachado `22 dB` (cerca de `1.26 m`),
andando `26 dB` (`2 m`) e correndo `44 dB` (`15.85 m`). O raio é
`10^((dB - 20) / 20)` e chega aos `NPCHearing` do mesmo `World3D` pelo grupo
`npc_hearing_listeners`. O sensor usa distância horizontal, guarda a posição
ouvida e alimenta investigação. Cultivos reduzem visão, mas não abafam passos:
correr ainda denuncia o ET. Este modelo não calcula oclusão acústica por paredes.

`hear_sound()`, `hear_noise()` e `hear_report()` ignoram listeners inativos,
em remoção ou mortos quando o papel expõe `is_alive()`. A varredura por velocidade
continua para veículos e personagens sem `PlayerNoise`; o ET usa seus eventos
para evitar ruído duplicado. Relatos de outros NPCs guardam a última posição
vista, sem confirmar visão própria. Perder contato visual também alimenta
`Search` pela memória de `last_seen_position`.

### Ataques dos inimigos

| Papel | Dano e aleatoriedade |
| --- | --- |
| Fazendeiro (`SmellyFarmer`) | Dano direto após alcance e contato visual confirmado; raycast de percepção, sem teste de tiro na boca da arma e sem RNG de precisão. |
| Guarda de cápsula | Dano direto de curto alcance após contato visual e cooldown, sem RNG. |
| Fotógrafo | Não causa dano; acumula foco, fotografa e alimenta o alerta SP ou o da campanha co-op. |
| Police/SWAT/MIB | Hitscan por raycast da arma; mira, cooldown/rajadas e desvio aleatório do `PursuitProfile`. Só causa dano se o raio atingir o alvo. Tracers e lasers são visuais. |

`npc_ranged_combat.gd` aplica spread angular configurado por perfil: Police
`2.5°`, SWAT `1.8°` e MIB `1°`. O antigo `smelly_farmer.gd`, com probabilidade
de acerto e penalidades por movimento/distância/ocultamento, não está mais em uso.

## NPCs com comportamento próprio

Living light, Gorilla e máquinas não passam automaticamente a usar os sensores
dos inimigos terrestres. Na fazenda co-op, living light recebe adaptação própria;
o Gorilla fica estacionário e sua quest aceita qualquer colega. Detalhes em
[multiplayer.md](multiplayer.md#npc-da-fazenda-co-op).

| Arquivo | Papel |
| --- | --- |
| `scripts/generic_NPC.gd` (`GenericNPC`) | Patrulha simples da nave; rig `CharactersScifiCity.glb`, com variante visual `RobotNPC.tscn` |
| `scripts/living_light.gd` (`LivingLight`) | Criatura-luz que vagueia, se assusta e foge |
| `scripts/drone_02.gd`, `scripts/spy_cam.gd`, `scripts/spider_bot/` | Drone, câmera espiã e robô auxiliar de coleta |

O `CharactersScifiCity.glb` atual não traz `AnimationPlayer`; por isso o
`GenericNPC` mantém a patrulha funcional sem exigir clipes, mas sua malha fica
em pose estática até receber animações compatíveis com esse rig.

Não estenda esses scripts com comportamento novo: se um deles precisar de
decisão mais rica, migre o papel para `NPCActor` + árvore compartilhada.

## Ao alterar

1. Comportamento novo = **uma folha nova** em `scripts/npc/behaviors/` + um nó
   na árvore compartilhada. Evite `if` extra dentro de uma folha existente.
2. Capacidade nova do corpo (mover, virar, navegar) = método no `NPCActor`.
3. Papel novo = subclasse de `NPCActor` que só fixa exports, + cena em
   `scenes/NPCs/` com a árvore compartilhada instanciada.
4. Animação: o rig Synty é o único que aceita os clipes de
   `Temporarios/Animations/Polygon/` — ver [animacoes.md](animacoes.md).
5. Validação: `tools/test_enemy_placement.gd` (colocação, malha salva e isolamento),
   `tools/test_player_noise.gd` (passos e percepção dos inimigos nos três cultivos),
   `tools/test_coop_player_state.gd` (ruído e ocultamento no host/owner),
   `tools/test_pursuit_system.gd` (reforços, navegação e combate),
   `tools/test_farmer_npc_behavior.gd` (IA, visão, audição, rotina),
   `tools/test_npc_animation.gd` (rig e trilhas),
   `tools/test_generic_npc_navigation.gd` (NPC genérico da nave). População do
   Country Town: `tools/build_country_town_population.gd` (gera) — ver
   [country-town.md](country-town.md).
