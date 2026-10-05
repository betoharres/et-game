"""Build Godot resources and a mesh/slot lookup from the purchased Synty lists.

Run with Python from any directory. Existing resources are backed up once under
build/polygon_materials_before; UIDs and authored scalar settings are retained.
The JSON catalog resolves equivalent materials to one canonical resource without
deleting pre-existing paths that scenes or import settings might already use.
"""

from pathlib import Path
import hashlib
import json
import re


ROOT = Path(__file__).resolve().parents[1]
PACKS = (
    "POLYGON_Generic_SourceFiles_v3",
    "POLYGON_NatureBiomes_AlpineMountain_SourceFiles_v3",
    "POLYGON_NatureBiomes_MeadowForest_SourceFiles_v3",
)
ALIASES = {
    "Circle_01.png": "Generic_Circle_01.png",
    "IceWall_01 copy.png": "IceWall_01.png",
}
ISSUES: list[dict[str, str]] = []
TEXTURES: list[Path] = []
CHANGED: list[str] = []
PRESERVED_SHADERS = {
    "Generic_Triplanar_Grass_01", "MossRock_Triplanar", "Snow_Rock_Tri",
    "Snow_Rock_Tri_Background", "Triplanar_Glacier_01", "Triplanar_Ice_01",
    "Triplanar_Snow_02", "Rock_Grass_Triplanar_Meadow_01", "Tree_Mat_03",
}
ALPINE_SURFACES = {
    "Dirt_Texture_01.png": "Dirt_Normals_01.png",
    "Grass_Texture_01.png": "Grass_Normals_01.png",
    "Grass_Texture_02.png": None,
    "Ice_Texture_01.png": "Ice_Normals_01.png",
    "Ice_Texture_02.png": "Ice_Normals_02.png",
    "Ice_Texture_03.png": "Ice_Normals_02.png",
    "IceSheet_Texture_01.png": "IceSheet_Normals.png",
    "IceSheet_Texture_02.png": None,
    "IceWall.png": "IceWall_Normals.png",
    "IceWall_01.png": "IceWall_Normals_01.png",
    "LakeFrozen.png": "LakeNormal.png",
    "LakeFrozenBLUE.png": "LakeNormal.png",
    "Moss_Red_Texture_01.png": "Moss_Normals_01.png",
    "Moss_Rock_Red_Texture_01.png": "Moss_Rock_Normals_01.png",
    "Mud_Texture_01.png": "Mud_Normals_01.png",
    "RiverRocks1_Texture.png": None,
    "RiverRocks2_Texture.png": "RiverRocks2_normals.png",
    "RiverRocks3_Texture.png": None,
    "RiverRocks4_Texture.png": "RiverRocks4_normals.png",
    "Rock_Alpine_Light.png": "Rock_Normals_01.png",
    "Rock_Rough_Moss_Red_Texture_01.png": "Rock_Rough_Moss_Normals_01.png",
    "Rock_Texture_01.png": "Rock_Normals_01.png",
    "Snow_01.png": "Snow_01_Normals.png",
    "Snow_02.png": None,
    "Snowcliff_baseTexBaked.png": "Snowcliff_normals.png",
    "Snowcliff_Texture.png": "Snowcliff_Normals_01.png",
}


def uri(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def texture(pack: str, name: str) -> Path | None:
    candidates = [p for p in TEXTURES if p.name.casefold() == name.casefold()]
    local = [p for p in candidates if p.relative_to(ROOT).parts[0] == pack]
    candidates = local or candidates
    if not candidates and name in ALIASES:
        ISSUES.append({"pack": pack, "texture": name, "substitute": ALIASES[name]})
        return texture(pack, ALIASES[name])
    if not candidates:
        issue = {"pack": pack, "texture": name, "status": "missing"}
        if issue not in ISSUES:
            ISSUES.append(issue)
        return None
    if len({digest(p) for p in candidates}) > 1:
        raise ValueError(f"Ambiguous texture {pack}/{name}: {candidates}")
    return sorted(candidates)[0]


def parse(pack: str) -> tuple[dict, list]:
    slots: dict[str, dict[str, str]] = {}
    meshes: list[dict] = []
    for source in sorted((ROOT / pack).glob("MaterialList*.txt")):
        slot = ""
        for line in source.read_text(encoding="utf-8-sig").splitlines():
            clean = line.strip()
            if clean.startswith("Prefab Name: "):
                prefab = clean.removeprefix("Prefab Name: ")
            elif clean.startswith("Mesh Name: "):
                mesh = {"source": uri(source), "prefab": prefab,
                        "mesh": clean.removeprefix("Mesh Name: "), "slots": []}
                meshes.append(mesh)
            elif clean.startswith("Slot: "):
                slot = clean.removeprefix("Slot: ")
                mesh["slots"].append(slot)
                slots.setdefault(slot, {})
            else:
                match = re.fullmatch(r"[^:]+: (.+) \((_[^)]+)\)", clean)
                if match:
                    name, parameter = match.groups()
                    previous = slots[slot].get(parameter, name)
                    if previous != name:
                        raise ValueError(f"Conflicting textures for {pack}/{slot}/{parameter}")
                    slots[slot][parameter] = name
    return slots, meshes


def write_material(path: Path, kind: str, props: dict[str, str | Path], name: str) -> str:
    # Previously authored shaders and baked LOD cards retain their exact setup.
    if path.exists() and (name in PRESERVED_SHADERS or name.startswith("Card_") or name.endswith("_Card")):
        return "preserved:" + uri(path)
    old = path.read_text(encoding="utf-8") if path.exists() else ""
    uid_match = re.search(r'\buid="([^"]+)"', old.splitlines()[0]) if old else None
    uid = f' uid="{uid_match[1]}"' if uid_match else ""
    # Texture bindings and shader implementations belong to this recipe;
    # non-texture settings authored in the editor continue to take precedence.
    previous = old.rpartition("[resource]")[2]
    for match in re.finditer(r"^([^\n=]+) = (.+)$", previous, re.MULTILINE):
        key, value = match[1].strip(), match[2].strip()
        if key in ("shader", "resource_name") or "Resource(" in value:
            continue
        if key.startswith("metadata/"):
            continue
        if key in props and not isinstance(props[key], Path):
            # Placeholder flags (transparency, culling, enable maps) are corrected.
            if key not in {"transparency", "cull_mode", "normal_enabled", "emission_enabled"}:
                props[key] = value
        elif key.startswith("shader_parameter/"):
            if kind == "ShaderMaterial" and key.rsplit("/", 1)[1] in {
                "albedo_a", "albedo_b", "blend_threshold", "uv1_scale", "uv1_offset",
                "_Angle", "_Transition", "triplanar_scale", "triplanar_offset",
            }:
                props[key] = value
        elif kind == "StandardMaterial3D":
            props.setdefault(key, value)
    refs: dict[Path, str] = {}
    lines = [f'[gd_resource type="{kind}" format=3{uid}]', ""]
    for value in props.values():
        if isinstance(value, Path) and value not in refs:
            ref = str(len(refs) + 1)
            refs[value] = ref
            rtype = "Shader" if value.suffix == ".gdshader" else "Texture2D"
            lines.append(f'[ext_resource type="{rtype}" path="{uri(value)}" id="{ref}"]')
    lines.extend(["", "[resource]", f'resource_name = {json.dumps(name)}'])
    for key, value in props.items():
        if isinstance(value, Path):
            value = f'ExtResource("{refs[value]}")'
        lines.append(f"{key} = {value}")
    content = "\n".join(lines) + "\n"
    if old != content:
        if old:
            backup = ROOT / "build/polygon_materials_before" / path.relative_to(ROOT)
            if not backup.exists():
                backup.parent.mkdir(parents=True, exist_ok=True)
                backup.write_text(old, encoding="utf-8")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")
        CHANGED.append(uri(path))
    signature = {key: uri(value) if isinstance(value, Path) else value for key, value in props.items()}
    # Identical copies of Core textures in different packs share materials.
    for key, value in props.items():
        if isinstance(value, Path) and value.suffix != ".gdshader":
            signature[key] = digest(value)
    return json.dumps([kind, signature], sort_keys=True)


def build(pack: str, name: str, maps: dict[str, str]) -> tuple[Path, str]:
    bound = {key: texture(pack, value) for key, value in maps.items()}
    props: dict[str, str | Path] = {}
    kind = "StandardMaterial3D"
    if "_Triplanar_Texture_Top" in maps or "_Top_Albedo" in maps:
        kind = "ShaderMaterial"
        props["shader"] = ROOT / "shaders/synty_triplanar.gdshader"
        top = bound.get("_Triplanar_Texture_Top", bound.get("_Top_Albedo"))
        side = bound.get("_Triplanar_Texture_Side", bound.get("_Base_Albedo")) or top
        bottom = bound.get("_Triplanar_Texture_Bottom") or side
        top_n = bound.get("_Triplanar_Normal_Texture_Top", bound.get("_Top_Normal"))
        side_n = bound.get("_Triplanar_Normal_Texture_Side", bound.get("_Base_Normal")) or top_n
        bottom_n = bound.get("_Triplanar_Normal_Texture_Bottom") or side_n
        for key, value in {"_MainTex": top, "_AngledTex": side, "bottom_texture": bottom,
                           "_MainNormalTex": top_n, "_AngledNormalTex": side_n,
                           "bottom_normal": bottom_n}.items():
            if value:
                props["shader_parameter/" + key] = value
        props.update({"shader_parameter/_Angle": "45.0", "shader_parameter/_Transition": "0.2"})
    elif bound.get("_Leaf_Texture") and bound.get("_Trunk_Texture") != bound.get("_Leaf_Texture") and bound.get("_Trunk_Texture"):
        kind = "ShaderMaterial"
        props["shader"] = ROOT / "shaders/synty_vertex_split.gdshader"
        props["shader_parameter/texture_albedo_a"] = bound["_Leaf_Texture"]
        props["shader_parameter/texture_albedo_b"] = bound["_Trunk_Texture"]
        for source, target in (("_Leaf_Normal", "leaf_normal"), ("_Trunk_Normal", "trunk_normal")):
            if bound.get(source):
                props["shader_parameter/" + target] = bound[source]
                props["shader_parameter/" + target + "_enabled"] = "true"
    elif "_Scrolling_Texture" in maps or name == "Waterflow_01":
        kind = "ShaderMaterial"
        props["shader"] = ROOT / "shaders/synty_source_water.gdshader"
        fallback = texture(pack, "Noise_Small.png")
        for source, target in (("_Normal_Texture", "normal_texture"), ("_Scrolling_Texture", "scrolling_texture"),
                               ("_Noise_Texture", "noise_texture"), ("_Shore_Foam_Noise_Texture", "foam_texture")):
            value = bound.get(source) or bound.get("_Overlay_Texture") or fallback
            if value:
                props["shader_parameter/" + target] = value
        if name == "Water_Ice_Lake":
            props["shader_parameter/flow"] = "Vector2(0, 0)"
            props["shader_parameter/water_color"] = "Color(0.4, 0.65, 0.8, 0.9)"
        if name == "Waterflow_01":
            props["shader_parameter/flow"] = "Vector2(0, -0.25)"
            if bound.get("_Overlay_Texture"):
                props["shader_parameter/opacity_texture"] = bound["_Overlay_Texture"]
                props["shader_parameter/opacity_enabled"] = "true"
    else:
        albedo = bound.get("_Albedo_Map") or bound.get("_Leaf_Texture")
        normal = bound.get("_Normal_Map") or bound.get("_Leaf_Normal")
        emission = bound.get("_Emission_Map") or bound.get("_Emissive_Mask")
        if albedo:
            props["albedo_texture"] = albedo
        if normal:
            props.update(normal_enabled="true", normal_texture=normal)
        if emission:
            props.update(emission_enabled="true", emission="Color(1, 1, 1, 1)", emission_texture=emission)
        props["roughness"] = "1.0"
        if "_Leaf_Texture" in maps or name in {"Generic_Ivy", "Generic_Leaf", "Mat_Lillies_01", "Circle_Cutout_Mat"}:
            props.update(transparency="2", alpha_scissor_threshold="0.5", cull_mode="2")
        if any(word in name for word in ("Circle_", "Glow", "Lightray", "Sun_Beam", "Wind_Streak", "Fog", "Cloud", "Ember", "FireFrames")) and name != "Circle_Cutout_Mat":
            props.update(transparency="1", cull_mode="2", shading_mode="0")
        if "Additive" in name or "Glow" in name or "Ember" in name or "FireFrames" in name:
            props["blend_mode"] = "1"
        if "Multiply" in name:
            props["blend_mode"] = "3"
        if "FireFrames" in name:
            # The purchased source directory contains no fire atlas.
            props["albedo_texture"] = texture(pack, "Generic_Circle_Soft_01.png")
            props["albedo_color"] = "Color(1, 0.25, 0.03, 0.7)"
        if "Glass" in name:
            props["roughness"] = "0.1"
            props["albedo_color"] = "Color(0.65, 0.85, 0.95, 1)" if "Opaque" in name else "Color(0.65, 0.85, 0.95, 0.25)"
            if "Opaque" not in name:
                props["transparency"] = "1"
        if "Water" in name:
            props.update(transparency="1", roughness="0.2", albedo_color="Color(0.2, 0.55, 0.65, 0.7)")
        if "Sky" in name:
            props.update(shading_mode="0", cull_mode="2")
    path = ROOT / pack / "Materials" / (name + ".tres")
    return path, write_material(path, kind, props, name)


def main() -> None:
    for pack in PACKS:
        TEXTURES.extend(p for p in (ROOT / pack / "Textures").rglob("*") if p.suffix.lower() in {".png", ".tga"})
    catalog: dict = {
        "packs": {}, "terrain": {}, "variants": {}, "issues": ISSUES,
        "limitations": [
            "Materials are not automatically assigned to imported FBX meshes.",
            "Existing material paths remain available; use catalog paths to share equivalent resources.",
            "Source lists omit Unity shader values, colors, wind settings and particle animation settings.",
            "Missing fire atlases use a soft orange circle without flipbook animation.",
            "Missing water scrolling texture uses Noise_Small.png; caustics and glacier refraction are unavailable.",
            "Textureless cloud, mountain and sky slots retain neutral defaults pending art direction.",
        ],
    }
    canonical: dict[str, str] = {}
    for pack in PACKS:
        slots, meshes = parse(pack)
        mapping = {}
        for name, maps in slots.items():
            path, signature = build(pack, name, maps)
            mapping[name] = canonical.setdefault(signature, uri(path))
        for mesh in meshes:
            mesh["materials"] = [mapping[name] for name in mesh["slots"]]
        catalog["packs"][pack] = {"slots": mapping, "meshes": meshes}
        if pack == PACKS[0]:
            variants = {}
            for albedo in sorted((ROOT / pack / "Textures/Alts").glob("Generic_*.png")):
                name = albedo.stem
                if name in mapping:
                    variants[name] = mapping[name]
                    continue
                maps = {"_Albedo_Map": albedo.name, "_Normal_Map": "Generic_Normals_01.png"}
                emission = ROOT / pack / "Textures/Emissive" / albedo.name.replace("Generic_", "Generic_Emissive_", 1)
                if emission.exists():
                    maps["_Emission_Map"] = emission.name
                path, signature = build(pack, name, maps)
                variants[name] = canonical.setdefault(signature, uri(path))
            path, signature = build(pack, "Generic_Water_Alt", {
                "_Albedo_Map": "Generic_Water_Texture.png", "_Normal_Map": "Generic_Water.png",
            })
            variants["Generic_Water_Alt"] = canonical.setdefault(signature, uri(path))
            catalog["variants"][pack] = variants
        terrain = {}
        for albedo in sorted((ROOT / pack / "Textures").rglob("*.png")):
            if pack == PACKS[0] and albedo.name in {"Generic_Carpet.png", "Generic_Dirt.png", "Generic_Grass.png"}:
                normal = albedo.with_name("Generic_Grass_Normals.png") if albedo.name == "Generic_Grass.png" else None
            elif pack == PACKS[1] and albedo.parent == ROOT / pack / "Textures" and albedo.name in ALPINE_SURFACES:
                normal_name = ALPINE_SURFACES[albedo.name]
                normal = albedo.with_name(normal_name) if normal_name else None
            elif "Terrain" in albedo.parts and "_Texture_" in albedo.name:
                normal_name = albedo.name.replace("_Texture_", "_Normals_")
                normal = albedo.with_name(normal_name)
                if not normal.exists() and albedo.name.startswith("Grass_"):
                    normal = albedo.with_name(normal_name.replace("Grass_", "Ground_", 1))
                if not normal.exists() and "_Red_" in albedo.name:
                    normal = albedo.with_name(normal_name.replace("_Red_", "_"))
                if not normal.exists() and albedo.name == "Rock_Moss_Texture_01.png":
                    normal = albedo.with_name("Rock_Moss_Normals.png")
            elif albedo.name.endswith("_basecolor.png"):
                normal = albedo.with_name(albedo.name.replace("_basecolor.png", "_normal.png"))
            else:
                continue
            props = {"albedo_texture": albedo, "roughness": "1.0"}
            if normal and normal.exists():
                props.update(normal_enabled="true", normal_texture=normal)
            path = ROOT / pack / "Materials/Terrain" / (albedo.stem + ".tres")
            signature = write_material(path, "StandardMaterial3D", props, albedo.stem)
            terrain[albedo.stem] = canonical.setdefault(signature, uri(path))
        catalog["terrain"][pack] = terrain
    target = ROOT / "POLYGON_Generic_SourceFiles_v3/Materials/material_catalog.json"
    target.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    print(f"{sum(len(p['slots']) for p in catalog['packs'].values())} slots; {len(canonical)} canonical materials; {len(CHANGED)} resources written")
    print(f"{len(ISSUES)} texture issues/substitutions recorded in {uri(target)}")


if __name__ == "__main__":
    main()
