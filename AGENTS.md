# Instruções para agentes — ET Game

Fonte única de regras para agentes. `CLAUDE.md` apenas importa este arquivo,
para o Claude Code e o Codex seguirem as mesmas instruções.

Este arquivo é o **índice**: visão geral, regras e para onde ir. O detalhe de
cada sistema mora em [`docs/`](docs/) e é a primeira coisa a ler antes de
alterar algo.

## O projeto em cinco linhas

Protótipo 3D single-player em Godot 4.8 dev4. Um ET explora um
mapa noturno, coleta destroços de uma nave e os leva até uma área de entrega.
Não há manager global: um mapa é uma cena que monta terreno, ambiente, jogador,
NPCs, veículos e itens, e os sistemas se falam por **sinais**, **grupos** e
**contratos de método**. Cena principal: `scenes/Menu/main_menu.tscn`. Mapa
jogável: `scenes/world.tscn`.

## Onde está a informação

| Preciso de… | Vá para |
| --- | --- |
| Mapa dos sistemas e por onde começar | [`docs/README.md`](docs/README.md) |
| Autoloads, grupos, contratos, camadas, convenções | [`docs/arquitetura.md`](docs/arquitetura.md) |
| Documentação do sistema que vou alterar | tabela em [`docs/README.md`](docs/README.md) |
| O que existe, como rodar, controles, limitações | [`README.md`](README.md) |
| Comandos de validação, ferramenta por sistema e roteiros manuais | [`tools/VALIDACAO.md`](tools/VALIDACAO.md) |
| O que cada script de `tools/` faz, por categoria | [`docs/ferramentas.md`](docs/ferramentas.md) |
| Autoloads, Input Map, camadas de física e render | `project.godot` |

## Antes de alterar

- Leia o documento de [`docs/`](docs/) do sistema envolvido e, em mudanças que
  cruzam sistemas, [`docs/arquitetura.md`](docs/arquitetura.md).
- Consulte no `README.md` a seção relevante; leia-o inteiro apenas ao alterar
  fluxo ou arquitetura.
- Confira em `project.godot` as chaves que a mudança tocar.
- Analise as cenas e os scripts envolvidos, e verifique as referências entre
  cenas, scripts, recursos, grupos, sinais, autoloads, materiais e modelos
  importados.
- Confirme no código o comportamento atual; não documente nem implemente
  funcionalidade presumida.
- Consulte `git status` e preserve mudanças existentes do usuário, inclusive as
  não relacionadas à tarefa atual.

## Escopo

- O projeto atual é um protótipo 3D single-player.
- Preserve o fluxo principal de explorar, coletar destroços e entregá-los.
- Não introduza multiplayer, backend, persistência ou arquitetura de servidor
  sem solicitação explícita.
- Faça a menor alteração necessária e evite reorganizações sem benefício claro.
- Mantenha compatibilidade com Godot 4.7, Godot 4.8 e com o preset Windows.

## Godot

- Prefira recursos nativos do Godot e GDScript tipado.
- Sempre use vars, funções e retornos com tipos explícitos
  (`var x: int = 0`; `func foo(delta: float) -> void:`).
- Use ações do Input Map em vez de teclas hard-coded. Ao criar uma ação:
  registre-a em `project.godot`, documente o controle no `README.md` e
  acrescente-a ao menu de controles do ESC — ver
  [`docs/ui-e-menus.md`](docs/ui-e-menus.md).
- Prefira sinais, grupos, composição e cenas reutilizáveis.
- Mantenha scripts e nós com responsabilidades pequenas.
- Preserve os grupos `characters`, `vehicles` e `pickup_items` ou atualize
  todos os seus consumidores na mesma mudança.
- Evite managers globais, duplicação e abstrações prematuras. Use o autoload
  `GlobalScore` somente para estado realmente global.
- Cena ou recurso gerado por ferramenta de `tools/` não se edita à mão: mude a
  receita no script e regere ([`docs/ferramentas.md`](docs/ferramentas.md)).
- Não edite `.godot/`, arquivos `.uid`, `.import` ou caches gerados.
- Não altere modelos, texturas ou materiais importados quando uma sobrescrita
  local na cena resolver o problema.
- Nunca grave senhas, tokens, chaves ou credenciais no repositório.
- Registre origem, autor e licença ao adicionar assets externos.

## Validação

- O padrão é não validar. Mudança no corpo de uma função, em valores, textos,
  comentários ou documentação vai direto, com um resumo do que mudou.
- Rode a checagem headless do Godot apenas nestes casos: script ou cena nova,
  arquivo movido ou renomeado, alteração em `project.godot`, ou quando o editor
  já estiver acusando erro. Uma vez, depois da última edição.
- Rode uma ferramenta de `tools/` só ao mexer no comportamento que ela cobre —
  a do sistema alterado, nunca a bateria inteira.
- Os comandos, o mapa de ferramentas por sistema, os roteiros do que pedir ao
  usuário e as regras para escrever uma verificação nova estão em
  [`tools/VALIDACAO.md`](tools/VALIDACAO.md).
- Nunca remova ou enfraqueça validações para ocultar falhas.
- Nunca declare algo como testado sem ter executado a validação.

## Documentação

- **Mudança arquitetural relevante atualiza a documentação correspondente em
  [`docs/`](docs/), na mesma alteração.** Conta como relevante: sistema, cena
  reutilizável, autoload, grupo, sinal ou contrato entre sistemas criado,
  removido ou renomeado; responsabilidade movida de um script para outro; etapa
  nova no fluxo de jogo; ferramenta de `tools/` adicionada ou com efeito
  alterado; decisão que um agente futuro precisaria conhecer para não repetir um
  erro. Ajuste de valor, correção dentro de uma função e mudança só visual não
  exigem documentação.
- Ao criar um documento novo em `docs/`, acrescente-o ao índice de
  [`docs/README.md`](docs/README.md).
- `docs/` descreve **relações, responsabilidades e decisões**. Valores de ajuste
  vivem nos `@export` e nas constantes, que são a fonte da verdade — não
  duplique número nem copie código para a documentação.
- Atualize `README.md` quando mudar o fluxo, controles, cena principal,
  arquitetura, dependências, comandos de execução ou limitações conhecidas; ao
  adicionar, remover ou renomear uma seção dele, atualize o índice no topo.
- Detalhe de pipeline de geração, parâmetros de ajuste, cotas de asset e
  armadilhas de ferramenta vão para `tools/VALIDACAO.md` ou para comentários no
  script que os implementa — não para o `README.md`.
- `docs/generated/` recebe snapshot de ferramenta; nunca escreva ali à mão.
- Atualize este `AGENTS.md` somente quando surgir uma regra permanente nova.
- Ao concluir, informe os arquivos alterados, as validações executadas e as
  limitações que permaneceram.
