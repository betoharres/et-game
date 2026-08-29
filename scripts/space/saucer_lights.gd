class_name SaucerLights
extends Node3D

## Anel de lampadas coloridas na borda da nave, no estilo dos discos voadores
## do cinema antigo: cada lampada tem sua propria cor e elas acendem em
## sequencia, de modo que a onda da a volta no casco.
##
## As lampadas sao geradas em codigo, e nao escritas na cena, porque sao doze
## posicoes em circulo: uma tabela de transformadas feita a mao ficaria ilegivel
## e teria de ser recalculada inteira a cada ajuste de raio ou de contagem.
##
## Cada lampada e um par mesh emissiva + OmniLight3D. A mesh e o que se ve (e o
## que alimenta o glow do Environment); a luz e o que derrama cor no casco em
## volta. As luzes nao projetam sombra e tem alcance curto de proposito: sao
## doze por nave, e o custo precisa ficar no orcamento de uma decoracao.
##
## O anel fica cravado na quina do disco, e nao sobre ele: as lampadas sobram
## um pouco para fora do raio do casco e um pouco abaixo da face de baixo, de
## modo que continuam visiveis para quem olha a nave do chao. Um anel apoiado
## na face de cima desapareceria por completo vista de baixo.

@export_group("Ring")
## Cores classicas de disco voador. A lista se repete ao redor do anel, entao
## uma contagem de lampadas multipla do tamanho dela fecha o circulo sem
## emendar duas cores iguais lado a lado. Nao e uma const porque Color() nao e
## uma expressao constante em GDScript.
@export var colors : PackedColorArray = PackedColorArray([
	Color(1.0, 0.16, 0.18),
	Color(1.0, 0.6, 0.12),
	Color(0.99, 0.92, 0.26),
	Color(0.22, 0.95, 0.38),
	Color(0.24, 0.6, 1.0),
	Color(0.78, 0.32, 1.0),
])
@export_range(3, 32, 1) var light_count : int = 12
@export var ring_radius : float = 9.15
@export var ring_height : float = 0.1
@export_range(0.04, 0.6, 0.01) var bulb_radius : float = 0.17

@export_group("Chase")
## Tempo que a onda leva para dar uma volta completa no anel.
@export_range(0.2, 8.0, 0.05) var cycle_duration : float = 2.2
## Fatia do anel acesa de cada vez, de 0 a 1. Valores baixos deixam um ponto
## correndo; valores altos acendem quase tudo e so pulsam.
@export_range(0.05, 0.5, 0.01) var wave_width : float = 0.2
## Brilho da lampada fora da onda. Nunca chega a zero: no cinema as lampadas
## continuam visiveis, so mudam de intensidade.
@export_range(0.0, 1.0, 0.01) var idle_level : float = 0.12

@export_group("Color Cycle")
## Tempo que a paleta leva para girar uma volta inteira ao redor do anel. E o
## que faz cada lampada trocar de cor: em vez de uma cor fixa por posicao, a
## paleta desliza pelo anel, entao a cor que estava numa lampada passa para a
## seguinte.
@export_range(0.5, 30.0, 0.1) var color_cycle_duration : float = 6.0
## 0 troca a cor de uma vez, como lampadas coloridas de verdade; 1 dissolve
## suavemente de uma cor para a proxima.
@export_range(0.0, 1.0, 0.01) var color_blend : float = 0.3

@export_group("Intensity")
@export_range(0.0, 12.0, 0.1) var light_energy : float = 2.6
@export_range(0.5, 12.0, 0.1) var light_range : float = 3.2
@export_range(0.0, 8.0, 0.1) var emission_energy : float = 4.5

var _bulb_materials : Array[StandardMaterial3D] = []
var _bulb_lights : Array[OmniLight3D] = []
var _elapsed : float = 0.0


func _ready() -> void:
	_build_ring()


func _process(delta : float) -> void:
	_elapsed += delta
	var wave : float = fposmod(_elapsed / maxf(cycle_duration, 0.01), 1.0)
	var color_phase : float = _elapsed / maxf(color_cycle_duration, 0.01)

	for index : int in range(_bulb_lights.size()):
		var level : float = _level_for(index, wave)
		var color : Color = _color_for(index, color_phase)

		var light : OmniLight3D = _bulb_lights[index]
		light.light_color = color
		light.light_energy = light_energy * level

		var material : StandardMaterial3D = _bulb_materials[index]
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = emission_energy * level


## Brilho de uma lampada, de idle_level a 1.0, conforme a onda passa por ela.
## A distancia e medida no circulo (wrapf entre -0.5 e 0.5), senao a lampada da
## posicao 0 nunca acenderia junto com a da ultima posicao, e a volta teria uma
## emenda parada.
func _level_for(index : int, wave : float) -> float:
	var offset : float = float(index) / float(maxi(light_count, 1))
	var distance : float = absf(wrapf(wave - offset, -0.5, 0.5))
	var falloff : float = clampf(1.0 - distance / maxf(wave_width, 0.01), 0.0, 1.0)
	# Ao quadrado: o pico fica curto e a queda longa, que e o que faz a onda
	# ler como um ponto correndo em vez de um apagar linear.
	return lerpf(idle_level, 1.0, falloff * falloff)


## Cor de uma lampada no instante atual. A paleta e amostrada numa posicao que
## avanca com o tempo, entao ela desliza ao redor do anel e cada lampada vai
## trocando de cor, em vez de guardar a mesma para sempre.
##
## O espacamento (colors.size() / light_count) mantem a paleta inteira
## distribuida no anel: com doze lampadas e seis cores, cada cor aparece duas
## vezes, em lados opostos.
func _color_for(index : int, phase : float) -> Color:
	var palette_size : int = colors.size()
	var slot : float = (
		float(index) * float(palette_size) / float(maxi(light_count, 1))
		+ phase * float(palette_size)
	)
	var lower : int = posmod(int(floor(slot)), palette_size)
	var upper : int = posmod(lower + 1, palette_size)
	# smoothstep em vez do fract cru: com color_blend baixo a troca acontece
	# quase de uma vez, mas sem o serrilhado de um corte seco frame a frame.
	var blend : float = smoothstep(
		0.5 - color_blend * 0.5, 0.5 + color_blend * 0.5, slot - floor(slot)
	)
	return colors[lower].lerp(colors[upper], blend)


func _build_ring() -> void:
	if colors.is_empty():
		push_warning("SaucerLights sem cores: o anel de lampadas nao foi criado.")
		set_process(false)
		return

	var bulb_mesh : SphereMesh = SphereMesh.new()
	bulb_mesh.radius = bulb_radius
	bulb_mesh.height = bulb_radius * 2.0
	bulb_mesh.radial_segments = 10
	bulb_mesh.rings = 5

	for index : int in range(light_count):
		var angle : float = TAU * float(index) / float(light_count)
		var bulb_position : Vector3 = Vector3(
			sin(angle) * ring_radius, ring_height, cos(angle) * ring_radius
		)
		var color : Color = colors[index % colors.size()]

		# Um material por lampada: a cor difere entre elas e a emissao e
		# animada, entao compartilhar um StandardMaterial3D piscaria todas
		# juntas na mesma cor.
		var material : StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy * idle_level
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var bulb : MeshInstance3D = MeshInstance3D.new()
		bulb.mesh = bulb_mesh
		bulb.material_override = material
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bulb.position = bulb_position
		add_child(bulb)

		var light : OmniLight3D = OmniLight3D.new()
		light.light_color = color
		light.light_energy = light_energy * idle_level
		light.shadow_enabled = false
		light.omni_range = light_range
		light.omni_attenuation = 1.25
		light.position = bulb_position
		add_child(light)

		_bulb_materials.append(material)
		_bulb_lights.append(light)
