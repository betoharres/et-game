# Player (o ET)

O jogador é `scenes/Player.tscn`, um `CharacterBody3D` autocontido: câmera,
rig, HUD, ragdoll e sensores viajam junto com ele. Mapas e cenas de teste
apenas instanciam essa cena — hoje `world.tscn`, `CountryTown.tscn`,
`HouseTest.tscn`, `Orbit.tscn`, `interior_space_ship_room_1.tscn` e
`Mat_test.tscn`.

## Arquivos

| Arquivo | Papel |
| --- | --- |
| `scenes/Player.tscn` | Montagem completa do ET |
| `scripts/player.gd` | Input, física, sobrevivência, equilíbrio, interação; é a autoridade de deslocamento |
| `scripts/player_animation_controller.gd` | Única máquina de estados do `AnimationTree` — ver [animacoes.md](animacoes.md) |
| `scripts/cinematic_camera_rig.gd` | Câmera de ombro, resposta orgânica, shake, colisão, FOV, binóculos/XRAY |
| `scripts/player_ragdoll.gd` | Constrói e destrói os `PhysicalBone3D` do ragdoll |
| `scripts/ragdoll_recovery_modifier.gd` | `SkeletonModifier3D` final: casa a pose caída com o início do clipe de levantar |
| `scripts/character_proportions.gd` | `SkeletonModifier3D` de proporções, barriga procedural e shaders de pele/olhos |
| `scripts/character_appearance.gd` | Autoload com o perfil salvo (`user://character_appearance.cfg`) |
| `scripts/energy_pool.gd` | Reserva de energia genérica com drenos nomeados |
| `scripts/ik_target_container.gd` | Alvos de mão/cotovelo do `TwoBoneIK3D` (poses de carregar e de sinalizar) |
| `scripts/audio/footstep_audio.gd` | Passos por tipo de superfície |
| `scripts/player_hud.gd` / `scenes/PlayerHUD.tscn` | Vida, stamina, energia e feedback de dano |

## Estrutura da cena

```text
CharacterBody3D (player.gd)
├── FootstepAudio
├── PlayerHUD
├── ET (ET_animated.glb) → ETArmature/Skeleton3D
│   ├── ET (MeshInstance3D) + FarSightGoggles
│   ├── CharacterProportions (SkeletonModifier3D)
│   ├── Head / Torso (LookAtModifier3D)
│   ├── HandR (TwoBoneIK3D)
│   ├── EyeLightAttachment (BoneAttachment3D) → EyeAreaLight (SpotLight3D)
│   └── RagdollRecovery (SkeletonModifier3D, último da pilha)
├── AnimationTree
├── EnergyPool, PlayerRagdoll, IKtargetContainer (HandR, ElbowR), CarrySocket
├── CollisionShape3D
├── CameraHolder (CinematicCameraRig) → PitchPivot → ShoulderOffset → SpringArm3D
│                                        → Camera3D (+HeadTarget) e XRAYCamera
├── InteractionArea (Area3D)
└── PlayerAnimationController
```

## Responsabilidades e limites

- **`player.gd` decide, `PlayerAnimationController` mostra.** O script do
  jogador nunca fala com o `AnimationTree` direto: passa estado
  (`set_motion_state`, `trigger_hit`, `trigger_stumble`, `trigger_landing`,
  `set_carry_mode`, `begin_get_up`…). O `CharacterBody3D` é a única autoridade
  de deslocamento; os clipes são in-place.
- **Step-up** de degraus é do próprio controlador de movimento
  (`max_step_height`), não da animação.
- **Sobrevivência**: vida, stamina e equilíbrio. Colidir correndo ou cair
  derruba o equilíbrio; passado o limite vem tropeço e, no extremo, ragdoll do
  qual o ET se levanta sozinho. Sinais: `health_changed`, `stamina_changed`,
  `energy_changed`, `stealth_alert_changed`, `died`.
- **Energia**: `EnergyPool` atende qualquer consumidor por chave de dreno; hoje
  o consumidor é a luz dos olhos (`eye_light`). Enquanto há dreno ativo a
  recarga fica suspensa; ao zerar, `depleted` manda os consumidores desligarem.
- **Furtividade**: `enter_concealment()` / `exit_concealment()` recebem áreas de
  vegetação (grupo `concealment_areas`) e reduzem `get_visibility_multiplier()`,
  que os sensores de NPC consultam. `set_vision_contact()` é como um sensor
  avisa que está vendo o ET; alimenta `get_stealth_alert()`.
- **Carregar**: itens do grupo `pickup_items` vão para o `CarrySocket`
  (`try_pickup`); personagens do grupo `carriable_characters` são levados no
  colo (`try_carry_character` / `release_carried_character`), aplicando
  `apply_carry()` no carregado.
- **Aparência**: o perfil vem do autoload `CharacterAppearance` e é aplicado por
  `CharacterProportions` — escala de bones num `SkeletonModifier3D`
  pós-animação, barriga procedural presa ao bone e shaders de pele e olhos
  (não há Blend Shapes no GLB). `get_appearance_replication_payload()` e o RPC
  `sync_appearance()` existem para uma futura camada multiplayer, que **não**
  deve ser construída sem pedido explícito.
- **Câmera**: `CinematicCameraRig` cuida de enquadramento, colisão, shake e do
  modo primeira pessoa (`set_first_person`), além dos binóculos com zoom e do
  material XRAY (a câmera secundária mostra o que a camada 6 esconde).
- **Modos de depuração**: `set_debug_god_mode_enabled()` e
  `set_debug_flight_enabled()` são acionados pelo ciclo do `F4`
  (`DebugMenus`); o Player entra no grupo `debug_player` para ser encontrado.

## Ao alterar

1. Movimento, física e estados visuais andam juntos: mudar um pede olhar o
   outro (`player.gd` ↔ `player_animation_controller.gd`).
2. Mexer no rig, nos bones ou na pilha de modificadores exige ler
   [animacoes.md](animacoes.md) — a ordem dos `SkeletonModifier3D` importa e o
   `RagdollRecovery` tem de continuar sendo o último.
3. Nova tecla: registre a ação no Input Map e no menu de rebind
   (ver [ui-e-menus.md](ui-e-menus.md)).
4. Novo consumo de energia: registre um dreno com chave própria no
   `EnergyPool`, não crie outra reserva.
5. Validação (`tools/VALIDACAO.md`): `test_player_animation.gd`,
   `test_player_jump_stamina.gd`, `test_player_steps.gd`,
   `test_player_reversal.gd`, `test_player_ragdoll.gd`,
   `test_player_debug_modes.gd`, `test_cinematic_camera.gd`.
