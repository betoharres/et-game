# NPCs

Existem **duas gerações** de NPC no projeto. A atual é composta: um chassi
(`NPCActor`) + sensores + uma behavior tree Beehave compartilhada. A anterior
são scripts monolíticos da fazenda, ainda em uso em `world.tscn`. Não misture
as duas: NPC novo nasce na arquitetura composta.

## Arquitetura atual (composição + Beehave)

| Arquivo | Papel |
| --- | --- |
| `scripts/npc/npc_actor.gd` (`NPCActor`) | Chassi: navegação, movimento, patrulha, velocidades, `reaction_mode`, estado e propagação de alerta. Entra sozinho no grupo `npc_actors` |
| `scripts/npc/npc_vision.gd` (`NPCVision`) | Cone de visão, linha de visada, tempo de detecção, última posição vista |
| `scripts/npc/npc_hearing.gd` (`NPCHearing`) | Raio de audição, ruído de movimento do ET, memória de ruído, `hear_report()` de outro NPC |
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
| `Chase` | `SequenceReactive` | vê o ET **e** `reaction_mode == CHASE` → persegue |
| `Flee` | `SequenceReactive` | vê o ET **e** `reaction_mode == FLEE` → foge para o refúgio |
| `Alert` | `SequenceReactive` | está notando o ET (detecção parcial) → pose de alerta |
| `Search` | `SequenceReactive` | tem última posição vista → procura ali, depois volta à patrulha |
| `Investigate` | `SequenceReactive` | ouviu ruído → investiga a posição, depois volta à patrulha |
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

### Percepção e alerta

- `NPCVision` respeita a furtividade do ET: consulta o multiplicador de
  visibilidade do Player (vegetação, agachamento) antes de confirmar contato, e
  reporta contato de volta ao Player (`set_vision_contact`).
- Um NPC que perde o alvo guarda `last_seen_position`; o ramo `Search` usa isso.
- O alerta se propaga pelo grupo `npc_actors`: quem vê avisa os vizinhos, que
  recebem por `NPCHearing.hear_report()`.
- Ruído de movimento do ET acima de um limiar de velocidade também é ouvido.

## NPCs da geração anterior (fazenda)

Ainda vivos em `world.tscn`, com visão e navegação próprias dentro do script:

| Arquivo | Papel |
| --- | --- |
| `scripts/smelly_farmer.gd` | Fazendeiro que patrulha, persegue e atira (dano instantâneo, sem projétil) |
| `scripts/photographer.gd` | Fotógrafo: fotografa o ET e alimenta o `PhotoAlertSystem` |
| `scripts/generic_NPC.gd` (`GenericNPC`) | NPC simples de patrulha, usado dentro da nave |
| `scripts/living_light.gd` (`LivingLight`) | Criatura-luz que vagueia, se assusta e foge |
| `scripts/drone_02.gd`, `scripts/spy_cam.gd`, `scripts/spider_bot/` | Máquinas: drone de patrulha, câmera espiã e o robô de pernas com IK que ajuda na coleta |

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
5. Validação: `tools/test_farmer_npc_behavior.gd` (IA, visão, audição, rotina),
   `tools/test_npc_animation.gd` (rig e trilhas),
   `tools/test_generic_npc_navigation.gd` (NPC genérico da nave). População do
   Country Town: `tools/build_country_town_population.gd` (gera) — ver
   [country-town.md](country-town.md).
