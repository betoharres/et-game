# Documentação do ET Game

Documentação persistente dos sistemas do projeto, escrita para que um agente
(ou uma pessoa nova) saiba **o que ler antes de mexer em cada coisa**, sem
precisar varrer o repositório inteiro nem depender de servidores externos.

As regras de trabalho estão em [`../AGENTS.md`](../AGENTS.md). A visão geral do
produto (o que existe, como rodar, controles, limitações) está no
[`../README.md`](../README.md). O procedimento de validação está em
[`../tools/VALIDACAO.md`](../tools/VALIDACAO.md).

## Como usar

1. Leia [`arquitetura.md`](arquitetura.md) — é o mapa: cenas de entrada,
   autoloads, grupos, contratos entre sistemas e convenções.
2. Abra o documento do sistema que você vai alterar (tabela abaixo).
3. Confira em `project.godot` as chaves que o documento citar (autoloads,
   Input Map, camadas, render).
4. Leia os arquivos listados na seção **Arquivos** do documento — os scripts
   têm docstrings de topo que explicam as decisões finas.
5. Valide conforme [`../tools/VALIDACAO.md`](../tools/VALIDACAO.md).

Estes documentos descrevem **relações, responsabilidades e decisões**. Valores
de ajuste (velocidades, distâncias, tempos) vivem nos `@export` das cenas e nas
constantes dos scripts, que são a fonte da verdade — não duplique número aqui.

## Índice por sistema

| Documento | Cobre | Leia antes de mexer em |
| --- | --- | --- |
| [arquitetura.md](arquitetura.md) | Cenas de entrada, autoloads, grupos globais, contratos, camadas de física/render, convenções de código | Qualquer coisa; obrigatório para mudanças que cruzam sistemas |
| [fluxo-de-jogo.md](fluxo-de-jogo.md) | Menu → criador de ET → órbita → catálogo de fases → chegada → coleta → entrega | Menu, catálogo de fases, chegada na fase, área de entrega, pontuação |
| [player.md](player.md) | `Player.tscn`, movimento, stamina/vida/equilíbrio, câmera, aparência, ragdoll, carregar itens e personagens | `scripts/player.gd` e tudo que pendura no ET |
| [npcs.md](npcs.md) | `NPCActor` + Beehave, visão/audição, rotina e atividades, papéis (fazendeiro, morador, policial) e os NPCs legados da fazenda | `scripts/npc/`, `scenes/NPCs/`, comportamento de qualquer NPC |
| [animacoes.md](animacoes.md) | Dois rigs incompatíveis: Mixamo (Player) e Synty (NPCs); `AnimationTree`, IK e modificadores | Animação do Player ou dos NPCs, troca de clipe, rig novo |
| [veiculos.md](veiculos.md) | Caminhonete dirigível, viatura com IA, avião, nave alienígena | `scripts/driveable_truck.gd`, `vehicle_ai_driver.gd`, `plane/`, `space/` |
| [mundo.md](mundo.md) | Mapas jogáveis, terreno, estradas, vegetação, masmorra procedural, portais | `scenes/world.tscn`, terreno, vegetação, `scripts/dungeon/` |
| [country-town.md](country-town.md) | O mapa gerado por ferramentas: distritos, pipeline de `tools/`, ordem de execução | Qualquer coisa dentro de `scenes/CountryTown/` |
| [casas-interiores.md](casas-interiores.md) | `House01`, portas automáticas, navegação interna, pontos de atividade | `scripts/house_door.gd`, `tools/build_house_01.gd`, interiores |
| [ambiente-e-fx.md](ambiente-e-fx.md) | Céu/noite, névoa, pós-processo de incidente alienígena, partículas, shaders e áudio | `scripts/night_environment.gd`, `shaders/`, `scripts/audio/` |
| [ui-e-menus.md](ui-e-menus.md) | Menus, HUDs, minimapa, menus de depuração, transições de cena, remapeamento de teclas | `scenes/Menu/`, HUDs, `scripts/vision_debug_map.gd` |
| [ferramentas.md](ferramentas.md) | O que cada script de `tools/` faz e quando rodar | Adicionar ou alterar uma ferramenta de geração/checagem |
| [generated/](generated/) | Área reservada para o snapshot automático do repositório (Repomix) | Nada — conteúdo gerado, nunca editado à mão |

## Mapa rápido de pastas

| Caminho | O que é |
| --- | --- |
| `scenes/` | Todas as cenas do jogo, agrupadas por sistema |
| `scripts/` | GDScript, espelhando a organização das cenas |
| `shaders/` | Céu, névoa, terreno, água, personagem e efeitos |
| `tools/` | Geradores de asset e checagens automatizadas (ver [ferramentas.md](ferramentas.md)) |
| `addons/` | Terrain3D, Beehave e PathMesh3D vendorados |
| `animations/mixamo/` | Rig e clipes do Player |
| `Temporarios/Animations/` | Rig e clipes Synty usados pelos NPCs |
| `assets/`, `Texturas/`, `Materiais/`, `3dModelos/` | Áudio, texturas, materiais e modelos |
| `Polygon*/`, `SICSFarm/` | Pacotes de asset importados, na forma em que vieram |
| `build/` | Cópias isoladas do projeto e saídas de inspeção; fora do versionamento |
