# Animação e rigs

O projeto tem **dois rigs incompatíveis entre si**. Trocar clipe de um para o
outro deforma o personagem — é a armadilha mais cara desta área.

| Rig | Quem usa | Origem dos clipes |
| --- | --- | --- |
| Mixamo (49 bones, prefixo `mixamorig_`) | Player (`animations/mixamo/ET_animated.glb`) | FBX Mixamo em `animations/mixamo/`, assados por `tools/build_mixamo_character.py` |
| Synty (50 bones, em metros, `Skeleton3D` na raiz) | NPCs de `scenes/NPCs/` | Biblioteca em `Temporarios/Animations/Polygon/`, feita para `Temporarios/Animations/Meshes/PolygonSyntyCharacter.fbx` |

Os clipes Synty gravam as trilhas como `Skeleton3D:osso`: só funcionam nesse rig
específico, com o `AnimationPlayer` apontando `root_node` para a raiz do modelo.
Os `SK_Character_*` de outros pacotes e o `FarmerOld2` **não** aceitam esses
clipes.

## Player — `PlayerAnimationController`

`scripts/player_animation_controller.gd` é a **única** máquina de estados do
`AnimationTree`. `player.gd` nunca fala com o `AnimationTree` direto; envia
estado e eventos:

| Chamada | Quando |
| --- | --- |
| `set_motion_state(velocidade, no_chão, …)` | Todo frame de física |
| `trigger_turn` / `trigger_moving_turn` / `cancel_moving_turn` | Giros no lugar e giros de 180° em movimento |
| `trigger_hit` / `trigger_stumble` / `trigger_landing` | Dano, desequilíbrio e aterrissagem forte |
| `set_ragdoll_active` / `begin_get_up` / `finish_get_up` | Entrada e saída do ragdoll |
| `set_carry_mode` / `trigger_pick_up_ground` | Carregar item ou personagem |
| `hold_pose` / `play_pose` / `release_pose` | Poses de autoria (ex.: sinal de intervenção na entrega) |

Decisões que valem lembrar:

- A máquina de estados é **construída em código** (`_build_state_machine`), a
  partir do dicionário `STATE_ANIMATIONS` (estado → clipe). Adicionar um clipe
  é acrescentar uma entrada ali e ligá-la ao gatilho certo, não recriar a
  árvore no editor.
- Os clipes são **in-place**: o `CharacterBody3D` é a autoridade de
  deslocamento. Só o deslocamento vertical do pulo/queda foi preservado no
  build do GLB.
- Locomoção mistura andar/correr/agachar/strafe por velocidade e direção
  local, com variantes de idle sorteadas depois de um tempo parado.
- Para olhar e alcançar alvos, a pilha usa dois
  `LookAtModifier3D` (cabeça e torso) e um `TwoBoneIK3D` no braço direito,
  alimentado pelos alvos de `scripts/ik_target_container.gd`.
- `CharacterProportions` é um `SkeletonModifier3D` pós-animação (escala de
  bones, barriga procedural) — ver [player.md](player.md).
- `RagdollRecovery` (`scripts/ragdoll_recovery_modifier.gd`) tem de ser o
  **último** da pilha: só dentro de `_process_modification` a pose real é
  legível, e é ele que casa a pose caída com o começo do clipe de levantar.

Ordem da pilha no `Skeleton3D`: `CharacterProportions` → `Head` → `Torso` →
`HandR` → `RagdollRecovery`.

## NPCs — `NPCAnimation`

`scripts/npc/npc_animation.gd` recebe dois `PackedScene` (`idle_clip`,
`walk_clip`), abre cada um, copia a `Animation` única para uma
`AnimationLibrary` local e toca no `AnimationPlayer` do NPC. O `NPCActor`
alterna entre `Idle` e `Walk` conforme se move — não há blend tree.

Mesma técnica de `Temporarios/Animations/Meshes/testanim_animation_controller.gd`,
que serve como cena de referência.

## Ao alterar

1. Clipe novo do Player: passe pelo pipeline do Blender
   (`tools/build_mixamo_character.py`, documentado em
   `animations/mixamo/SOURCE.md`), acrescente o estado em `STATE_ANIMATIONS` e
   ligue-o a um gatilho no controlador.
2. Clipe novo de NPC: use um da biblioteca Synty e aponte o `PackedScene` no
   export do `NPCAnimation`; confira que o modelo é o rig compatível.
3. Modificador novo no `Skeleton3D`: cuide da posição na pilha e nunca deixe
   nada depois do `RagdollRecovery`.
4. Validação: `tools/test_player_animation.gd` e `tools/test_npc_animation.gd`;
   o resultado visual quem julga é o usuário, no editor.
