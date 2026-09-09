# Veículos

Todo veículo dirigível entra no grupo `vehicles` (grupo global declarado em
`project.godot`), o que faz a vegetação reagir a ele e as portas de casa se
abrirem na sua chegada. As cenas ficam em `scenes/Vehicles/`.

## Caminhonete dirigível — a referência

`scenes/Vehicles/DriveableTruck.tscn` + `scripts/driveable_truck.gd`
(`VehicleBody3D`).

- `try_enter_vehicle()` / `enter_vehicle(player)` / `exit_vehicle()`: ao entrar,
  o processamento e a câmera do jogador são desativados, o ET aparece sentado no
  banco (com as mesmas `CharacterProportions` do Player, para o boneco no banco
  respeitar a aparência escolhida) e o controle passa ao veículo; ao sair, o
  personagem é restaurado.
- Câmera própria: terceira pessoa com colisão e retorno automático, e primeira
  pessoa (`set_first_person_camera`) no mesmo `V` do jogador a pé.
- O mesmo caminho de física atende jogador e IA: `_update_driving()` chama
  `VehicleAIDriver.get_control_input()` quando o veículo **não** está sob
  controle do jogador. Aceleração e direção nunca têm dois caminhos distintos.
- O `steering_input` da IA pode passar de `[-1, 1]` de propósito, para atingir
  esterço total em manobra de baixa velocidade: **não** normalize isso no
  veículo, ou a manobra perde o raio de giro.

## Viatura de polícia com IA

`scenes/Vehicles/PoliceCarDriveable.tscn` reúne três scripts:
`driveable_truck.gd` (o chassi dirigível), `vehicle_ai_driver.gd` (o motorista)
e `cops_car.gd` (giro das luzes da sirene).

`scripts/vehicle_ai_driver.gd` (`VehicleAIDriver`) percorre um **grafo de ruas**:

- `road_nodes` são os centros dos tiles de rua, **gravados na cena**. A IA não
  consegue ler o gerador de layout em tempo de execução, por isso o grafo é
  assado por `tools/bake_police_patrol_route.gd`: rode-o e cole a linha impressa
  no nó `AIDriver` sempre que `ROAD_RUNS` mudar, senão a patrulha continua
  dirigindo pela grade antiga.
- Em cada cruzamento sorteia uma rua diferente daquela de onde veio; ramos
  curtos demais são ignorados enquanto houver alternativa.
- Mantém o carro na mão certa da via (`lane_offset`), reduz velocidade em curva,
  olha à frente proporcionalmente à velocidade, tem sensores de obstáculo,
  detecção de "preso" com manobra de desencalhe e recuperação de capotamento.

## Avião

`scenes/Vehicles/FlyablePlane.tscn` + `scripts/plane/`: `flyable_plane.gd`
(`RigidBody3D` com motor, sustentação e arrasto), `aim_target_arm.gd` (o alvo
que o mouse move e que orienta o voo) e `camera_arm.gd`. `E` assume e devolve o
controle perto da cabine. É uma cena de teste isolada, fora do fluxo principal.

## Nave alienígena

Não é um veículo dirigível, mas transporta o jogador. `scenes/Space/AlienShip.tscn`
+ `scripts/space/`:

- `alien_ship.gd`: giro lento em yaw, `stop_spin_facing()` para alinhar a vista
  antes de uma cutscene, e a remoção da camada 12 (casco) da câmera enquanto o
  ET está dentro, para a janela panorâmica mostrar o espaço e não o interior do
  casco.
- `ship_carry_field.gd`: leva junto quem está no grupo `ship_passengers`; roda
  antes do Player na ordem de processamento, para o transform do convés já estar
  aplicado quando o jogador se move.
- `spaceship_interior.gd`: o pad de descida, que emite `descend_requested`.
- `saucer.gd`, `saucer_lights.gd`, `tapered_shell.gd`, `triangular_deck.gd`:
  geometria e luzes; `ship_crew_alien.gd` é o tripulante.

A mesma nave é reutilizada na órbita, na chegada à fase e no celeiro —
ver [fluxo-de-jogo.md](fluxo-de-jogo.md).

## Veículos de cenário

`Harvester01`, `PickUp01`, `QuadBike`, `TractorOld`, `VintageCar`,
`EngineTruck` (`scripts/engine_truck.gd`), `cops_car.tscn` e `dozer.gd` são
props animados ou estáticos, sem entrada de jogador.

## Ao alterar

1. Veículo dirigível novo: entre no grupo `vehicles` e reaproveite o contrato de
   entrada/saída de `driveable_truck.gd` em vez de reimplementar a troca de
   controle e de câmera.
2. IA nova: use `VehicleAIDriver` pelo mesmo caminho de física do jogador.
3. Mudou o traçado das ruas do Country Town? Reassar o grafo é obrigatório
   (`tools/bake_police_patrol_route.gd`) — ver [country-town.md](country-town.md).
4. Validação: roteiro manual do veículo em `tools/VALIDACAO.md` (entrada,
   direção, troca de câmera, saída e devolução do controle).
