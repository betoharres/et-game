"""Render selected Polygon Prototype OBJ meshes as transparent HUD icons.

This is an authoring utility, not a runtime dependency. It uses only NumPy and
Pillow and keeps the shipped HUD lightweight by baking the low-poly meshes into
regular PNG textures.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


@dataclass(frozen=True)
class IconSpec:
	output_name: str
	mesh_name: str
	view_axis: str = "z"
	rotation_degrees: int = 0


ICON_SPECS = (
	IconSpec("arrow", "SM_Icon_Arrow_Small_01"),
	IconSpec("arrow_long", "SM_Icon_Arrow_Long_01", "y"),
	IconSpec("audio", "SM_Icon_Audio_01"),
	IconSpec("camera", "SM_Icon_Camera_01", "x"),
	IconSpec("circle", "SM_Icon_Circle_01"),
	IconSpec("controller", "SM_Icon_Controller_01"),
	IconSpec("gauge", "SM_Icon_Guage_01"),
	IconSpec("heart", "SM_Icon_Heart_01"),
	IconSpec("home", "SM_Icon_Home_01"),
	IconSpec("player", "SM_Icon_Player_01"),
	IconSpec("power", "SM_Icon_Power_01"),
	IconSpec("selection_ring", "SM_Icon_SelectionRing_01", "y"),
	IconSpec("glow_ring", "SM_FX_Glow_Ring_01", "y"),
	IconSpec("star_filled", "SM_Icon_Star_01"),
	IconSpec("star_empty", "SM_Icon_Star_02"),
	IconSpec("switch_button", "SM_Switch_Button_01", "y"),
	IconSpec("tick", "SM_Icon_Tick_01"),
	IconSpec("warning", "SM_Icon_Warning_01"),
	IconSpec("watch", "SM_Icon_Watch_01"),
)


def parse_obj(path: Path) -> tuple[np.ndarray, list[list[int]]]:
	vertices: list[tuple[float, float, float]] = []
	faces: list[list[int]] = []

	for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
		line = raw_line.strip()
		if line.startswith("v "):
			parts = line.split()
			vertices.append(tuple(float(value) for value in parts[1:4]))
		elif line.startswith("f "):
			indices: list[int] = []
			for token in line.split()[1:]:
				index = int(token.split("/", maxsplit=1)[0])
				indices.append(index - 1 if index > 0 else len(vertices) + index)
			if len(indices) >= 3:
				faces.append(indices)

	if not vertices or not faces:
		raise ValueError(f"Mesh without usable geometry: {path}")

	return np.asarray(vertices, dtype=np.float64), faces


def project_vertices(
	vertices: np.ndarray,
	view_axis: str,
	canvas_size: int,
	padding_ratio: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
	if view_axis == "x":
		projected = vertices[:, [2, 1]].copy()
		depth = vertices[:, 0].copy()
		view_direction = np.array([1.0, 0.0, 0.0])
	elif view_axis == "y":
		projected = vertices[:, [0, 2]].copy()
		projected[:, 1] *= -1.0
		depth = vertices[:, 1].copy()
		view_direction = np.array([0.0, 1.0, 0.0])
	else:
		projected = vertices[:, [0, 1]].copy()
		depth = vertices[:, 2].copy()
		view_direction = np.array([0.0, 0.0, 1.0])

	projected[:, 1] *= -1.0
	minimum = projected.min(axis=0)
	maximum = projected.max(axis=0)
	extent = np.maximum(maximum - minimum, 1e-6)
	usable_size = canvas_size * (1.0 - padding_ratio * 2.0)
	scale = usable_size / float(max(extent[0], extent[1]))
	projected = (projected - (minimum + maximum) * 0.5) * scale
	projected += canvas_size * 0.5
	return projected, depth, view_direction


def render_icon(
	mesh_path: Path,
	output_path: Path,
	view_axis: str,
	rotation_degrees: int,
	size: int,
) -> None:
	supersample = 4
	canvas_size = size * supersample
	vertices, faces = parse_obj(mesh_path)
	projected, depth, view_direction = project_vertices(
		vertices,
		view_axis,
		canvas_size,
		0.12,
	)

	face_data: list[tuple[float, list[tuple[float, float]], int]] = []
	light_direction = np.array([0.35, 0.7, 0.62])
	light_direction /= np.linalg.norm(light_direction)

	for face in faces:
		face_vertices = vertices[face]
		normal = np.cross(
			face_vertices[1] - face_vertices[0],
			face_vertices[2] - face_vertices[0],
		)
		normal_length = np.linalg.norm(normal)
		if normal_length <= 1e-8:
			continue
		normal /= normal_length
		front_light = abs(float(np.dot(normal, light_direction)))
		view_light = abs(float(np.dot(normal, view_direction)))
		brightness = int(150 + 72 * front_light + 33 * view_light)
		brightness = min(brightness, 255)
		points = [tuple(projected[index]) for index in face]
		face_data.append((float(depth[face].mean()), points, brightness))

	face_data.sort(key=lambda entry: entry[0])
	base = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
	draw = ImageDraw.Draw(base, "RGBA")
	for _, points, brightness in face_data:
		draw.polygon(
			points,
			fill=(brightness, brightness, brightness, 255),
			outline=(255, 255, 255, 105),
			width=max(1, supersample),
		)

	alpha = base.getchannel("A")
	glow_alpha = alpha.filter(ImageFilter.GaussianBlur(radius=3.2 * supersample))
	glow_alpha = glow_alpha.point(lambda value: int(value * 0.22))
	glow = Image.new("RGBA", base.size, (180, 242, 255, 0))
	glow.putalpha(glow_alpha)
	composited = Image.alpha_composite(glow, base)
	composited = composited.resize((size, size), Image.Resampling.LANCZOS)

	if rotation_degrees:
		composited = composited.rotate(
			rotation_degrees,
			resample=Image.Resampling.BICUBIC,
			expand=False,
		)

	output_path.parent.mkdir(parents=True, exist_ok=True)
	composited.save(output_path, optimize=True)


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument(
		"--source",
		type=Path,
		default=Path(r"C:\dev\godot_3d\assets\_SourceFiles\OBJ"),
	)
	parser.add_argument(
		"--output",
		type=Path,
		default=Path("assets/ui/prototype_icons"),
	)
	parser.add_argument("--size", type=int, default=128)
	args = parser.parse_args()

	for spec in ICON_SPECS:
		mesh_path = args.source / f"{spec.mesh_name}.obj"
		if not mesh_path.exists():
			raise FileNotFoundError(mesh_path)
		output_path = args.output / f"{spec.output_name}.png"
		render_icon(
			mesh_path,
			output_path,
			spec.view_axis,
			spec.rotation_degrees,
			args.size,
		)
		print(f"Rendered {mesh_path.name} -> {output_path}")


if __name__ == "__main__":
	main()
