extends SceneTree

## Gera a textura de banda de rodagem usada pelas marcas de pneu (TireTrack3D).
## A imagem repete ao longo do caminho: V corre no sentido da marcha e U cruza a
## largura da fita. RGB guarda a granulacao da terra pisada e A a cobertura --
## cheio sob os blocos da banda, fraco nos sulcos e nulo nas bordas.
const OUTPUT: String = "res://Texturas/tire_tread.res"
const WIDTH: int = 128
const HEIGHT: int = 256
## Blocos da banda em uma volta da textura.
const LUGS: int = 7
const SEED: int = 20260907


func _init() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var image: Image = Image.create_empty(WIDTH, HEIGHT, true, Image.FORMAT_RGBA8)
	for y: int in HEIGHT:
		var v: float = float(y) / float(HEIGHT)
		for x: int in WIDTH:
			var u: float = (float(x) + 0.5) / float(WIDTH)
			image.set_pixel(x, y, _tread(u, v, rng))
	image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var result: Error = ResourceSaver.save(texture, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		push_error("Cannot save tire tread texture: " + OUTPUT)
		quit(1)
		return
	print("Tire tread texture saved to %s (%d x %d)." % [OUTPUT, WIDTH, HEIGHT])
	quit()


## Um pixel da banda: blocos em V, sulco longitudinal no centro e borda que
## dissolve, para a fita nao terminar em aresta reta sobre o pasto.
func _tread(u: float, v: float, rng: RandomNumberGenerator) -> Color:
	var lateral: float = absf(u - 0.5) * 2.0
	# Os blocos atrasam em direcao ao ombro: e isso que desenha o V da banda.
	var slot: float = fposmod((v + lateral * 0.11) * float(LUGS), 1.0)
	var lug: float = smoothstep(0.08, 0.2, slot) * (1.0 - smoothstep(0.6, 0.74, slot))
	# Sulco central: o pneu apoia nos dois ombros e deixa o meio mais limpo.
	var groove: float = 1.0 - exp(-pow(lateral / 0.22, 2.0))
	var contact: float = clamp(mix_max(lug, 0.28) * mix_max(groove, 0.45), 0.0, 1.0)
	var edge: float = 1.0 - smoothstep(0.66, 1.0, lateral)
	var grain: float = rng.randf_range(-0.09, 0.09)
	var alpha: float = clamp(contact * edge + grain * edge * 0.6, 0.0, 1.0)
	var shade: float = clamp(0.78 + lug * 0.22 + grain * 1.4, 0.0, 1.0)
	return Color(shade, shade, shade, alpha)


## Piso minimo: mesmo fora do bloco resta terra revirada, so que mais fraca.
func mix_max(value: float, floor_value: float) -> float:
	return floor_value + (1.0 - floor_value) * value
