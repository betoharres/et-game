# Documentação do ET Game

Documentação persistente dos sistemas do projeto, escrita para que um agente
(ou uma pessoa nova) saiba **o que ler antes de mexer em cada coisa**, sem
precisar varrer o repositório inteiro nem depender de servidores externos.

As regras de trabalho estão em [`../AGENTS.md`](../AGENTS.md). A visão geral do
produto (o que existe, como rodar, controles, limitações e o mapa de pastas do
projeto) está no [`../README.md`](../README.md). O procedimento de validação
está em [`../tools/VALIDACAO.md`](../tools/VALIDACAO.md).

## Como usar

Para ajuste local com arquivo conhecido, vá direto ao código e à cena; não
é obrigatório ler um documento. Se não souber onde editar, use os atalhos
abaixo. Para comportamento novo ou mudança estrutural, consulte o índice por
sistema; acrescente [arquitetura.md](arquitetura.md) quando cruzar sistemas.
Se a investigação revelar efeitos em consumidores, amplie a leitura antes de editar.

Busca pontual (a partir da raiz; substitua os exemplos pelo alvo da tarefa):

```powershell
rg -n 'stamina|func .*jump' scripts/player.gd
rg -n -F 'res://scripts/house_door.gd' scenes tools
rg -n 'pickup_items|begin_abduction' scripts scenes/Player.tscn
```

Evite ler cenas grandes inteiras, pacotes importados, `addons/` ou snapshots
de `docs/generated/` para uma alteração local. Restrinja a busca ao sistema;
amplie quando as referências apontarem para fora dele. Os snapshots servem
para transportar contexto, não são uma etapa de leitura do projeto.

## Atalhos por problema

Os símbolos são pontos de partida, não diagnósticos. Busque com `rg -n -F`
e confira sobrescritas na cena antes de alterar o default do script.

| Problema / ajuste | Arquivo | Símbolo para buscar |
| --- | --- | --- |
| Velocidade de corrida do ET | `scripts/player.gd` | `sprint_speed` |
| ET prende em degrau | `scripts/player.gd` | `max_step_height` |
| Consumo da luz dos olhos | `scripts/player.gd` | `eye_light_energy_cost_per_second` |
| Câmera em primeira pessoa | `scripts/cinematic_camera_rig.gd` | `set_first_person_mode` |
| Clipe associado a um estado do Player | `scripts/player_animation_controller.gd` | `STATE_ANIMATIONS` |
| Alcance de visão dos NPCs compostos (Country Town) | `scripts/npc/npc_vision.gd` | `sight_distance` |
| Quem abre uma porta sozinho, quem abre no `interact` | `scripts/house_door.gd` | `auto_open_groups`, `manual_groups` |
| Porta que começa trancada e quem tem chave | `scripts/house_door.gd` | `starts_locked`, `key_groups` |
| Tempo segurando o sinal de entrega | `scripts/delivery_area.gd` | `signal_hold_duration` |
| Alcance do minimapa | `scripts/vision_debug_map.gd` | `world_radius` |
| Ação ausente no remapeamento do ESC | `scripts/pause_menu.gd` | `REBIND_ACTIONS` |
| Traçado das ruas do Country Town | `tools/build_country_town_layout.gd` | `ROAD_RUNS` |

Remapeamento e traçado envolvem outros arquivos: consulte respectivamente
[UI](ui-e-menus.md#remapeamento-de-teclas) e [Country Town](country-town.md).
Mantenha os atalhos restritos às tarefas recorrentes, sem copiar valores ou
números de linha. Ao renomear um símbolo listado, ajuste sua entrada.

## Índice por sistema

| Documento | Cobre | Localizar mudanças estruturais em |
| --- | --- | --- |
| [arquitetura.md](arquitetura.md) | Autoloads, grupos globais, contratos, camadas de física/render, convenções locais | Mudanças que cruzam sistemas |
| [fluxo-de-jogo.md](fluxo-de-jogo.md) | Menu → criador de ET → órbita → catálogo de fases → chegada → coleta → entrega | Menu, catálogo de fases, chegada na fase, área de entrega, pontuação |
| [player.md](player.md) | `Player.tscn`, movimento, stamina/vida/equilíbrio, câmera, aparência, ragdoll, carregar itens e personagens | `scripts/player.gd` e tudo que pendura no ET |
| [npcs.md](npcs.md) | `NPCActor` + Beehave, visão/audição, rotina e atividades, papéis (fazendeiro, morador, policial) e os NPCs legados da fazenda | `scripts/npc/`, `scenes/NPCs/`, comportamento de qualquer NPC |
| [animacoes.md](animacoes.md) | Dois rigs incompatíveis: Mixamo (Player) e Synty (NPCs); `AnimationTree`, IK e modificadores | Animação do Player ou dos NPCs, troca de clipe, rig novo |
| [veiculos.md](veiculos.md) | Caminhonete dirigível, viatura com IA, avião, nave alienígena | `scripts/driveable_truck.gd`, `vehicle_ai_driver.gd`, `plane/`, `space/` |
| [mundo.md](mundo.md) | Mapas jogáveis, terreno, estradas, vegetação, masmorra procedural, portais | `scenes/world.tscn`, terreno, vegetação, `scripts/dungeon/` |
| [country-town.md](country-town.md) | Distritos, autoria das cenas, integração da casa e população | `scenes/CountryTown/`; comandos e ordem de geração em `tools/VALIDACAO.md` |
| [casas-interiores.md](casas-interiores.md) | `House01`, portas automáticas, navegação interna, pontos de atividade | `scripts/house_door.gd`, `tools/build_house_01.gd`, interiores |
| [ambiente-e-fx.md](ambiente-e-fx.md) | Céu/noite, névoa, pós-processo de incidente alienígena, partículas, shaders e áudio | `scripts/night_environment.gd`, `shaders/`, `scripts/audio/` |
| [ui-e-menus.md](ui-e-menus.md) | Menus, HUDs, minimapa, menus de depuração, transições de cena, remapeamento de teclas | `scenes/Menu/`, HUDs, `scripts/vision_debug_map.gd` |
| [ferramentas.md](ferramentas.md) | Geradores: receita → saída → sistema; inspeções e bibliotecas auxiliares | Localizar quem gera um asset; escolher teste em `tools/VALIDACAO.md` |
| [generated/](generated/) | Snapshots do repositório em cinco perfis (Repomix), gerados por `tools/build_snapshots.ps1` | Nada — conteúdo gerado, nunca editado à mão |

## Manutenção da documentação

[revisao-documentacao.md](revisao-documentacao.md): procedimento de revisão,
intervalo de commits e onde manter cada informação. Leia só em tarefa de documentação.
