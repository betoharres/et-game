# Casas e interiores

A primeira casa em que Player e NPCs entram de verdade é a **House01**: uma cena
separada e autocontida, gerada por ferramenta. **House02** é uma segunda planta,
mesma técnica de geração, com garagem; ainda não é instanciada em nenhum mapa.

| Arquivo | Papel |
| --- | --- |
| `scenes/Buildings/House01.tscn` | A casa: estrutura, mobília, luzes, portas, navegação e pontos de atividade |
| `scenes/Buildings/House02.tscn` | Segunda planta: quarto de casal, quarto de solteiro, banheiro, sala/cozinha e garagem anexa |
| `scenes/Buildings/HouseDoor.tscn` / `HouseDoorInner.tscn` | Porta externa e porta interna, reaproveitadas pelas duas plantas |
| `scripts/house_door.gd` (`HouseDoor`) | NPC abre por proximidade, quem joga abre com `interact`; guarda a tranca |
| `scripts/house_variant.gd` (`HouseVariant`) | Aplicado a uma instância de `House01` no Country Town: varia tranca, luzes, cortinas e móveis por `variant_seed` — ver [Country Town](country-town.md#população) |
| `scenes/Buildings/HouseTest.tscn` | Cena de teste: terreno simples, Player, uma moradora e a casa |
| `scenes/Buildings/HouseTestNavigation.res` | Malha de navegação usada pela cena de teste |
| `tools/build_house_01.gd` | **Gera** a House01, as duas portas, a cena de teste e a navegação interna |
| `tools/build_house_02.gd` | **Gera** a House02 (mesmo padrão de receita, sem cena de teste própria) |
| `tools/check_house_01.gd` | Verifica que a House01 é habitável (navegação, portas, tranca, moradora até a cama) |
| `tools/shoot_house_01.gd` | Capturas para inspeção visual (sem `--headless`) |
| `scripts/house_lights.gd` | Luzes de janela, com cintilação e participação no menu `F6` |

## Decisões de projeto

- **A casa é gerada.** `tools/build_house_01.gd` regrava `House01.tscn`,
  `HouseDoor.tscn`, `HouseDoorInner.tscn`, `HouseTest.tscn` e a malha de
  navegação. Ajuste feito à mão no `.tscn` **se perde** na próxima execução:
  mude a receita no script.
- **O kit manda na medida.** As peças do PolygonTown trabalham num grid de
  2,5 m (parede de 2,5 × 2,9, piso e teto de 2,5 × 2,5), e as águas do telhado
  fecham sobre um vão específico — daí a largura da casa. Alterar dimensão sem
  respeitar o grid quebra o telhado.
- **Porta é composição, não animação.** `HouseDoor` é `Folha`
  (`AnimatableBody3D` com malha e colisão) + `Trigger` (`Area3D`), mais um aviso
  e um alto-falante criados em código — a cena é regravada pelo gerador, nó
  posto à mão nela se perde. Rangido, trinco e maçaneta chacoalhando saem do
  `ProceduralSFX` ([ambiente-e-fx.md](ambiente-e-fx.md)).
- **Quem tem mão abre com a mão.** Os grupos de `auto_open_groups` (por padrão
  `npc_actors`) abrem só de chegar perto, porque NPC não tem teclado; os de
  `manual_groups` (`characters`) veem o aviso na folha e apertam `interact`.
  Aberta na mão, a folha fica aberta até o mesmo `interact` fechá-la; aberta por
  NPC, ela fecha sozinha depois de `close_delay`.
- **Tranca é do lado de dentro.** Com `starts_locked`, a porta só cede a quem
  está em `key_groups` (os moradores) ou a quem já está do lado de dentro — o
  interior é o `-Z` local da folha. Quem tem chave destranca ao abrir e não
  tranca de novo, então a casa não fica fechada para sempre. A porta de entrada
  da House01 começa trancada; as internas, não.
- **A casa conhece a rotina dos NPCs.** O nó `Atividades` traz `Marker3D` com o
  script `NPCActivity` (`Cama`, `Sofa`, `Cozinha`, `MesaJantar`, `Varanda`), que
  o `NPCRoutine` percorre e cujas vagas reserva — ver [npcs.md](npcs.md).
- **Navegação interna assada.** A malha liga o jardim a cada ponto de atividade;
  é isso que `check_house_01.gd` verifica de ponta a ponta (a moradora sai do
  jardim, atravessa a porta e chega à cama).
- **Uma planta, várias casas.** No Country Town, cada lote habitável instancia
  `House01.tscn` de novo (`GEN_EDIT_STATE_INSTANCE`, para não perder a
  sobrescrita ao empacotar) e recebe `HouseVariant` (`_enter_tree`, antes do
  `_ready` de portas e luzes): sorteia a intensidade e a distância de corte das
  luzes, esconde parte das cortinas e da mobília reserva (`spare_furniture`) e
  destranca ou não a porta de entrada — tudo a partir de um único
  `variant_seed`. Mesma semente, mesma casa; sem isso todo lote habitável
  sairia idêntico à `House01` original.

## Onde a casa aparece

`House01`/`HouseDoor` são consumidos por `HouseTest.tscn`, `world.tscn`,
`scenes/CountryTown/Districts/FarmDistrict.tscn`, `Mat_test.tscn` e, dentro do
`TownDistrict`, por vários lotes do settlement gerado — ver
[Country Town — População](country-town.md#população) para quais lotes e como
a tranca varia. Outros prédios da fazenda (`Barn01`, `FarmHouse01`, `Silo02`,
`garage`, `cafe`, `windmill`) são cenas montadas à mão, sem interior navegável.
`House02` ainda não é instanciada em nenhuma cena — existe só como saída de
`tools/build_house_02.gd`.

## Ao alterar

1. Mudança na House01: edite `tools/build_house_01.gd` e regere (editor
   fechado ou cópia isolada), depois rode `tools/check_house_01.gd`. Mudança na
   House02: edite `tools/build_house_02.gd` e regere; ainda não há checagem
   dedicada.
2. Ponto de atividade novo: acrescente o `NPCActivity` na receita, com
   `slots` suficientes para quantos NPCs devem usá-lo ao mesmo tempo.
3. Porta em outro prédio: instancie `HouseDoor.tscn` e ajuste os grupos ou a
   tranca pelo inspetor — não escreva outra lógica de porta.
4. Variação nova por lote (luz, cortina, móvel, tranca): acrescente ao
   `HouseVariant`, não à receita do settlement — ele já aplica por
   `variant_seed` a qualquer instância de `House01`.
5. Inspeção visual: `tools/shoot_house_01.gd` sem `--headless`; para as
   instâncias do Country Town, `tools/shoot_country_town_windows.gd` (ver
   [ferramentas.md](ferramentas.md)). Quem julga o resultado é o usuário.
