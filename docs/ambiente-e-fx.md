# Ambientação, efeitos e áudio

O mapa é permanentemente noturno. A ambientação é uma cena reutilizável
(`scenes/NightEnvironment.tscn`), instanciada por cada mapa, e um conjunto de
peças que se acham por grupo em vez de se referenciarem direto.

## Ambiente noturno

`scripts/night_environment.gd` concentra:

- **Presets de qualidade** (`Low`/`Medium`/`High`) que ligam ou desligam
  partículas, névoa volumétrica, sombras e névoa rasteira de uma vez.
- **Céu procedural** (`shaders/night_sky.gdshader`): densidade e brilho das
  estrelas, cintilação, Lua com tamanho angular e sombra de nuvens, estrelas
  cadentes em intervalos sorteados.
- **Névoa atmosférica** e o *glow*, com perfis distintos para chão e voo — é o
  que `world.gd` alterna na descida da nave.
- **Coordenação por grupo**: age sobre `volumetric_lights`,
  `alien_volumetric_lights` e `ufo_lighting`; responde a chamadas de grupo
  (`night_environment`) vindas do mundo e do menu de depuração.

## Névoa rasteira

- `scripts/ground_fog_layer.gd` (`GroundFogLayer`) desenha camadas de névoa que
  acompanham o jogador, sondando a altura do chão, com o
  `shaders/ground_fog.gdshader`.
- `scripts/fog_zone.gd` (`FogZone`) adensa a névoa localmente. Zonas entram no
  grupo `fog_zones`; a camada lê **até um número fixo** das zonas mais próximas
  e as envia ao shader como um vetor de parâmetros — por isso zona nova é barata,
  mas passar do limite simplesmente ignora as excedentes.
- Limitação conhecida: a névoa rasteira não recebe luz das fontes do mapa; com a
  volumetria desligada, feixes e holofotes não formam cone de luz no ar.

## Incidente alienígena

- `scripts/alien_interference_source.gd` (`AlienInterferenceSource`): fonte com
  raio de intensidade plena, raio de dissipação e pulsação. Entra no grupo
  `alien_interference_sources`.
- `scripts/alien_incident_post_process.gd` (`AlienIncidentPostProcess`,
  `CanvasLayer`): soma as fontes próximas e aplica o filtro de tela
  (`shaders/alien_incident_post.gdshader`) — grão, vinheta, aberração cromática,
  contraste. É o mesmo filtro que o `NightEnvironment` intensifica durante um
  evento.

## Efeitos de cena

`scenes/FX/` reúne fogo, fumaça, poeira, chuva, neve, folhas, moscas, vaga-lumes
e o feixe de chegada (`ArrivalBeam.tscn` + `scripts/arrival_beam.gd`), além da
cúpula de escudo. `scripts/ambient_particles.gd` liga e desliga sistemas de
partículas por distância do jogador, com histerese — é o que permite espalhar
partículas pelo mapa sem pagar por todas ao mesmo tempo.

`scripts/living_light.gd` é a criatura-luz, com trilha nativa (`Trail3D`) e o
`shaders/living_light_trail.gdshader`.

## Shaders

`shaders/` guarda o material do terreno (`terrain_natural`, derivado do
Terrain3D), céu, névoa, água (`water`, `ea_coolwater`), personagem
(`character_body`, `character_belly`, `character_eyes`, `eyes`), nave
(`ship_floor_cutout`, `ship_floor_glass`, `body_glass`), feixes (`ufo_beam`,
`tractor_beam_wipe`, `abduction_flash`), planeta (`earth_planet`,
`planet_atmosphere`), vias (`rural_tracks`, `tire_track`), pós-processo
(`alien_incident_post`, `damage_vignette`, `xray_binos`) e variação de solo.

Cada shader é usado por uma cena ou material específico: antes de alterar,
procure quem o referencia (`rg -n -F nome.gdshader` em `scenes/`,
`Materiais/` e `scripts/`).

## Áudio

| Arquivo | Papel |
| --- | --- |
| `scripts/audio/footstep_audio.gd` | Passos por tipo de superfície (terra, pedra, madeira), escolhida pelo nome da superfície pisada |
| `scripts/audio/farm_environment_audio.gd` | Ambiência da fazenda: vento, grilos e cães em posições fixas |
| `scripts/audio/farmer_gunshot_audio.gd` | Tiro do fazendeiro, gerado proceduralmente |
| `scripts/audio/beam_travel_audio.gd` (`BeamTravelAudio`) | Som do feixe, com pitch variando entre nave e solo |
| `scripts/audio/procedural_sfx.gd` (`ProceduralSFX`) | Utilitário `RefCounted` que sintetiza os efeitos |

As portas de casa também sintetizam pelo `ProceduralSFX` — rangido, trinco e
maçaneta chacoalhando na porta trancada ([casas-interiores.md](casas-interiores.md)).
Cada `HouseDoor` guarda esses streams em `static`: sintetizar por porta custa
caro e o resultado é sempre o mesmo.

Os arquivos de áudio ficam em `assets/audio/`, com procedência registrada em
`assets/audio/SOURCE.md`. O Country Town ainda reusa as posições fixas de
ambiência da fazenda.

## Ao alterar

1. Peça nova de ambientação: entre no grupo que o `NightEnvironment` ou o
   `DebugMenus` já consultam, em vez de criar referência direta.
2. Para aparecer no menu `F6`, um nó precisa implementar os métodos de
   depuração de iluminação e entrar no grupo `debug_*` correspondente
   ([ui-e-menus.md](ui-e-menus.md)).
3. Validação: `tools/test_atmosphere_presets.gd` (presets de névoa e evento),
   `tools/test_alien_interference.gd` (filtro) e
   `tools/measure_atmosphere_cost.gd` (custo de render, **sem** `--headless`).
   Aparência quem julga é o usuário.
