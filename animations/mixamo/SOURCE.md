# Mixamo player animations

The FBX files in this directory were supplied by the project owner from
Mixamo. No separate license file accompanied them; confirm the account and
redistribution terms before distributing the raw source assets.

`ET_para_mixamo.fbx` is the ET mesh already bound to the common 49-bone
`mixamorig:` hierarchy. `ET_animated.glb` is the runtime asset generated from
that mesh and the selected clips with:

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python tools/build_mixamo_character.py
```

The build script keeps one mesh and one visual Skeleton, normalizes the FBX
armature transform, converts hip translation from centimeters to meters, and
removes horizontal root displacement so `CharacterBody3D` remains authoritative
for movement. Vertical motion authored in the jump and landing clips is kept.

## Runtime mapping

| Runtime animation | Source FBX | Use |
| --- | --- | --- |
| `idle` | `idle.fbx` | Main idle loop |
| `idle_variant_a` | `idle (2).fbx` | Random idle variation |
| `idle_variant_b` | `idle (3).fbx` | Random idle variation |
| `walk` | `walking.fbx` | Forward locomotion |
| `run` | `running.fbx` | Sprint locomotion |
| `strafe_left_walk` | `left strafe walking.fbx` | Walking left |
| `strafe_right_walk` | `right strafe walking.fbx` | Walking right |
| `strafe_left_run` | `left strafe.fbx` | Running left |
| `strafe_right_run` | `right strafe.fbx` | Running right |
| `turn_left` | `left turn 90.fbx` | Small left turn |
| `turn_right` | `right turn 90.fbx` | Small right turn |
| `turn_left_wide` | `left turn.fbx` | Wide left turn |
| `turn_right_wide` | `right turn.fbx` | Wide right turn |
| `walk_turn_180` | `Walking Turn 180.fbx` | Walking reversal pivot |
| `run_turn_180` | `Running Turn 180.fbx` | Running reversal pivot |
| `run_turn_right` | `Running Right Turn.fbx` | Sharp running right turn |
| `run_stop` | `run to stop.fbx` | Abrupt sprint stop |
| `jump_start` | `jumping up.fbx` | Jump anticipation/takeoff |
| `jump` | `jump.fbx` | Ascending phase |
| `fall` | `falling idle.fbx` | Airborne descending loop |
| `land_hard` | `hard landing.fbx` | Significant non-ragdoll landing |
| `crouch_idle` | `Crouch Idle.fbx` | Stationary crouched loop |
| `crouch_walk` | `Crouched Walking.fbx` | Forward crouched locomotion |
| `crouch_left` | `crouched sneaking left.fbx` | Crouched lateral movement |
| `crouch_right` | `crouched sneaking right.fbx` | Crouched lateral movement |
| `stumble_forward` | `Jogging Stumble.fbx` | Forward stumble reaction |
| `stumble_back` | `Stumble Backwards.fbx` | Backward stumble reaction |
| `hit_front` | `Getting Hit.fbx` | Frontal hit reaction |
| `hit_side` | `Hit On Side Of Body.fbx` | Side hit reaction |
| `get_up_back` | `Getting Up.fbx` | Get up from a face-up/back fall |
| `get_up_front` | `Standing Up.fbx` | Get up from a face-down/front fall |
| `pick_up_ground` | `Kneeling Down.fbx` | Crouch down and lift from the floor |
| `carry_walk` | `Carrying.fbx` | Walking while carrying in both arms |
| `carry_idle` | `Carrying.fbx` (frame 0, held) | Standing still while carrying |
| `carry_turn` | `Carrying Turn.fbx` | Turning in place while carrying |
| `carried_from_ground` | `Being Carried_grabing_on_ground.fbx` | Frame 0 only: the downed pose held on the ship floor |

`carried_idle` (`Being Carried.fbx`) is still built into the GLB but nothing
plays it: a carried ET is a ragdoll pinned to the carrier's `CarrySocket`, so
the body hangs limp instead of running an authored clip.

`carry_idle` has no clip of its own: the build script freezes the first
frame of `carry_walk` into a short looping action, because no carrying idle
was supplied. Replacing it later only takes adding the real FBX to `CLIPS`
and dropping the entry from `STATIC_CLIPS`.

The complete source inventory also contained the following seven cover/roll
clips, which were inspected but deliberately not copied into the project
because no current Player state uses them:

- `cover to stand.fbx`
- `cover to stand (2).fbx`
- `stand to cover.fbx`
- `stand to cover (2).fbx`
- `left cover sneak.fbx`
- `right cover sneak.fbx`
- `falling to roll.fbx`

`Pick Fruit_ground.fbx` and `Pick Fruit_one_many_ground.fbx` are also present
but unused: they read as picking a plant, so `Kneeling Down.fbx` drives the
floor lift instead.
