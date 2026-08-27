# Instruções para agentes — ET Game

## Antes de alterar

- Leia `README.md` e `project.godot`.
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
- Mantenha compatibilidade com Godot 4.7 e com o preset Windows existente.

## Godot

- Prefira recursos nativos do Godot e GDScript tipado.
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

- `scenes/main_menu.tscn` é a cena principal configurada; ela inicia
  `scenes/world.tscn`.
- `world.tscn` deve compor o mapa. Comportamentos reutilizáveis devem permanecer
  nas cenas próprias em vez de serem duplicados no mundo.
- Preserve o contrato de itens coletáveis: grupo `pickup_items`, métodos
  `pickup()` e `drop()` e propriedade `score_value` quando aplicáveis.
- Alterações na entrega devem manter consistência entre `player.gd`,
  `delivery_area.gd`, os itens e `GlobalScore.gd`.
- Alterações no veículo devem considerar entrada, saída, câmera, visibilidade do
  jogador, congelamento da física e restauração dos processos do personagem.
- Alterações no fazendeiro devem considerar navegação pronta, perda de visão,
  transições entre estados e ausência atual de um sistema de dano.
- Vegetação reativa deve continuar funcionando tanto para `characters` quanto
  para `vehicles`, sem custo desnecessário por instância.

## Validação

- Valide apenas o que for relevante para a alteração, mas não conclua sem uma
  checagem proporcional ao risco.
- Após mudar GDScript, cenas ou `project.godot`, execute, quando disponível:

```powershell
godot --headless --path . --editor --quit
```

- Mudanças visuais, de câmera, física, IK, navegação, interação ou gameplay
  também exigem validação em uma janela normal do Godot.
- Para coleta e entrega, teste pegar, largar e entregar um item solto e um item
  carregado; confirme a atualização da pontuação no console.
- Para o veículo, teste entrada, direção, troca de câmera, saída e devolução do
  controle ao jogador.
- Para o fazendeiro, teste patrulha, detecção, perseguição, perda do alvo e
  estado de disparo.
- Não há suíte automatizada no repositório atualmente. Se forem adicionados
  testes, prefira GUT e organize-os em `test/unit` e `test/integration`.
- Nunca remova ou enfraqueça validações para ocultar falhas.
- Nunca declare algo como testado sem ter executado a validação.

## Documentação

- Atualize `README.md` quando mudar o fluxo, controles, cena principal,
  arquitetura, dependências, comandos de execução ou limitações conhecidas.
- Atualize `AGENTS.md` somente quando surgir uma regra permanente nova.
- Ao concluir, informe os arquivos alterados, as validações executadas e as
  limitações que permaneceram.
