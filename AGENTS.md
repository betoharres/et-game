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
| Quando e como revisar a documentação | seção [Documentação](#documentação) deste arquivo |
| Autoloads, Input Map, camadas de física e render | `project.godot` |

## Antes de alterar

- Leia o documento de [`docs/`](docs/) do sistema envolvido e, em mudanças que
  cruzam sistemas, [`docs/arquitetura.md`](docs/arquitetura.md). A documentação
  pode estar atrás do código: use-a como mapa de onde olhar, não como verdade.
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

Documentação é mínima. Prefira código claro a comentário, e comentário a
documento.

### Comentários no código

- Não comente o óbvio. Se dá para ver lendo o código, não escreva: nome, tipo,
  `@export` e constante já dizem o quê.
- Comente apenas restrição técnica não óbvia, contorno de bug e decisão que
  alguém quebraria sem perceber — sempre o **porquê**, nunca o quê.
- Comentário é curto. Se precisa de vários parágrafos, ou a explicação vale para
  o sistema inteiro e vai para [`docs/`](docs/), ou o código está pedindo para
  ficar mais simples.
- Não registre suposição, histórico, alternativa descartada, plano futuro nem
  regra especulativa.
- Comentário que descreve código morre com ele: ao alterar uma função, apague o
  que ela invalidou em vez de acumular camadas.

### Documentos

**Desenvolvimento não documenta.** Enquanto a tarefa for implementar, corrigir
ou ajustar, não atualize `docs/`, `README.md` nem este arquivo: entregue o
código e o resumo do que mudou. Revisar documentação é uma tarefa própria,
pedida explicitamente pelo desenvolvedor — em geral na hora do commit.

- **A mensagem de commit é o registro.** É o único lugar onde o *porquê* de uma
  decisão sobrevive até a revisão; o diff não o recupera. Ao commitar mudança de
  contrato entre sistemas, diga na mensagem o que mudou e por quê.
- Exceção única: se a alteração deixa um trecho de `docs/` afirmando algo que
  levaria outro agente a escrever código errado, corrija esse trecho junto. Um
  parágrafo, não uma revisão.
- `docs/` está possivelmente atrás do código. Serve para saber onde olhar, não
  como verdade.
- `docs/generated/` recebe snapshot de ferramenta; nunca escreva ali à mão.
- Ao concluir, informe os arquivos alterados, as validações executadas e as
  limitações que permaneceram.

### Revisar a documentação

Só quando pedido. O escopo é o intervalo desde o último commit que tocou
`docs/`, `README.md`, `AGENTS.md` ou `tools/VALIDACAO.md`: leia esse intervalo
com `git log` e `git diff` e atualize apenas o que os commits invalidaram.

- Atualize o documento de [`docs/`](docs/) correspondente quando o intervalo
  criar, remover ou renomear sistema, cena reutilizável, autoload, grupo, sinal
  ou contrato entre sistemas; mover responsabilidade de um script para outro;
  acrescentar etapa ao fluxo de jogo; adicionar ferramenta de `tools/` ou mudar
  o efeito de uma; ou registrar decisão que um agente futuro precisaria conhecer
  para não repetir um erro. Ajuste de valor, correção dentro de uma função e
  mudança só visual não entram.
- Ao criar um documento novo em `docs/`, acrescente-o ao índice de
  [`docs/README.md`](docs/README.md).
- `docs/` descreve **relações, responsabilidades e decisões**. Valores de ajuste
  vivem nos `@export` e nas constantes, que são a fonte da verdade — não
  duplique número nem copie código para a documentação.
- `docs/` descreve a arquitetura atual. Apague o trecho que deixou de valer em
  vez de acumular regra histórica ou seção de "como era antes".
- Atualize `README.md` quando mudar o fluxo, controles, cena principal,
  arquitetura, dependências, comandos de execução ou limitações conhecidas; ao
  adicionar, remover ou renomear uma seção dele, atualize o índice no topo.
- Detalhe de pipeline de geração, parâmetros de ajuste, cotas de asset e
  armadilhas de ferramenta vão para `tools/VALIDACAO.md` ou para comentários no
  script que os implementa — não para o `README.md`.
- Atualize este `AGENTS.md` somente quando surgir uma regra permanente nova.

### Aviso de atraso

`python .claude/hooks/aviso-docs.py` informa quantos commits e quantos dias se
passaram desde a última revisão. Rode-o no início da sessão; se ele imprimir um
aviso, repita-o ao desenvolvedor na resposta e ofereça a revisão — nunca revise
por conta própria.
