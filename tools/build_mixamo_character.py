"""Build one Godot-friendly GLB containing the Mixamo ET and selected actions.

Run with Blender:
    blender --background --factory-startup --python tools/build_mixamo_character.py
"""

from __future__ import annotations

import pathlib

import bpy
from mathutils import Quaternion


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT / "animations" / "mixamo"
OUTPUT_PATH = SOURCE_ROOT / "ET_animated.glb"

CLIPS = {
    "idle": "idle.fbx",
    "idle_variant_a": "idle (2).fbx",
    "idle_variant_b": "idle (3).fbx",
    "walk": "walking.fbx",
    "run": "running.fbx",
    "strafe_left_walk": "left strafe walking.fbx",
    "strafe_right_walk": "right strafe walking.fbx",
    "strafe_left_run": "left strafe.fbx",
    "strafe_right_run": "right strafe.fbx",
    "turn_left": "left turn 90.fbx",
    "turn_right": "right turn 90.fbx",
    "turn_left_wide": "left turn.fbx",
    "turn_right_wide": "right turn.fbx",
    "walk_turn_180": "Walking Turn 180.fbx",
    "run_turn_180": "Running Turn 180.fbx",
    "run_turn_right": "Running Right Turn.fbx",
    "run_stop": "run to stop.fbx",
    "jump_start": "jumping up.fbx",
    "jump": "jump.fbx",
    "fall": "falling idle.fbx",
    "land_hard": "hard landing.fbx",
    "crouch_idle": "Crouch Idle.fbx",
    "crouch_walk": "Crouched Walking.fbx",
    "crouch_left": "crouched sneaking left.fbx",
    "crouch_right": "crouched sneaking right.fbx",
    "stumble_forward": "Jogging Stumble.fbx",
    "stumble_back": "Stumble Backwards.fbx",
    "hit_front": "Getting Hit.fbx",
    "hit_side": "Hit On Side Of Body.fbx",
    "get_up_back": "Getting Up.fbx",
    "get_up_front": "Standing Up.fbx",
    "pick_up_ground": "Kneeling Down.fbx",
    "carry_walk": "Carrying.fbx",
    "carry_turn": "Carrying Turn.fbx",
    "carried_idle": "Being Carried.fbx",
    "carried_from_ground": "Being Carried_grabing_on_ground.fbx",
}

# No carrying idle was authored, so the runtime one is a single frame of the
# carrying walk held still. Source clip name and the frame to sample.
STATIC_CLIPS = {
    "carry_idle": ("carry_walk", 0.0),
}

ROOT_YAW_REMOVED_ANIMATIONS = {
    "turn_left",
    "turn_right",
    "turn_left_wide",
    "turn_right_wide",
    "walk_turn_180",
    "run_turn_180",
    "run_turn_right",
    "carry_turn",
}


def iter_action_fcurves(action: bpy.types.Action):
    """Yield curves from Blender's layered action representation."""
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                yield from channelbag.fcurves


def normalize_root_motion(action: bpy.types.Action) -> None:
    """Convert FBX centimeters and keep horizontal locomotion in place."""
    root_location_path = 'pose.bones["mixamorig:Hips"].location'
    for curve in iter_action_fcurves(action):
        if curve.data_path != root_location_path:
            continue

        for keyframe in curve.keyframe_points:
            keyframe.co.y *= 0.01
            keyframe.handle_left.y *= 0.01
            keyframe.handle_right.y *= 0.01

        # After the FBX armature conversion is baked, this Mixamo rig's root
        # channels map to Godot as X/Z horizontal and Y vertical. Keep only Y
        # so CharacterBody3D owns all movement and looping clips cannot snap
        # backward when their translated root returns to the first frame.
        if curve.array_index in (0, 2) and curve.keyframe_points:
            base_value = curve.keyframe_points[0].co.y
            for keyframe in curve.keyframe_points:
                delta_left = keyframe.handle_left.y - keyframe.co.y
                delta_right = keyframe.handle_right.y - keyframe.co.y
                keyframe.co.y = base_value
                keyframe.handle_left.y = base_value + delta_left
                keyframe.handle_right.y = base_value + delta_right


def remove_root_yaw(action: bpy.types.Action) -> None:
    """Leave authored body motion while CharacterBody3D supplies the turn."""
    rotation_path = 'pose.bones["mixamorig:Hips"].rotation_quaternion'
    curves = {
        curve.array_index: curve
        for curve in iter_action_fcurves(action)
        if curve.data_path == rotation_path
    }
    if set(curves) != {0, 1, 2, 3}:
        raise RuntimeError(f"Missing Hips quaternion curves in {action.name}")

    frames = sorted(
        {point.co.x for curve in curves.values() for point in curve.keyframe_points}
    )
    first = Quaternion(tuple(curves[index].evaluate(frames[0]) for index in range(4)))
    first.normalize()
    cleaned_by_frame: dict[float, Quaternion] = {}
    previous: Quaternion | None = None

    for frame in frames:
        current = Quaternion(tuple(curves[index].evaluate(frame) for index in range(4)))
        current.normalize()
        delta = first.inverted() @ current
        swing, _twist_angle = delta.to_swing_twist("Y")
        cleaned = first @ swing
        cleaned.normalize()
        if previous is not None and previous.dot(cleaned) < 0.0:
            cleaned.negate()
        cleaned_by_frame[frame] = cleaned
        previous = cleaned

    for channel, curve in curves.items():
        for point in curve.keyframe_points:
            value = cleaned_by_frame[point.co.x][channel]
            point.co.y = value
            point.handle_left.y = value
            point.handle_right.y = value
            point.interpolation = "LINEAR"


def freeze_action(action: bpy.types.Action, frame: float) -> None:
    """Flatten every curve onto one authored frame, leaving a still pose.

    The keyframes are kept and only their values are rewritten: removing them
    one by one reallocates the curve on each call and never finishes.
    """
    for curve in iter_action_fcurves(action):
        value = curve.evaluate(frame)
        for keyframe in curve.keyframe_points:
            keyframe.co.y = value
            keyframe.handle_left.y = value
            keyframe.handle_right.y = value


def import_fbx(path: pathlib.Path) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    result = bpy.ops.import_scene.fbx(filepath=str(path))
    if "FINISHED" not in result:
        raise RuntimeError(f"Could not import {path}")
    return [obj for obj in bpy.data.objects if obj not in before]


def find_armature(objects: list[bpy.types.Object]) -> bpy.types.Object:
    armatures = [obj for obj in objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError(f"Expected one armature, found {len(armatures)}")
    return armatures[0]


def remove_objects(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)

    base_objects = import_fbx(SOURCE_ROOT / "ET_para_mixamo.fbx")
    base_armature = find_armature(base_objects)
    base_armature.name = "ETArmature"
    base_armature.data.name = "ETSkeleton"

    meshes = [obj for obj in base_objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one ET mesh, found {len(meshes)}")
    meshes[0].name = "ET"

    # FBX stores centimeters and a +90 degree X conversion on the armature
    # object. Bake both into the rig before exporting GLB so Godot receives an
    # identity armature transform and physics/IK can keep using meter units.
    bpy.ops.object.select_all(action="DESELECT")
    base_armature.select_set(True)
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = base_armature
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    if base_armature.animation_data is None:
        base_armature.animation_data_create()
    base_armature.animation_data.action = None
    base_bone_names = {bone.name for bone in base_armature.data.bones}

    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    for animation_name, file_name in CLIPS.items():
        imported_objects = import_fbx(SOURCE_ROOT / file_name)
        source_armature = find_armature(imported_objects)
        source_bone_names = {bone.name for bone in source_armature.data.bones}
        if source_bone_names != base_bone_names:
            missing = sorted(base_bone_names - source_bone_names)
            unexpected = sorted(source_bone_names - base_bone_names)
            raise RuntimeError(
                f"Incompatible rig in {file_name}: "
                f"missing={missing}, unexpected={unexpected}"
            )
        source_data = source_armature.animation_data
        if source_data is None or source_data.action is None:
            raise RuntimeError(f"No action found in {file_name}")

        source_action = source_data.action
        action = source_action.copy()
        action.name = animation_name
        action.use_fake_user = True
        normalize_root_motion(action)
        if animation_name in ROOT_YAW_REMOVED_ANIMATIONS:
            remove_root_yaw(action)

        # Assign once so Blender 4.4+/5.x binds the action slot to the target
        # armature. The data paths are compatible because every clip came from
        # the same Mixamo auto-rig.
        base_armature.animation_data.action = action
        base_armature.animation_data.action = None
        remove_objects(imported_objects)
        if source_action.name in bpy.data.actions:
            bpy.data.actions.remove(source_action)

    for animation_name, (source_name, frame) in STATIC_CLIPS.items():
        source_action = bpy.data.actions.get(source_name)
        if source_action is None:
            raise RuntimeError(
                f"Missing source action {source_name} for {animation_name}"
            )
        action = source_action.copy()
        action.name = animation_name
        action.use_fake_user = True
        freeze_action(action, frame)
        base_armature.animation_data.action = action
        base_armature.animation_data.action = None

    allowed_objects = {base_armature, *meshes}
    for obj in list(bpy.data.objects):
        if obj not in allowed_objects:
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in allowed_objects:
        obj.select_set(True)
    base_armature.select_set(True)
    bpy.context.view_layer.objects.active = base_armature

    result = bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_PATH),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_skins=True,
        export_morph=False,
        export_lights=False,
        export_cameras=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"Could not export {OUTPUT_PATH}")

    print(
        "BUILT|%s|bones=%d|animations=%d" % (
            OUTPUT_PATH,
            len(base_armature.data.bones),
            len(CLIPS) + len(STATIC_CLIPS),
        )
    )


if __name__ == "__main__":
    main()
