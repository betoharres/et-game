# Instruções para agentes — ET Game

Fonte única de instruções para agentes. `CLAUDE.md` apenas importa este arquivo,
para o Claude Code e o Codex seguirem as mesmas regras.

## Antes de alterar

- Consulte no `README.md` a seção relevante à mudança (índice no topo);
  leia-o inteiro apenas ao alterar fluxo ou arquitetura.
- Consulte em `project.godot` as chaves relevantes: autoloads, Input Map,
  camadas de física e configuração de render.
- Analise as cenas e os scripts envolvidos antes de editar.
- Verifique referências entre cenas, scripts, recursos, grupos, sinais,
  autoloads, materiais e modelos importados.
- Confirme no código o comportamento atual; não documente ou implemente
  funcionalidades presumidas.
- Consulte `git status` e preserve mudanças existentes do usuário, inclusive
  alterações não relacionadas à tarefa atual.

## Escopo

- O projeto atual é um protótipo 3D single-player.
- Preserve o fluxo principal de explorar, coletar destroços e entregá-los.
- Não introduza multiplayer, backend, persistência ou uma arquitetura de
  servidor sem solicitação explícita.
- Faça a menor alteração necessária e evite reorganizações sem benefício claro.
- Mantenha compatibilidade com Godot 4.7, Godot 4.8 e com o preset Windows existente.

## Godot

- Prefira recursos nativos do Godot e GDScript tipado.
- Sempre use vars, funções e retornos com tipos explícitos (var x: int = 0; func foo(delta: float) -> void:).
- Use ações do Input Map em vez de adicionar teclas hard-coded. Ao criar uma
  nova ação, registre-a em `project.godot`, documente o controle no README e
  adicione-a ao menu de controles do ESC (`REBIND_ACTIONS`/`REBIND_LABELS` e
  `action_buttons` em `scripts/pause_menu.gd`, com o botão correspondente em
  `scenes/PauseMenu.tscn`), para que fique visível e rebindável pelo jogador.
- Prefira sinais, grupos, composição e cenas reutilizáveis.
- Mantenha scripts e nós com responsabilidades pequenas.
- Preserve os grupos `characters`, `vehicles` e `pickup_items` ou atualize
  todos os seus consumidores na mesma mudança.
- Evite managers globais, duplicação e abstrações prematuras. Use o autoload
  `GlobalScore` somente para estado realmente global.
- Não edite `.godot/`, arquivos `.uid`, arquivos `.import` ou caches gerados.
- Não altere modelos, texturas ou materiais importados quando uma sobrescrita
  local na cena resolver o problema.
- Nunca grave senhas, tokens, chaves ou credenciais no repositório.
- Registre origem, autor e licença ao adicionar assets externos.

## Gameplay e cenas

- `scenes/Menu/main_menu.tscn` é a cena principal configurada; o botão de jogar
  inicia `scenes/Space/Orbit.tscn`, que leva à fase escolhida.
- `world.tscn` deve compor o mapa. Comportamentos reutilizáveis devem permanecer
  nas cenas próprias em vez de serem duplicados no mundo.
- Preserve o contrato de itens coletáveis: grupo `pickup_items`, métodos
  `pickup()` e `drop()` e propriedade `score_value` quando aplicáveis.
- Alterações na entrega devem manter consistência entre `player.gd`,
  `delivery_area.gd`, os itens e `GlobalScore.gd`.
- Alterações no veículo devem considerar entrada, saída, câmera, visibilidade do
  jogador, congelamento da física e restauração dos processos do personagem.
- Alterações no fazendeiro devem considerar navegação pronta, perda de visão,
  transições entre estados, disparos, dano e morte do jogador.
- Vegetação reativa deve continuar funcionando tanto para `characters` quanto
  para `vehicles`, sem custo desnecessário por instância.

## Validação

- Valide o que for relevante à alteração, proporcional ao risco, e apenas uma
  vez, depois da última edição. Repita só se o código mudar após a checagem.
- Rode a checagem headless do Godot quando a mudança puder quebrar parsing,
  importação ou referências: script ou cena nova, recurso movido ou renomeado,
  assinatura alterada, mudança em `project.godot`. Ajuste dentro de uma função
  existente não exige.
- Mudanças visuais, de câmera, física, IK, navegação ou gameplay precisam de
  uma execução em janela normal. Quando o editor já estiver aberto na máquina
  do usuário, diga o que ele deve conferir em vez de abrir o jogo por conta
  própria.
- Os comandos, o mapa de ferramentas de `tools/` por sistema, os roteiros de
  teste manual e as regras para escrever uma verificação nova estão em
  `tools/VALIDACAO.md`. Consulte-o antes de validar.
- Nunca remova ou enfraqueça validações para ocultar falhas.
- Nunca declare algo como testado sem ter executado a validação.

## Documentação

- Atualize `README.md` quando mudar o fluxo, controles, cena principal,
  arquitetura, dependências, comandos de execução ou limitações conhecidas.
- Ao adicionar, remover ou renomear uma seção do `README.md`, atualize o
  índice no topo dele.
- Atualize `AGENTS.md` somente quando surgir uma regra permanente nova.
- Ao concluir, informe os arquivos alterados, as validações executadas e as
  limitações que permaneceram.
